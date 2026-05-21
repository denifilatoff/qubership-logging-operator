# L2 Triage — Design

**Status:** draft v0.1.

L2 triage is a skill that inspects a live troubleshooting session before any knowledge-area skill is invoked. It looks at the cluster, identifies the affected area or areas, and hands off to the matching skill. It does not diagnose root causes itself.

This document describes the internals of L2 triage: why it exists, how it traverses the problem space, what tables it consults, and what it must not do. The broader two-level workflow (L1 triage on tickets, L2 troubleshooting on live systems) is the context but is not described here.

---

## 1. Why L2 triage exists

- A handoff from L1 triage can be ambiguous between several areas.
- Within one area the symptom branches at runtime. "Logs not arriving" splits into CPU throttling, configuration syntax error, OOMKilled worker, an out-of-disk destination, and so on.
- Real cases chain skills. A failed deployment leads into a collector that does not start, which leads into a resource-limit problem. Without L2 triage the engineer would pick the next skill by hand after every step.

---

## 2. Inputs

The L2 triage accepts two input shapes:

1. **Ticket-driven handoff** — a structured envelope from the ticket-side triage carrying affected application, version, deploy parameters, symptom scope, symptom text, optional job link, chosen area (or `ambiguous` with a ranked list), and supporting evidence.
2. **Engineer-driven request** — a free-form problem description. The L2 triage gathers the rest from the live cluster, asking the engineer only for what it cannot derive.

---

## 3. Two levels of traversal

The L2 triage and the knowledge-area skills operate at two different levels of granularity. These are intentionally separated.

**Outer graph — across skills.** Owned by the L2 triage. Nodes are skills. Edges fire on the artefact returned by the previous skill. The L2 triage decides which skill to invoke next, when to stop, and when to escalate to a human.

**Inner funnel — within a skill.** Owned by the knowledge-area skill. A sequence of read-safe drills that narrows down the cause inside the skill's area. The L2 triage does not see the funnel — only the final artefact the skill returns.

Example. The engineer reports degraded throughput. The L2 triage picks the Graylog server skill. That skill internally walks: check API status → if throttled, check which buffer (input / processing / output) → if output, check the downstream store's disk metrics. All of that is one invocation. The skill returns one of: `resolved`, `hypothesis_refuted`, or `new_symptom`. Only then the L2 triage re-evaluates the outer graph.

---

## 4. Internal graph (outer)

The L2 triage holds a lazy graph of nodes. Each node carries:
- the skill to invoke,
- the entry symptom that justifies invoking it,
- the artefact expected back,
- a successor for the case where the hypothesis is confirmed,
- a successor for the case where it is refuted.

The graph is recomputed after every step using the latest evidence. The engineer sees only the current step — which skill is being invoked, which symptom it is testing, which artefact is expected. The full graph stays internal. The engineer is not asked to approve a multi-step plan up front.

---

## 5. Decision flow

```
INPUT: handoff envelope OR free-form engineer request

Step 1  Parse input.
        Single area in input  → primary hypothesis.
        Ambiguous area        → ranked hypothesis list.
        Free-form request     → derive a quick classification from the text
                                and from a minimal read-safe probe.

Step 2  Run a minimal read-safe envelope to validate the area
        AND probe for customisation. Customisation probes check whether
        the installation deviates from the vanilla configuration:
          - custom index mappings on the storage,
          - custom outputs on the collectors,
          - network policies in the affected namespaces,
          - custom Helm values that change topology.
        Customisation findings re-rank the hypothesis list.

Step 3  Match runtime signals to the L2 triage table.
        Rank candidates by (match strength × prior probability).
        One strong match    → Step 4 with that skill.
        Several candidates  → take the top, keep the rest as refutation
                              successors.
        No match            → emit recommend for manual diagnosis; END.

Step 4  Invoke the chosen knowledge-area skill with the collected evidence.
        It runs its inner funnel and returns one of:
        resolved | hypothesis_refuted | new_symptom.

Step 5  Re-evaluate.
        resolved           → emit final recommend + audit trail; END.
        hypothesis_refuted → next refutation successor; Step 4.
        new_symptom        → recompute, Step 3.
        N hops without progress → escalate to a human; END.
```

---

## 6. Runtime-signal table

The L2 triage's signals are outputs of `read-safe` commands — what the live system shows. This is what makes the L2 triage distinct from the ticket-side triage, which matches against ticket text.

Each row carries a **prior**: the SME-observed base rate of this signal corresponding to the listed cause. Priors come from the SME owner of the corresponding area. The L2 triage ranks candidates by `match × prior`, not by match alone.

The table is filled iteratively as knowledge-area skills are written. First-round seed:

| Runtime signal | Command | Target skill | Prior |
|---|---|---|---|
| Pod in `CrashLoopBackOff` in the logging namespace | `kubectl get pods -n logging` | FluentD or FluentBit (per pod label) | high |
| OpenSearch cluster status RED with unassigned shards | `curl /_cluster/health` | OpenSearch cluster | high |
| Graylog host disk at 95% or more | `df -h` on the Graylog host | Graylog server (then `investigate-graylog-disk-usage`) | high |
| Helm release status `failed` or `pending-upgrade` | `helm list -A` | Helm / operator | medium |
| CI job failed at install stage | CI platform API | ArgoCD or Jenkins deployment (per job source) | high |
| FluentD pod recently OOMKilled | `kubectl describe pod` | FluentD | high |
| Graylog UI returns 502 while the container is running | `curl <url>` + `docker ps` | Graylog server | medium |
| MongoDB connection errors in Graylog logs | `docker logs graylog` | MongoDB | medium |
| Graylog output buffer growing, journal utilisation rising | Graylog API status | Graylog server (downstream-store sub-funnel) | high |

The authoritative table lives alongside the L2 triage skill once created.

---

## 7. What the L2 triage does not do

- Diagnose the root cause. That is the knowledge-area skill's job.
- Execute any `recommend` action.
- Run `read-heavy` commands outside a knowledge-area skill's declared caps.
- Render the full multi-step plan to the engineer.

---

## 8. Open questions

- **Artefact schema.** Exact structure a knowledge-area skill returns to the L2 triage for `resolved | hypothesis_refuted | new_symptom`. Must be fixed before the first knowledge-area skill is written.
- **Evidence passing.** Send the full accumulated audit trail to each invoked skill, or only the slice relevant to its area. Full is simpler but bloats context.
- **Step budget.** How many outer-graph hops before escalation to a human. Candidate: five to seven, validated against real cases.
- **Prior calibration.** Initial priors will be SME estimates. Need a feedback loop to update them from observed outcomes — schema and cadence to be defined.
