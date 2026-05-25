---
name: opensearch-troubleshoot
description: Diagnose OpenSearch (or Elasticsearch) problems in the Qubership logging stack — mapping/field-limit explosions, `.opendistro-ism-config` noise, heap-sizing pitfalls beyond 32 GB, disk-allocator read-only locks. Use when symptoms point at the search/storage backend behind Graylog. Read-only against the live cluster and the OpenSearch API; mutations go out as `recommend` blocks, never executed.
---

# Troubleshoot OpenSearch

## Protocol

Read [references/shared-contract.md](references/shared-contract.md) first — it governs invocation, action tiers, read-before-recommend, the `recommend` block schema, the expert output schema, and the anti-fabrication rule.

OpenSearch-specific notes:

- Endpoint and credentials come from the Kubernetes deployment (Secret, ConfigMap, or whatever the chart installs). Confirm what the engineer has access to before running any API call.
- `_search` and `_update_by_query` against `*` are **`read-heavy`**. Always cap with `size`, time window, or a concrete index pattern. If you can't, demote to `recommend`.
- Deleting indices, clearing read-only flags, or toggling cluster settings (`cluster.routing.allocation.*`) are mutating. Never run; emit as `recommend` with rollback.

## First read-safe diagnostic pass

```bash
# Cluster health and node count. RED status anywhere reframes everything else.
curl -sk -u <u>:<p> https://<os-host>:9200/_cluster/health?pretty
curl -sk -u <u>:<p> https://<os-host>:9200/_cat/nodes?v

# Disk allocator state — read-only locks are 95%-threshold-driven.
curl -sk -u <u>:<p> https://<os-host>:9200/_cat/allocation?v

# Indices listing. Cap with a pattern if the cluster is large.
curl -sk -u <u>:<p> 'https://<os-host>:9200/_cat/indices?v&s=store.size:desc' | head -50

# Read-only / block flags on the indices of interest.
curl -sk -u <u>:<p> https://<os-host>:9200/<index>/_settings?pretty

# Recent OpenSearch logs.
kubectl -n <ns> logs <opensearch-pod> --tail=500 | grep -iE 'error|warn|read.only|fields'

# Heap configuration (`-Xmx`) — the "more than 32 GB" trap.
curl -sk -u <u>:<p> https://<os-host>:9200/_nodes/jvm?pretty | grep -E 'heap_init|heap_max|using_compressed_ordinary_object_pointers'
```

## Symptom catalogue

[references/symptoms.md](references/symptoms.md) — match against it; add patterns via `docs/troubleshooting/opensearch.md` in the operator repo first.

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
