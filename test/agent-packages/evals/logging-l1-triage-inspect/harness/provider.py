"""Custom inspect ModelAPI driving the Claude Agent SDK for single-shot
completions on the subscription. Registered as `claude-agent/<model>` so it can
back the `grader` model role used by the judge scorer.
"""
import os

from inspect_ai.model import (
    ModelAPI,
    ModelOutput,
    GenerateConfig,
    modelapi,
)

from claude_agent_sdk import (
    query,
    ClaudeAgentOptions,
    AssistantMessage,
    ResultMessage,
    TextBlock,
)

from .usage import to_model_usage


def _subscription_env() -> dict:
    """Env that forces subscription auth: blank ANTHROPIC_API_KEY so the SDK
    cannot pick up an inherited key and fall through to the direct API."""
    env = dict(os.environ)
    env["ANTHROPIC_API_KEY"] = ""
    return env


@modelapi(name="claude-agent")
def claude_agent():
    return ClaudeAgentAPI


class ClaudeAgentAPI(ModelAPI):
    def __init__(self, model_name, base_url=None, api_key=None,
                 api_key_vars=None, config=GenerateConfig()):
        super().__init__(model_name, base_url, api_key, api_key_vars or [], config)

    async def generate(self, input, tools, tool_choice, config):
        prompt = "\n\n".join(getattr(m, "text", "") or "" for m in input).strip()
        options = ClaudeAgentOptions(
            model=self.model_name,
            allowed_tools=[],
            permission_mode="bypassPermissions",
            env=_subscription_env(),
        )
        text_parts: list[str] = []
        final = ""
        result_msg = None
        async for message in query(prompt=prompt, options=options):
            if isinstance(message, AssistantMessage):
                for block in message.content:
                    if isinstance(block, TextBlock):
                        text_parts.append(block.text)
            elif isinstance(message, ResultMessage):
                final = message.result or ""
                result_msg = message
        completion = final or "\n".join(text_parts)
        output = ModelOutput.from_content(model=self.model_name, content=completion)
        # Inspect's model layer wraps this call, so returning usage here is enough
        # for the judge's tokens to land in the log.
        usage = to_model_usage(result_msg)
        if usage is not None:
            output.usage = usage
        return output
