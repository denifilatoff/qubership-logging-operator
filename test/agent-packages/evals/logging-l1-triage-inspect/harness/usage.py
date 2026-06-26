"""Map the Claude Agent SDK usage onto inspect-ai's ModelUsage.

The Agent SDK drives the model outside inspect's native model layer, so token
counts never reach the eval log on their own. This translates the SDK's terminal
`ResultMessage` usage into a `ModelUsage` the log and viewer understand.
"""
from inspect_ai.model import ModelUsage


def to_model_usage(result) -> ModelUsage | None:
    """Build a ModelUsage from an Agent SDK ResultMessage, or None when absent.

    The SDK reports non-cached input, output, and cache read/write counts
    separately; `total_tokens` sums all four.
    """
    if result is None:
        return None
    u = getattr(result, "usage", None) or {}
    inp = u.get("input_tokens", 0) or 0
    out = u.get("output_tokens", 0) or 0
    cache_write = u.get("cache_creation_input_tokens", 0) or 0
    cache_read = u.get("cache_read_input_tokens", 0) or 0
    usage = ModelUsage(
        input_tokens=inp,
        output_tokens=out,
        total_tokens=inp + out + cache_write + cache_read,
        input_tokens_cache_write=cache_write,
        input_tokens_cache_read=cache_read,
    )
    cost = getattr(result, "total_cost_usd", None)
    if cost is not None:
        usage.total_cost = cost
    return usage
