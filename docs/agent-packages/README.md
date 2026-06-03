# Agent packages — meta documentation

Domain-agnostic methodology for building **triage and troubleshooting skill packages** for coding-agent harnesses
(Claude Code, Cursor, Codex, OpenCode, Gemini CLI). A skill package bundles the procedural knowledge an agent needs to
assess, route, and diagnose production issues — and to propose fixes without mutating live systems.

**Scope.** These documents cover only triage and troubleshooting. Skill packages for other software-engineering work —
coding, testing, refactoring, code review, documentation generation — follow different conventions and are out of scope.
Within triage and troubleshooting we further split L1 (no system access, ticket-driven) and L2 (live access,
diagnostic); the rest of these documents elaborates that split and the conventions that fall out of it.

The methodology was developed against the Qubership logging stack but is not tied to infrastructure observability. The
same structure applies to troubleshooting any complex system an engineer can investigate from a coding-agent harness:
other platform components (monitoring, tracing, profiling, databases, queues, app servers), domain applications (BSS,
OSS, business services), or whole product stacks. Lift these documents out of the repo, instantiate them for the new
domain, and the package shapes, contracts, and eval pipeline carry over.

## Audience

You are reading these docs if you are about to:

- design a new skill package for an unfamiliar domain,
- restructure or evaluate an existing one,
- understand the conventions a contribution must follow.

You do **not** need to read these to _use_ the logging skill packages — install them via `apm` and follow the package
README.

## Reading order

The four documents below are designed to be read end-to-end in about twenty minutes. Read them in order; each assumes
the previous one.

| #   | Document                                               | Topic                                                                                                                                             |
| --- | ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | [01-package-composition.md](01-package-composition.md) | How a domain ships as two packages (L1 triage + L2 troubleshooting), each with its own shape. Optional extension points when more domains arrive. |
| 2   | [02-triage-methodology.md](02-triage-methodology.md)   | What skills do: the L1 (ticket-only) vs L2 (live-cluster) split, invariants, action tiers, naming convention.                                     |
| 3   | [03-package-internals.md](03-package-internals.md)     | Internal design of one package: the expert/orchestrator pattern, structured I/O contract, reference-document shapes.                              |
| 4   | [04-evaluation.md](04-evaluation.md)                   | How we grade a package: capability tier, skill-vs-no-skill A/B, judge separation, pipeline architecture.                                          |

## How this repo applies the methodology

Concrete artefacts that instantiate the patterns above live with the code, not here. Cross-reference once you have read
the meta docs:

| Concern                                                   | Where to look                                                                                                                            |
| --------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| L1 triage skill package                                   | [`agent-packages/logging-l1-triage/README.md`](../../agent-packages/logging-l1-triage/README.md)                                         |
| L2 troubleshooting skill package (orchestrator + experts) | [`agent-packages/logging-l2-troubleshooting/README.md`](../../agent-packages/logging-l2-troubleshooting/README.md)                       |
| Reproducible cluster failures (scenarios)                 | [`test/agent-packages/scenarios/README.md`](../../test/agent-packages/scenarios/README.md)                                               |
| L2 evaluation pipeline                                    | [`test/agent-packages/evals/logging-l2-troubleshooting/README.md`](../../test/agent-packages/evals/logging-l2-troubleshooting/README.md) |
| Local cluster baseline                                    | [`deploy/kind/README.md`](../../deploy/kind/README.md)                                                                                   |

## Sibling docs

`docs/` (the parent directory) holds operator user-facing documentation — `api.md`, `architecture.md`, `cookbook/`,
CRDs. Different audience, different lifecycle. The methodology documents here do not ship with any skill package.
