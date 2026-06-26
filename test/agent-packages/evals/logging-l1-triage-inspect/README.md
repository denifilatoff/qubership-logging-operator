# L1 triage eval — inspect-ai port

inspect-ai port of the promptfoo L1 triage eval (next door at
`../logging-l1-triage/`). Same 9 cases, same skill, same conditions: agent on
Haiku, judge on Sonnet, both through the Claude Code subscription — no
`ANTHROPIC_API_KEY`.

## Why this exists

A spike to test inspect-ai as an eval spine against promptfoo. The headline
result: inspect-ai's native model layer is API-key-only, so honoring the
subscription-only constraint meant writing the Agent-SDK wrapper that promptfoo
ships for free — `solver.py` (agent) and `provider.py` (judge), ~140 lines.
Everything else is native inspect-ai: the dataset, the routing scorer, `epochs`
variance, the `.eval` log, `inspect view`, and `samples_df` reporting.

## Scoring

Two scorers run per sample:

- `routing_scorer` — deterministic: both skills fired in order.
- `triage_scorer` — composed. A hard **safety gate** (no live-system CLI executed),
  a deterministic **disposition** match (the agent's `outcome:` vs the gold), and the
  **semantic judge** (the 3 remaining rubric checks). The score is
  `gate AND (disposition_ok + judge_passed) / (1 + expected_checks)`. The denominator
  is the expected number of semantic checks, so a judge that emits fewer cannot
  inflate the score; `judge_passed` is counted from the judge's `checks[]` array, not
  its self-reported `score`.

The judge grades only the semantic checks; the disposition value and live-system
access are scored by code (see `scorer.py`).

## Results

Full run, 9 cases x 3 epochs (27 samples), on the subscription:

- `triage_scorer` mean: **0.954**
- Safety gate pass-rate: **1.000** (no live-system access)
- Disposition pass-rate: **0.963** (26/27)
- Judge semantic checks passed: **77/81**
- Routing pass-rate: **1.000**
- Cost: **$3.74** ($0.138/sample), exact from the Agent SDK `total_cost_usd`.

Per disposition (`triage_scorer` mean): `additional_info_required` 0.972,
`handoff_to_l2` 0.972, `suspected_known_issue` 0.917. The 0.917 is the known
weak-model (Haiku) ceiling on that branch, not a regression.

The single-file `ground-truth.yaml` case format was adopted after an ablation against
the old two-file gold: the single file scored 0.935 vs current 0.954, a gap within
agent run-to-run variance (the deterministic `disposition_ok` alone moved 0.037 between
the two runs) while the judge's semantic checks were flat (76 vs 77 of 81).

## Prerequisites

- `claude` CLI logged into the subscription (or `CLAUDE_CODE_OAUTH_TOKEN`).
- `apm`, `node`, `python3` on PATH.
- `make setup` — creates `.venv`, installs deps, and `pip install -e .` to
  register the `claude-agent` provider entry point.

## Run

```bash
unset ANTHROPIC_API_KEY   # or prefix with: env -u ANTHROPIC_API_KEY
make eval-slice   # 3 cases, 1 epoch — debug
make eval         # 9 cases, epochs=3
make report       # results/<run>/summary.md from logs/full
make view         # inspect log viewer
```

## Layout

Root holds the inspect entry point and packaging; all eval source lives in the
`harness/` package.

- `task.py` — the whole eval, loaded by `inspect eval`: dataset + solver + routing
  scorer + judge + epochs. Imports `harness.*`.
- `pyproject.toml` — installs `harness` and registers the provider via an inspect
  entry point (model roles resolve before `task.py` loads, so a late import is too late).
- `conftest.py` — puts the eval root on `sys.path` for the test suite.
- `harness/dataset.py` — builds Samples from the shared `../logging-l1-triage/cases/`.
- `harness/solver.py` — glue #1: Agent SDK on Haiku (subscription).
- `harness/provider.py` — glue #2: Agent SDK judge on Sonnet (subscription).
- `harness/registry.py` — the entry-point shim; imports `provider` for its side effect.
- `harness/scorer.py` — routing scorer + judge scorer (reshape, rubric template, grade parse).
- `harness/workdir.py` — `apm install` + symlink dereference.
- `harness/report.py` — `samples_df` -> `results/<run>/summary.md` (run via
  `python -m harness.report`); `results/LAST_RUN` names the latest.
- `references/` — offline inspect-ai and Agent-SDK docs + `api-notes.md`.

## inspect-ai vs promptfoo (spike notes)

| Concern | promptfoo | inspect-ai |
|---|---|---|
| Subscription auth | bundled `anthropic:claude-agent-sdk` provider, `apiKeyRequired: false` | ~140 lines of own glue (`solver.py` + `provider.py`) |
| Provider registration | inline in YAML | Python entry point + `pip install -e .` (roles resolve pre-task-load) |
| Judge | `llm-rubric` returning a JSON score | built-in `model_graded_qa` too coarse (C/P/I, final answer only); custom `@scorer` instead |
| Agent + judge harness | one provider, two configs | `@solver` + custom `ModelAPI` |
| Variance | `--repeat N` | `epochs` + reducers (native) |
| Transcript | `metadata.toolCalls` | first-class in the `.eval` log; `inspect view` |
| Reporting | `report.js` | `samples_df` (native) |

Net: inspect-ai needs more glue and packaging to honor subscription-only, but
gives a richer native transcript/variance/log story once that glue is in place.
