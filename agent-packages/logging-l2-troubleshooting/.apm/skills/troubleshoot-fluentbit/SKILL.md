---
name: troubleshoot-fluentbit
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

If the symptom is not in the catalogue, do **not** invent a solution. Report what you observed, suggest the adjacent area that might own it (FluentD buffer, Graylog GELF input, network path), and stop. Adding new patterns means editing `docs/troubleshooting/fluentbit.md` in the operator repo first.
