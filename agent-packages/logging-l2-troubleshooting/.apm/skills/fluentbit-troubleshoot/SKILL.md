---
name: fluentbit-troubleshoot
description: Diagnose FluentBit problems in the Qubership logging stack — connection failures to Graylog, stuck pipelines, dropped or delayed logs, ConfigMap reload failures. Use when symptoms point at the FluentBit DaemonSet (forwarder or aggregator). Read-only against the live cluster; mutations go out as `recommend` blocks, never executed.
---

# Troubleshoot FluentBit

You are the L2 troubleshooting skill for the **FluentBit** knowledge area. Entry points: a handoff from `logging-l2-triage`, or an engineer invoking you directly during a co-debug session. The target cluster is already reachable from the current shell.

Your job: diagnose, propose a fix as a `recommend` block, stop. You never mutate the cluster.

## Protocol

Read [references/shared-contract.md](references/shared-contract.md) before doing anything else. It defines the `read-safe` / `read-heavy` / `recommend` tiers, the read-before-recommend rule, and the exact `recommend` block schema. Every action you take in this skill is governed by it.

## First read-safe sweep

Gather baseline state before consulting the symptom catalogue. Skip steps already covered by the L1 handoff envelope (don't re-collect what the engineer already gave you).

```bash
# FluentBit workload(s). Name varies: standard DaemonSet vs forwarder/aggregator HA.
kubectl -n <ns> get ds,sts -l app.kubernetes.io/name=fluentbit -o wide

# Pod-level health.
kubectl -n <ns> get pods -l app.kubernetes.io/name=fluentbit -o wide
kubectl -n <ns> describe pod <pod>     # restart count, last-state reason, OOM, evictions

# Recent error tail. Cap at 500 lines per pod unless you have a reason to go wider.
kubectl -n <ns> logs <pod> --tail=500 | grep -iE 'error|warn|stuck|timeout|gelf'

# Effective configuration.
kubectl -n <ns> get cm logging-fluentbit -o yaml

# Resource limits — most frequent root cause for connection timeouts to Graylog.
kubectl -n <ns> get pod <pod> -o jsonpath='{.spec.containers[*].resources}'
```

Whatever you actually observe becomes the `evidence` field on any `recommend` you emit.

## Symptom catalogue

Match the report against [references/symptoms.md](references/symptoms.md). That file is the canonical catalogue — patterns, root causes, fixes. Do not paraphrase it back into this SKILL; load it on demand and cite the section you used.

Adding new patterns means editing `docs/troubleshooting/fluentbit.md` in the operator repo first; do not invent a solution to retrofit into this skill.

## Zone definition (for the refute contract)

See the [Hypothesis refute](references/shared-contract.md#hypothesis-refute) section in the shared contract for the output shape and triage semantics. The FluentBit zone is **clean** — and you must refute rather than recommend — when all of these hold:

- DaemonSet/StatefulSet pods are `Running`, no `CrashLoopBackOff`, no recent OOMKilled / Evicted in `describe`.
- `kubectl logs --tail=500` has no FluentBit-side errors (parser failures, ConfigMap reload failures, plugin init errors, internal panics).
- Resource limits are not throttling the workload (CPU throttling stats clean, memory headroom).
- The output endpoint (Graylog / FluentBit aggregator / etc.) is reachable from the pod.
- Any quoted downstream error in FluentBit logs (e.g. an OpenSearch flood-stage message surfaced from Graylog) names another area as the actual owner — set `likely_downstream_area` accordingly.
