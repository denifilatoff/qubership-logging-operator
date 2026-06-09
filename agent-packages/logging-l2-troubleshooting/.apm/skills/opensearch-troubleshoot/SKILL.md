---
name: opensearch-troubleshoot
description: Diagnose OpenSearch (or Elasticsearch) problems in the Qubership logging stack — mapping/field-limit explosions, `.opendistro-ism-config` noise, heap-sizing pitfalls beyond 32 GB, disk-allocator read-only locks. Use when symptoms point at the search/storage backend behind Graylog. Read-only against the live cluster and the OpenSearch API; state-changing fixes are surfaced as proposed actions for the operator, never executed.
---

# Troubleshoot OpenSearch

## Protocol

Read [references/shared-contract.md](references/shared-contract.md) first — it governs invocation, action tiers,
read-before-recommend, the expert output contract, and the anti-fabrication rule.

OpenSearch-specific notes:

- Endpoint and credentials come from the Kubernetes deployment (Secret, ConfigMap, or whatever the chart installs).
  Confirm what the engineer has access to before running any API call.
- `_search` and `_update_by_query` against `*` are **`read-heavy`**. Always cap with `size`, time window, or a concrete
  index pattern. If you can't, demote to `recommend`.
- Deleting indices, clearing read-only flags, or toggling cluster settings (`cluster.routing.allocation.*`) are
  mutating. Never run; emit as `recommend` with rollback.

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

## Match symptoms

1. Concatenate the diagnostic-pass output above into a single text buffer (a temp file is fine).
2. Run the deterministic matcher over it:

   ```bash
   python3 scripts/match_symptoms.py <diagnostic-output-file>
   ```

   It prints a JSON list of `symptom_id`s whose patterns matched. Each is a **hint**, not a verdict.

3. For every returned id, read its section in [references/symptoms.md](references/symptoms.md) and confirm the
   **Confirm** condition actually holds against your evidence — including any non-textual threshold (for example a
   memory limit).
4. **Always** also review the `Detection: manual` entries in [references/symptoms.md](references/symptoms.md). The
   matcher never returns them by design; check whether your diagnostic evidence fits one. An empty matcher result does
   **not** mean "no symptom" — do this manual sweep first.

## Write your analysis

Write prose for the engineer, per the contract in
[references/shared-contract.md](references/shared-contract.md#expert-output). For each confirmed symptom:

- Copy the `symptom_id` from the matcher output verbatim: the exact token, no reformatting, never one you invent (see
  the contract).
- Quote the verbatim diagnostic lines or values that prove it.
- Give the **Fix** from the symptom's section as prose, with the rollback, blast radius, and a confidence level. Include
  the read-safe snapshot the fix relies on (actual command output).

Do not emit a fenced YAML block. The triage orchestrator reads your prose.

## Anti-fabrication

If neither the matcher nor the manual sweep confirms a symptom, say so plainly, paste a short digest of the
diagnostic-pass output, and stop. Do not invent a `symptom_id`. Do not infer or speculate about causes. Do not propose a
fix. A "no known symptom matched" result is valid and expected — the orchestrator routes from there.
