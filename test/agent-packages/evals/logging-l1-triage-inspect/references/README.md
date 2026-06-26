# References

This directory holds offline copies of the documentation pages and installed-package API
notes needed to implement the inspect-ai eval for the logging-l1-triage agent package.
The files are checked in so that later tasks (writing the custom `@solver` and the custom
`ModelAPI` judge provider) can read them without network access.

## Auth note (load-bearing)

Inspect's built-in `anthropic` provider requires `ANTHROPIC_API_KEY`. This eval does **not**
use that provider. Both roles — the Haiku `@solver` that drives the triage agent and the
Sonnet `ModelAPI` judge that calls `model_graded_qa` — invoke `claude_agent_sdk.query()`
directly. When `ANTHROPIC_API_KEY` is absent from the environment, the Agent SDK CLI
subprocess falls back to the subscription credentials in `~/.claude/`. That is the intended
auth path: no API key is required, and billing goes through the Claude Code subscription.

## File index

| File | Source | Contents |
|---|---|---|
| `api-notes.md` | Introspection (authoritative) | Real signatures for every symbol used in glue code; plan-vs-reality divergences flagged with ⚠️ |
| `inspect-solvers.md` | https://inspect.aisi.org.uk/solvers.html | `@solver` protocol, `TaskState` members, built-in solvers |
| `inspect-scorers.md` | https://inspect.aisi.org.uk/scorers.html | Scorer overview, `model_graded_qa`, `Score`, `accuracy` |
| `inspect-scorer-api.md` | https://inspect.aisi.org.uk/reference/inspect_ai.scorer.html | Full `model_graded_qa` signature, default template + instructions verbatim |
| `inspect-model-api.md` | https://inspect.aisi.org.uk/reference/inspect_ai.model.html | `ModelAPI`, `ModelOutput`, `modelapi` decorator, chat message types |
| `inspect-providers.md` | https://inspect.aisi.org.uk/providers.html + extensions page | Custom provider pattern (`@modelapi`, two-file layout, entry points) |
| `inspect-agent-bridge.md` | https://inspect.aisi.org.uk/agent-bridge.html | `agent_bridge()` / `sandbox_agent_bridge()` (not used by this eval) |
| `inspect-eval-logs.md` | https://inspect.aisi.org.uk/eval-logs.html | `read_eval_log`, `samples_df`, `evals_df`, log formats |
| `inspect-swe-claude-code.md` | https://meridianlabs-ai.github.io/inspect_swe/claude_code.html | `inspect_swe.claude_code()` agent (reference only; not used) |
| `agent-sdk-python.md` | https://code.claude.com/docs/en/agent-sdk/python | `query()`, `ClaudeAgentOptions`, message/block types, auth behavior |

## Authority

**`api-notes.md` is the single authority for implementation code.** It was produced by
introspecting `EVAL/.venv` (inspect-ai 0.3.238, claude-agent-sdk 0.2.94) and records the
real signatures. Where the plan's assumed names differ from reality, the notes call that out
explicitly. All glue task code must match `api-notes.md`, not the plan's best-effort
pseudocode.
