---
name: logging-l2-triage
description: L2 triage for the Qubership logging stack — runs an initial read-safe diagnostic pass across the live cluster, identifies the affected knowledge area, and invokes the right `troubleshoot-*` or `investigate-*` skill via the Skill tool to continue diagnosis in the same session. Use whenever an engineer reports a live logging-stack problem (Graylog, OpenSearch, FluentD, FluentBit, log volume, "logs not arriving", "Graylog journal full") — even when the area looks obvious from the description, route through this skill first so the routing decision is grounded in what the cluster actually shows, not just words in a ticket. Also use when an L1 handoff envelope lands with `area: ambiguous` or with a primary area that needs confirmation. Read-only; does not diagnose root causes — the area skill you invoke does that.
---

# L2 Triage — logging stack

Figure out which knowledge area to investigate, then invoke that area's skill yourself via the `Skill` tool so the
diagnosis continues in this same session.

Cluster reachability and the K8s-only invariant: see
[references/shared-contract.md](references/shared-contract.md#how-l2-skills-are-invoked).

## Prereq discovery (do not ask the engineer)

`kubectl` context is already attached. Discover what you need from the cluster, do not interrupt the session with
questions about namespaces, endpoints, or credentials:

- Logging namespace: `kubectl get ns | grep -iE 'logging|graylog|opensearch'`
- Service endpoints (Graylog, OpenSearch, log-generator):
  `kubectl get svc -A | grep -iE 'graylog|opensearch|log-generator'`
- Graylog admin password: `kubectl get secret -n <ns> graylog -o jsonpath='{.data.password}' | base64 -d` (fallback:
  chart default `admin:admin`)
- OpenSearch credentials: `kubectl get secret -n <ns> opensearch -o jsonpath='{.data.password}' | base64 -d` (fallback:
  chart default `admin:admin`)
- Graylog/OpenSearch HTTP access: `kubectl port-forward -n <ns> svc/<svc> <local>:<remote>` in the background, then
  `curl http://localhost:<local>/...`

Only if discovery genuinely fails (RBAC denial, missing secret) escalate to the engineer. Never ask for cluster details
as your first action — it dead-ends automated sessions and wastes a turn for a human one.

## Protocol

Read [references/shared-contract.md](references/shared-contract.md) first. Action tiers, read-before-recommend, the
expert output contract. They apply to triage too: do **not** route blind. If the diagnostic pass can't be read, escalate
to the engineer rather than guessing.

You never run `recommend`-tier actions yourself. You also don't run a knowledge-area's heavy diagnostics — that is why
you invoke the area skill at the end. Your scope is the cluster-wide initial diagnostic pass below, plus matching
against `topology.md` and `cited-strings.md`.

## Initial read-safe diagnostic pass

This is the same diagnostic pass regardless of what the engineer said. It produces concrete observations that decide
where to route. Skip individual steps only if the L1 envelope already supplies the equivalent observation — don't
re-collect what's already in evidence.

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
#     graylog-server first (TooLongFrameException is graylog-side).
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
#    skill in this package — see topology.md "Coverage gaps").
kubectl get loggingservice -A
helm list -A | grep -i log
# On an image-pull failure (ErrImagePull / ImagePullBackOff), do not guess the
# corrected tag. Derive it from cluster state: the release's prior working tag
# (helm history <release> -n <ns>), the chart appVersion, or the tag other healthy
# stack pods run. Recommend that derived tag and show the read that produced it.
```

Endpoints in step 3–4: `<graylog>` and `<os-host>` resolve in-cluster (Service / port-forward) or via an externally
exposed route — whichever the engineer's shell has set up. Confirm credentials and reachability before issuing any HTTP
probe.

Capture each command's actual output — those strings are your `evidence` for the handoff.

## Build the ranked candidate list

Read [references/topology.md](references/topology.md) and the diagnostic-pass output above. Produce a ranked list of
expert skills to walk.

1. **Direct hits** — any node whose zone shows concrete signal in the diagnostic pass goes onto the list first, ordered
   by signal strength.
   - **"Cannot reach Graylog" is a collector-side hit.** FluentBit/FluentD logs showing
     `no upstream connections available`, `connection refused …:12201`, or `… timed out` to Graylog are a collector-side
     direct hit — rank `fluentbit-troubleshoot` (or `fluentd-troubleshoot`) first; a starved or misconfigured collector
     emits exactly these strings while Graylog is healthy. Rank `graylog-server-troubleshoot` first only on an
     independent Graylog-side fault: the GELF input is stopped or on the wrong port (`/api/system/inputstates`), Graylog
     pods are not Ready, or Graylog logs show a real input error (e.g. `TooLongFrameException`). Benign Graylog startup
     warnings such as `SO_RCVBUF` / `receiveBufferSize` are not fault signals.
2. **Topology fallback** — if step 1 surfaces nothing, ask "where does the symptom most plausibly originate?" given the
   topology graph, and walk from there in the natural data-flow order
   (`app-pods → fluentbit → fluentd → graylog → opensearch` for "logs not arriving"; reversed for "stored logs
   corrupted").
3. **Coverage check** — drop any candidate whose `skill` field in topology.md is `null` (those zones have no expert in
   this package; if the diagnostic pass clearly points at one, hand back to the engineer per
   [references/topology.md](references/topology.md#coverage-gaps) and stop).

The result is always a list (length ≥ 1). Length 1 = overdetermined case, single hop expected.

## Chain-walk loop

Walk the ranked list top-down, step budget **5 expert invocations** per session. Maintain a `walked` set of expert
skills already invoked in this session (one entry per invocation). For each candidate:

1. Invoke the expert: `Skill({"skill": "<candidate>"})`. The expert returns a prose analysis that names any confirmed
   `symptom_id`, quotes the diagnostic evidence, and may propose a fix. Add `<candidate>` to `walked`. Each invocation
   consumes one of the 5 budgeted slots.
2. If the expert confirmed a symptom and proposed a fix, **STOP**: surface that proposed fix as the final case output.
3. Otherwise apply the routing-policy below to pick the next hop. If the routing-policy yields a hop, prepend it to the
   remaining list and continue from step 1. If the routing-policy yields STOP, exit the loop.
4. If the step budget is exhausted, emit a `manual-diagnosis` recommendation with the audit trail, and stop.

The list is dynamic: routing-policy rule 1 may consume an entry from it, and rules 2 / 3 may prepend a node that was not
originally in it.

## Routing-policy

Apply in order; first match wins. A candidate that equals the current node or is already in `walked` does not match —
fall through to the next rule.

1. **No symptom confirmed** → the expert states no known symptom matched. Prefer the next un-walked candidate already in
   the remaining ranked list. If the ranked list is exhausted, take the current expert's `downstream` node per
   [references/topology.md](references/topology.md); for the terminal `opensearch` node, take `upstream` instead. If the
   chosen neighbour is in `walked`, fall through to step 4.
2. **Evidence cites an external component** → for any pattern in
   [references/cited-strings.md](references/cited-strings.md), match it (regex) against the evidence the expert quotes
   in its prose. First match → next hop is that pattern's `points_to` node. If the `points_to` node equals the current
   node, is in `walked`, or has no expert in this package, fall through to step 3.
3. **The wider prose cites an external component** → same pattern set, applied to the rest of the expert's prose (beyond
   the quoted evidence). Covers the case where the expert recognised a symptom but the cited string appears in its
   broader diagnostic narrative rather than the lines it quoted as evidence. Same fall-through rules as step 2.
4. **Otherwise (or all earlier rules fell through)** → STOP. The expert's analysis is the final result; surface it (and
   any proposed fix) as the case output. If no symptom was confirmed here, escalate to the engineer with the audit trail
   (the chain exhausted its options).

## Internal handoff envelope (mental model only)

```yaml
triage_l2:
  input_shape: ticket | engineer
  candidates:                # ranked, length ≥ 1, walked top-down
    - target_skill: <one of the *-troubleshoot skills>
      derived_from: direct_signal | topology_fallback | cited_strings | topology_neighbour
      confidence: high | medium | low
  diagnostic_pass:           # the read-safe snapshot — every command run, its output, abbreviated
    - command: kubectl get pods -n logging
      output: |
        ...
    - command: curl -sk -u .. https://<graylog>/api/system/journal
      output: |
        ...
  expert_analysis: |         # confirmed symptom_id(s), quoted evidence, proposed fix — as prose
    ...
  diagnostic_digest: |       # broader expert narrative (beyond the quoted evidence lines)
    ...
  notes:                     # partial diagnostic pass, unusual customisation observed, engineer constraints
```

This envelope is an internal scratch pad. It is never the final user-facing output. The final output is either a
proposed fix (from an expert or from `manual-diagnosis`) or an escalation to the engineer.

## What this skill does not do

- Diagnose root causes. That is the expert skill it invokes.
- Execute `recommend` actions.
- Run `read-heavy` queries. Those belong inside an expert skill where they have declared caps.
- Render a multi-step plan to the engineer up front. Surface one hop at a time.
- Route to a node whose `skill` is `null` in topology.md.
