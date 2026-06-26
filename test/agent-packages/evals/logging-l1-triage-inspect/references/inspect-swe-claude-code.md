# Claude Code — Inspect SWE
# Source: https://meridianlabs-ai.github.io/inspect_swe/claude_code.html

## Overview

`inspect_swe` provides a `claude_code()` agent that uses the unattended mode of Anthropic
Claude Code to execute agentic tasks within the Inspect sandbox.

## Basic Usage

```python
from inspect_ai import Task, task
from inspect_ai.dataset import json_dataset
from inspect_ai.scorer import model_graded_qa

from inspect_swe import claude_code

@task
def system_explorer() -> Task:
    return Task(
        dataset=json_dataset("dataset.json"),
        solver=claude_code(),
        scorer=model_graded_qa(),
        sandbox="docker",
    )
```

## Configuration Options

| Option | Purpose |
|---|---|
| `system_prompt` | Append additional instructions to default prompt |
| `skills` | Include additional skills for the agent |
| `mcp_servers` | Configure Model Context Protocol servers |
| `bridged_tools` | Expose host-side Inspect tools via MCP |
| `disallowed_tools` | Restrict specific tools |
| `model` | Specify model for agent execution |
| `cwd` | Set working directory |
| `env` | Define environment variables |
| `version` | Control Claude Code version |
| `centaur` | Enable human-model collaboration mode |

## MCP Servers

```python
from inspect_ai.tool import MCPServerConfigStdio
from inspect_swe import claude_code

claude_code(
    mcp_servers=[
        MCPServerConfigStdio(
            name="memory",
            command="npx",
            args=["--offline", "@modelcontextprotocol/server-memory"],
        )
    ]
)
```

## Bridged Tools

Expose host-side tools to the sandboxed agent:

```python
from inspect_ai.agent import BridgedToolsSpec
from inspect_ai.tool import tool

@tool
def search_database():
    async def execute(query: str) -> str:
        """Search the internal database.

        Args:
            query: The search query.
        """
        return f"Results for: {query}"
    return execute

claude_code(
    bridged_tools=[
        BridgedToolsSpec(name="host_tools", tools=[search_database()])
    ]
)
```

## Versioning

```python
claude_code(version="auto")     # auto-detect or download stable (default)
claude_code(version="sandbox")  # use sandbox-installed version only
claude_code(version="latest")   # download latest dev build
claude_code(version="0.29.0")   # exact version
```

## Centaur Mode (human-model collaboration)

```python
claude_code(centaur=True)
```

## Notes for this eval

This package (`inspect_swe`) is a separate installable library, not part of `inspect-ai`
itself. The eval in this repository does NOT use `inspect_swe.claude_code()` — it implements
its own `@solver` that calls `claude_agent_sdk.query()` directly, which gives finer control
over the prompt, model, options, and cwd without requiring a Docker sandbox.
