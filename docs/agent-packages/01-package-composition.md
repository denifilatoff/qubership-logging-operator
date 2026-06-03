# 1. Package composition

The unit of distribution is a **skill package** — one APM package with one `apm.yml`, installable into a consumer repo
via `apm install`. This document covers how packages are composed for the scope these methodology docs care about:
triage and troubleshooting of production issues. Packages for coding, testing, refactoring, or other
software-engineering work follow different conventions and are out of scope.

## 1.1. The working model — two packages per troubleshooting domain

A new troubleshooting domain typically ships **two separate APM packages** that engineers install independently. The
split mirrors the L1 / L2 distinction described in `02-triage-methodology.md`:

- A **triage-only package** (`<domain>-l1-triage`) reads support tickets and produces a routing decision. No cluster
  access, no internal sub-skills. One classifier skill plus its reference catalogues.
- A **troubleshooting package** (`<domain>-l2-troubleshooting`) runs against a live cluster. One orchestrator skill plus
  one expert skill per technology the domain involves.

They are separate packages because they have different consumer audiences (a ticket handler vs an engineer in a live
debugging session) and different install footprints — the L1 trigger should fire on ticket-pasting prose, the L2 trigger
only on live troubleshooting. A single package conflating both would over-trigger in both contexts.

### L1 triage package

```text
+-------------------------------------------------------+
|  <domain>-l1-triage   (one APM package, one skill)    |
|                                                       |
|     skill:       <domain>-l1-triage                   |
|     references:  trivial-cases.yaml                   |
|                  knowledge-areas.md                   |
|                  output-schemas.md                    |
+-------------------------------------------------------+
```

One classifier skill matching a ticket against a curated catalogue. Reference data is loaded on demand and grep-keyed.
No internal orchestration, no sub-skills. What the skill actually does is defined in `02-triage-methodology.md §2.2`.

### L2 troubleshooting package

```text
+-------------------------------------------------------+
|  <domain>-l2-troubleshooting   (one APM package)      |
|                                                       |
|     orchestrator:  <domain>-l2-triage                 |
|     experts:       <tech-a>-troubleshoot              |
|                    <tech-b>-troubleshoot              |
|                    <tech-c>-troubleshoot              |
|     shared:        action-tier contract,              |
|                    canonical symptom catalogues       |
+-------------------------------------------------------+
```

The orchestrator runs a cluster-wide read-safe diagnostic pass, picks an expert based on the signal it surfaces, and
chains across experts when the evidence calls for it. Shared material that more than one skill consumes (the action-tier
contract, canonical symptom catalogues) lives directly under the package's `.apm/shared/`. The internal contract between
orchestrator and experts is in `03-package-internals.md`.

> **Example — this repo.** `logging-l1-triage` ships the L1 classifier with its trivial-cases catalogue.
> `logging-l2-troubleshooting` ships the `logging-l2-triage` orchestrator plus four experts (graylog, opensearch,
> fluentbit, fluentd) and the shared catalogues they read. Two separate APM packages, one shared domain.

## 1.2. Extension point — shared lower-level material

The moment a _second_ domain package starts copy-pasting the same cross-cutting material — a Kubernetes-context entry
guard, a generic pod-debug procedure, the methodology document set itself — that material graduates into its own package
that both domains depend on. By convention this is called Layer 0.

If you ever get there, the realistic first extractions are `troubleshooting-common` (entry guard + methodology), and,
only as genuine reuse forces them, narrower packages such as `troubleshoot-k8s-net` or `troubleshoot-k8s-storage`.

This is not a starting point. Born from concrete reuse, not anticipation. **No Layer 0 package exists today** — every
domain we ship is the first.

## 1.3. Extension point — bundling several domains

Once several domain packages exist and a typical platform deployment combines them, a thin **umbrella package** can list
them as dependencies:

```yaml
# troubleshoot-observability/apm.yml
dependencies:
  apm:
    - troubleshoot-logging
    - troubleshoot-monitoring
    - troubleshoot-tracing
```

The umbrella has no skills of its own beyond a one-line top-level router ("observability ticket → pick by primary signal
source"). Service teams pull one umbrella instead of three packages.

Do not create umbrellas pre-emptively. They earn their place only when a real platform deployment genuinely bundles the
domains they collect.

## 1.4. Dependency rule

Whichever layers end up materialising, the rule is the same: a package depends only on packages at a strictly lower
level, never on a sibling at the same level. Two domain packages do not share skills with each other; if they would, the
shared content belongs in a lower-level package (extension §1.2).

## 1.5. Always-on context budget

Each package merges a short trigger instruction into the consumer's `AGENTS.md` / `CLAUDE.md`. Keep it small — **≤ ~20
lines per package**. A consumer pulling several packages otherwise blows its persistent-context budget. Everything
beyond the trigger moves to on-demand SKILL content that the agent loads only when relevant.
