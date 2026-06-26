"""Build inspect-ai Samples from the package-local L1 triage cases."""
from pathlib import Path
import re

from inspect_ai.dataset import Sample

EVAL_DIR = Path(__file__).parent.parent
CASES_DIR = (EVAL_DIR / "cases").resolve()

# Wrapper prompt sent to the agent under evaluation.
PROMPT = """You are an L1 support engineer triaging an incoming Qubership logging-stack
support ticket. Triage it end to end: first classify the ticket, then decide
the next action on it. Use your installed skills and follow them exactly. Do
not touch any live system.

--- TICKET ---
{ticket}"""


def _disposition(ground_truth_yaml: str) -> str:
    """Read the gold disposition from the top-level `disposition:` key of
    ground-truth.yaml (a single scalar; parsed without a YAML dep)."""
    m = re.search(r"^disposition:\s*(\S+)", ground_truth_yaml, re.MULTILINE)
    return m.group(1) if m else ""


def _count_checks(text: str) -> int:
    """Number of `- id:` check entries in a ground-truth YAML (no YAML dep)."""
    return len(re.findall(r"^\s*-\s*id:", text, re.MULTILINE))


def triage_dataset() -> list[Sample]:
    samples: list[Sample] = []
    for case_dir in sorted(p for p in CASES_DIR.iterdir() if p.is_dir()):
        ticket = (case_dir / "ticket.txt").read_text().strip()
        ground_truth = (case_dir / "ground-truth.yaml").read_text()
        disposition = _disposition(ground_truth)
        if not disposition:
            raise ValueError(f"case {case_dir.name}: no top-level disposition found")
        samples.append(
            Sample(
                input=PROMPT.format(ticket=ticket),
                target=disposition,
                metadata={
                    "slug": case_dir.name,
                    "disposition": disposition,
                    "judge_instructions": ground_truth,
                    "expected_checks": _count_checks(ground_truth),
                },
            )
        )
    return samples
