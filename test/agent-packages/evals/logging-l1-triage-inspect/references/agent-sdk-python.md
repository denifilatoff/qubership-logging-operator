# Agent SDK Reference — Python
# Source: https://code.claude.com/docs/en/agent-sdk/python

## Installation

```bash
pip install claude-agent-sdk
```

## Choosing between `query()` and `ClaudeSDKClient`

| Feature | `query()` | `ClaudeSDKClient` |
|---|---|---|
| Session | Creates a new session by default | Reuses same session |
| Conversation | Single exchange | Multiple exchanges in same context |
| Connection | Managed automatically | Manual control |
| Interrupts | Not supported | Supported |
| Hooks | Supported | Supported |
| Custom Tools | Supported | Supported |
| Continue Chat | Manual via `continue_conversation` or `resume` | Automatic |
| Use Case | One-off tasks | Continuous conversations |

## `query()` — signature

```python
async def query(
    *,
    prompt: str | AsyncIterable[dict[str, Any]],
    options: ClaudeAgentOptions | None = None,
    transport: Transport | None = None,
) -> AsyncIterator[UserMessage | AssistantMessage | SystemMessage | ResultMessage | StreamEvent | RateLimitEvent]
```

- `query` is an **async generator function** (`isasyncgenfunction=True`).
- Yields messages as they arrive.
- Each `await` iterates one message at a time.

## `ClaudeAgentOptions` — key fields

```python
class ClaudeAgentOptions:
    tools: list[str] | ToolsPreset | None = None
    allowed_tools: list[str] = []
    system_prompt: str | SystemPromptPreset | SystemPromptFile | None = None
    mcp_servers: dict[str, McpStdioServerConfig | ...] | str | Path = {}
    permission_mode: Literal["default", "acceptEdits", "plan",
                             "bypassPermissions", "dontAsk", "auto"] | None = None
    model: str | None = None
    fallback_model: str | None = None
    cwd: str | Path | None = None
    cli_path: str | Path | None = None
    settings: str | None = None           # path to a settings.json file
    setting_sources: list[Literal["user", "project", "local"]] | None = None
    skills: list[str] | Literal["all"] | None = None
    add_dirs: list[str | Path] = []
    env: dict[str, str] = {}
    max_turns: int | None = None
    max_budget_usd: float | None = None
    disallowed_tools: list[str] = []
    session_id: str | None = None
    continue_conversation: bool = False
    resume: str | None = None
    permission_prompt_tool_name: str | None = None
    can_use_tool: Callable[...] | None = None
    hooks: dict[...] | None = None
    user: str | None = None
    include_partial_messages: bool = False
    include_hook_events: bool = False
    fork_session: bool = False
    agents: dict[str, AgentDefinition] | None = None
    sandbox: SandboxSettings | None = None
    plugins: list[SdkPluginConfig] = []
    max_thinking_tokens: int | None = None
    thinking: ThinkingConfigAdaptive | ThinkingConfigEnabled | ThinkingConfigDisabled | None = None
    effort: Literal["low", "medium", "high", "xhigh", "max"] | None = None
    output_format: dict[str, Any] | None = None
    enable_file_checkpointing: bool = False
    session_store: SessionStore | None = None
    load_timeout_ms: int = 60000
    task_budget: TaskBudget | None = None
    betas: list[Literal["context-1m-2025-08-07"]] = []
    extra_args: dict[str, str | None] = {}
    debug_stderr: Any = sys.stderr
    stderr: Callable[[str], None] | None = None
    strict_mcp_config: bool = False
```

## Message types returned by `query()`

### `AssistantMessage`

```python
@dataclass
class AssistantMessage:
    content: list[TextBlock | ThinkingBlock | ToolUseBlock | ToolResultBlock | ServerToolUseBlock | ServerToolResultBlock]
    model: str
    parent_tool_use_id: str | None = None
    error: Literal["authentication_failed", "billing_error", "rate_limit",
                   "invalid_request", "server_error", "unknown"] | None = None
    usage: dict[str, Any] | None = None
    message_id: str | None = None
    stop_reason: str | None = None
    session_id: str | None = None
    uuid: str | None = None
```

### `ResultMessage`

```python
@dataclass
class ResultMessage:
    subtype: str
    duration_ms: int
    duration_api_ms: int
    is_error: bool
    num_turns: int
    session_id: str
    stop_reason: str | None = None
    total_cost_usd: float | None = None
    usage: dict[str, Any] | None = None
    result: str | None = None              # final text result
    structured_output: Any = None
    model_usage: dict[str, Any] | None = None
    permission_denials: list[Any] | None = None
    errors: list[str] | None = None
    api_error_status: int | None = None
    uuid: str | None = None
```

### `TextBlock`

```python
@dataclass
class TextBlock:
    text: str
```

### `ToolUseBlock`

```python
@dataclass
class ToolUseBlock:
    id: str
    name: str
    input: dict[str, Any]
```

### Other content block types

- `ThinkingBlock` — extended thinking output
- `ToolResultBlock` — result of a tool call
- `ServerToolUseBlock` — server-side tool use
- `ServerToolResultBlock` — result of a server-side tool call

## Typical iteration pattern

```python
import asyncio
from claude_agent_sdk import query, ClaudeAgentOptions, AssistantMessage, ResultMessage, TextBlock

async def run(prompt: str, cwd: str, model: str) -> str:
    opts = ClaudeAgentOptions(
        model=model,
        cwd=cwd,
        permission_mode="bypassPermissions",
    )
    final_text = ""
    async for msg in query(prompt=prompt, options=opts):
        if isinstance(msg, AssistantMessage):
            for block in msg.content:
                if isinstance(block, TextBlock):
                    final_text += block.text
        elif isinstance(msg, ResultMessage):
            if msg.result:
                final_text = msg.result
    return final_text
```

## Auth behavior

The SDK invokes the Claude Code CLI subprocess. When `ANTHROPIC_API_KEY` is **not set** in
the environment, the CLI falls back to the subscription-based auth stored in `~/.claude/`
(the same auth used by the interactive Claude Code session). This is the intended behavior
for this eval: both the `@solver` role (Haiku) and the judge role (Sonnet) run without
`ANTHROPIC_API_KEY`, so they consume the subscription rather than the API key.

## `setting_sources` field

```python
setting_sources: list[Literal["user", "project", "local"]] | None = None
```

Controls which settings layers Claude Code loads. Omitting it (default `None`) loads all
layers. To load only the user-level settings (to pick up skills installed in `~/.claude/`):

```python
ClaudeAgentOptions(setting_sources=["user"])
```

## `skills` field

```python
skills: list[str] | Literal["all"] | None = None
```

List of skill names to activate, or `"all"` to activate all available skills.

## `cwd` field

```python
cwd: str | Path | None = None
```

Working directory for the Claude Code subprocess. Set this to the eval's working directory
so skills in `<cwd>/.claude/skills/` are discoverable.

## `ClaudeSDKClient`

```python
class ClaudeSDKClient:
    def __init__(self, options: ClaudeAgentOptions | None = None, transport: Transport | None = None)
    async def connect(self, prompt: str | AsyncIterable[dict] | None = None) -> None
    async def query(self, prompt: str | AsyncIterable[dict], session_id: str = "default") -> None
    async def receive_messages(self) -> AsyncIterator[Message]
    async def receive_response(self) -> AsyncIterator[Message]
    async def interrupt(self) -> None
    async def disconnect(self) -> None
    # ...additional session management methods
```

Supports async context manager for automatic lifecycle management.
