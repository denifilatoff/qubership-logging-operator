# Vocabulary cleanup task — `sweep` → `eval run`

Small standalone rename task surfaced during the expert-orchestration refactor (May 2026). Independent of the refactor; can be done in any session.

## Problem

The project uses `sweep` for two distinct concepts:

1. **Per-skill diagnostic pass** — the read-safe probe set each expert SKILL runs at the start of an invocation. This was renamed to `diagnostic pass` during the refactor (commit `384803f`).
2. **Eval batch run** — one execution of the eval suite producing a `summary.md`. Still uses `sweep`.

Sense #2 is semantically wrong: `parameter sweep` in ML means *searching over a parameter space*, not running a measurement. Our eval batch is a measurement, not a search. The accurate English term is `eval run` or `evals full run`; the Russian equivalent is `прогон evals`.

The misnomer is intelligible but inaccurate; it should be renamed for the project to stand on precise vocabulary.

## Scope

Rename `sweep` → `run` (or `eval run` where the type matters) in:

- `docs/agent-packages/eval-pipeline-design.md` (multiple occurrences in design prose).
- `docs/agent-packages/skill-evaluation-methodology.md` if it uses `sweep` for the batch sense.
- `test/agent-packages/evals/logging-l2-troubleshooting/README.md` ("Full sweep:" comment, etc.).
- Any new `summary.md` headers — `aggregate.sh` currently emits `# Eval run <id>` already; verify.
- `expert-orchestration-pattern.md` Validation section if any `sweep` survives.

Keep filenames (`results/<timestamp>Z/summary.md`) — those are historical, renaming them rewrites baseline references.

## What to verify

After the rename, the per-skill diagnostic-pass sense should be the only place `diagnostic pass` appears in the live package, and `sweep` should not appear at all in surviving project docs (except in `references/` or guidance docs that explicitly compare the new vocabulary to the old).

Grep checks:

```bash
grep -rn 'sweep\|Sweep' --include='*.md' docs/agent-packages/ test/agent-packages/evals/ | grep -v archive
```
Expected after the rename: zero matches outside intentional vocabulary-comparison passages.

## Why this is its own task

It touches docs outside `agent-packages/logging-l2-troubleshooting/.apm/` (eval-pipeline-design, eval README, etc.) and crosses skill-package + eval-pipeline boundaries. Doing it as part of the architectural refactor would have noisy-up the refactor diff. Folded out so the refactor's `git log` stays clean.

## Out of scope

- Renaming historical `results/<timestamp>Z/` directories.
- Touching the `apm` upstream — `apm` itself doesn't use this term.
- Translating "sweep" inside conversation transcripts or memory files — those are session artifacts, not project docs.
