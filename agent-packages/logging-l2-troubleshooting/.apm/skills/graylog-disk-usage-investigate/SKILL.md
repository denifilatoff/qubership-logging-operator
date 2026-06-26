---
name: graylog-disk-usage-investigate
description: Produce a ranked breakdown of who is filling Graylog/OpenSearch disk — which microservices, namespaces, containers, or hosts contributed the most bytes of logs over a chosen time window. Use when an engineer asks "what is eating our log storage", "which service is the noisiest producer", "why did the log storage fill up again", or as a sub-routine called from `graylog-server-troubleshoot` after the disk-full symptom is confirmed. Callable both standalone by the engineer and as a sub-step by another L2 skill. Read-only — produces a report, never deletes or rotates indices.
---

# Investigate Graylog disk usage

Given a time window, list the producers contributing the most bytes of logs to Graylog/OpenSearch storage, ranked. Do
not act on the breakdown — the retention / quota / parser-fix decision is the operator's.

## Protocol

Read [references/shared-contract.md](references/shared-contract.md) first. All commands here are `read-safe` or
`read-heavy` (terms-aggregations on log indices); nothing mutates state, but several queries need caps.

## Input contract

The caller (engineer or another skill) must supply, or you must ask for:

- **Window** — start/end timestamps, or a relative range like "last 24h", "last 7d".
- **Index scope** — one Graylog index pattern, or "all". If the cluster has many index sets, narrowing to the suspect
  one keeps the query cheap.
- **Grouping dimension** — which field to rank by. Typical candidates in this stack:
  - `container_name` — most precise on Kubernetes deployments.
  - `namespace_name` / `kubernetes_namespace_name` — coarser, often the right level for "which team is loud".
  - `source` — K8s node level. Useful when the question is "which node is being noisy".
  - `app_kubernetes_io_name` or `microservice` — application-level if present.
- **Top-N** — how many producers to return (default 20).

If the engineer didn't specify, propose defaults (window = last 24h, scope = active write indices, grouping =
`container_name`, N = 20) and confirm before querying.

## First read-safe diagnostic pass

```bash
# Indices and current sizes — this picks the candidate index scope.
curl -sk -u <u>:<p> 'https://<os-host>:9200/_cat/indices?v&s=store.size:desc' | head -30

# Confirm the grouping field exists and has reasonable cardinality on the chosen scope.
curl -sk -u <u>:<p> "https://<os-host>:9200/<index>/_mapping/field/<grouping_field>?pretty"
```

## Read-heavy ranking query

Terms-aggregation on the grouping field, scoped to the window. Bytes-per-producer is estimated as
`doc_count × avg_doc_size_bytes` for that index — OpenSearch does not store a per-document byte size, so the estimate
uses index-level `store.size_in_bytes / docs.count`.

```bash
# 1. Get total docs and store size of the index to compute avg doc size.
curl -sk -u <u>:<p> "https://<os-host>:9200/<index>/_stats/store,docs?pretty"

# 2. Run the aggregation. Replace <field>, <gte>, <lte>, <N>.
curl -sk -u <u>:<p> -H 'Content-Type: application/json' \
  "https://<os-host>:9200/<index>/_search" -d '{
    "size": 0,
    "query": {
      "range": {
        "timestamp": { "gte": "<gte>", "lte": "<lte>" }
      }
    },
    "aggs": {
      "producers": {
        "terms": { "field": "<grouping_field>", "size": <N> }
      }
    }
  }'
```

Caps you must declare up front:

- `size: 0` — never return hits, only the aggregation. Non-negotiable.
- `terms.size` capped to the requested N (default 20). Do not return more without a reason.
- Time window must be a bounded `range`, never open-ended.
- If `<index>` is a wildcard spanning many shards, ask the engineer to narrow it before running, or run the query on one
  index at a time.

If the cluster is under load (you see the cluster health is YELLOW, or shard queue is high), demote the query to a
`recommend`: produce the exact `curl` and ask the engineer to run it during a quieter window.

## Output

Return one ranked table — no prose, no recommendations. Schema:

```yaml
investigation: graylog-disk-usage
window:
  gte: <gte>
  lte: <lte>
scope:
  index: <index_or_pattern>
  grouping: <field>
estimate_basis:
  avg_doc_size_bytes: <bytes>   # index store_size / index doc_count
  note: |
    Per-producer bytes is doc_count × avg_doc_size_bytes. OpenSearch
    has no per-document byte size, so this is an estimate of the
    same order of magnitude as the truth, not an exact number.
producers:
  - rank: 1
    value: <producer-name>
    doc_count: <N>
    estimated_bytes: <bytes>
    estimated_share_pct: <pct of total docs in the window>
  - rank: 2
    ...
notes:
  - <anything the engineer should know: producers whose share looks
    abnormal vs. usual, missing/empty values for the grouping field,
    skew across shards, etc.>
```

What you must **not** do:

- Recommend deleting indices, dropping streams, lowering retention, or fixing a parser. Producing the ranked breakdown
  is the whole job; the decision is the operator's, in `graylog-server-troubleshoot` or in a retention review.
- Run the aggregation across "all indices, all time". Always cap.
- Re-run the same query repeatedly during one investigation — cache the output in the report.

## Related

- `graylog-server-troubleshoot` — the Graylog server expert; its `graylog-opensearch-storage-full` symptom is the
  disk-full context this skill usually slots into. The canonical operator guide is `docs/troubleshooting.md` (the "HDD
  Full on Graylog VM" section).
