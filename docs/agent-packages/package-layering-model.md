# Skill-Pack Layering Model

**Status:** draft v0.1, captured for reference. **Not yet adopted.** This document records a proposed architecture for organising troubleshooting skills across multiple domains and technologies as APM packages. It exists so the model can be revisited in a later session without being reconstructed from chat.

The model assumes the methodology already established for one domain (`logging`) — L1 triage on tickets, L2 triage on a live cluster, knowledge-area skills per technology, Kubernetes-only execution surface — and asks how to scale that shape across observability, databases, and application-level troubleshooting.

---

## 1. The four layers

```
LAYER 3 — UMBRELLAS (deps-only metapackages)
          • troubleshoot-observability
          • troubleshoot-app-platform
          • troubleshoot-everything

LAYER 2 — DOMAINS (triage and routing within a domain)
          • troubleshoot-logging
          • troubleshoot-monitoring
          • troubleshoot-tracing
          • troubleshoot-profiling
          • troubleshoot-databases
          • troubleshoot-queues

LAYER 1 — TECH AREAS (one technology = one package)
          • troubleshoot-graylog          • troubleshoot-prometheus
          • troubleshoot-opensearch       • troubleshoot-grafana
          • troubleshoot-fluentbit        • troubleshoot-jaeger
          • troubleshoot-fluentd          • troubleshoot-tempo
          • troubleshoot-victorialogs     • troubleshoot-otelcollector
          • ...                           • troubleshoot-pyroscope
                                          • troubleshoot-postgres
                                          • troubleshoot-cassandra
                                          • ...

LAYER 0 — CROSS-CUTTING (foundational shared blocks)
          • troubleshooting-common
          • troubleshoot-k8s-net
          • troubleshoot-k8s-storage
```

Each layer depends only on layers below it. A higher layer never declares dependencies on its siblings at the same layer.

### Roles per layer

- **Layer 0 — cross-cutting.** Universal building blocks. `kubernetes-context`, the L1/L2 methodology document, generic K8s pod-debug patterns, K8s resource heuristics. `troubleshoot-k8s-net` and `troubleshoot-k8s-storage` are separate packages because not every consumer needs them and bundling everything into one Layer 0 package would inflate persistent context.

- **Layer 1 — tech area.** Owns one knowledge area: one symptom catalogue, one diagnostic pass, one set of recommendations. Examples: `troubleshoot-graylog`, `troubleshoot-prometheus`. Owned by the team that owns that technology. Depends on `troubleshooting-common` and optionally other Layer 0 packages.

- **Layer 2 — domain.** Owns triage and routing across the technologies of one domain. Ships an `<domain>-l1-triage` (ticket-driven, no live access) and an `<domain>-l2-triage` (live cluster diagnostic pass + signal-table routing). Depends on the Layer 1 packages it routes to, plus `troubleshooting-common`.

- **Layer 3 — umbrella.** A `apm.yml` with dependencies only, no skills or instructions of its own beyond a thin top-level router instruction. Service teams pull umbrellas based on what their service uses.

---

## 2. Observability slice, expanded

