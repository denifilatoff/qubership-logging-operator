# 2. Triage methodology

This document defines what the **triage and troubleshooting** skills in a domain package actually _do_. It describes the
two support levels (L1 and L2), the invariants that apply to both, the action tiers an L2 skill is allowed to use, the
handoff shape between L1 and L2, and the naming convention that keeps the resulting skill set navigable. (Skills for
coding, testing, refactoring, or other software-engineering work are out of scope; the conventions below assume the goal
is to assess, route, and diagnose a production issue.)

The skills are delivered as Agent Skills under the APM standard. An engineer runs them from a local coding agent (Claude
Code, Cursor, OpenCode, Codex, Gemini CLI) — there is no separate orchestrator agent. Each level is itself a skill,
validated by engineer-driven use before being handed to an autonomous agent for unattended ticket triage. The skills
support both modes without forking.

## 2.1. Invariants

These rules apply at every level and override any local convenience.

**Do-no-harm.** No skill executes a mutating action against a live system or against the ticket-tracker. Mutations are
emitted as structured `recommend` blocks; the operator decides whether and when to apply them.

**Read-before-recommend.** A `recommend` is a proposed mutation. Before emitting it, the skill captures a read-safe
snapshot of the state on which the recommendation depends and attaches that snapshot to the block. The snapshot is _what
the action mutates plus what proves the action is still needed_ — not the whole namespace. It lets the operator verify
the recommendation is still valid when they read it, and gives a rollback baseline. If the state cannot be read, the
skill escalates instead of recommending blind.

**References, not duplication.** Domain troubleshooting knowledge — symptoms, signs, solutions — lives in dedicated
reference documents. A skill does not copy content from a reference into itself; it loads the relevant slice on demand.
Adding a new pattern means adding it to the appropriate reference first, then linking it from the skill.

**Lookups by grep, not by retrieval.** References are searched with `grep` and `Read`, not retrieved from a vector
store. The skill body describes the shape of each reference it depends on (which columns exist, what the row key is,
what to search by) so the agent can query a reference it has never opened before. This forces references to be designed
for deterministic lookup: stable headings, predictable layouts, searchable keys. No out-of-package state, no offline
indexing step.

**Kubernetes-only execution surface.** Skills assume a Kubernetes cluster reachable via `kubectl`. SSH-driven
procedures, on-host `docker` shells, on-VM filesystem paths, and non-K8s installers are out of scope. If the engineer's
environment is one of those, the skill stops and hands back rather than guessing.

**HTTP/REST exception.** Endpoints exposed by a backend over HTTP — health APIs, cluster-state APIs, admin APIs — are
reachable identically regardless of where the server runs. HTTP probes stay in scope and may partially cover VM-deployed
backends. The limit is explicit: the skill _only_ sees what the HTTP surface returns. If a symptom can only be resolved
by inspecting the underlying container (logs, exec, filesystem) and the deployment is not K8s, the skill must recognise
it has run out of evidence and hand back to the engineer.

## 2.2. L1 — triage without system access

L1 reads a support ticket and decides what should happen next. It has **no access to any live system**: no `kubectl`, no
SSH, no API calls.

**Input.** Ticket text and attachments.

**Allowed.**

- Read the ticket.
- One round of clarifying questions to the author.
- Match the symptom against a curated table of trivial cases.
- Classify by textual signals.

**Forbidden.**

- Any command against a live system.
- Editing configuration.
- Closing the ticket.
- Multi-round interviews.

**Mandatory first axis — symptom scope.** Before any area classification, L1 disambiguates the scope of the symptom
along this axis:

| Scope      | Meaning                                                                   |
| ---------- | ------------------------------------------------------------------------- |
| `total`    | No signal at all from the affected boundary (cluster, namespace, tenant). |
| `partial`  | Some signal is missing — by category, by service, by field.               |
| `degraded` | Signal is present but slow, lagging, or out of order.                     |
| `none`     | No domain symptom; the ticket is about something else.                    |

Scope changes the area. "Total absence" leads toward the collector, network, or destination. "Partial absence" leads
toward parsing or routing. "Degraded" leads toward performance and downstream storage. A ticket whose scope cannot be
established is bounced back.

**Outcomes.**

- `recommend_resolve` — trivial case; draft a reply, recommend closing. The operator confirms; the skill never closes
  tickets itself.
- `escalate` — defect with enough information to hand off to L2. Uses the fixed handoff envelope below.
- `bounce_back` — insufficient information, or symptom plausibly maps to several areas. One clarifying question.

**Handoff envelope (L1 → L2).** When L1 escalates, it produces a structured envelope. L2 expects exactly this shape from
a ticket-driven entry:

