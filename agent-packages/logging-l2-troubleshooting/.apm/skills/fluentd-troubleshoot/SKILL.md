---
name: fluentd-troubleshoot
description: Diagnose FluentD problems in the Qubership logging stack — worker OOM kills, sustained DiskIO read load, GELF UDP "data too big / 128 chunks" buffer flush failures, ConfigMap-reloader-driven restarts. Use when symptoms point at the FluentD DaemonSet. Read-only against the live cluster; mutations go out as `recommend` blocks, never executed.
---

# Troubleshoot FluentD

## Protocol

Read [references/shared-contract.md](references/shared-contract.md) first — it governs invocation, action tiers, read-before-recommend, the `recommend` block schema, the expert output schema, and the anti-fabrication rule.

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

## Lookup and output

1. Take the diagnostic-pass output above.
2. For each entry in [references/symptoms.md](references/symptoms.md), evaluate its `match` block against the diagnostic-pass output. Collect every entry that matches.
3. Emit the result in the schema from [references/shared-contract.md](references/shared-contract.md#expert-output-schema):

```yaml
findings:
  - symptom_id: <id of the matched entry>
    evidence: |
      <verbatim lines / values referenced by the entry's evidence_template>
    proposed_fix: |
      <proposed_fix from the entry, instantiated with any concrete values>
raw_diagnostic_pass: |
  <abbreviated digest of the diagnostic-pass output above>
```

If the matched entry's `proposed_fix` warrants a structured operator action, also emit a `recommend` block per the shared contract, citing the matched `symptom_id` in `why`.

## Anti-fabrication

If no entry in the catalogue matches, return `findings: []` with a non-empty `raw_diagnostic_pass` digest. Do not invent a `symptom_id`. Do not infer or speculate. Do not emit a `recommend`. An empty `findings` array is a valid and expected outcome — the orchestrator handles routing from there.
