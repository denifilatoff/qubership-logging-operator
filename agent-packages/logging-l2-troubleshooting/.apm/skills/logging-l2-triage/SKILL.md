---
name: logging-l2-triage
description: L2 triage for the Qubership logging stack — runs an initial read-safe diagnostic pass across the live cluster, identifies the affected knowledge area, and invokes the right `troubleshoot-*` or `investigate-*` skill via the Skill tool to continue diagnosis in the same session. Use whenever an engineer reports a live logging-stack problem (Graylog, OpenSearch, FluentD, FluentBit, log volume, "logs not arriving", "Graylog journal full") — even when the area looks obvious from the description, route through this skill first so the routing decision is grounded in what the cluster actually shows, not just words in a ticket. Also use when an L1 handoff envelope lands with `area: ambiguous` or with a primary area that needs confirmation. Read-only; does not diagnose root causes — the area skill you invoke does that.
---

# L2 Triage — logging stack

Figure out which knowledge area to investigate, then invoke that area's skill yourself via the `Skill` tool so the diagnosis continues in this same session.

Cluster reachability and the K8s-only invariant: see [references/shared-contract.md](references/shared-contract.md#how-l2-skills-are-invoked).

## Prereq discovery (do not ask the engineer)

`kubectl` context is already attached. Discover what you need from the cluster, do not interrupt the session with questions about namespaces, endpoints, or credentials:

- Logging namespace: `kubectl get ns | grep -iE 'logging|graylog|opensearch'`
- Service endpoints (Graylog, OpenSearch, log-generator): `kubectl get svc -A | grep -iE 'graylog|opensearch|log-generator'`
- Graylog admin password: `kubectl get secret -n <ns> graylog -o jsonpath='{.data.password}' | base64 -d` (fallback: chart default `admin:admin`)
- OpenSearch credentials: `kubectl get secret -n <ns> opensearch -o jsonpath='{.data.password}' | base64 -d` (fallback: chart default `admin:admin`)
- Graylog/OpenSearch HTTP access: `kubectl port-forward -n <ns> svc/<svc> <local>:<remote>` in the background, then `curl http://localhost:<local>/...`

Only if discovery genuinely fails (RBAC denial, missing secret) escalate to the engineer. Never ask for cluster details as your first action — it dead-ends automated sessions and wastes a turn for a human one.

## Protocol

Read [references/shared-contract.md](references/shared-contract.md) first. Action tiers, read-before-recommend, recommend-block schema. They apply to triage too: do **not** route blind. If the diagnostic pass can't be read, escalate to the engineer rather than guessing.

You never run `recommend`-tier actions yourself. You also don't run a knowledge-area's heavy diagnostics — that is why you invoke the area skill at the end. Your scope is the cluster-wide initial diagnostic pass below, plus matching against the signal table.

## Initial read-safe diagnostic pass

This is the same diagnostic pass regardless of what the engineer said. It produces concrete observations that decide where to route. Skip individual steps only if the L1 envelope already supplies the equivalent observation — don't re-collect what's already in evidence.

All commands below assume Kubernetes plus HTTP access to Graylog and OpenSearch.

```bash
# 1. Logging-namespace pod state. Disambiguates collector failures (FluentBit / FluentD)
#    from server-side failures (Graylog / OpenSearch) immediately.
kubectl get pods -n <ns> -o wide
kubectl get pods -n <ns> --field-selector=status.phase!=Running
kubectl get events -n <ns> --sort-by=.lastTimestamp | tail -30

# 2. Recent restarts / OOM / evictions on the suspect pods (only ones that look unhealthy
#    from step 1; don't describe every pod).
kubectl describe pod <pod>     # look at LastState.terminated.reason, RestartCount

# 3. Graylog API status — journal, processing, cluster nodes. The single most informative
#    Graylog-side probe; many symptoms are "journal full" downstream of something else.
curl -sk -u <u>:<p> https://<graylog>/api/system/journal
curl -sk -u <u>:<p> https://<graylog>/api/system/cluster/nodes
curl -sk -u <u>:<p> https://<graylog>/api/system/inputstates

# 3b. Graylog input-side errors. Catches GELF frame-size drops and similar
#     input-parser issues that don't surface in /api/system/* but explain
#     "logs not arriving" without any collector-side failure. Routes to
#     graylog-server first via the signal-table row for TooLongFrameException.
kubectl -n <ns> logs <graylog-pod> --tail=500 | grep -iE 'TooLongFrame|max_message_size|drop'

# 4. OpenSearch cluster health and disk. RED status / unassigned shards / read-only flags
#    each route to opensearch-troubleshoot with high prior.
curl -sk -u <u>:<p> https://<os-host>:9200/_cluster/health?pretty
curl -sk -u <u>:<p> https://<os-host>:9200/_cat/allocation?v
curl -sk -u <u>:<p> 'https://<os-host>:9200/_cat/indices?v&s=store.size:desc' | head -20

# 5. Disk pressure. Look at the PVC backing Graylog/OpenSearch and node-level disk
#    pressure conditions. OpenSearch's own /_cat/allocation (step 4) is the most
#    informative probe for the cluster-side view.
kubectl -n <ns> get pvc
kubectl -n <ns> describe pvc <graylog-pvc>
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}: {.status.conditions[?(@.type=="DiskPressure")].status}{"\n"}{end}'

# 6. Operator / Helm state. A LoggingService in a bad reconcile state, or a Helm release
#    in failed/pending state, redirects to the deployment area (not yet covered by a
#    skill in this package — see signal-table.md "Areas not covered yet").
kubectl get loggingservice -A
helm list -A | grep -i log
```

Endpoints in step 3–4: `<graylog>` and `<os-host>` resolve in-cluster (Service / port-forward) or via an externally exposed route — whichever the engineer's shell has set up. Confirm credentials and reachability before issuing any HTTP probe.

Capture each command's actual output — those strings are your `evidence` for the handoff.

## Routing — build the ranked candidate list

Match the observations against [references/signal-table.md](references/signal-table.md). That file has the symptom → target-skill mapping with priors, the downstream-error-in-upstream-log principle, and class-level fallback chains. Do not paraphrase it back into this SKILL; load it on demand and cite the rows or principles you matched.

The output of routing is always a **ranked list of candidates** (length ≥ 1), not a single pick. Build it in this order:

1. Rows from the seed table whose signals fired in the diagnostic pass, ranked by `match strength × prior`.
2. Plus any area named by the downstream-error-in-upstream-log principle, even when the row-based probe wasn't run.
3. If steps 1–2 yield nothing but the symptom matches a class in the fallback-chains table → use that chain verbatim.
4. If still nothing → don't invent a target. Emit a `recommend` for manual diagnosis with the full diagnostic pass attached, and stop.

A list of length 1 is the overdetermined case: confirm-or-recommend, no fallback.

## Chain of hypotheses

The candidate list is walked top-down by a single loop:

```
for candidate in ranked_list:
    Skill({"skill": candidate})
    if candidate emitted a recommend:
        finish — emit recommend for that cause, stop
    if candidate returned hypothesis_refuted:
        switch signal_class:
          clean:                  continue with the next candidate already in ranked_list
          secondary_backpressure: find immediate downstream of <candidate> per topology table;
                                  if not yet walked, prepend to remaining list;
                                  else walk one more hop downstream
          secondary_quoted:       for each entry in cited_external_components, look up the cited-string map;
                                  prepend each match to the remaining list;
                                  if no match, treat as clean
        continue
    if step budget exhausted:
        break
emit a recommend for manual diagnosis with the full audit trail, stop
```

Rules:

- **Found the cause → stop.** As soon as any area skill produces a recommend backed by evidence of an actual root cause in its zone, the case is done. Do not walk the rest of the list "for completeness". Extra invocations cost a diagnostic pass each and risk noise.
- **Refute → route per `signal_class`.** Each `hypothesis_refuted` carries a `signal_class`: `clean` advances the existing list; `secondary_backpressure` and `secondary_quoted` may insert new candidates derived from the stack topology and the cited-string map in `signal-table.md`. Treat all three as legitimate advance signals — don't stop early because the next candidate wasn't in the original ranked list.
- **Step budget: 5 area-skill invocations per session.** Most chains converge in 1–2 hops; the budget is for cases where the symptom is genuinely ambiguous across the stack. After 5 refutes, the case is harder than the catalogue covers — escalate.
- **Don't shop.** "Try the next skill just in case" is not the contract. Advance only on refute or budget exhaustion.

Advance the chain with `Skill({"skill": "<candidate>"})`. After the call, continue in your own voice, applying that area skill's protocol with the diagnostic pass evidence already in your context.

**Do not end on a "handoff envelope" message.** Emit a YAML envelope only as an internal note to organise what you carry into each area skill — never as the final user-facing output.

### Internal mental model (what to carry into the area skill)

```yaml
triage_l2:
  input_shape: ticket | engineer
  candidates:             # ranked list, length ≥ 1. Walked top-down by the loop above.
    - target_skill: fluentbit-troubleshoot | fluentd-troubleshoot | graylog-server-troubleshoot | opensearch-troubleshoot | graylog-disk-usage-investigate
      signals_matched:
        - row: <verbatim "Runtime signal observed" cell, OR "downstream-error: <quoted phrase>", OR "fallback-chain: <class>">
          evidence: |
            <verbatim command output or quoted log line, trimmed to the relevant lines>
          prior: high | medium | low
      confidence: high | medium | low
  diagnostic_pass:                  # the read-safe snapshot — every command run, its output, abbreviated.
    - command: kubectl get pods -n logging
      output: |
        ...
    - command: curl -sk -u .. https://<graylog>/api/system/journal
      output: |
        ...
  notes:                  # partial diagnostic pass, unusual customisation observed, engineer constraints.
```

## What this skill does not do

- Diagnose root causes. That's the knowledge-area skill.
- Execute `recommend` actions.
- Run `read-heavy` queries (large `_search`, full index listings, full log dumps). Those belong inside a knowledge-area skill where they have declared caps.
- Render a multi-step plan to the engineer up front. Surface one hop at a time — the cluster's actual responses change the next decision.
- Route to an area that doesn't have a skill in this package yet. If the diagnostic pass clearly points at MongoDB / monitoring / a deployment-time failure, hand back to the engineer with the observation and stop (see signal-table.md "Areas not covered yet").
