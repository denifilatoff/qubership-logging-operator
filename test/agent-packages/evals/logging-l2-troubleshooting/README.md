# Eval pipeline — logging-l2-troubleshooting

Local eval for the L2 skill package. One declarative `promptfooconfig.yaml` runs
every case serially against a live kind cluster: a scenario injects a fault, the
agent under test (Claude Code on Haiku) troubleshoots it, and a judge (Claude
Code on Sonnet) grades the transcript. See `docs/agent-packages/04-evaluation.md`
for the design.

## Prerequisites

- kind cluster + helmfile baseline up. `BACKEND=graylog` is required for
  `opensearch-flood-stage-readonly`, `fluentbit-cpu-throttle`, and
  `graylog-gelf-input-size-too-small`; the others work on either backend.
- `claude` CLI logged into the Claude Code subscription — both providers route
  through this session, so no `ANTHROPIC_API_KEY` is needed.
- `apm`, `node`, and `npx` on PATH. `promptfoo` runs via `npx promptfoo@latest`.
- One-time setup in this directory:

  ```bash
  cd test/agent-packages/evals/logging-l2-troubleshooting
  make setup
  ```

  This installs `@anthropic-ai/claude-agent-sdk` into a local `node_modules/`
  (gitignored).

## Run

```bash
# All cases, --repeat 3 (override with REPEATS=N). Writes the run JSON and a
# summary.md, then leaves the cluster clean.
make eval

# Re-summarise the last run without re-running it.
make report

# Open promptfoo's web UI on the stored runs.
make view
```

`make eval` aborts if a scenario is already active (`make baseline-check`), so a
dirty cluster cannot poison the run. To run one case, filter by its slug:

```bash
npx promptfoo@latest eval -c promptfooconfig.yaml --repeat 1 --no-cache \
  --filter-pattern '^fluentbit-config-syntax$' --output results/smoke.json
node report.js results/smoke.json
```

## Layout

- `promptfooconfig.yaml` — the whole eval: `cases.js` generates the tests,
  `hooks.js` drives the scenario lifecycle, and two inline providers (the Haiku
  agent and the Sonnet judge) plus the `rubric` and `routing` assertions score
  each run.
- `cases.js` — enumerates `cases/*/` into promptfoo test cases.
- `hooks.js` — `beforeAll` preps the agent workdir (`apm install`); `beforeEach`
  applies the case's scenario; the teardown hook reverts. Calls `../../scenarios/`.
- `report.js` — turns the run JSON into `results/<run>/summary.md` from
  promptfoo's native metrics (named `rubric`/`routing` scores, per-call cost,
  `numTurns`).
- `Makefile` — `eval`, `report`, `view`, `clean`, `setup`, `baseline-check`.
- `judge-prompt.txt` — the LLM judge's rubric prompt.
- `cases/<slug>/` — one directory per case:
  - `prompt.txt` — what the agent is asked, in a naive-user voice.
  - `ground_truth.md` — expected diagnosis and recommendation.
  - `rubric.yaml` — the checks the judge applies.
  - `meta.yaml` — case metadata (backend, expected area).
- `results/` — per-run JSON and `summary.md` (gitignored).

The case slug equals the scenario slug — no mapping needed. The fault-injection
scenarios themselves live in `../../scenarios/` (shared with any other harness).
