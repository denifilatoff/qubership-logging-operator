# Agent Bridge — Inspect Documentation
# Source: https://inspect.aisi.org.uk/agent-bridge.html

## Overview

Inspect provides integration capabilities for third-party agents through bridging mechanisms.
You can integrate agents created with 3rd party frameworks like OpenAI Agents SDK, Pydantic AI,
and LangChain, or use fully custom agents.

Two bridging approaches are supported:

1. **Python-based agents** running in the same process via `agent_bridge()`
2. **Sandboxed agents** written in any language via `sandbox_agent_bridge()`

## Python Agent Bridge

The `agent_bridge()` context manager redirects native API calls to Inspect's model provider.

Steps:
1. Write your agent using OpenAI, Anthropic, or Google SDKs.
2. Specify `model="inspect"` when making API calls.
3. Wrap execution in the `agent_bridge()` context manager.
4. Return the tracked state changes.

```python
from inspect_ai.agent import agent, agent_bridge
from inspect_ai.model import messages_to_openai

@agent
def my_agent() -> Agent:
    async def execute(state: AgentState) -> AgentState:
        async with agent_bridge(state) as bridge:
            client = AsyncOpenAI()
            await client.chat.completions.create(
                model="inspect",
                messages=messages_to_openai(state.messages)
            )
        return bridge.state
    return execute
```

## Sandbox Agent Bridge

For agents running in containers, `sandbox_agent_bridge()` works differently:
1. Configure your sandbox with the agent binary.
2. Set environment variables to redirect API calls to `localhost:13131`.
3. Use `sandbox().exec()` to invoke the agent.
4. The bridge provides a proxy server relaying requests.

```python
async with sandbox_agent_bridge(state) as bridge:
    prompt = user_prompt(state.messages)
    result = sandbox().exec(
        cmd=["/opt/my_agent", "--prompt", prompt.text],
        env={"OPENAI_BASE_URL": f"http://localhost:{bridge.port}/v1"}
    )
    return bridge.state
```

## Model Configuration

Use the prefix `inspect/` to specify non-OpenAI models through the bridge:

```python
model = ChatOpenAI(model="inspect/google/gemini-1.5-pro")
```

## Generation Parameters

By default, the bridge filters out generation parameters like `max_tokens` and `temperature`
to prevent model mismatch issues. Enable full parameter forwarding with
`forward_generation_config=True`.

## Notes for the Claude Agent SDK use case

The agent bridge is NOT needed when driving the Agent SDK from a custom `@solver`, because
the SDK launches its own Claude Code process and messages travel through its own channel.
The bridge is relevant only when you want the Agent SDK calls to be routed through Inspect's
active model (using `model="inspect"` or similar).

For the eval design in this repository, the custom `@solver` uses `claude_agent_sdk.query()`
directly and builds a `ModelOutput` from the result — no bridge required.
