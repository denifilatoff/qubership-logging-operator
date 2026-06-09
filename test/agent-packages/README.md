# Tests for agent packages

Test infrastructure for the AI-skill packages under
`agent-packages/`. Not shipped to APM consumers — internal to this
repository.

## Layout

- `scenarios/` — reproducible failures on a running logging stack
  (`apply.sh` / `revert.sh` per scenario). Shared across skills.
- `evals/<skill-package>/` — per-skill evaluation harness (promptfoo
  config, prompts, ground truth, rubrics, runner scripts). One
  subdirectory per skill being evaluated.

## Mental model

- One scenario reproduces one cluster failure.
- One eval is a (skill, scenario) pair — same scenario can feed evals
  for multiple skills.
- The scenario slug and the matching eval case slug are identical, so
  the orchestrator does not need a separate mapping.

## See also

- `scenarios/README.md` — runtime contract scenarios assume.
- `evals/logging-l2-troubleshooting/README.md` — current eval pipeline.
- `docs/agent-packages/04-evaluation.md` — design background.
