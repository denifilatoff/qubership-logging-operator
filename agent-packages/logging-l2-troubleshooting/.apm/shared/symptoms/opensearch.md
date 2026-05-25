# OpenSearch — symptom catalogue

## Limit of total fields exceeded (mapping explosion)

```yaml
id: opensearch-mapping-fields-limit-exceeded
match:
  log_grep:
    target: opensearch
    pattern: 'Limit of total fields \[\d+\] in index \[.+\] has been exceeded'
evidence_template: |
  Quote the `Limit of total fields [N] in index [<index>] has been exceeded`
  log line (visible in OpenSearch and/or Graylog logs and API responses).
  Capture the offending index's mapping size:
  `curl -sk -u <u>:<p> https://<os>:9200/<index>/_mapping | jq '.[].mappings.properties | length'`.
  Identify a few example "trash" fields (often look like
  `_lte_2024-08-31_04_59_40_… = +6199354.549415617`).
proposed_fix: |
  Default OpenSearch/Elasticsearch field cap is 1000 fields per index.
  This usually fires because FluentBit / FluentD parsed something inside a
  log `message` as a `key=value` pair (e.g. mongo filter strings,
  bracketed segments). Each spurious key becomes a permanent dynamic
  field.

  1. Upgrade to the latest Logging release first — newer FluentBit/FluentD
     parsing configs avoid most of these cases. Re-check after upgrade.
  2. If an external agent or a service is sending logs directly to
     Graylog, audit its parsing config.
  3. Clean already-saved trash fields from indices via OpenSearch
     `_update_by_query` with a painless script that removes keys starting
     with a known bad prefix. **Warning: slow and CPU-heavy** because it
     rewrites every document in every targeted index.

     Painless script template (change the prefix `ErrorEntry_` to match
     your trash keys):
     ```painless
     List fieldsToRemove = new ArrayList();
     for (entry in ctx._source.keySet()) {
       if (entry.startsWith('ErrorEntry_')) { fieldsToRemove.add(entry); }
     }
     for (field in fieldsToRemove) { ctx._source.remove(field); }
     ```
     Run via
     `POST /<index_name>/_update_by_query` (`<index_name>` may be a CSV or
     `*`).
  4. If the index is locked on write during cleanup, unlock it:
     `PUT /<index>/_settings -d '{"index.blocks.write": "false"}'`.

  Trash fields in indices that the rotation policy will eventually delete
  are not worth scrubbing — they go away on rotation.
```

## Spurious `no such index [.opendistro-ism-config]` errors

```yaml
id: opensearch-ism-config-missing-noop
match:
  log_grep:
    target: opensearch
    pattern: 'no such index \[\.opendistro-ism-config\]|ManagedIndexCoordinator.*IndexNotFoundException'
evidence_template: |
  Quote one `ManagedIndexCoordinator … get managed-index failed:
  [.opendistro-ism-config] IndexNotFoundException` line. Capture the
  OpenSearch version (`GET /` → `version.number`).
proposed_fix: |
  Cosmetic. The index-management plugin logs this on every
  ClusterChangedEvent until `.opendistro-ism-config` exists, which only
  happens once an ISM policy is created. The upstream plugin re-classified
  the log from ERROR to DEBUG in 2.10.0.0
  (opensearch-project/index-management#846).

  Four ways to silence it:
  - Create at least one ISM rule so OpenSearch creates
    `.opendistro-ism-config`.
  - Disable the plugin:
    `plugins.index_state_management.enabled: False`.
  - Upgrade OpenSearch to ≥ 2.10.x.
  - Ignore the log message — it has no functional impact.
```

## OpenSearch heap above ~32 GB (compressed-OOPs ceiling)

```yaml
id: opensearch-heap-above-32gb
match:
  config_check:
    configmap: opensearch jvm options / Helm values
    expects: '-Xmx > ~32g'
evidence_template: |
  Quote the OpenSearch `-Xmx` setting from its JVM options / Helm values.
  Include OOM events, throughput drops, or pod restarts that started after
  the heap was raised above ~32 GB.
proposed_fix: |
  Above ~32 GB, the JVM switches from 32-bit compressed object pointers to
  64-bit pointers, and effective memory usage gets worse. You need roughly
  40–50 GB of allocated heap to recover the effective memory of a
  ~32 GB heap with compressed OOPs.

  1. Decrease OpenSearch `-Xmx` to ~32 GB.
  2. Remember Graylog and OpenSearch pods coexist with MongoDB and other
     workloads on the same nodes. Each Java pod can exceed its `-Xmx` due
     to off-heap memory, and the node still needs headroom for kubelet,
     container runtime, and neighbouring pods. Keep the sum of pod memory
     requests on a node well below the node's allocatable memory.
  3. This operator does **not** manage OpenSearch lifecycle — only its
     client config in `LoggingService.spec.openSearch.url` / `tls`. Adjust
     OpenSearch heap and pod limits in whatever operator or chart deploys
     OpenSearch.

  Sizing reference: `docs/installation.md` ships a hardware-requirements
  table; its OpenSearch heap recommendation tops out at "16+ GB (but less
  than ~32 GB)".

  After lowering `-Xmx` and stabilising OOMs, analyse remaining
  performance issues separately — the heap fix is necessary, not
  sufficient.
```

## Index read-only (disk-allocator block)

```yaml
id: opensearch-index-read-only
match:
  log_grep:
    target: graylog
    pattern: 'index .* is read-only|index .* blocks read-only_allow_delete|cluster_block_exception|FORBIDDEN/12/index read-only'
  api_check:
    path: /<index_name>/_settings
    expects: '"index.blocks.read_only_allow_delete":"true"'
evidence_template: |
  Quote the `index <name> is read-only` warnings from
  `https://<graylog>/system/indices/failures`. Confirm via
  `GET /<index>/_settings` showing
  `"index.blocks.read_only_allow_delete":"true"`. Capture current disk
  usage (`GET /_cat/allocation?v`) — block triggers at ~95% by default.
proposed_fix: |
  OpenSearch's disk allocator marks indices read-only when node disk
  utilisation exceeds the high watermark (default 95%). Thresholds: low
  80%, high 90%, flood 95%.

  1. First, free disk space. Use the OpenSearch API to list and remove old
     indices:
     - `GET /_cat/indices`
     - `DELETE /<index_name_or_regex>` (e.g.
       `DELETE /graylog_30,graylog_31`)
  2. If OpenSearch is unreachable via API, on-disk cleanup of its data PVC
     is **out of scope** for this skill (K8s-only execution surface).
     Escalate to the cluster operator — they have the PVC-cleanup
     procedure (debug pod or scale-down + clean workflow) for the
     OpenSearch StatefulSet.
  3. Once disk space is freed, clear the read-only block:
     `PUT /_settings -d '{"index.blocks.read_only_allow_delete": null}'`.
  4. This makes indices writeable again but only buys time. Re-check
     Graylog index-rotation settings so the cluster does not climb back to
     95%.

  Prevention:
  - Configure index rotation in Graylog so the total rotation size of all
    index sets stays under ~85% of total HDD capacity.
  - If using time- or count-based rotation, size headroom for the upper
    bound — rotation strategies use unpredictable on-disk size.
  - As a last resort (NOT recommended for production), disable the
    disk-allocator threshold entirely:
    `PUT /_cluster/settings -d '{"persistent":
    {"cluster.routing.allocation.disk.threshold_enabled":"false"}}'`. With
    this off, indices never lock — but a misconfigured rotation will
    consume all free space.
```
