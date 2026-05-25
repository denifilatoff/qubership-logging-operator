# Troubleshooting Methodology: L1 and L2

**Status:** draft v0.3.

This document defines two support levels for the logging-stack troubleshooting workflow and the boundary between them.

The workflow is delivered as a set of skills. The engineer runs them from a local coding agent (Claude Code, Cursor, OpenCode, Codex, and similar) — there is no dedicated orchestrator agent. Each level is itself a skill.

Once the skills have been validated through engineer-driven use, the same set is handed to an autonomous agent for unattended ticket triage and incident investigation. The skills are designed to support both modes without forking: human-in-the-loop today, agent-in-the-loop later.

---

## 1. Invariants

These rules apply across both levels and override any local convenience.

**References, not duplication.** Domain troubleshooting knowledge — symptoms, signs, solutions — lives in dedicated reference documents. Each skill has its own set: a knowledge-area skill may point at one runbook, several, or none, depending on what already exists for its area. A skill does not copy content from a reference into itself; it loads the relevant slice on demand by reference. Adding a new pattern means adding it to the appropriate reference first, then linking it from the skill.

**Lookups by grep, not by retrieval.** References are searched with `grep` and `Read`, not retrieved from a vector store. The skill body describes the shape of each reference it depends on (which columns exist, what the row key is, what to search by, how rows are delimited) so the agent knows how to query it without scanning the whole file. This forces references to be designed for deterministic lookup: stable headings, predictable layouts, searchable keys, one fact per row. No out-of-package state, no offline indexing step, no infrastructure beyond the files in the skill package. A reference that cannot be grepped against a known key is prose, not a reference, and belongs somewhere else.

**Do-no-harm.** No skill executes a mutating action against a live system or against the ticket-tracker. Mutations are emitted as structured `recommend` blocks; the operator decides whether and when to apply them.

**Read-before-recommend.** A `recommend` from the troubleshooting agent is a proposed mutation of system state. Before proposing it, the agent captures a `read-safe` snapshot of the state on which the proposal depends, and attaches that snapshot to the block. Relevant state is what the action mutates plus what proves the action is still needed — not the whole namespace. Example: a Graylog restart recommendation carries container status, recent error tail, free disk, memory pressure. The snapshot lets the operator verify the recommendation is still valid when they read it and gives a rollback baseline. If the state cannot be read, the skill escalates instead of recommending blind.

**Kubernetes-only execution surface.** The skills assume a Kubernetes cluster reachable via `kubectl`. SSH-driven procedures, on-host `docker` shells, on-VM filesystem paths (`/srv/docker/...`), and non-K8s installers (e.g. the `external-logging-installer` Ansible playbook) are out of scope for diagnosis. If the engineer's environment is one of those, the skill stops and hands back rather than guessing.

**HTTP/REST exception to the K8s-only rule.** Endpoints exposed by Graylog and OpenSearch over HTTP — `/api/system/journal`, `/_cluster/health`, `/_cat/indices`, and the rest — are reachable identically regardless of where the server runs (K8s pod, VM, bare-metal). HTTP probes stay in scope and may partially cover VM-deployed Graylog/OpenSearch. The limit is explicit: the skill *only* sees what the HTTP surface returns. If a symptom can only be resolved by inspecting the underlying container (logs, exec, filesystem) and the deployment is not K8s, the skill must recognise it has run out of evidence and hand back to the engineer — never extrapolate cluster-internal state from the HTTP API alone.

---

## 2. Coverage zones

### 2.1. L1 — triage without system access

Implemented as the `logging-l1-triage` skill. It reads a support ticket and decides what should happen next. No access to any live system.

**Input:** ticket text and attachments.

**Allowed:**
- Read the ticket.
- One round of clarifying questions to the author.
- Match the symptom against a curated table of trivial cases.
- Classify by textual signals.

**Forbidden:**
- Any command against a live system.
- Editing configuration.
- Closing the ticket.
- Multi-round interviews.

**Mandatory first axis — symptom scope.** Before any area classification, L1 disambiguates the scope of the symptom along this axis:

| Scope | Meaning |
|---|---|
| `total` | No logs at all from the affected boundary (cluster, namespace, tenant). |
| `partial` | Some logs are missing — by category, by service, by field, by parser. |
| `degraded` | Logs are present but slow, lagging, or out of order. |
| `none` | No log-flow symptom; the ticket is about something else (e.g. UI error, deploy failure with no log claim). |

Scope changes the area. "No logs total" leads toward the collector, network, or destination. "No logs partial" leads toward parsing or routing. "Degraded" leads toward performance and downstream storage. A ticket whose scope cannot be established is bounced back.

