# OpenSearch — symptom catalog

Prose condensed from `docs/troubleshooting.md`. For each `symptom_id` the matcher returns, read its section, confirm the
condition holds, then write your analysis. Always also review the `Detection: manual` entries — the matcher never
returns them.

## opensearch-mapping-fields-limit-exceeded

**What:** OpenSearch rejects new fields because the index has hit the default 1,000-field mapping limit, usually caused
by FluentBit or FluentD incorrectly parsing log message content as `key=value` pairs. **Confirm:** Quote the
`Limit of total fields [N] in index [<index>] has been exceeded` error line from OpenSearch or Graylog logs (or API
responses). Capture the offending index's field count:
`curl -sk -u <u>:<p> https://<os>:9200/<index>/_mapping | jq '.[].mappings.properties | length'`. Identify a few example
"trash" fields (often look like `_lte_2024-08-31_04_59_40_… = +6199354.549415617`). **Fix:** 1. Upgrade to the latest
Logging release — newer FluentBit/FluentD parsing configs avoid most of these cases; re-check after upgrade. 2. If an
external agent or a service sends logs directly to Graylog, audit its parsing config. 3. To clean already-saved trash
fields from indices, run an `_update_by_query` with a Painless script that removes keys starting with the known bad
prefix (change `ErrorEntry_` to match your trash keys), via `POST /<index_name>/_update_by_query`:

```json
{"script": {"lang": "painless", "source": "List f=new ArrayList(); for(e in ctx._source.keySet()){if(e.startsWith('ErrorEntry_'))f.add(e);} for(k in f){ctx._source.remove(k);}"}}
```

Warning: slow and CPU-heavy — rewrites every document in every targeted index. If the index is locked on write during
cleanup, unlock it first: `PUT /<index>/_settings -d '{"index.blocks.write": "false"}'`. Trash fields in indices that
the rotation policy will eventually delete are not worth scrubbing — they go away on rotation. Rollback: the
`_update_by_query` is irreversible per document; ensure a backup or confirm the trash fields are safe to remove before
running.

## opensearch-ism-config-missing-noop

