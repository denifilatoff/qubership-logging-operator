---
name: fluentbit-troubleshoot
description: Diagnose FluentBit problems in the Qubership logging stack — connection failures to Graylog, stuck pipelines, dropped or delayed logs, ConfigMap reload failures. Use when symptoms point at the FluentBit DaemonSet (forwarder or aggregator). Read-only against the live cluster; mutations go out as `recommend` blocks, never executed.
---

# Troubleshoot FluentBit

## Protocol

Read [references/shared-contract.md](references/shared-contract.md) first — it governs invocation, action tiers, read-before-recommend, the `recommend` block schema, the symptom-catalogue convention, and the refute contract.

## First read-safe sweep

Skip steps already covered by the L1 handoff envelope.

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

## Symptom catalogue

[references/symptoms.md](references/symptoms.md) — match against it; add patterns via `docs/troubleshooting/fluentbit.md` in the operator repo first.

## Zone signal classification (refute contract)

Walk the four classes in order. Emit on the first match.

**1. CLEAN**
- All pods `Running`, no recent `OOMKilled` / `Evicted` / `CrashLoopBackOff`.
- `kubectl logs --tail=500` clean of errors and warnings (no parser failures, no plugin init errors, no output retries, no panics).
- Output endpoint configured AND reachable from the pod.

→ `hypothesis_refuted`, `signal_class: clean`.

**2. QUOTED**
- Logs contain a verbatim citation of an external endpoint as the trigger: `[upstream] connection ... timed out`, `no upstream connections available`, `getaddrinfo <host>`, `connection refused to <host>`, or similar naming a host/port.

→ `hypothesis_refuted`, `signal_class: secondary_quoted`. Capture each quote verbatim in `cited_external_components`.

**3. BACKPRESSURE** — all of:
- Pods `OOMKilled` OR repeatedly restarting on OOM.
- Output stanza present in the ConfigMap AND output endpoint reachable from the pod.
- Memory limit is tight for the workload: **forwarder DaemonSet ≤ 128Mi**, **aggregator StatefulSet ≤ 512Mi**.
- **AND a positive backpressure signal**: `kubectl logs --tail=500` shows output write errors or connection retries to the output target, OR FluentBit `/api/v1/metrics` shows non-zero growing `fluentbit_output_retries_total` / `fluentbit_output_dropped_records_total`.

→ `hypothesis_refuted`, `signal_class: secondary_backpressure`.

The positive-signal requirement is what separates this class from PRIMARY. OOM at a tight limit without any visible retry / error / dropped-records signal is just "memory misconfig" → PRIMARY. OOM at a tight limit AND output is visibly failing to drain = backpressure.

**4. PRIMARY** (everything else with a signal — emit `recommend`):
- ConfigMap reload error / parser failure / plugin init crash / internal panic.
- Pods `Evicted` for non-memory reasons (disk pressure on host).
- `OOMKilled` but memory limit is NOT tight by step-3 thresholds — treat as misconfig / leak, not backpressure.
- Output not configured, or output endpoint genuinely unreachable (DNS / network — distinct from a quoted refusal).
