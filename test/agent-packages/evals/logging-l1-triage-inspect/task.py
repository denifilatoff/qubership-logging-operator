"""L1 triage eval — inspect-ai port. One Task wires the dataset, the Agent-SDK
solver, the routing scorer, and the custom judge scorer.
"""
import os

from inspect_ai import Task, task
from inspect_ai.dataset import MemoryDataset

from harness.dataset import triage_dataset
from harness.solver import claude_agent_solver
from harness.scorer import routing_scorer, triage_scorer
from harness import provider  # noqa: F401  -- registers the `claude-agent` ModelAPI


def _sliced() -> MemoryDataset:
    samples = triage_dataset()
    slugs = os.environ.get("INSPECT_SLICE", "").split()
    if slugs:
        samples = [s for s in samples if s.metadata["slug"] in slugs]
    return MemoryDataset(samples)


@task
def triage() -> Task:
    return Task(
        dataset=_sliced(),
        solver=claude_agent_solver(model="claude-haiku-4-5"),
        scorer=[routing_scorer(), triage_scorer()],
        epochs=3,
    )
