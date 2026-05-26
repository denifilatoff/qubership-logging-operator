---
name: fluentbit-troubleshoot
description: Diagnose FluentBit problems in the Qubership logging stack — connection failures to Graylog, stuck pipelines, dropped or delayed logs, ConfigMap reload failures. Use when symptoms point at the FluentBit DaemonSet (forwarder or aggregator). Read-only against the live cluster; mutations go out as `recommend` blocks, never executed.
---

# Troubleshoot FluentBit

## Protocol

Read [references/shared-contract.md](references/shared-contract.md) first — it governs invocation, action tiers, read-before-recommend, the `recommend` block schema, the expert output schema, and the anti-fabrication rule.

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
3. **Emit the result as a YAML code block.** Your response MUST begin with a fenced `yaml` code block (` ```yaml `) containing the schema below. Do NOT precede it with Markdown headers (`## Findings`, `## Recommendation`) or narrative prose. The structural emission is the contract — prose-style headers do not satisfy it.

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

If the matched entry's `proposed_fix` warrants a structured operator action, append a `recommend` block per the schema in [references/shared-contract.md](references/shared-contract.md#recommend-block-schema) — within the same YAML code block, immediately after `raw_diagnostic_pass`. Cite the matched `symptom_id` verbatim in `why`. Do NOT emit the recommend as prose; structural emission is required.

Plain-prose narration about what you found, after the YAML block, is fine for the human reader, but the YAML block above is the machine-checkable contract and must come first.

## Anti-fabrication

If no entry in the catalogue matches, return `findings: []` with a non-empty `raw_diagnostic_pass` digest. Do not invent a `symptom_id`. Do not infer or speculate. Do not emit a `recommend`. An empty `findings` array is a valid and expected outcome — the orchestrator handles routing from there.
