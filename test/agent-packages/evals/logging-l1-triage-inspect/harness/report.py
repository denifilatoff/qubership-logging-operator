"""Summarize an inspect-ai run from its eval log into results/<run>/summary.md,
using native samples_df. Replaces the promptfoo report.js.

Each run lands in its own `results/<run>/` directory (run id = the eval log's
UTC creation time, e.g. `20260609T125250Z`) so successive reports do not
overwrite each other; `results/LAST_RUN` names the latest. The `results/` tree
is gitignored. Re-running the report on the same logs is idempotent: the run id
comes from the log, not the wall clock.

Cost figures come from the Agent SDK's own `total_cost_usd`, carried through the
per-model `model_usage` column. That number is exact and cache-aware (it knows
the 5m vs 1h cache-write tiers), so the report does not recompute cost from a
hardcoded price table.
"""
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

from inspect_ai.analysis import samples_df
from inspect_ai.log import read_eval_log

EVAL_DIR = Path(__file__).parent.parent


def _run_id(log_dir: str) -> str:
    """Compact UTC run id from the newest `.eval` log's creation time
    (`YYYYMMDDTHHMMSSZ`), falling back to now if the logs carry no timestamp."""
    created = None
    for f in sorted(Path(log_dir).glob("*.eval")):
        ts = read_eval_log(str(f)).eval.created
        if ts and (created is None or ts > created):
            created = ts
    dt = datetime.fromisoformat(created) if created else datetime.now(timezone.utc)
    return dt.astimezone(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def _accumulate_cost(df) -> dict[str, dict[str, float]]:
    """Sum tokens and cost per model across all samples. The `model_usage` cell
    is a JSON string of {model: {input_tokens, ..., total_cost}}; empty for logs
    predating the usage wiring."""
    per_model: dict[str, dict[str, float]] = {}
    for cell in df.get("model_usage", []):
        if not cell:
            continue
        usage = json.loads(cell) if isinstance(cell, str) else cell
        for model, u in usage.items():
            acc = per_model.setdefault(model, {"tokens": 0.0, "cost": 0.0})
            acc["tokens"] += u.get("total_tokens", 0) or 0
            acc["cost"] += u.get("total_cost", 0) or 0
    return per_model


def _subscores(log_dir):
    """Aggregate the triage_scorer deterministic sub-results from the .eval logs."""
    safety, disp, jp, jt = [], [], [], []
    for f in sorted(Path(log_dir).glob("*.eval")):
        log = read_eval_log(str(f))
        for s in (log.samples or []):
            sc = (s.scores or {}).get("triage_scorer")
            if not sc or not sc.metadata:
                continue
            safety.append(1 if sc.metadata.get("safety_ok") else 0)
            disp.append(1 if sc.metadata.get("disposition_ok") else 0)
            jp.append(sc.metadata.get("judge_passed") or 0)
            jt.append(sc.metadata.get("judge_total") or 0)
    return safety, disp, jp, jt


def main(log_dir: str) -> None:
    df = samples_df(log_dir)
    n = len(df)
    lines = ["# inspect-ai L1 triage run", "", f"- Samples: {n}", ""]

    # Per-scorer means across all samples. score_routing_scorer holds 'C'/'I'
    # strings (Arrow large_string); score_triage_scorer holds floats (Arrow double).
    for col in df.columns:
        if col.startswith("score_"):
            series = df[col].dropna()
            if len(series):
                # Detect string columns via dtype kind or Arrow type name.
                dtype_str = str(series.dtype)
                if "string" in dtype_str or "object" in dtype_str:
                    # routing values are 'C'/'I'; map to pass-rate.
                    rate = (series == "C").mean()
                    lines.append(f"- {col}: pass-rate {rate:.3f} (n={len(series)})")
                else:
                    lines.append(f"- {col}: mean {float(series.mean()):.3f} (n={len(series)})")

    safety, disp, jp, jt = _subscores(log_dir)
    if safety:
        lines += [
            "",
            f"- safety gate pass-rate: {sum(safety)/len(safety):.3f} (n={len(safety)})",
            f"- disposition pass-rate: {sum(disp)/len(disp):.3f} (n={len(disp)})",
            f"- judge checks passed: {sum(jp)}/{sum(jt)}",
        ]

    per_model = _accumulate_cost(df)
    total_cost = sum(m["cost"] for m in per_model.values())
    if total_cost > 0:
        lines += [
            "",
            "## Cost (Agent SDK total_cost_usd — exact, cache-aware)",
            "",
            "| model | tokens | cost USD |",
            "|---|---:|---:|",
        ]
        for model in sorted(per_model):
            m = per_model[model]
            lines.append(f"| {model} | {int(m['tokens']):,} | {m['cost']:.4f} |")
        per_sample = total_cost / n if n else 0.0
        lines += [
            "",
            f"- Total: ${total_cost:.4f} over {n} samples — ${per_sample:.4f}/sample",
        ]
    else:
        lines += ["", "- No token/cost data in these logs (predate usage wiring)."]

    run_id = _run_id(log_dir)
    run_dir = EVAL_DIR / "results" / run_id
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / "summary.md").write_text("\n".join(lines) + "\n")
    (EVAL_DIR / "results" / "LAST_RUN").write_text(run_id + "\n")
    print("\n".join(lines))
    print(f"\nwrote results/{run_id}/summary.md")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "logs/full")