| Field                | Purpose                                                               |
| -------------------- | --------------------------------------------------------------------- |
| Affected component   | Which component of the stack (collector, server, store, destination). |
| Version              | Stack version. Many patterns are version-bound.                       |
| Deploy parameters    | What was actually deployed (values, flags, profile).                  |
| Symptom scope        | `total` / `partial` / `degraded` / `none`.                            |
| Symptom text         | Verbatim error text or a description of what the author observes.     |
| Job link or job logs | If the path is "something failed during deploy".                      |
| Chosen area          | L1's best guess. May be `ambiguous` with a ranked list.               |
| Evidence             | What from the ticket supports the chosen area.                        |

Missing required fields trigger `bounce_back`, not `escalate`.

## 2.3. L2 — troubleshooting with system access

L2 is the diagnostic level. It runs against live systems but never mutates them.

**Two co-equal entry points.**

1. **Ticket-driven.** L2 receives the L1 handoff envelope. All fields are already present.
2. **Engineer-driven.** The engineer describes the problem in their own words — possibly a single sentence — and lets L2
   work. L2 has live access and gathers most of what it needs itself (versions, deploy parameters, pod state, logs). It
   asks only for what it cannot derive: business context, recent changes the engineer is aware of, confirmation of
   intent before a `recommend`.

Both paths are first-class. The engineer-driven path is the common one during co-debug sessions and local incident
investigation; the methodology does not require the engineer to fill out a form before starting.

**Triage before knowledge-area skills.** L2 does not jump into a knowledge-area skill on the first signal. A triage step
first inspects the live cluster, identifies the affected area or areas, and only then hands off to the matching
knowledge-area skill.

**Action tiers.**

| Tier         | Behaviour                                                                                                                                                                                                              |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `read-safe`  | Cheap, idempotent, predictable read commands. Executed automatically.                                                                                                                                                  |
| `read-heavy` | Read-only but potentially expensive or load-inducing. Executed only with explicit caps declared up front (size limit, time window, response cap). If caps cannot be met, the operation is reclassified as `recommend`. |
| `recommend`  | Anything that mutates state. **Never executed.** Emitted as a structured block: what to do, why, the risk, how to roll back.                                                                                           |

**Forbidden.**

- Mutating actions without a human in the loop.
- Working without a fixed knowledge area.
- Skipping read-before-recommend.

**Ticket artefact.** An audit trail of every executed read command and its output, plus every emitted `recommend` block
and its disposition.

## 2.4. End-to-end flow

**Ticket-driven path.**

1. A ticket arrives. The engineer invokes the domain's L1 triage skill from their local coding agent.
2. L1 disambiguates symptom scope, then returns `recommend_resolve`, `bounce_back`, or `escalate`.
3. On `escalate` the engineer invokes the L2 triage skill with the handoff. At this point the engineer's local machine
   must already have access to the target Kubernetes cluster — the skill executes commands through that access.
4. L2 triage inspects the live cluster and selects a knowledge-area skill.
5. The knowledge-area skill diagnoses, may chain to other skills via L2 triage, and ultimately produces a `recommend`.
6. The operator decides on the `recommend`. Execution is manual. Audit trail stays in the ticket.

**Engineer-driven path.** The engineer invokes L2 triage directly with a free-form description; steps 4–6 above apply.

## 2.5. Skill naming convention

A skill name is `[<area>-]<target>-<verb>`: an optional area prefix, a target, and a **mandatory purpose verb at the
end**. Verb-last keeps all skills for a given target adjacent in any sorted list (file tree, skill picker, docs index).

**Purpose verb.** One of:

- `triage` — assess and route. No diagnosis, no fix.
- `troubleshoot` — diagnose within a knowledge area; chain to other skills as needed.
- `investigate` — run a focused, reusable diagnostic procedure with a defined input and output.

The verb is not optional. A skill named after a product alone (e.g. `graylog-server`) does not say what it is for.

**Area prefix.** Used only for high-level skills whose bare name risks colliding with skills from other domain packages.
The prefix is the broad domain — `logging-`, `monitoring-`, `tracing-`, …

- High-level skills get the prefix: `logging-l1-triage`, `monitoring-l2-triage`. Bare `l1-triage` could plausibly exist
  in any domain.
- Knowledge-area and investigation skills do not get the prefix when the target itself is self-describing:
  `prometheus-troubleshoot`, `jaeger-troubleshoot`, `postgres-troubleshoot`. The product name already says which domain.

**Examples.**

| Skill                            | Verb         | Area prefix | Target             |
| -------------------------------- | ------------ | ----------- | ------------------ |
| `logging-l1-triage`              | triage       | logging     | l1                 |
| `monitoring-l2-triage`           | triage       | monitoring  | l2                 |
| `prometheus-troubleshoot`        | troubleshoot | —           | prometheus         |
| `graylog-disk-usage-investigate` | investigate  | —           | graylog-disk-usage |

**Packages** follow the same shape when they wrap a single area (`logging-l1-triage`). A multi-skill package is named
topically by what the package is about (`logging-l2-troubleshooting` contains `logging-l2-triage` plus several
`*-troubleshoot` skills) — the package directory name does not have to equal any skill inside it.
