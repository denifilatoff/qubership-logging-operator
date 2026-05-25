---
name: opensearch-troubleshoot
description: Diagnose OpenSearch (or Elasticsearch) problems in the Qubership logging stack — mapping/field-limit explosions, `.opendistro-ism-config` noise, heap-sizing pitfalls beyond 32 GB, disk-allocator read-only locks. Use when symptoms point at the search/storage backend behind Graylog. Read-only against the live cluster and the OpenSearch API; mutations go out as `recommend` blocks, never executed.
---

# Troubleshoot OpenSearch

## Protocol

Read [references/shared-contract.md](references/shared-contract.md) first — it governs invocation, action tiers, read-before-recommend, the `recommend` block schema, the symptom-catalogue convention, and the refute contract.

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

## Zone signal classification (refute contract)

Walk the four classes in order. Emit on the first match. `secondary_*` classes are rare on OpenSearch — the terminal store usually owns its own pathology; the default is `primary`.

**1. CLEAN**
- Cluster `GREEN`, no unassigned shards.
- `_cat/allocation` shows `disk.percent` well under all `cluster.routing.allocation.disk.watermark.*` values.
- No `index.blocks.read_only_allow_delete` flag on indices in scope.
- Logs clean of mapping / field-limit errors and parser-fed mapping explosions.
- Heap configuration sane (`heap_max` ≤ 32 GB so compressed-oop is enabled, or above with documented intent).

→ `hypothesis_refuted`, `signal_class: clean`.

**2. QUOTED**
- Very rare on OpenSearch (terminal store doesn't push). Use only when OS logs explicitly cite an external trigger.

→ `hypothesis_refuted`, `signal_class: secondary_quoted`. Capture verbatim.

**3. BACKPRESSURE** — all of:
- Shard-write rejection events climbing.
- Disk well under watermark AND heap within sane bounds AND queue config default / reasonable.
- No mapping / field-limit errors in logs.

(I.e. OS is healthy by its own standards but still rejecting writes — upstream is dumping more than the cluster can absorb.)

→ `hypothesis_refuted`, `signal_class: secondary_backpressure`.

**4. PRIMARY** (emit `recommend`) — the common path:
- Mapping / field-limit exceeded by parser-fed schema explosion.
- Heap above 32 GB (compressed-oop trap).
- Disk above watermark → read-only blocks.
- `RED` status from index corruption.
- ISM / `.opendistro-ism-config` noise, security-config issues.
