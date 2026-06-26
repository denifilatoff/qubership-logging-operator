# API Notes — Installed-Version Signatures
# inspect-ai 0.3.238  |  claude-agent-sdk 0.2.94
# Obtained by introspecting EVAL/.venv — this file is the authority for glue task code.

All signatures below were extracted with `inspect.signature()` and `inspect.getmembers()`
against the installed packages. Plan-vs-reality divergences are flagged with ⚠️.

---

## 1. inspect_ai.solver

### @solver decorator

```python
solver(name: str | Callable) -> Callable
```

- No-argument form `@solver` uses the wrapped function's name automatically.
- Named form: `@solver(name="my_solver")`.
- The decorated function must **return** an `async def solve(state, generate) -> TaskState`.

### Solver protocol

```python
async def solve(state: TaskState, generate: Generate) -> TaskState:
    ...
```

`Generate` is a `Protocol` (not a callable class). The `generate(state)` call is `await`-able.

### TaskState — real `__init__` signature

```python
TaskState(
    model: ModelName,
    sample_id: int | str,
    epoch: int,
    input: str | list[ChatMessage],
    messages: list[ChatMessage],
    target: Target = Target(),
    choices: list[str] | None = None,
    output: ModelOutput | None = None,
    message_limit: int | None = None,
    token_limit: int | None = None,
    cost_limit: float | None = None,
    completed: bool = False,
    metadata: dict[str, Any] | None = None,
    store: dict[str, Any] | None = None,
    scores: dict[str, Score] | None = None,
    sample_uuid: str | None = None,
)
```

### TaskState — all public attributes (from `dir()`)

```
completed, cost_limit, cost_usage, epoch, input, input_text, max_messages,
message_limit, messages, metadata, metadata_as, model, output, sample_id,
scores, store, store_as, target, token_limit, token_usage, tool_choice,
tools, user_prompt, uuid
```

Key ones for solvers:
- `state.input` — original input (str or list[ChatMessage])
- `state.input_text` — original input as plain string ✅ (plan assumed this; it exists)
- `state.messages` — mutable list of ChatMessage (append here to add turns)
- `state.output` — ModelOutput from the last generate call
- `state.metadata` — dict from the Sample
- `state.store` — plain `dict[str, Any] | None`
- `state.store_as(ModelClass)` — typed access via a pydantic model instance
- `state.completed` — set to `True` to terminate early
- `state.user_prompt` — convenience property returning first ChatMessageUser

### ⚠️ CORRECTED (Task 6): state.store IS a Store object with .get()/.set()

This note originally claimed `state.store` was a plain dict. **That was wrong** — verified
against a live run in Task 6. In inspect-ai 0.3.238 `state.store` is a read-only property
returning a `Store` object with `.get(key, default=None)` and `.set(key, value)` methods.
Use it as:

```python
state.store.set("key", value)
value = state.store.get("key")
```

`state.store or {}` still works for readers because `Store` is truthy and exposes `.get()`,
so the scorer's `(state.store or {}).get("tool_calls")` is fine. Solvers must use
`state.store.set(...)` (there is no item assignment). Or use `state.store_as(MyPydanticModel)`.

### Appending an assistant message to state

```python
from inspect_ai.model import ChatMessageAssistant
state.messages.append(ChatMessageAssistant(content="some text"))
```

`ChatMessageAssistant` accepts `content` as a plain string or as `list[ContentText | ...]`.
It also has a `.text` property that returns the string version of content.

---

## 2. inspect_ai.scorer

### model_graded_qa — real signature

```python
model_graded_qa(
    template: str | None = None,
    instructions: str | None = None,
    grade_pattern: str | None = None,
    include_history: bool | Callable[[TaskState], str] = False,
    partial_credit: bool = False,
    model: list[str | Model] | str | Model | None = None,
    model_role: str | None = "grader",
) -> Scorer
```

`template` and `instructions` are **plain strings** (or `None`), not callables.

