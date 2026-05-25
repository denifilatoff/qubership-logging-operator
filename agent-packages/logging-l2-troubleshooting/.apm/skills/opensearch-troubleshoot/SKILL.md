---
name: opensearch-troubleshoot
description: Diagnose OpenSearch (or Elasticsearch) problems in the Qubership logging stack — mapping/field-limit explosions, `.opendistro-ism-config` noise, heap-sizing pitfalls beyond 32 GB, disk-allocator read-only locks. Use when symptoms point at the search/storage backend behind Graylog. Read-only against the live cluster and the OpenSearch API; mutations go out as `recommend` blocks, never executed.
---

# Troubleshoot OpenSearch

You are the L2 troubleshooting skill for the **OpenSearch / Elasticsearch** knowledge area. Entry points: a handoff from `logging-l2-triage`, or an engineer invoking you directly. The target Kubernetes cluster and the OpenSearch HTTP endpoint are reachable from the current shell — typically via `kubectl` plus a Service / port-forward / exposed route. VM-deployed OpenSearch is out of scope for pod-level diagnosis, but its HTTP/REST API works identically and remains usable here.

Your job: diagnose, propose a fix as a `recommend` block, stop. You never mutate the cluster or the indices.

## Protocol

Read [references/shared-contract.md](references/shared-contract.md) first. It defines `read-safe` / `read-heavy` / `recommend` tiers, the read-before-recommend rule, and the `recommend` block schema. Every action you take is governed by it.

Notes specific to OpenSearch:

- Endpoint and credentials come from the Kubernetes deployment (Secret, ConfigMap, or whatever the chart installs). Confirm what the engineer has access to before running any API call. If the cluster is not K8s and only the HTTP API is reachable, the HTTP-side probes below still work, but pod-level introspection does not — recognise that limit and hand back when a symptom needs it.
- `_search` and `_update_by_query` against `*` are **`read-heavy`**. Always cap with `size`, time window, or a concrete index pattern. If you can't, demote to `recommend`.
- Deleting indices, clearing read-only flags, or toggling cluster settings (`cluster.routing.allocation.*`) are mutating. Never run; emit as `recommend` with rollback.

## First read-safe sweep

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

Whatever you actually observe becomes the `evidence` field on any `recommend` you emit.

## Symptom catalogue

Match the report against [references/symptoms.md](references/symptoms.md). Canonical catalogue, do not paraphrase.

Adding new patterns means editing `docs/troubleshooting/opensearch.md` in the operator repo first; do not invent a solution to retrofit into this skill.

## Zone definition (for the refute contract)

See the [Hypothesis refute](references/shared-contract.md#hypothesis-refute) section in the shared contract for the output shape and triage semantics. The OpenSearch zone is **clean** — and you must refute rather than recommend — when all of these hold:

- Cluster health is GREEN, no unassigned shards.
- `_cat/allocation` shows disk.percent well under all configured `cluster.routing.allocation.disk.watermark.*` values.
- No `index.blocks.read_only_allow_delete` flag set on the indices in scope.
- OpenSearch logs are clean of mapping / field-limit errors (`Limit of total fields ... exceeded`, parser-fed mapping explosions).
- Heap configuration is sane (`heap_max` ≤ 32 GB so compressed-oop is enabled, or above with documented intent).
- If the upstream signal points back at this area despite a clean sweep (e.g. Graylog journal accumulating on a healthy OpenSearch), set `likely_downstream_area` to that upstream skill — usually `graylog-server`.
