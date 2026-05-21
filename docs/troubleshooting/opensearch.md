# OpenSearch — Troubleshooting

## Limit of total fields has been exceeded

**Symptoms:**

In OpenSearch's or Graylog's logs (or responses on API calls) generated one or some errors like:

```bash
Limit of total fields [1000] in index [test_index] has been exceeded
```

**Root cause:**

OpenSearch has a mechanism to prevent mapping explosions (too many dynamical fields):

* [https://www.elastic.co/guide/en/elasticsearch/reference/master/mapping.html#mapping-limit-settings](https://www.elastic.co/guide/en/elasticsearch/reference/master/mapping.html#mapping-limit-settings)
* [https://www.elastic.co/guide/en/elasticsearch/reference/master/mapping-settings-limit.html](https://www.elastic.co/guide/en/elasticsearch/reference/master/mapping-settings-limit.html)
* [https://opensearch.org/docs/latest/field-types/#mapping-limit-settings](https://opensearch.org/docs/latest/field-types/#mapping-limit-settings)

By default OpenSearch/Elasticsearch doesn't allow to save new fields in the index after reach the limit in **1000** fields.

**How to fix:**

Usually this issue occurs due the incorrect work of agent that should parse logs and send them to Graylog.

FluentBit or FluentD has a logic to parse new dynamical fields from the log's `message` and add these fields as metadata
in logs sending to Graylog.

There are some issues in FluentBit and FluentD that could lead to parse parts of `message` as `key=value` pairs.
For example, from the log:

```bash
[2024-09-30T04:59:40.498] [DEBUG] [request_id=1a04d001-37e6-418b-bc7f-4904d4dfc753] [tenant_id=-] [thread=main-8e36d]
[class=mongo:storage.go:236] [traceId=0000000000000000176d565380a60f8b] [spanId=04546e4d3320dc9b] try to delete objects
from certificates by filter map[$and:[map[meta.status:map[$ne:trusted]] map[$or:[map[meta.deactivatedAt:map[$lte:2024-08-31
04:59:40.498507159 +0000 UTC m=+6199354.549415617]] map[details.validTo:map[$lte:2024-08-31 04:59:40.498507159 +0000 UTC
m=+6199354.549415617]]]]]]
```

expect `key=value` from the `message` part

```bash
[request_id=1a04d001-37e6-418b-bc7f-4904d4dfc753] [tenant_id=-] [thread=main-8e36d] [class=mongo:storage.go:236] [traceId=0000000000000000176d565380a60f8b] [spanId=04546e4d3320dc9b]
```

was parsed the `key=value` pair:

```bash
_lte_2024-08-31_04_59_40_498507159__0000_UTC_m = +6199354.549415617
```

So if you faced with such issues we recommended to update to latest version of Logging and check again.

In the case, if you use external agent or send logs directly to Graylog, need to check your agent settings or
service/application that send these logs.

**Useful script to clean `trash` fields:**

All early saved `trash` `key=value` pairs will removed with indices when rotation strategy decided to remove index.

But if you already fixed the root cause of issue due FluentBit or FluentD (or other agent) generated a lot of dynamic fields
you can use the script to remove already saved `trash` fields in indices:

```painless
List fieldsToRemove = new ArrayList();
for (entry in ctx._source.keySet()) {
  if (entry.startsWith('ErrorEntry_')) {
    fieldsToRemove.add(entry);
  }
}
for (field in fieldsToRemove) {
  ctx._source.remove(field);
}
```

where `ErrorEntry_` it's a prefix of fields that should be remove and that you need to change.

This script can be execute using OpenSearch API:

**Warning!** Pay attention that it may require a lot of time, and CPU resources because you need to update all indices
and docs in indices.

```bash
curl -X POST -u <username>:<password> -H 'Content-Type: application/json' http://localhost:9200/<index_name>/_update_by_query -d '{
  "query": {
    "match_all": {}
  },
  "script": {
    "lang": "painless",
    "source": "List fieldsToRemove = new ArrayList();\nfor (entry in ctx._source.keySet()) {\n  if (entry.startsWith(\"ErrorEntry_\")) {\n    fieldsToRemove.add(entry);\n  }\n}\nfor (field in fieldsToRemove) {\n  ctx._source.remove(field);\n}"
  }
}'
```

where `<index_name>` can contain some indices separated by a comma, or "*", see
[https://opensearch.org/docs/latest/api-reference/document-apis/update-by-query/#path-parameters](https://opensearch.org/docs/latest/api-reference/document-apis/update-by-query/#path-parameters).

**Note:** If the index will be locked on write you can unlock it using the command:

```bash
curl -X PUT -u <username>:<password> -H 'Content-Type: application/json' -d '{"index.blocks.write": "false"}' http://localhost:9200/<index_name>/_settings
```

## Errors `no such index [.opendistro-ism-config]`

**Symptoms:**

In OpenSearch's logs generated one or some errors like:

```bash
[2024-10-11T11:47:21,697][ERROR][o.o.i.i.ManagedIndexCoordinator] [881c8d26fd21] get managed-index failed: [.opendistro-ism-config] IndexNotFoundException[no such index [.opendistro-ism-config]]
```

**Root cause:**

This error message has no effect on your OpenSearch.

It is generated in the `index-management` plugin for OpenSearch. Someone already asked the community
about this error in the GitHub issue:
[https://github.com/opensearch-project/index-management/issues/697](https://github.com/opensearch-project/index-management/issues/697)

The quote from the GitHub issue about this error log:

> This is actually intended behavior for the ISM plugin, and should not have any negative impact.
> However, we agree that logging this exception as an "ERROR" is inappropriate for this use case.
> This occurs because the plugin listener picks up a "ClusterChangedEvent" whenever an index is deleted,
> as we want the plugin to then check for any plugin-specific metadata related to that index.
> However, since the ISM plugin had not been used yet in your example (e.g., an ISM policy hasn't been created),
> the `.opendistro-ism-config` index had not been created.

The plugin's authors changed the level from ERROR to DEBUG since version 2.10.0.0:

* [https://github.com/opensearch-project/index-management/releases/tag/2.10.0.0](https://github.com/opensearch-project/index-management/releases/tag/2.10.0.0)
* [https://github.com/opensearch-project/index-management/pull/846](https://github.com/opensearch-project/index-management/pull/846)

**How to fix:**

There are four theoretical ways to avoid/remove this error:

* Add at least one ISM rule in OpenSearch, in this case, OpenSearch should create the system index
  `.opendistro-ism-config` which by default doesn't exist
* Disable this plugin

  ```yaml
  plugins.index_state_management.enabled: False
  ```

  Official documentation: [https://opensearch.org/docs/latest/im-plugin/ism/settings/](https://opensearch.org/docs/latest/im-plugin/ism/settings/)

* Upgrade OpenSearch to `>=2.10.x` version
* Ignore this error message

The option with upgrade OpenSearch to 2.x version now is not available, it's just a theoretical option.

## OpenSearch uses more than 32 GB of RAM

In case of a high load to Graylog and OpenSearch, you may want to allocate more than ~32 GB RAM
for OpenSearch. After that, you may notice that OpenSearch performance got even worse.

For example, if become often fails with OOM or processes less throughput than with a memory limit less than ~32 GB.

It occurs because after you set `-Xmx` for OpenSearch to more than ~32 GB it starts to use 64-bit
Ordinary Object Pointers (OOP) instead of 32-bit pointers. As a result, it decreases memory efficiency.

The official OpenSearch documentation tells us that in fact, it takes until around **40–50 GB** of allocated heap
before you have the same effective memory of a heap just under **32 GB** using compressed oops.

OpenSearch/Elasticsearch documentation
[Don't Cross 32 GB!](https://www.elastic.co/guide/en/elasticsearch/guide/current/heap-sizing.html#compressed_oops).

**How to fix:**

Usually, if you want to increase the memory limit for OpenSearch it means that you don't want
to do a deeper analysis of the problems. And you want just adding resources in hopes it will help.

To fix this issue you first of all need to decrease the memory limit for OpenSearch to ~32 GB.

Second, you need to remember that on the Logging VM, there are other applications and processes like Graylog,
MongoDB and Nginx. All these applications run as Docker containers and require some memory to run. Also, Java
applications can use more than set in `-Xmx`. This happens because of the way Java handles memory.

Deployment scripts of the Logging VM allow to specify limits for Graylog and OpenSearch.
So you have to specify a summary of limits for Graylog and OpenSearch less than the total VM memory size.
Also, you need to remember that you must leave 20-50% of free RAM on the VM.

Some examples (it's not recommendations, just examples):

* Graylog VM has 16 GB RAM, in this case, you can allocate:
  * Graylog - 4 GB
  * OpenSearch - 8 GB
* Graylog VM has 32 GB RAM, in this case, you can allocate:
  * Graylog - 8 GB
  * OpenSearch - 12-18 GB
* Graylog VM has 64 GB RAM, in this case, you can allocate:
  * Graylog - 20 GB
  * OpenSearch - 24-31 GB

After it and after you will fix OOM in Graylog or OpenSearch you can try to analyze which other
performance issues you have.

## Index read-only Warnings

**Symptoms:**

* A lot of `index X is read-only` warnings in `https://<graylog_url>/system/indices/failures`
* Graylog does not store logs in the OpenSearch. In or Out messages count is non-zero,
  but recent logs cannot be found on the **Search** page.

**Root cause:**

OpenSearch has a disk-allocator feature that marks indices as `read-only` if disk space utilization is too high.
By default, this feature is turned on and indices become `read-only` if disk space usage is **95%**.

Also, there are two threshold after reach which OpenSearch start signal about problems about high disk usage:

* Low - **80%**
* High - **90%**

**How to fix:**

Fist of all, if OpenSearch indices already marked as `read-only` you need to check disk space and cleanup data.

You can use the OpenSearch API to get list of indices and to remove old indices.
For example:

* To get list of indices:

  ```bash
  curl -X GET -u <username>:<password> http://localhost:9200/_cat/indices
  ```

* To remove indices by name, by some names (use colon `,` as separator) or regular expression:

  ```bash
  curl -X DELETE -u <username>:<password> http://localhost:9200/<index_name_or_regex>
  ```

  example:

  ```bash
  curl -X DELETE -u <username>:<password> http://localhost:9200/graylog_30,graylog_31
  ```

If OpenSearch is unavailable or you can't use it API usually OpenSearch save all it data in the host directories:

```bash
/srv/docker/graylog/opensearch/nodes
/srv/docker/graylog/opensearch/archives
/srv/docker/graylog/opensearch/snapshots
```

So you can clean data from these directories manually.

**Warning!** After remove some data from directories manually you **have to restart** OpenSearch container.

Next, you can run the command to remove `read-only` flag from indices:

```bash
curl -X PUT -u <username>:<password> -H "Content-Type: application/json" -d '{"index.blocks.read_only_allow_delete": null}' http://localhost:9200/_settings
```

It makes the OpenSearch indices writeable, but it helps only for some time.
Because indices were locked, the Graylog indices rotation is configured incorrectly and the disk is used for **95%** again.

Next, you should re-check your Index rotation settings in Graylog and change the to avoid this situation in the future.

**How to avoid this issue:**

You need to configure the indices rotation in Graylog to avoid high disk space utilization. Best practices are as follows:

* The total rotation size of all index sets should not be more than **85%** of the total HDD size
* If you want to use time or message count based on rotation, you **must** correctly calculate the required storage,
  but please keep in mind that rotation strategies can use unpredictable storage size on disk

You can disable the OpenSearch disk allocator feature by executing the following command on the Logging VM:

**Warning!** We strongly don't recommend use it for production environments!

```bash
curl -X PUT -u <username>:<password> -H "Content-Type: application/json" -d '{"persistent": {"cluster.routing.allocation.disk.threshold_enabled": "false"}}' http://localhost:9200/_cluster/settings
```

In this case, the indices are never locked in a read-only state. If the indices rotation configuration is incorrect,
the free space can be fully occupied. Ensure that the rotation configuration is correct.