```
┌──────────────────────────────────────────────────────────────────────┐
│                  LAYER 3:  troubleshoot-observability                │
│                                                                      │
│                      apm.yml  (deps only)                            │
│                      apm:                                            │
│                        - troubleshoot-logging                        │
│                        - troubleshoot-monitoring                     │
│                        - troubleshoot-tracing                        │
│                        - troubleshoot-profiling                      │
│                                                                      │
│        One instruction `observability-router.instructions.md`        │
│        (short sentence: "observability ticket → one of L2-...        │
│         triages below; pick by primary signal source")               │
└─────┬────────────────┬────────────────┬────────────────┬─────────────┘
      │                │                │                │
      ▼                ▼                ▼                ▼
┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│   LAYER 2:  │  │   LAYER 2:  │  │   LAYER 2:  │  │   LAYER 2:  │
│troubleshoot-│  │troubleshoot-│  │troubleshoot-│  │troubleshoot-│
│  logging    │  │  monitoring │  │  tracing    │  │  profiling  │
│             │  │             │  │             │  │             │
│logging-l1-  │  │monitoring-  │  │tracing-l1-  │  │profiling-   │
│triage       │  │l1-triage    │  │triage       │  │l1-triage    │
│             │  │             │  │             │  │             │
│logging-l2-  │  │monitoring-  │  │tracing-l2-  │  │profiling-   │
│triage       │  │l2-triage    │  │triage       │  │l2-triage    │
│             │  │             │  │             │  │             │
│apm:         │  │apm:         │  │apm:         │  │apm:         │
│- common     │  │- common     │  │- common     │  │- common     │
│- graylog    │  │- prometheus │  │- jaeger     │  │- pyroscope  │
│- opensearch │  │- grafana    │  │- tempo      │  │- ...        │
│- fluentbit  │  │- alertmgr   │  │- otelcol    │  │             │
│- fluentd    │  │- ...        │  │- ...        │  │             │
└──┬──────────┘  └──┬──────────┘  └──┬──────────┘  └──┬──────────┘
   │                │                │                │
   │  Each L2-triage routes within its own domain to the tech-area
   │  packages it depends on, using its own signal-table.
   ▼                ▼                ▼                ▼
┌────────────────────────────────────────────────────────────────────┐
│              LAYER 1:  tech-area packages                          │
│                                                                    │
│  graylog-server-troubleshoot   prometheus-troubleshoot             │
│  opensearch-troubleshoot       grafana-troubleshoot                │
│  fluentbit-troubleshoot        alertmanager-troubleshoot           │
│  fluentd-troubleshoot          jaeger-troubleshoot                 │
│  victorialogs-troubleshoot     tempo-troubleshoot                  │
│  graylog-disk-usage-investigate  otelcollector-troubleshoot        │
│                                pyroscope-troubleshoot              │
│                                                                    │
│  Each package: ONE knowledge area, ONE symptom catalogue, plus     │
│  optional investigate-* sub-skills.  apm:  - common  (everything   │
│  it needs is cross-cutting).                                       │
└────────────────────────┬───────────────────────────────────────────┘
                         │
                         ▼
┌────────────────────────────────────────────────────────────────────┐
│              LAYER 0:  cross-cutting packages                      │
│                                                                    │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │ troubleshooting-common                                     │    │
│  │   • kubernetes-context     — entry guard to live sessions  │    │
│  │   • troubleshooting-methodology — L1/L2 framework doc      │    │
│  │   • k8s-pod-debug          — describe/events/OOM patterns  │    │
│  │   • k8s-resources          — limits/QoS/pressure           │    │
│  │   • security-credentials   — anti-exposure patterns        │    │
│  └────────────────────────────────────────────────────────────┘    │
│                                                                    │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │ troubleshoot-k8s-net                                       │    │
│  │   • tls-pki        — Graylog TLS, Prom TLS, ...            │    │
│  │   • ingress-routing — Ingress/Route, L7 path debugging     │    │
│  │   • network-policy — NetworkPolicy blocking                │    │
│  └────────────────────────────────────────────────────────────┘    │
│                                                                    │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │ troubleshoot-k8s-storage                                   │    │
│  │   • pvc-debug      — PVC pending, mount failures           │    │
│  │   • storage-perf   — IO patterns, latency                  │    │
│  └────────────────────────────────────────────────────────────┘    │
└────────────────────────────────────────────────────────────────────┘
```

---

## 3. What belongs in Layer 0

Not everything that appears in two domains deserves to live in a cross-cutting package. The criterion is: **the skill is identical in content for its consumers, not merely thematically related.**

| Zone | Used by | Truly cross-cutting? |
|---|---|---|
| `kubernetes-context` | Every L2-triage of every domain | **Yes** — content is identical. |
| `troubleshooting-methodology` (L1/L2 framework doc) | Every domain | **Yes** — a contract, not a skill; for authors. |
| `k8s-pod-debug` (describe/events/OOM) | Every domain whose workloads run in K8s | **Yes** — same commands, same interpretation. |
| `k8s-resources` (limits/QoS/pressure) | Every domain | **Yes** — universal heuristics. |
| `security-credentials` (anti-exposure) | Every domain with API auth | **Conditionally** — the Golden Rule is universal; the command patterns differ (psql vs Graylog basic auth vs Grafana API tokens). Keep it abstract; domains extend it with their own examples. |
| `tls-pki` | Graylog→OpenSearch TLS, Prometheus scrape TLS, Postgres SSL, Jaeger | **Yes**, but as a **separate package** — not every consumer is touched, do not bundle. |
| `ingress-routing` (Ingress, Route, LB) | UI fronts: Graylog UI, Grafana, Jaeger UI | **Yes**, separate package, same reason. |
| `network-policy` | Any cross-service flow | **Yes**, separate package. |
| `storage-debug` (PVC, IO) | Any stateful workload: Graylog journal, OpenSearch data, Prom TSDB, Postgres data | **Yes**, separate package. |

Principle: **`troubleshooting-common` is a small stable core (`kubernetes-context` + methodology + base K8s debugging)**. Every other cross-cutting concern is its own package; domains pull only the ones they actually need.

---

## 4. APM dependency declarations

Concrete shape of inter-package relationships, observability slice:

```yaml
# troubleshoot-graylog/apm.yml (Layer 1)
dependencies:
  apm:
    - troubleshooting-common               # kubernetes-context, methodology
    - troubleshoot-k8s-net                  # TLS/Ingress; Graylog has UI and TLS to OS

# troubleshoot-opensearch/apm.yml (Layer 1)
dependencies:
  apm:
    - troubleshooting-common
    - troubleshoot-k8s-net                  # Graylog↔OS TLS
    - troubleshoot-k8s-storage              # PVC behind OS data

# troubleshoot-fluentbit/apm.yml (Layer 1)
dependencies:
  apm:
    - troubleshooting-common

# troubleshoot-logging/apm.yml (Layer 2)
dependencies:
  apm:
    - troubleshooting-common               # for l2-triage
    - troubleshoot-graylog
    - troubleshoot-opensearch
    - troubleshoot-fluentbit
    - troubleshoot-fluentd
    - troubleshoot-victorialogs            # alternative backend

# troubleshoot-observability/apm.yml (Layer 3)
dependencies:
  apm:
    - troubleshoot-logging
    - troubleshoot-monitoring
    - troubleshoot-tracing
    - troubleshoot-profiling
# no instructions or skills of its own beyond a thin top-level router
```

