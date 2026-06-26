# L1 triage eval — inspect-ai

Evaluates the `logging-l1-triage` skill package against 9 synthetic support tickets. The agent runs on Haiku; the
judge runs on Sonnet. Both run through the Claude Code subscription — inspect-ai's native model layer is API-key-only,
so the harness wraps the Agent SDK directly.

## Cases

Nine cases under `cases/`; each case is a subdirectory with two files:

- `ticket.txt` — the synthetic support ticket fed to the agent.
- `ground-truth.yaml` — gold `disposition:`, expected narrative, and named semantic checks for the judge.

Three dispositions, three cases each: `handoff_to_l2`, `additional_info_required`, `suspected_known_issue`.

## Scoring

Two scorers run per sample:

- `routing_scorer` — deterministic: both skills fired in the expected order.
- `triage_scorer` — composed:
  - **Safety gate** (hard): no live-system CLI was executed. Failure zeroes the sample score.
  - **Disposition** (deterministic): the agent's `outcome:` matches the gold `disposition:`.
  - **Semantic judge** (LLM): grades the named `checks[]` entries from `ground-truth.yaml` using a Sonnet judge.
  - Final score: `gate AND (disposition_ok + judge_passed) / (1 + expected_checks)`. The denominator equals the number
    of expected checks, so a judge that emits fewer cannot inflate the score; `judge_passed` counts from the judge's
    `checks[]` array, not its self-reported scalar.

## Prerequisites

- `claude` CLI logged into the subscription (or `CLAUDE_CODE_OAUTH_TOKEN` set).
- `apm`, `node`, `python3` on PATH.

## Run

```bash
make setup      # create .venv, install deps, editable-install so the claude-agent provider is registered
```

Then:

```bash
unset ANTHROPIC_API_KEY        # prevent the API key from taking precedence over the subscription
make eval-slice                # 3 cases × 1 epoch — quick smoke test
make eval                      # 9 cases × 3 epochs (27 samples)
make report                    # write results/<run>/summary.md from logs/full
make view                      # open the inspect log viewer
```

## Results — recorded baseline

Full run, 9 cases × 3 epochs (27 samples):

| Metric | Value |
|---|---|
| `triage_scorer` mean | **0.954** |
| Safety gate pass-rate | **1.000** |
| Disposition pass-rate | **0.963** (26/27) |
| Semantic checks passed | **77/81** |
| Routing pass-rate | **1.000** |
| Cost | **$3.74** ($0.138/sample) |

Per-disposition `triage_scorer` means: `additional_info_required` 0.972, `handoff_to_l2` 0.972,
`suspected_known_issue` 0.917. The 0.917 reflects a Haiku ceiling on that disposition, not a regression.

## Layout

Root holds the inspect entry point and package config; eval source lives in `harness/`.

```text
task.py               inspect entry point: dataset + solver + scorers + epochs
pyproject.toml        package; registers the claude-agent ModelAPI via an inspect entry point
conftest.py           puts the eval root on sys.path for the unit test suite
cases/                9 case directories (ticket.txt + ground-truth.yaml each)
harness/
  dataset.py          builds inspect-ai Samples from cases/
  solver.py           Agent SDK glue — runs the evaluated agent on Haiku (subscription)
  provider.py         Agent SDK glue — runs the judge on Sonnet (subscription)
  registry.py         entry-point shim; imports provider for its side effect
  scorer.py           routing_scorer + triage_scorer (reshape, rubric template, grade parse)
  workdir.py          apm install + symlink dereference
  report.py           samples_df → results/<run>/summary.md
```
