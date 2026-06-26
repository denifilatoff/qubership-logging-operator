"""Agent solver: drive the Claude Agent SDK on Haiku (subscription) with the
L1 skills installed in a per-sample workdir. Records assistant text and a
normalized tool-call list into state.store. This is the glue promptfoo bundled.
"""
import os

from inspect_ai.solver import solver, Solver, TaskState, Generate
from inspect_ai.model import ChatMessageAssistant, ModelOutput
from inspect_ai.model._model import record_and_check_model_usage

from claude_agent_sdk import (
    query,
    ClaudeAgentOptions,
    AssistantMessage,
    ResultMessage,
    TextBlock,
    ToolUseBlock,
)

from .workdir import prepare_workdir, EVAL_DIR
from .usage import to_model_usage


def _subscription_env() -> dict:
    """Env that forces subscription auth: blank ANTHROPIC_API_KEY so the SDK
    cannot pick up an inherited key and fall through to the direct API."""
    env = dict(os.environ)
    env["ANTHROPIC_API_KEY"] = ""
    return env


@solver
def claude_agent_solver(model: str = "claude-haiku-4-5") -> Solver:
    async def solve(state: TaskState, generate: Generate) -> TaskState:
        slug = state.metadata["slug"]
        workdir = prepare_workdir(EVAL_DIR / ".workdir" / slug)

        options = ClaudeAgentOptions(
            model=model,
            cwd=str(workdir),
            permission_mode="bypassPermissions",
            setting_sources=["project"],
            skills="all",
            env=_subscription_env(),
        )

        assistant_text: list[str] = []
        tool_calls: list[dict] = []
        final = ""
        result_msg = None
        async for message in query(prompt=state.input_text, options=options):
            if isinstance(message, AssistantMessage):
                for block in message.content:
                    if isinstance(block, TextBlock):
                        assistant_text.append(block.text)
                    elif isinstance(block, ToolUseBlock):
                        tool_calls.append({"name": block.name, "input": block.input})
            elif isinstance(message, ResultMessage):
                final = message.result or ""
                result_msg = message

        if not final and assistant_text:
            final = assistant_text[-1]

        state.store.set("assistant_text", assistant_text)
        state.store.set("tool_calls", tool_calls)
        state.store.set("final", final)
        state.messages.append(ChatMessageAssistant(content="\n\n".join(assistant_text)))
        output = ModelOutput.from_content(model=model, content=final)
        # The Agent SDK ran the model outside inspect's model layer, so attribute
        # the run's aggregate token usage to this sample by hand; otherwise the
        # log and viewer report nothing.
        usage = to_model_usage(result_msg)
        if usage is not None:
            output.usage = usage
            record_and_check_model_usage(model, usage)
        state.output = output
        return state

    return solve