### Default template (DEFAULT_MODEL_GRADED_QA_TEMPLATE)

```
You are assessing a submitted answer on a given task based on a criterion. Here is the data:

[BEGIN DATA]
***
[Task]: {question}
***
[Submission]: {answer}
***
[Criterion]: {criterion}
***
[END DATA]

Does the submission meet the criterion?

{instructions}
```

**Real placeholders: `{question}`, `{answer}`, `{criterion}`, `{instructions}`.**

⚠️ The plan mentioned `{criterion}` — this is correct. The variable is `criterion`, not
`target` or `rubric`.

### Default grade_pattern

```
(?is).*GRADE\s*:\s*([CPI])
```

### Default instructions (partial_credit=False)

```
After assessing the submitted answer, reply with 'GRADE: $LETTER' (without quotes) where
LETTER is one of CI. ...
GRADE: C for correct, GRADE: I for incorrect.
```

### Default instructions (partial_credit=True)

```
After assessing the submitted answer, reply with 'GRADE: $LETTER' (without quotes) where
LETTER is one of CPI. ...
GRADE: C for correct, GRADE: P for partial, GRADE: I for incorrect.
```

### scorer decorator — real signature

```python
scorer(
    metrics: Sequence[Metric | Mapping[str, Sequence[Metric]]] | Mapping[str, Sequence[Metric]],
    name: str | None = None,
    **metadata: Any,
) -> Callable
```

A `@scorer`-decorated factory must return `async def score(state: TaskState, target: Target) -> Score`.

### Score — real signature

```python
Score(
    *,
    value: str | int | float | bool | Sequence[...] | Mapping[...],
    answer: str | None = None,
    explanation: str | None = None,
    metadata: dict[str, Any] | None = None,
    history: list[ScoreEdit] = [],
)
```

### Constants

```python
CORRECT   = "C"
INCORRECT = "I"
# PARTIAL = "P"  (not exported as a constant name — use the string directly)
# NOANSWER = "N" (not exported — use the string directly)
```

### accuracy

```python
accuracy(to_float: ValueToFloat = value_to_float()) -> Metric
```

---

## 3. inspect_ai.model — custom ModelAPI

### @modelapi decorator

```python
@modelapi(name: str) -> Callable[..., type[ModelAPI]]
```

✅ Name confirmed: `modelapi` (lowercase, one word). Import: `from inspect_ai.model import modelapi`.

The decorated function must **return the class** (not an instance):

```python
@modelapi(name="agent-sdk")
def agent_sdk_provider():
    from ._provider import AgentSDKModelAPI
    return AgentSDKModelAPI
```

### ModelAPI.__init__ — real signature

```python
ModelAPI.__init__(
    self,
    model_name: str,
    base_url: str | None = None,
    api_key: str | None = None,
    api_key_vars: list[str] = [],
    config: GenerateConfig = GenerateConfig(),
)
```

### ModelAPI.generate — real signature (ABSTRACT, ASYNC)

```python
async def generate(
    self,
    input: list[ChatMessageSystem | ChatMessageUser | ChatMessageAssistant | ChatMessageTool],
    tools: list[ToolInfo],
    tool_choice: Literal["auto", "any", "none"] | ToolFunction,
    config: GenerateConfig,
) -> ModelOutput | tuple[ModelOutput | Exception, ModelCall]
```

`generate` is `async` (`iscoroutinefunction=True`). It is the only abstract method.

### ModelOutput — real factory method

```python
ModelOutput.from_content(
    model: str,
    content: str | list[ContentText | ContentReasoning | ...],
    stop_reason: Literal["stop", "max_tokens", "model_length",
                         "tool_calls", "content_filter", "unknown"] = "stop",
    error: str | None = None,
    stop_details: StopDetails | None = None,
) -> ModelOutput
```

Minimal usage in a custom provider:

```python
return ModelOutput.from_content(model=self.model_name, content="response text")
```

### ⚠️ ModelOutput constructor form

