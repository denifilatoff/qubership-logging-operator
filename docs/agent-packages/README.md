# Agent packages — internal docs

Cross-cutting documentation for our AI-skill packages. Audience: us,
working on the skills themselves. Not part of any skill's distribution.

## Layout

- `specs/` — implementation design specs (`YYYY-MM-DD-<slug>-design.md`).
- `plans/` — ephemeral implementation plans; removed after execution.
- `archive/` — superseded or historical material we keep for reference.

## Documents

- [eval-pipeline-design.md](eval-pipeline-design.md) — promptfoo-based pipeline for grading skill behaviour against scenarios on a live cluster.
- [eval-framework-survey.md](eval-framework-survey.md) — comparison of promptfoo / inspect-ai / others for our use case.
- [skill-evaluation-methodology.md](skill-evaluation-methodology.md) — what we mean by "evaluating" a skill, what we measure, and why.
- [package-layering-model.md](package-layering-model.md) — how the L1 / L2 / topic-specific skill packages stack.
- [chain-of-hypotheses-design.md](chain-of-hypotheses-design.md) — chain-of-hypotheses routing, signal classification, cascade-refute pattern. The L2 logging package is the first instance.
- [routing-redesign-proposal.md](routing-redesign-proposal.md) — proposal to simplify the leaf contract to two outcomes and move all routing judgment into triage. Gated on a baseline sweep with the current model.
- [troubleshooting-methodology.md](troubleshooting-methodology.md) — domain knowledge that informs the L1 and L2 skills.
- [reference-documents.md](reference-documents.md) — index of external references we draw on.

## Sibling product docs

`docs/` (the parent directory) holds operator user-facing documentation
— `api.md`, `architecture.md`, `cookbook/`, CRDs. Different audience,
different lifecycle.
