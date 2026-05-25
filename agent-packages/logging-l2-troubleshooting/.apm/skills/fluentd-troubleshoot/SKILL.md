---
name: fluentd-troubleshoot
description: Diagnose FluentD problems in the Qubership logging stack — worker OOM kills, sustained DiskIO read load, GELF UDP "data too big / 128 chunks" buffer flush failures, ConfigMap-reloader-driven restarts. Use when symptoms point at the FluentD DaemonSet. Read-only against the live cluster; mutations go out as `recommend` blocks, never executed.
---

# Troubleshoot FluentD

## Protocol

Read [references/shared-contract.md](references/shared-contract.md) first — it governs invocation, action tiers, read-before-recommend, the `recommend` block schema, the symptom-catalogue convention, and the refute contract.

## First read-safe diagnostic pass

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

## Symptom catalogue

[references/symptoms.md](references/symptoms.md) — match against it; add patterns via `docs/troubleshooting/fluentd.md` in the operator repo first.

## Zone signal classification (refute contract)

Walk the four classes in order. Emit on the first match.

**1. CLEAN**
- DaemonSet pods `Running`, no worker `SIGKILL` / `OOMKilled`.
- `kubectl logs --tail=500` clean of FluentD errors (no flush failures, no plugin panics, no reloader-driven restarts).
- Output stanzas in `logging-fluentd` ConfigMap configured to a reachable endpoint.

→ `hypothesis_refuted`, `signal_class: clean`.

**2. QUOTED**
- Flush or output errors name a destination: `failed to flush ... Connection refused to <host>`, `Data too big`, `more than 128 chunks`, or any output-plugin error citing a hostname / endpoint / GELF protocol limit.

→ `hypothesis_refuted`, `signal_class: secondary_quoted`. Capture verbatim in `cited_external_components`.

**3. BACKPRESSURE** — all of:
- Flush retries climbing OR sustained DiskIO read load from buffer rewinds.
- Output endpoint (Graylog or aggregator) responds to probes.
- No FluentD-side error explains the flush failure (no parser bug, no plugin crash in `--tail=500`).

→ `hypothesis_refuted`, `signal_class: secondary_backpressure`.

**4. PRIMARY** (emit `recommend`):
- ConfigMap parse error (`unmatched end tag`, config validation failure) → reloader-driven restart.
- Plugin panic unrelated to flush.
- Worker `OOMKilled` / `SIGKILL` with memory limit at the **~1Gi trap value** — this is the canonical FluentD memory-limit misconfig (hardcoded ~1Gi buffer cannot fit). Fix is to raise the limit or shrink the buffer; emit `recommend`, do not refute. (The buffer overflowing the 1Gi limit is a sizing trap, not downstream backpressure — backpressure would surface as flush retries per step 3.)
- Worker exit with any other internal reason.
