# Eval pipeline — logging-l2-troubleshooting

Local eval pipeline for the L2 skill package. See
`docs/agent-packages/eval-pipeline-design.md` for design.

## Prerequisites

- kind cluster + helmfile baseline up. `BACKEND=graylog` is required
  for `opensearch-flood-stage-readonly`, `fluentbit-cpu-throttle`,
  `graylog-gelf-input-size-too-small`; the others work on either
  backend.
- `claude` CLI logged into the Claude Code subscription (the
  `anthropic:claude-agent-sdk` provider routes through this session).
- `apm`, `node` / `npx`, `jq` on PATH. `promptfoo` is invoked via
  `npx promptfoo@latest`.
- One-time setup in this directory:

  ```bash
  cd test/agent-packages/evals/logging-l2-troubleshooting
  make setup
  ```

  Installs `@anthropic-ai/claude-agent-sdk` into a local `node_modules/`
  (gitignored).

## Run

```bash
# Full sweep: all cases, with-pkg vs no-pkg, --repeat 3
make eval

# Single case
make eval-fluentbit-oom
make eval-fluentbit-config-syntax
make eval-opensearch-flood-stage-readonly
# ... one target per case ...
```

`make eval` and `make eval-<case>` both run a baseline-clean check
before starting and abort if a scenario is already active.

## Layout

- `promptfooconfig.yaml` — promptfoo eval config (templated).
- `Makefile` — entry points: `eval`, `eval-<case>`, `report`, `clean`.
- `orchestrator.sh` — serial loop over cases: apply scenario → run
  promptfoo → revert.
- `prep-workdir.sh` — prepares a workdir per (case, variant).
- `aggregate.sh` — collapses the last run's JSON outputs into
  `results/<run-id>/summary.md`.
- `cases/<case-slug>/` — one directory per evaluation case:
  - `prompt.txt` — what the agent is asked.
  - `ground_truth.md` — expected diagnosis + recommendation.
  - `rubric.yaml` — checks the judge evaluates.
  - `meta.yaml` — case metadata (backend, expected area, etc.).
- `providers/` — promptfoo provider definitions.
- `judge-prompt.txt` — system prompt for the LLM judge.
- `results/` — per-run output (gitignored).

The case slug equals the scenario slug — no mapping needed.