**Outcomes:**
- `recommend_resolve` — trivial case, draft a reply, recommend closing. The operator confirms.
- `escalate` — defect with enough information to hand off to L2. The handoff format is fixed (see below).
- `bounce_back` — insufficient information, or the symptom plausibly maps to several areas. One clarifying question.

**Handoff format (L1 → L2).** When L1 escalates, it produces a structured envelope. L2 expects exactly this shape from a ticket-driven entry:

| Field | Purpose |
|---|---|
| Affected application | Which component of the stack (collector, server, store, destination). |
| Version | Stack version. Many patterns are version-bound. |
| Deploy parameters | What was actually deployed (values, flags, profile). |
| Symptom scope | `total` / `partial` / `degraded` / `none` per the L1 axis. |
| Symptom text | Verbatim error text or a description of what the author observes. |
| Job link or job logs | If the path is "something failed during deploy". |
| Chosen area | L1's best guess. May be `ambiguous` with a ranked list. |
| Evidence | What from the ticket supports the chosen area. |

L1 collects these fields from the ticket and the author. Missing required fields trigger `bounce_back`, not `escalate`.

### 2.2. L2 — troubleshooting with system access

L2 is the diagnostic level. It runs against live systems but never mutates them.

**Two co-equal entry points:**

1. **Ticket-driven.** L2 receives the L1 handoff envelope (§2.1). All fields are already present.
2. **Engineer-driven.** The engineer describes the problem in their own words — possibly a single sentence — and lets L2 work. L2 has live access and gathers most of what it needs itself (versions, deploy parameters, pod state, logs). It asks the engineer only for what it cannot derive: business context, recent changes the engineer is aware of, or confirmation of intent before a `recommend`.

Both paths are first-class. The engineer-driven path is the common one during co-debug sessions and local incident investigation; the methodology does not require the engineer to fill out a form before starting.

**Triage before knowledge-area skills.** L2 does not jump into a knowledge-area skill on the first signal. A triage step first inspects the live cluster, identifies the affected area or areas, and only then hands off to the matching knowledge-area skill. This triage role is filled by the `logging-l2-triage` skill. Its internal design — how it scores candidates, how it chains skills, what tables it consults — is out of scope for this document.

**Action tiers:**
- `read-safe` — cheap, idempotent, predictable read commands. Executed automatically.
- `read-heavy` — read-only but potentially expensive or load-inducing. Executed only with explicit caps declared up front (size limit, time window, response cap). If the caps cannot be met the operation is reclassified as `recommend`.
- `recommend` — anything that mutates state. Never executed. Emitted as a structured block: what to do, why, the risk, and how to roll back.

**Forbidden:**
- Mutating actions without a human in the loop.
- Working without a fixed knowledge area.
- Skipping read-before-recommend.

**Ticket artifact:** an audit trail of every executed read command and its output, plus every emitted `recommend` block and its disposition.

---

## 3. Knowledge areas

A **knowledge area** is a topic that requires its own body of expertise to troubleshoot: documentation, diagnostic tooling, characteristic failure patterns, and usually a distinct group of experts. One area maps to one L2 skill. Skill names follow the convention in §5.

**Operational areas** — runtime problems on a deployed system.

| Area | Skill |
|---|---|
| Graylog server | `graylog-server-troubleshoot` |
| OpenSearch / Elasticsearch cluster | `opensearch-troubleshoot` |
| Victoria Logs | `victoria-logs-troubleshoot` |
| MongoDB (Graylog metadata store) | `mongodb-troubleshoot` |
| FluentD | `fluentd-troubleshoot` |
| FluentBit | `fluentbit-troubleshoot` |
| Monitoring stack (Prometheus exporters, Grafana) | `monitoring-troubleshoot` |
| Backup tooling | `backup-troubleshoot` |

**Deployment areas** — failures during installation, upgrade, or reconciliation.

| Area | Skill |
|---|---|
| ArgoCD deployment | `argocd-deployment-troubleshoot` |
| Jenkins deployment | `jenkins-deployment-troubleshoot` |
| Logging operator and Helm chart | `logging-operator-troubleshoot` |

The Ansible VM installer (`external-logging-installer` playbook) deploys Graylog onto a Linux VM via Docker — out of scope per the K8s-only invariant. L1 still recognises tickets pointing at it and routes them out (escalate-to-installer-team), but there is no corresponding L2 knowledge-area skill in this package.

**Narrow investigation skills** — focused, callable both standalone by the engineer and as sub-routines by a knowledge-area skill. They are not full areas; they are reusable diagnostic procedures with a defined input and output.

