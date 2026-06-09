**Area:** opensearch-troubleshoot

**Root cause:** OpenSearch is in a flood-stage-equivalent state. Two
related conditions were applied to the cluster:

1. The transient cluster settings hold disk watermark overrides below
   current disk utilisation:
   `cluster.routing.allocation.disk.watermark.low=10%`,
   `...high=15%`, `...flood_stage=20%`, while the data directory sits
   at ~50% used.
2. Every user index has `index.blocks.read_only_allow_delete=true` set
   directly on `index.settings` — the same end state a real
   flood-stage event produces.

New writes are rejected at the OpenSearch layer. Graylog's indexer
surfaces this as `cluster_block_exception` / `FORBIDDEN/12/index
read-only` errors. FluentBit and Graylog pods are otherwise healthy,
and `kubectl logs` on the source pods shows new lines being produced
— the loss is downstream of the collector.

Disk is **not** physically full: `_cat/allocation` and `df -h` on the
node both report healthy free space. The smoking gun lives in
`_cluster/settings` (the lowered watermarks) and per-index `_settings`
(the read-only block), not at the filesystem layer.

**Expected recommend:**

- type: opensearch-cluster-settings-change
- target: the OpenSearch cluster reached via the in-cluster service
  `opensearch.opensearch.svc:9200` (admin credentials), specifically:
  - `PUT /_cluster/settings` to clear the transient watermark
    overrides (set each of `low`, `high`, `flood_stage` back to
    `null` so the OpenSearch defaults take over);
  - `PUT /*,-.*/_settings?expand_wildcards=open` to set
    `index.blocks.read_only_allow_delete=false` on every user index
    (the `*,-.*` pattern skips system / dotted indices that the
    security plugin refuses to bulk-update).
- change: both calls must be in the recommend. The block does not
  lift itself when watermarks rise, so clearing the watermarks alone
  is insufficient; clearing the block while the watermarks stay
  lowered means OpenSearch will reapply the block on the next disk
  check.
- rollback: re-`PUT` the captured pre-incident `_cluster/settings`
  snapshot (the cluster fixture snapshots transient settings to
  `test/agent-packages/scenarios/.state/opensearch-flood-stage-readonly.snapshot.json`).

**Required snapshot fields attached to the recommend:**

- `_cluster/settings?flat_settings=true` output showing the lowered
  watermarks under `transient.*`.
- per-index `_settings` showing
  `index.blocks.read_only_allow_delete=true` on the user indices
  that hold the missing logs.
- evidence that disk is not actually full: `_cat/allocation` row for
  each OpenSearch node and / or `df -h` output from the OpenSearch
  pod showing free space well above 50%.
- Graylog indexer error sample (`cluster_block_exception` /
  `FORBIDDEN/12/index read-only`) from `kubectl logs <graylog-pod>`,
  to anchor the symptom in Graylog to the cause in OpenSearch.
