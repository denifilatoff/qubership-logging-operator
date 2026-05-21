---
name: troubleshoot-fluentd
description: Diagnose FluentD problems in the Qubership logging stack — worker OOM kills, sustained DiskIO read load, GELF UDP "data too big / 128 chunks" buffer flush failures, ConfigMap-reloader-driven restarts. Use when symptoms point at the FluentD DaemonSet. Read-only against the live cluster; mutations go out as `recommend` blocks, never executed.
---

# Troubleshoot FluentD

You are the L2 troubleshooting skill for the **FluentD** knowledge area. Entry points: a handoff from `logging-l2-triage`, or an engineer invoking you directly. The target cluster is already reachable from the current shell.

Your job: diagnose, propose a fix as a `recommend` block, stop. You never mutate the cluster.

## Protocol

Read [references/shared-contract.md](references/shared-contract.md) first. It defines `read-safe` / `read-heavy` / `recommend` tiers, the read-before-recommend rule, and the `recommend` block schema. Every action you take is governed by it.

## First read-safe sweep

```bash
# Workload. FluentD is a DaemonSet in standard mode; in HA mode it may not be present at all.
kubectl -n <ns> get ds -l app.kubernetes.io/name=fluentd -o wide

# Pod-level health. `LastState.terminated.reason: OOMKilled` is the headline you're hunting in the SIGKILL case.
kubectl -n <ns> get pods -l app.kubernetes.io/name=fluentd -o wide
kubectl -n <ns> describe pod <pod>     # restart count, last-state reason, OOM, evictions

# Recent error/warn tail. Worker SIGKILL and flush errors both surface here.
kubectl -n <ns> logs <pod> --tail=500 | grep -iE 'error|warn|sigkill|flush|chunks|oom'

# Memory limit (1Gi is the trap value: the hardcoded ~1GB buffer cannot fit).
kubectl -n <ns> get pod <pod> -o jsonpath='{.spec.containers[*].resources}'

# Effective configuration. Output/buffer stanzas in `output-graylog.conf` matter most.
kubectl -n <ns> get cm logging-fluentd -o yaml

# DiskIO from the node side — only if symptom mentions high read load and you have node-exec rights.
# This is read-safe but node-local; skip if unsure.
```

Whatever you actually observe becomes the `evidence` field on any `recommend` you emit.

## Symptom catalogue

Match the report against [references/symptoms.md](references/symptoms.md). That file is the canonical catalogue; do not paraphrase it back into this SKILL.

If the symptom is not in the catalogue, do **not** invent a solution. Report what you observed, suggest the adjacent area (FluentBit upstream, Graylog GELF input, OpenSearch backpressure), and stop. Adding new patterns means editing `docs/troubleshooting/fluentd.md` in the operator repo first.
