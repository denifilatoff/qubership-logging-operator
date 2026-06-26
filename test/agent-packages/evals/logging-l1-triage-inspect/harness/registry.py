"""Inspect entry-point shim. Inspect imports this module before it resolves any
model name, so the custom `claude-agent` ModelAPI is registered in time to back
both the primary model and the `grader` role. Without it, role resolution runs
before `task.py` imports `provider`, and `claude-agent/...` is unrecognized.

Inspect's entry-point loader only *imports* the referenced object; it never
calls it. The registration therefore has to be a top-level import side effect:
importing `provider` runs its `@modelapi` registration.
"""
from . import provider  # noqa: F401  -- registers the `claude-agent` ModelAPI
