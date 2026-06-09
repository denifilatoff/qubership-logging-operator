# OpenSearch flood-stage: indices read-only

**Backend required**: `graylog`

## Case

OpenSearch disk watermarks are forced below current disk utilisation
(`low=10%`, `high=15%`, `flood_stage=20%` while the data directory sits at
~50% used). In addition, every existing index is directly set to
`index.blocks.read_only_allow_delete=true` — the same end state a real
flood-stage event produces.

New logs stop reaching Graylog: FluentBit retries, and Graylog shows
indexer errors mentioning `cluster_block_exception` or
`FORBIDDEN/12/index read-only`.

Disk is **not** physically filled. The watermark settings in
`_cluster/settings` are the smoking gun. `df -h` on the node still reports
healthy free space, so the diagnostic path must rely on OpenSearch APIs
(`_cluster/settings`, `_cat/indices`, `_cluster/allocation/explain`) rather
than filesystem-level probes.

## Mechanics

`apply.sh` snapshots current transient settings to `.state/F3-disk-readonly.snapshot.json`
and pushes the malicious settings. `revert.sh` restores from snapshot and
clears `read_only_allow_delete` on all indices.
