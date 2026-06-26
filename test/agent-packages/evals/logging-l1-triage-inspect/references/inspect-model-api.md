# Model API Reference — Inspect Documentation
# Source: https://inspect.aisi.org.uk/reference/inspect_ai.model.html
# Supplemented by introspection of inspect-ai 0.3.238

## get_model

```python
get_model(
    model: str | Model | None = None,
    *,
    role: str | None = None,
    required: bool = False,
    default: str | Model | None = None,
    config: GenerateConfig | None = None,
    base_url: str | None = None,
    api_key: str | None = None,
    memoize: bool = True,
    **model_args: Any,
) -> Model
```

Retrieves (or creates) a memoized `Model` instance. Supports async context manager for
automatic client closure.

## ModelAPI (custom provider base class)

```python
class ModelAPI:
    def __init__(
        self,
        model_name: str,
        base_url: str | None = None,
        api_key: str | None = None,
        api_key_vars: list[str] = [],
        config: GenerateConfig = GenerateConfig(),
    ) -> None: ...

    async def generate(
        self,
        input: list[ChatMessageSystem | ChatMessageUser | ChatMessageAssistant | ChatMessageTool],
        tools: list[ToolInfo],
        tool_choice: Literal["auto", "any", "none"] | ToolFunction,
        config: GenerateConfig,
    ) -> ModelOutput | tuple[ModelOutput | Exception, ModelCall]: ...
```

`generate()` is the only **abstract** method. It is `async`. May return just `ModelOutput` or
a `(ModelOutput, ModelCall)` tuple for call recording.

### Optional override methods

| Method | Default | Purpose |
|---|---|---|
| `connection_key()` | `"default"` | Scope for connection limits |
| `max_connections()` | built-in | Default concurrent connection limit |
| `max_tokens()` | `None` | Default max tokens |
| `should_retry(ex)` | `False` | Retry on exception |
| `is_auth_failure(ex)` | `False` | Identify auth failures |
| `collapse_user_messages()` | `False` | Merge consecutive user messages |
| `collapse_assistant_messages()` | `False` | Merge consecutive assistant messages |

## @modelapi decorator

```python
@modelapi(name: str) -> Callable[..., type[ModelAPI]]
```

Registers a custom model API under a given name. Usage:

```python
@modelapi(name="my-provider")
def my_provider():
    from .impl import MyModelAPI
    return MyModelAPI
```

Then use as `model="my-provider/model-name"`.

## ModelOutput

Pydantic model. Fields:

```python
model: str = ""
choices: list[ChatCompletionChoice] = []
completion: str = ""       # text of the first choice
usage: ModelUsage | None = None
time: float | None = None
metadata: dict[str, Any] | None = None
error: str | None = None
```

Properties:
- `stop_reason` — stop reason of the first choice message
- `message` — `ChatMessageAssistant` from the first choice

### Factory methods

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

This is the primary way to build a `ModelOutput` from plain text in a custom provider:

```python
return ModelOutput.from_content(model=self.model_name, content="some text")
```

## ChatCompletionChoice

Pydantic model. Fields:

```python
message: ChatMessageAssistant    # required
stop_reason: Literal["stop", "max_tokens", "model_length",
                      "tool_calls", "content_filter", "unknown"] = "unknown"
stop_details: StopDetails | None = None
logprobs: Logprobs | None = None
prompt_logprobs: Logprobs | None = None
```

## ChatMessageAssistant

Pydantic model. Fields:

```python
id: str | None = None
content: str | list[ContentText | ContentReasoning | ContentImage | ...]  # required
source: Literal["input", "generate", "operator"] | None = None
metadata: dict[str, Any] | None = None
role: Literal["assistant"] = "assistant"
tool_calls: list[ToolCall] | None = None
model: str | None = None
```

Also has a `.text` property that returns the text content as a string.

Construction: `ChatMessageAssistant(content="plain text")` works directly.

## ChatMessageUser

Pydantic model. Fields:

```python
id: str | None = None
content: str | list[ContentText | ...]  # required
source: Literal["input", "generate", "operator"] | None = None
metadata: dict[str, Any] | None = None
role: Literal["user"] = "user"
tool_call_id: list[str] | None = None
```

## ContentText

Pydantic model. Fields:

```python
type: Literal["text"] = "text"
text: str                         # required
refusal: bool | None = None
citations: Sequence[...] | None = None
internal: JsonValue | None = None
```

Construction: `ContentText(text="hello")`.

## GenerateConfig

Dataclass with generation parameters. Key fields:
- `max_retries`, `timeout`, `attempt_timeout`
- `temperature`, `top_p`, `top_k`
- `max_tokens`
- `seed`
- `reasoning_effort`, `effort`
- `stop_seqs`

## Message type hierarchy

```
ChatMessage (union)
  ├── ChatMessageSystem
  ├── ChatMessageUser
  ├── ChatMessageAssistant
  └── ChatMessageTool
```