---

## 5. Onboarding sequence

Bottom-up across layers, possibly by different teams on independent timelines.

### Stage 1 — Foundation (Layer 0)

`troubleshooting-common` ships first. Owned by a dedicated team (devops-skills / platform). Contents: `kubernetes-context`, methodology document, `k8s-pod-debug`, `k8s-resources`, `security-credentials`. Version 1.0.0.

Nothing depends on it yet. Prepared in isolation.

### Stage 2 — Cross-cutting domain modules (Layer 0, specialised)

In parallel with or after Stage 1: `troubleshoot-k8s-net`, `troubleshoot-k8s-storage`. These can lag behind Stage 1, but any Layer 1 package that needs them is blocked.

### Stage 3 — Tech-area packages (Layer 1)

Each technology team (Graylog team, Prometheus team, Postgres team) writes its own `troubleshoot-<tech>`. Dependencies: `troubleshooting-common` (mandatory) plus other cross-cutting Layer 0 packages as needed.

These packages can be written independently and in parallel. The only requirement is to follow the contract from Layer 0: symptom catalogue in the agreed format, diagnostic pass + recommend, no mutating actions.

### Stage 4 — Domain triage packages (Layer 2)

Each domain owner (observability team, databases team, ...) assembles a `troubleshoot-<domain>` package. Dependencies: `troubleshooting-common` plus every relevant Layer 1 package for that domain.

Contents: L1-triage (ticket-driven) + L2-triage (live routing) + signal-table.

### Stage 5 — Umbrella metapackages (Layer 3)

Once several domains are ready, the organisation publishes umbrellas such as `troubleshoot-observability`. This is just an `apm.yml` with deps plus one short router instruction ("ticket about observability → one of the L1 domains below").

### Stage 6 — Service-team consumption

A service team in its own repo writes:

```yaml
# my-app/apm.yml
dependencies:
  apm:
    - troubleshoot-observability   # logs / metrics / traces
    - troubleshoot-databases        # we use Postgres + Redis
    - troubleshoot-app-platform     # queues + API gateway
```

`apm install + apm compile` → their `CLAUDE.md` is enriched with all L1-skill triggers across the pulled domains, plus the cross-cutting layer.

---

## 6. Activation and token budget

Each L1 trigger is an always-on instruction (~15 lines). A consumer that pulls observability + databases + app-platform — say six domains — accumulates ~6 × 15 = ~90 lines of always-on context, plus cross-cutting activation (kubernetes-context trigger, methodology if needed). That ends up around ~150 lines of persistent context.

That is manageable **if every L1 trigger stays small**. If a Layer 2 package grows fat always-on instructions (the way some existing packages have ~150-line security-guidelines files baked in), the token budget explodes. The contract therefore must say: **always-on content per Layer 2 package stays ≤ ~20 lines**; everything else moves to on-demand SKILL.md.

---

## 7. Open questions

These are deliberately left unresolved here. They came up during the design discussion and need a decision before this model is adopted.

1. **One L1 per domain, or several?** Logging currently has one L1. If monitoring turns out to benefit from splitting L1 by backend (Prometheus vs VictoriaMetrics), is the split at Layer 1 or Layer 2? Suggested default: keep one Layer 2 (`troubleshoot-monitoring`) and discriminate backends in the signal-table — one L1 = one mental window for the engineer. But this is not validated against a real case yet.

2. **Is Layer 3 actually needed?** If domains are small and engineers can pick the domains they need directly, umbrella packages are an indirection. Probably useful for **typical platform stacks** (a standard observability bundle) but not for every combination. Avoid creating umbrellas pre-emptively.

3. **Layer 0 ownership.** Who maintains `troubleshooting-common` platform-wide? A dedicated maintainer is required, otherwise the package degrades. Open whether this is a logging-team responsibility or a platform-wide one.

4. **Versioning across layers.** A breaking change in `troubleshooting-common` (e.g. the schema of a `recommend` block changes) requires every Layer 1, 2, and 3 package to bump. Semver and lockfile-based deps handle the mechanics, but the release discipline has to exist.

5. **Cross-domain investigation.** A business service can simultaneously have a problem in logs **and** traces (e.g. no logs from service X **and** no traces from it — possibly a network issue next to the service). There is no current skill that specifically handles cross-domain correlation. Open whether that lives in Layer 3 or in a new Layer 4 ("cross-domain investigation").

---

## 8. What this document is not

- It is not an adopted architecture. The logging skill-pack today (this repo) is Layer 2 + Layer 1 fused into one package, with `kubernetes-context` not yet integrated.
- It is not a migration plan. Refactoring the current package into the layered shape is a separate decision and a separate effort.
- It is not a normative specification. The numbers (line budgets, layer counts) are starting points and will need calibration against real consumers.