The plan may have assumed `ModelOutput(model=..., choices=[...])`. While this works (it is a
Pydantic model), **`from_content()` is the recommended factory** and handles the
`ChatCompletionChoice` wrapping automatically. Do not use `ModelOutput(...)` directly unless
you are building choices manually.

### ModelOutput fields

```python
model: str = ""
choices: list[ChatCompletionChoice] = []
completion: str = ""
usage: ModelUsage | None = None
time: float | None = None
metadata: dict[str, Any] | None = None
error: str | None = None
```

Properties: `.stop_reason` (str), `.message` (ChatMessageAssistant from first choice).

### ChatCompletionChoice fields

```python
message: ChatMessageAssistant           # required
stop_reason: Literal[...] = "unknown"
stop_details: StopDetails | None = None
logprobs: Logprobs | None = None
prompt_logprobs: Logprobs | None = None
```

✅ `ChatCompletionChoice` exists as named in the plan. Import:
`from inspect_ai.model import ChatCompletionChoice`.

### ChatMessageAssistant fields

```python
content: str | list[ContentText | ...]  # required
role: Literal["assistant"] = "assistant"
tool_calls: list[ToolCall] | None = None
model: str | None = None
# + id, source, metadata
```

Has `.text` property. Accepts plain string for `content`.

### ContentText fields

```python
type: Literal["text"] = "text"
text: str                 # required
refusal: bool | None = None
citations: ... | None = None
```

### get_model

```python
get_model(
    model: str | Model | None = None,
    *,
    role: str | None = None,
    config: GenerateConfig | None = None,
    base_url: str | None = None,
    api_key: str | None = None,
    memoize: bool = True,
    **model_args: Any,
) -> Model
```

---

## 4. inspect_ai.analysis — samples_df / evals_df

### Import path

```python
from inspect_ai.analysis import samples_df, evals_df
```

✅ Import path confirmed: `inspect_ai.analysis` (not `inspect_ai.log` or similar).

### samples_df signature

```python
samples_df(
    logs: LogPaths | EvalLog | Sequence[EvalLog] | None = None,
    columns: Sequence[Column] = <defaults>,
    full: bool = False,
    strict: bool = True,
    parallel: bool | int = False,
    quiet: bool | None = None,
) -> pd.DataFrame | tuple[pd.DataFrame, list[ColumnError]]
```

### evals_df signature

```python
evals_df(
    logs: LogPaths | EvalLog | Sequence[EvalLog] | None = None,
    columns: Sequence[Column] = <defaults>,
    strict: bool = True,
    quiet: bool | None = None,
) -> pd.DataFrame | tuple[pd.DataFrame, Sequence[ColumnError]]
```

When `strict=True` (default), returns just a `DataFrame`. When `strict=False`, returns a
`(DataFrame, list[ColumnError])` tuple.

---

## 5. claude_agent_sdk (0.2.94)

### query — real signature

```python
async def query(   # isasyncgenfunction=True
    *,
    prompt: str | AsyncIterable[dict[str, Any]],
    options: ClaudeAgentOptions | None = None,
    transport: Transport | None = None,
) -> AsyncIterator[UserMessage | AssistantMessage | SystemMessage | ResultMessage | StreamEvent | RateLimitEvent]
```

`query` is an **async generator** (`isasyncgenfunction=True`, `iscoroutinefunction=False`).
Use `async for msg in query(prompt=..., options=...):`.

All parameters are **keyword-only** (no positional args).

### ClaudeAgentOptions — key fields for this eval

```python
model: str | None = None
cwd: str | Path | None = None
permission_mode: Literal["default", "acceptEdits", "plan",
                         "bypassPermissions", "dontAsk", "auto"] | None = None
setting_sources: list[Literal["user", "project", "local"]] | None = None
skills: list[str] | Literal["all"] | None = None
allowed_tools: list[str] = []
disallowed_tools: list[str] = []
env: dict[str, str] = {}
max_turns: int | None = None
system_prompt: str | SystemPromptPreset | SystemPromptFile | None = None
```