| Skill | Purpose |
|---|---|
| `graylog-disk-usage-investigate` | Identify which microservices or namespaces produce the bulk of the log volume. Output: ranked breakdown of producers by bytes over a chosen window. |

**Cross-cutting knowledge** is shared across several areas: Kubernetes pod debugging, resource limits and QoS, OpenShift security primitives, TLS and PKI, L7 routing and ingress, GELF protocol mechanics, custom parsers and multiline. Packaged as shared modules loaded by knowledge-area skills on demand. Not invoked directly by the engineer.

---

## 4. End-to-end flow

**Ticket-driven path:**
1. A ticket arrives. The engineer invokes `logging-l1-triage` from their local coding agent (Claude Code, Cursor, OpenCode, Codex, etc.).
2. `logging-l1-triage` disambiguates symptom scope, then returns `recommend_resolve`, `bounce_back`, or `escalate`.
3. On `escalate` the engineer invokes `logging-l2-triage` with the handoff. At this point the engineer's local machine must already have access to the target Kubernetes cluster — `kubectl` and any HTTP endpoints exposed by Graylog / OpenSearch must be reachable from where the coding agent runs; the skill executes commands through that access.
4. `logging-l2-triage` inspects the live cluster and selects a knowledge-area skill.
5. The knowledge-area skill diagnoses, may chain to other skills via `logging-l2-triage`, and ultimately produces a `recommend`.
6. The operator decides on the `recommend`. Execution is manual. Audit trail stays in the ticket.

**Engineer-driven path:**
1. The engineer invokes `logging-l2-triage` directly with a free-form problem description.
2. Steps 4–6 of the ticket-driven path apply.

---

## 5. Skill naming

A skill name is `[<area>-]<target>-<verb>`: an optional area prefix, a target, and a mandatory purpose verb at the end. Verb-last keeps all skills for a given target adjacent in any sorted list (file tree, skill picker, docs index).

- **With area prefix** — `<area>-<target>-<verb>`. Example: `logging-l1-triage`.
- **Without area prefix** — `<target>-<verb>`. Example: `fluentbit-troubleshoot`.

**Purpose verb.** One of:
- `triage` — assess and route. No diagnosis, no fix.
- `troubleshoot` — diagnose within a knowledge area; chain to other skills as needed.
- `investigate` — run a focused, reusable diagnostic procedure with a defined input and output.

The verb is not optional. A skill named after a product alone (e.g. `graylog-server`) does not say what it is for.

**Area prefix.** Used only for high-level skills whose bare name risks colliding with skills from other skill-packs. The prefix is the broad domain of the skill-pack — for the logging-stack pack it is `logging-`.

- High-level skills get the prefix: `logging-l1-triage`, `logging-l2-triage`. Bare `l1-triage` could plausibly exist in a monitoring or database skill-pack.
- Knowledge-area and investigation skills do not get the prefix when the target itself is self-describing: `graylog-server-troubleshoot`, `opensearch-troubleshoot`, `fluentd-troubleshoot`, `graylog-disk-usage-investigate`. "Graylog server" already says which domain.

**Packages** follow the same `<area>-<target>-<verb>` shape when they wrap a single area (e.g. `logging-l1-triage`, `logging-l2-troubleshooting`). The package directory name does not have to equal the name of any skill inside it; a multi-skill package — like `logging-l2-troubleshooting`, which contains `logging-l2-triage`, four `*-troubleshoot` skills, and `graylog-disk-usage-investigate` — is named topically, by what the package is about.

**Examples.**

| Skill | Purpose verb | Area prefix | Target |
|---|---|---|---|
| `logging-l1-triage` | triage | logging | l1 |
| `logging-l2-triage` | triage | logging | l2 |
| `graylog-server-troubleshoot` | troubleshoot | — | graylog-server |
| `fluentbit-troubleshoot` | troubleshoot | — | fluentbit |
| `graylog-disk-usage-investigate` | investigate | — | graylog-disk-usage |

---

## 6. Out of scope

- Internal design of L2 triage (covered separately).
- Content of individual knowledge-area skills.
- Content of trivial-cases tables and runtime-signal tables.
- Knowledge extraction for knowledge areas that do not yet have a reference document.
- Evaluation framework for the skills.
- Evolution of the action tiers beyond `read-safe` / `read-heavy` / `recommend`.
- Ticket deduplication against the ticket-tracker API.
- Non-K8s execution surfaces — VM-deployed Graylog with on-host `docker` shells, SSH-driven procedures, and the `external-logging-installer` Ansible playbook. HTTP/REST endpoints exposed by Graylog and OpenSearch remain in scope per §1 even when the server happens to run outside K8s.
