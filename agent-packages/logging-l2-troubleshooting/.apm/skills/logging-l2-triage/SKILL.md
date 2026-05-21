---
name: logging-l2-triage
description: L2 triage for the Qubership logging stack — runs an initial read-safe sweep across the live cluster, identifies the affected knowledge area, and hands off to the right `troubleshoot-*` or `investigate-*` skill. Use whenever an engineer reports a live logging-stack problem (Graylog, OpenSearch, FluentD, FluentBit, log volume, "logs not arriving", "Graylog journal full") — even when the area looks obvious from the description, route through this skill first so the routing decision is grounded in what the cluster actually shows, not just words in a ticket. Also use when an L1 handoff envelope lands with `area: ambiguous` or with a primary area that needs confirmation. Read-only; does not diagnose root causes — that is the downstream skill's job.
---

# L2 Triage — logging stack

You are the router between the engineer's complaint and the right knowledge-area skill. Your job is to **figure out which area to investigate**, not to investigate it. The downstream `troubleshoot-*` / `investigate-*` skill does the actual diagnosis and proposes the fix.

Two entry shapes — same flow:

1. **Ticket-driven** — an L1 handoff envelope (affected app, version, deploy params, symptom scope, symptom text, chosen area or `ambiguous`).
2. **Engineer-driven** — a free-form sentence like "logs from service X disappeared", "Graylog is slow", "who's flooding the disk this time".

The target cluster is already reachable from the current shell (`kubectl`, OpenSearch API, Graylog API, or SSH to the Logging VM — whichever applies to the deployment).

## Protocol

Read [references/shared-contract.md](references/shared-contract.md) first. Action tiers, read-before-recommend, recommend-block schema. They apply to triage too: do **not** route blind. If the sweep can't be read, escalate to the engineer rather than guessing.

You never run `recommend`-tier actions yourself. You also don't run a knowledge-area's heavy diagnostics — that is what handing off is for. Your scope is the cluster-wide initial sweep below, plus matching against the signal table.

## Initial read-safe sweep

This is the same sweep regardless of what the engineer said. It produces concrete observations that decide where to route. Skip individual steps only if the L1 envelope already supplies the equivalent observation — don't re-collect what's already in evidence.

Adapt commands to the deployment shape (Kubernetes vs Logging VM); each section says how.

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

# 4. OpenSearch cluster health and disk. RED status / unassigned shards / read-only flags
#    each route to troubleshoot-opensearch with high prior.
curl -sk -u <u>:<p> https://<os-host>:9200/_cluster/health?pretty
curl -sk -u <u>:<p> https://<os-host>:9200/_cat/allocation?v
curl -sk -u <u>:<p> 'https://<os-host>:9200/_cat/indices?v&s=store.size:desc' | head -20

# 5. Disk pressure. On VM deployments, df -h on the Graylog host is the canonical probe
#    for "HDD Full". On K8s, look at the PVC or the node.
ssh <graylog-vm> df -h                                     # VM deployment
kubectl -n <ns> describe pvc <graylog-pvc>                 # K8s deployment

# 6. Operator / Helm state. A LoggingService in a bad reconcile state, or a Helm release
#    in failed/pending state, redirects to the deployment area (not yet covered by a
#    skill in this package — see signal-table.md "Areas not covered yet").
kubectl get loggingservice -A
helm list -A | grep -i log
```

What "deployment shape" means in step 3–5:

- **Kubernetes** — Graylog and OpenSearch run as pods, reachable through Services or port-forward; `<graylog>` and `<os-host>` resolve in-cluster.
- **Logging VM (Docker)** — `<graylog>` is the VM's hostname or vIP; `<os-host>` is the same VM on port 9200 (storage container).
- Confirm which shape the engineer is on before running anything. The L1 envelope's `Deploy parameters` field usually says.

Capture each command's actual output — those strings are your `evidence` for the handoff.

## Routing

Match the observations against [references/signal-table.md](references/signal-table.md). That file has the symptom → target-skill mapping with priors. Do not paraphrase it back into this SKILL; load it on demand and cite the rows you matched.

Decision rules (also in the signal table):

- **One row fires** → that's the target skill. Hand off (schema below).
- **Multiple rows, same target** → still that target; case is over-determined, raise confidence.
- **Multiple rows, different targets** → rank by `match strength × prior`. Primary = top; the rest become refutation successors.
- **No row fires** after a complete sweep → emit a `recommend` for manual diagnosis with the full sweep attached, and stop. Do not route to "the closest skill".
- **Sweep partially blocked** (RBAC, endpoint down) → escalate to the engineer; do not route blind.

## Handoff output

Emit exactly this shape, then stop. Do not invoke the downstream skill yourself — the engineer (or the runtime, depending on the agent) does that, with this artefact as the input.

```yaml
triage_l2:
  input_shape: ticket | engineer
  primary:
    target_skill: troubleshoot-fluentbit | troubleshoot-fluentd | troubleshoot-graylog-server | troubleshoot-opensearch | investigate-graylog-disk-usage
    signals_matched:
      - row: <verbatim "Runtime signal observed" cell from signal-table.md>
        evidence: |
          <verbatim command output that matched, trimmed to the relevant lines>
        prior: high | medium | low
    confidence: high | medium | low
  alternatives:           # refutation successors, ranked. Empty list if primary is unique.
    - target_skill: ...
      signals_matched: [...]
      confidence: ...
  sweep:                  # the read-safe snapshot — every command run, its output, abbreviated.
    - command: kubectl get pods -n logging
      output: |
        ...
    - command: curl -sk -u .. https://<graylog>/api/system/journal
      output: |
        ...
  notes:                  # anything the downstream skill should know — partial sweep,
                          # unusual customisation observed, engineer's stated constraints.
```

## After the downstream skill returns

The knowledge-area skill returns one of:

- `resolved` — emit the recommendation chain it produced, append the audit trail (sweep + downstream's snapshots + every emitted `recommend` and its disposition), stop.
- `hypothesis_refuted` — go back to the alternatives list. Pick the next refutation successor. If empty, recompute against the signal table with the new evidence in hand.
- `new_symptom` — recompute from Step 3 of the methodology decision flow: re-match the signal table with the additional evidence.

Step budget: **5 outer-graph hops**. If you've handed off five times without `resolved`, escalate to a human with the accumulated audit trail. Spinning is worse than admitting the case is harder than the table covers.

## What this skill does not do

- Diagnose root causes. That's the knowledge-area skill.
- Execute `recommend` actions.
- Run `read-heavy` queries (large `_search`, full index listings, full log dumps). Those belong inside a knowledge-area skill where they have declared caps.
- Render a multi-step plan to the engineer up front. Surface one hop at a time — the cluster's actual responses change the next decision.
- Route to an area that doesn't have a skill in this package yet. If the sweep clearly points at MongoDB / monitoring / a deployment-time failure, hand back to the engineer with the observation and stop (see signal-table.md "Areas not covered yet").