✅ `setting_sources` exists (plan assumed it; confirmed real).
✅ `skills` exists (plan assumed it; confirmed real). Type: `list[str] | Literal["all"] | None`.
✅ `cwd` exists. Type: `str | Path | None`.

⚠️ There is NO field named `setting_sources` that accepts filesystem paths — it is a list of
source **names** (`"user"`, `"project"`, `"local"`), not paths. To load skills installed in
`~/.claude/`, use `setting_sources=["user"]` or pass `cwd` to point to a project that has
`.claude/` present.

### AssistantMessage — real fields

```python
content: list[TextBlock | ThinkingBlock | ToolUseBlock | ToolResultBlock | ServerToolUseBlock | ServerToolResultBlock]
model: str
error: Literal["authentication_failed", "billing_error", ...] | None = None
usage: dict[str, Any] | None = None
message_id: str | None = None
stop_reason: str | None = None
session_id: str | None = None
```

### ResultMessage — real fields

```python
subtype: str
duration_ms: int
is_error: bool
num_turns: int
session_id: str
result: str | None = None         # final text result (use this)
total_cost_usd: float | None = None
errors: list[str] | None = None
```

### TextBlock

```python
text: str    # only field
```

Access: `block.text`

### ToolUseBlock

```python
id: str
name: str
input: dict[str, Any]
```

⚠️ The plan mentioned `block.tool` and `block.type`. These do not exist.
- Tool name: `block.name` (not `block.tool`)
- No `.type` discriminator field on the blocks themselves. Use `isinstance()` to discriminate:

```python
for block in msg.content:
    if isinstance(block, TextBlock):
        text += block.text
    elif isinstance(block, ToolUseBlock):
        tool_name = block.name
        tool_input = block.input
```

### Auth precedence

When `ANTHROPIC_API_KEY` is **not set** in the environment, the Claude Code CLI subprocess
uses the subscription-based credentials stored in `~/.claude/`. This is the intended behavior
for this eval. Both the Haiku solver role and the Sonnet judge role call the SDK without
setting `ANTHROPIC_API_KEY`, relying on the subscription.

---

## 6. Summary of plan-vs-reality divergences

| Symbol / assumption | Plan assumed | Reality |
|---|---|---|
| `state.store.set(k, v)` / `.get(k)` | (initially mis-noted as dict) | CORRECT as a `Store` object: `state.store.set(k, v)` / `.get(k)` — see Task 6 correction above |
| `block.type` on SDK content blocks | `.type` discriminator | No `.type`; use `isinstance(block, TextBlock)` etc. |
| `block.tool` on ToolUseBlock | `.tool` for tool name | `.name` is the tool name field |
| `ModelOutput(model=..., choices=[...])` | Direct constructor | Use `ModelOutput.from_content(model, content)` instead |
| `setting_sources` as filesystem paths | Paths to settings files | List of layer names: `["user"]`, `["project"]`, `["local"]` |
| `state.input_text` | May or may not exist | ✅ Confirmed real attribute |
| `@modelapi(name=...)` | Correct decorator name | ✅ Confirmed; import from `inspect_ai.model` |
| `ChatCompletionChoice` | Correct class name | ✅ Confirmed; in `inspect_ai.model` |
| `model_graded_qa` placeholders | `{question}`, `{answer}`, `{criterion}` | ✅ Confirmed; also `{instructions}` |
| `from inspect_ai.analysis import samples_df` | Unsure of path | ✅ Confirmed correct import path |
| `query` is async generator | Assumed | ✅ `isasyncgenfunction=True`, all args keyword-only |
| `ClaudeAgentOptions.setting_sources` | Assumed | ✅ Confirmed; type `list[Literal["user","project","local"]] \| None` |
| `ClaudeAgentOptions.skills` | Assumed | ✅ Confirmed; type `list[str] \| Literal["all"] \| None` |