**What:** The OpenSearch index-management plugin logs spurious `IndexNotFoundException` errors for
`.opendistro-ism-config` on every `ClusterChangedEvent` until at least one ISM policy exists; these errors have no
functional impact. **Confirm:** Quote one
`ManagedIndexCoordinator … get managed-index failed: [.opendistro-ism-config] IndexNotFoundException[no such index [.opendistro-ism-config]]`
line from OpenSearch logs. Capture the OpenSearch version: `GET /` → `version.number`. **Fix:** Four ways to silence it:
(1) create at least one ISM rule so OpenSearch creates `.opendistro-ism-config`; (2) disable the plugin: set
`plugins.index_state_management.enabled: False` in OpenSearch config (official docs:
<https://opensearch.org/docs/latest/im-plugin/ism/settings/>); (3) upgrade OpenSearch to ≥ 2.10.x — the upstream plugin
re-classified the log from ERROR to DEBUG in 2.10.0.0 (opensearch-project/index-management#846); (4) ignore the message
— it has no functional impact. Rollback: re-enable the plugin if disabled and it is required for index lifecycle
management.

## opensearch-heap-above-32gb

**Detection: manual** **What:** OpenSearch performance degrades or OOM events increase after raising `-Xmx` above ~32 GB
because the JVM switches from 32-bit compressed object pointers to 64-bit pointers, worsening memory efficiency —
roughly 40–50 GB of allocated heap is needed to recover the effective memory of a ~32 GB heap with compressed OOPs.
**Confirm:** Quote the OpenSearch `-Xmx` setting from its JVM options or Helm values:
`curl -sk -u <u>:<p> https://<os>:9200/_nodes/jvm?pretty | grep -E 'heap_init|heap_max|using_compressed_ordinary_object_pointers'`.
Note the value exceeds ~32 GB. Include any OOM events, throughput drops, or pod restarts that began after the heap was
raised. **Fix:** 1. Decrease OpenSearch `-Xmx` to ~32 GB. 2. Remember that Graylog and OpenSearch pods coexist with
MongoDB and other workloads on the same nodes. Java pods can use more memory than `-Xmx` due to off-heap allocations;
keep the sum of pod memory requests on a node well below the node's allocatable memory (leave 20–50% free). 3. This
operator does not manage OpenSearch lifecycle — only its client config in `LoggingService.spec.openSearch.url` / `tls`.
Adjust OpenSearch heap and pod limits in the operator or chart that deploys OpenSearch. Sizing reference:
`docs/installation.md` ships a hardware-requirements table; its OpenSearch heap recommendation tops out at "16+ GB (but
less than ~32 GB)". Rollback: restore the previous `-Xmx` value in the OpenSearch JVM options / Helm values and restart
the pod. **Caveat / next:** after lowering `-Xmx` and stabilizing OOMs, analyze remaining performance issues separately
— the heap fix is necessary but not sufficient.

## opensearch-index-read-only

**What:** OpenSearch's disk allocator marks indices read-only when node disk utilization exceeds the flood-stage
watermark (default 95%), causing Graylog to stop writing logs to OpenSearch. **Confirm:** Quote the
`index <name> is read-only` warnings from `https://<graylog>/system/indices/failures`. Confirm via
`GET /<index>/_settings` showing `"index.blocks.read_only_allow_delete":"true"`. Read both current disk usage
(`GET /_cat/allocation?v`) and the effective watermarks
(`GET /_cluster/settings?include_defaults=true&flat_settings=true` →
`cluster.routing.allocation.disk.watermark.flood_stage`/`high`/`low`, `threshold_enabled`; defaults low 85%, high 90%,
flood 95%). Read disk fullness from `_cat/allocation`'s `disk.percent` (the real filesystem); never infer it by comparing
the PVC's declared capacity to index `store.size` — on local-path or kind the PVC size is not the disk limit, and that
comparison fabricates a false "almost full" reading. OpenSearch auto-releases the block once disk falls below the high
watermark, so a block that persists while disk sits below the high watermark means the watermark itself is set low (or
the block was set by hand) — not live disk pressure. **Fix:** First decide which cause the Confirm reads point to.
(A) Disk genuinely at/over the high watermark:
free disk space — list and remove old indices (`GET /_cat/indices`, then `DELETE /<index_name_or_regex>`, e.g.
`DELETE /graylog_30,graylog_31`); if OpenSearch is unreachable via API, on-disk PVC cleanup is out of scope (K8s-only
surface) — escalate to the cluster operator for the StatefulSet PVC-cleanup procedure. (B) Disk below the high watermark
but the block persists: the watermark/threshold is misconfigured — correct `cluster.routing.allocation.disk.watermark.*`
(or, last resort, `threshold_enabled`) first, because clearing the block alone re-triggers on the next allocator pass.
Once the cause is addressed, clear the read-only block explicitly — the recommend must carry this call, never lean on
auto-release, which does not fire while a watermark stays set below current disk usage:
`PUT /_settings -d '{"index.blocks.read_only_allow_delete": null}'`. Then re-check Graylog index-rotation settings so
the cluster does not climb back to 95% — the total rotation size of all index sets should stay under ~85% of total HDD
capacity. As a last resort (not recommended for production), disable the disk-allocator threshold entirely:
`PUT /_cluster/settings -d '{"persistent": {"cluster.routing.allocation.disk.threshold_enabled":"false"}}'` — with this
off, a misconfigured rotation will consume all free space. Rollback: the `read_only_allow_delete: null` unlock is safe
to re-run; index deletion is irreversible — ensure old indices are not needed before deleting. **Caveat / next:** also
check `graylog-server-troubleshoot` symptom `graylog-opensearch-storage-full` if the PVC itself is full and disk-space
cleanup requires on-host access.
