---
name: fluentbit-troubleshoot
description: Diagnose FluentBit problems in the Qubership logging stack — connection failures to Graylog, stuck pipelines, dropped or delayed logs, ConfigMap reload failures. Use when symptoms point at the FluentBit DaemonSet (forwarder or aggregator). Read-only against the live cluster; mutations go out as `recommend` blocks, never executed.
---

# Troubleshoot FluentBit

## Protocol

Read [references/shared-contract.md](references/shared-contract.md) first — it governs invocation, action tiers, read-before-recommend, the `recommend` block schema, the symptom-catalogue convention, and the refute contract.

## First read-safe diagnostic pass

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
