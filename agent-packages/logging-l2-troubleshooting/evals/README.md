# Eval pipeline — logging-l2-troubleshooting

Local-only v1 eval pipeline for the L2 skill package. See
`../docs/eval-pipeline-design.md` for design and
`../docs/2026-05-22-eval-pipeline-plan.md` for the implementation plan.

## Prerequisites

- kind cluster + helmfile baseline up. v1 fixtures (F2, F4) work on either
  `BACKEND=victorialogs` or `BACKEND=graylog`.
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
# Full v1: both fixtures, with-pkg vs no-pkg, --repeat 3
make eval

# Single fixture
make eval-F2
make eval-F4

# Aggregate the last run into summary.md
make report

# Wipe ephemeral workdirs and result trees
make clean
```

Cluster fixtures (apply/revert mechanics) live in `deploy/kind/fixtures/`.
The eval-fixture `fixtures/<id>/meta.yaml` links to a cluster fixture by id.
