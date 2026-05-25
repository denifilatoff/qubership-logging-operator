# Eval pipeline — logging-l2-troubleshooting

Local eval pipeline for the L2 skill package. See
`../docs/eval-pipeline-design.md` for design.

## Prerequisites

- kind cluster + helmfile baseline up. `BACKEND=graylog` is required for
  F3, F5b, F7; F1, F2, F4 work on either backend.
- `claude` CLI logged into the Claude Code subscription (the
  `anthropic:claude-agent-sdk` provider routes through this session).
- `apm`, `node`/`npx`, `jq` on PATH. `promptfoo` is invoked via
  `npx promptfoo@latest`.
- One-time setup in this directory:

  ```bash
  cd agent-packages/logging-l2-troubleshooting/evals
  npm install --no-save @anthropic-ai/claude-agent-sdk
  ```

  The promptfoo provider resolves the SDK from the local `node_modules/`.

## Run

```bash
# Full sweep: all fixtures, with-pkg vs no-pkg, --repeat 3
make eval

# Single fixture
make eval-F1
make eval-F2
make eval-F3
make eval-F4
make eval-F5b
make eval-F7

# Aggregate the last run into summary.md
make report

# Wipe ephemeral workdirs and result trees
make clean
```

Cluster fixtures (apply/revert mechanics) live in `deploy/kind/fixtures/`.
The eval-fixture `fixtures/<id>/meta.yaml` links to a cluster fixture by id.

## Reports

Each run writes both formats per fixture:

- `results/<run-id>/<fix>.json` — raw eval record (read by `aggregate.sh`).
- `results/<run-id>/<fix>.html` — static, self-contained table; open in a
  browser.
- `results/<run-id>/summary.md` — with-pkg vs no-pkg deltas across the
  run.

For cross-run browsing of any historical eval (sort / filter / diff):

```bash
npx promptfoo@latest view   # serves http://localhost:15500
```
