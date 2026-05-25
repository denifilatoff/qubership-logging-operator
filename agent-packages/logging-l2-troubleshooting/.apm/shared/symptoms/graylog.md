# Graylog — Troubleshooting

This section describes common problems with Graylog (server, web UI, deflector/indices, connection paths) and how to troubleshoot them.

## Problems with Connection to Graylog

### Unable to Connect to Graylog via Browser

To identify the root cause, inspect the Graylog workload state in the cluster:

```bash
kubectl -n <logging-ns> get pods,svc -l app.kubernetes.io/name=graylog -o wide
kubectl -n <logging-ns> describe pod <graylog-pod>
```

Healthy state: all Graylog pods `Running` with no recent restarts. If a pod is in `CrashLoopBackOff`,
`OOMKilled`, or has a high restart count, follow the matching section below (OOM, performance, etc.).

If the pods look healthy but the UI is still unreachable from the browser, the path between the browser
and the Service is the next thing to check — Ingress/Route, TLS, and any L7 load balancer in front of
Graylog. The HTTP API at `https://<graylog>/api/...` is the canonical reachability probe.

### Unable to Read Log Messages

To check for errors, navigate to the **System > Overview** tab.

![graylog-system-overview](../images/graylog/system-overview.png)

Navigate to the deployed FluentD (usually it is the "logging" project), and see the pods' health-check reports.

### Ingress/Route to Graylog cyclic redirect

Applicable for DR no-vIP schema only.

In this schema Logging service deploy procedure creates an external service in OpenShift.
By accessing this external service via OpenShift coordinates `graylog.logging.svc.cluster.local` other
applications can work with active Graylog instances.

Also, we created a Route for accessing of active Graylog Web UI. If OpenShift contains separate Load Balancers
with HTTPS certificates on them, this route will not work. It returns 302 (redirect) to itself,
getting an infinite loop.

To fix it manual actions are required. Route URL needs to be added into _os_sni_passthrough.map_ file on Load Balancers.

## Typical Issues

### Storage Full

**Symptoms:**

* Graylog does not process any new messages.
* Search in logs shows various errors (for example, HTTP 500).
* OpenSearch pod is down or constantly restarting.

**How to check:**

```bash
# PVC utilisation behind Graylog and OpenSearch
kubectl -n <logging-ns> get pvc
kubectl -n <logging-ns> describe pvc <graylog-pvc> <opensearch-pvc>

# Node-level disk pressure on the nodes hosting the workloads
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}: {.status.conditions[?(@.type=="DiskPressure")].status}{"\n"}{end}'

# OpenSearch-side view (most informative)
curl -sk -u <u>:<p> https://<os-host>:9200/_cat/allocation?v
```

**How to fix:**

The disk-cleanup itself — clearing OpenSearch node data on the underlying PVC — is **out of scope for
these skills** (K8s-only execution surface; we do not run destructive workflows against PVC contents).
Escalate to the cluster operator: the recovery procedure typically involves scaling down the OpenSearch
StatefulSet, mounting the PVC into a debug pod, removing the noisy node data, and starting OpenSearch
back up. The exact procedure depends on the chart and the operator team's runbook.

What stays in scope here is unlocking indices once disk pressure is relieved. If you see `index
read-only` warnings in the Graylog UI after the cleanup, unlock the indices via the OpenSearch HTTP API:

```bash
curl -X PUT -u <username>:<password> -H "Content-Type: application/json" \
     -d '{"index.blocks.read_only_allow_delete": null}' \
     https://<opensearch-host>:9200/_settings
```

**Note**: Any logs that lived on the wiped node data are lost. To prevent this in the future, adjust
the Graylog index-rotation policy to fit the PVC size. Restore old logs from backup if you have one.

To check which indices are blocked:

```bash
curl -X GET -u <username>:<password> -H "Content-Type: application/json" \
     https://<opensearch-host>:9200/<index_name>/_settings
```

If an index has `"read_only_allow_delete": "true"`, it is blocked and cannot accept new data — unlock it
with the PUT above.

### Graylog Pod OOM Killed (out of RAM)

**Symptoms:**

Graylog Web UI is not accessible or displays a 504 error.

**How to check:**

```bash
kubectl -n <logging-ns> get pods -l app.kubernetes.io/name=graylog
kubectl -n <logging-ns> describe pod <graylog-pod> | grep -A3 'Last State\|OOMKilled'
```

If the pod's `LastState.terminated.reason` is `OOMKilled`, or restart count is climbing, the cause is
memory-related. The same check applies to the OpenSearch pod (`-l app.kubernetes.io/name=opensearch`).

**How to fix:**

Heap and memory limits for Graylog and its MongoDB sidecar are owned by the operator's
`LoggingService` CR (or, on a chart-only install, by Helm values). Do **not** edit pod specs or
container env directly — the operator reconciles them back.

Adjust:

* `graylog.graylogResources.{requests,limits}.memory` — pod memory request and limit. Chart defaults:
  requests `1536Mi`, limits `2048Mi`.
* `graylog.javaOpts` — Graylog server `JAVA_OPTS` string. Chart-shipped default is
  `-Xms1024m -Xmx1024m`. Keep `-Xmx` inside the pod's memory limit (rule of thumb: heap ≤ ~75% of the
  limit so the off-heap and JVM-internal allocations fit).
* `graylog.mongoResources.{requests,limits}.memory` if MongoDB itself is OOMing (chart default 256Mi).

For OpenSearch, **this operator does not manage OpenSearch lifecycle** — `LoggingService.spec.openSearch`
is only a client config (`url`, TLS, credentials). OpenSearch heap and pod limits live in whatever
operator / chart deploys OpenSearch in your installation. The `installation.md` document in this repo
notes: "When deploying Graylog in the cloud, you need to include the resource requirements for the
OpenSearch cluster — refer to the OpenSearch documentation for details on hardware requirements."

For sizing reference (pairings of message rate × Graylog heap × OpenSearch heap × disk speed) the
operator repo ships a Hardware-requirements table at `docs/installation.md` with concrete Small /
Medium / Large profiles calibrated to message-per-second load. If that file is reachable from the
agent's working directory (it is, in this repo), grep it for the table; otherwise the
LoggingService chart's defaults (cited above) are the canonical starting point.

The operator picks up CR / values changes and rolls the Graylog StatefulSet on its own. If a rollout
doesn't happen, force it with `kubectl -n <logging-ns> rollout restart sts/graylog`.

### Low Graylog Performance

**Symptoms:**

1. Graylog Web UI is very slow
2. Graylog doesn't show any messages in search within the last 5-15 minutes
3. There is a notification "Journal utilization is too high" in the UI

**How to check:**

```bash
# Pod-level resource consumption
kubectl -n <logging-ns> top pod -l 'app.kubernetes.io/name in (graylog,opensearch)'

# Node-level pressure on the nodes hosting Graylog / OpenSearch
kubectl top nodes
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}: cpu={.status.conditions[?(@.type=="CPUPressure")].status} mem={.status.conditions[?(@.type=="MemoryPressure")].status} disk={.status.conditions[?(@.type=="DiskPressure")].status}{"\n"}{end}'

# Graylog-side view — the journal is the canonical indicator
curl -sk -u <u>:<p> https://<graylog>/api/system/journal
```

Identify whether the bottleneck is CPU, RAM, or disk IOPS. OpenSearch is disk-IO greedy; Graylog under
journal pressure becomes both CPU- and disk-heavy.

**How to fix:**

Increase the constrained resource via the `LoggingService` CR (or Helm values for chart-only installs).
The relevant Graylog-side fields are `graylog.graylogResources.{requests,limits}` and
`graylog.javaOpts` (heap). OpenSearch lifecycle is **not** managed by this operator — adjust it via
whatever operator / chart deploys OpenSearch in your installation. The logging-operator rolls
Graylog on its own once the CR / values change.

See [Performance tuning](#performance-tuning) for Graylog-internal knobs (process/output buffers,
ring size, journal toggle).

If a restart is needed (e.g. to apply a ConfigMap-loaded change that did not pick up):

```bash
kubectl -n <logging-ns> rollout restart sts/graylog
```

After restart, go to `/system/inputs` in the Graylog UI and click `Stop input` for each input. This
prevents repeated flooding. Wait for the input buffer to drain and the journal utilization to fall to
0–5%, then re-enable the inputs.

### Graylog Not Processing Messages

**Symptoms:**

* New logs are not available for search
* Search does not work at all

**How to check:**

1. Navigate to `http://<graylog>/system/nodes`.
2. Check `The journal contains X unprocessed messages`.
3. If `X` is high (> 100000) and keeps growing, it is an issue.

**How to fix:**

Root cause: OpenSearch does not take payload.

Possible reasons and solutions:

* [Storage Full](#storage-full)
* [Graylog Pod OOM Killed (out of RAM)](#graylog-pod-oom-killed-out-of-ram)
* [Low Graylog Performance](#low-graylog-performance)
* OpenSearch issue. Restarting the OpenSearch pod can help in this case (`kubectl -n <logging-ns> rollout restart sts/opensearch`). For more information, see [Low Graylog performance](#low-graylog-performance).

### Index Oversized

**Symptoms:**

* PVC utilisation behind Graylog/OpenSearch is high. It exceeds the maximum possible utilisation
  configured in the indices rotation policies.
* The size of one of the indices in OpenSearch is very big, more than what is configured
  in the `Max index size` parameter on the Index Set configuration.

You can check the indices size using the Graylog HTTP API:

```bash
curl -X GET -u <username>:<password> -sk https://<graylog>/api/system/indexer/indices
```

**Root cause:**

Graylog indexer bug. It is a rare cause. A manual workaround can be applied if this issue occurs.

**How to fix:**

**Note**: Take a backup prior to deleting.

Delete an oversized index manually via the Graylog API:

```bash
curl -X DELETE -u <username>:<password> -H "X-Requested-By: graylog" https://<graylog>/api/system/indexer/indices/<index_name>
```

### Negative number of Unprocessed Messages

If you have a negative number of unprocessed messages in the `Disk Journal` section it means that
the journal directory was cleared partially while Graylog kept its in-memory counters.

**How to fix:**

Recovery is to stop Graylog, completely empty the journal directory on its persistent storage, and
start Graylog again. In-flight messages still in the journal at the time of cleanup are lost; messages
buffered upstream (FluentD / FluentBit) will be re-delivered.

The actual cleanup runs against the Graylog StatefulSet's PVC — the typical sequence is `kubectl
-n <logging-ns> scale sts graylog --replicas=0`, mount the PVC into a debug pod, `rm -rf` the
journal directory, scale back up. The exact mechanic depends on the chart and the operator team's
runbook — escalate to the cluster operator. This skill emits the diagnosis but does not execute the
PVC-side cleanup (K8s-only execution surface; destructive writes against PVC contents are out of scope).

If you'd like to disable the journal entirely, set `message_journal_enabled=false` in the Graylog
configuration. Under the operator, this lives in the `LoggingService` CR (or the Helm values for
chart-only installs) — do not edit the ConfigMap directly, the operator reconciles it back.

### Incorrect timestamps in Graylog

If you have different time values (time zones) in the `message`,  the `time`, and the `timestamp` fields,
need to check the timezone on nodes. The timezone must be set to UTC on each node.

Or you can change the timezone in the user settings in the Graylog to the timezone that is set on the nodes,
but this will not change the time inside the `message` field  (it will be equal UTC timezone).

### Information about OpenSearch nodes is unavailable

If you log in to Graylog UI, go to `System -> Nodes` and see that info about Elastic nodes is unavailable:

![Node info is unavailable](../images/graylog/wrong-certificate-nodes-info.png)

Then, if you click on the node's name (`44a226cb/graylog-0` from the example above), you'll probably face an error like
this:

![Unavailable node details](../images/graylog/wrong-certificate-details.png)

In this case, you should check that your Graylog's TLS certificate is not expired and contains valid alt names (e.g.
it must contain `graylog-service.logging.svc` if your Graylog is deployed into the `logging` namespace in the Cloud).

If you use a self-signed certificate,
[the article about certificate generation](../user-guides/tls.md#self-signed-certificate-generation) can be useful for you.

### Widgets do not show data with errors

In case of problems with indices in OpenSearch Graylog can show errors on the widgets.

For example with messages:

<!-- markdownlint-disable line-length -->
```bash
While retrieving data for this widget, the following error(s) occurred:

Unable to perform search query: Elasticsearch exception [
  type=illegal_argument_exception,
  reason=Text fields are not optimized for operations that require per-document field data like aggregations and sorting, so these operations are disabled by default. Please use a keyword field instead. Alternatively, set fielddata=true on [timestamp] in order to load field data by uninverting the inverted index. Note that this can use significant memory.
].
```
<!-- markdownlint-enable line-length -->

Also, in the Graylog logs you can see a similar error:

<!-- markdownlint-disable line-length -->
```bash
type=illegal_argument_exception,
reason=Text fields are not optimized for operations that require per-document field data like aggregations and sorting, so these operations are disabled by default. Please use a keyword field instead. Alternatively, set fielddata=true on [timestamp] in order to load field data by uninverting the inverted index. Note that this can use significant memory.
```
<!-- markdownlint-enable line-length -->

This error usually occurs when:

* Created custom OpenSearch index
* Created a Stream that routes messages in custom OpenSearch index

Created custom OpenSearch index may have fields declared with incorrect type or non-declared fields.
The second reason is most typical for custom indices.

OpenSearch has a dynamic typing and a set of fields in the index. It means that OpenSearch
tries to automatically select a type for a new field if you didn't declare the field, and OpenSearch
receives a request to save data with this new field.

And selected type may not apply to Graylog. For example, Graylog can't use text fields to use them in sorting.

**Solution:**

Check the error and find which field has an incorrect type. For example, for the error above the problem field will be:

```bash
Alternatively, set fielddata=true on [timestamp] in ...
```

field with name `timestamp`.

Next, you have to check its type using requests to OpenSearch API. The following requests will help you:

* If you don't know index name or want to check the field type in all indices:

    ```bash
    GET /_mapping/field/<field>
    ```

* If you know the index name:

    ```bash
    GET /<index_name>/_mapping/field/<field>
    ```

* If you want to check all index mapping:

    ```bash
    GET /_index_template/<index_name>
    ```

After that, you need to change your index mapping, declare the necessary field (if it wasn't declared)
and set the correct type. For example, if you are faced with an incorrect type to `timestamp` field you need to use
the `date` type for this field.

**How to avoid this issue:**

You have to remember about dynamic typing and declare all fields for custom OpenSearch indices.

### Deflector exists as an index and is not an alias

Graylog uses a special OpenSearch alias to write and read logs always in the last index. This alias has
a postfix `_deflector` and it is managed by Graylog.

If Graylog detects that OpenSearch already has the index with a name:

```bash
<index_name>_deflector
```

it will raise the error in the UI (you can see it on the Overview page):

```bash
Deflector exists as an index and is not an alias
```

This problem may occur in two cases:

* Somebody manually created an index in OpenSearch with the name that Graylog wants to use as an alias
* During the update, you faced the following scenario:
  * Graylog is working and can receive logs
  * Agents active and send logs
  * Stream is already created, but mapped on non-existing Index
  * Index (that should store data from the Stream above) does not exist

In the last case, OpenSearch can receive a request to save data before Graylog creates the index and assigns
the deflector alias to it. You can understand and verify it by Graylog and OpenSearch logs.
For example:

* Graylog logs:

    ```bash
    [2023-10-26T12:49:12,327][WARN]Active write index for index set "v2_cis_inventory_change_log" (653a6047ab6c072bb306a2d5) doesn't exist yet
    ```

* OpenSearch logs:

    ```bash
    [2023-10-26T12:49:12,391][INFO ][o.o.c.m.MetadataCreateIndexService] [604eb8d3c4b3] [v2_cis_inventory_change_log_deflector] creating index, cause [auto(bulk api)], templates [v2_cis_inventory_change_log], shards [1]/[1]
    [2023-10-26T12:49:12,839][INFO ][o.o.c.m.MetadataMappingService] [604eb8d3c4b3] [v2_cis_inventory_change_log_deflector/3_kIpr9zQYunZMeZgumPVA] update_mapping [_doc]
    ```

**Solution:**

If you manually create the index with such a name, you have to remove it. And do not try to use such a name in the future.

If you are faced with such a problem during a Logging-stack upgrade, it means that before the upgrade
you must **disable all Graylog Inputs**.

To do it you need:

* Open Graylog UI
* Navigate to `System -> Inputs`
* Click on the button `Stop input` for each input

After upgrade will be successfully complete you can start all inputs.

**How to avoid this issue:**

You shouldn't create indices with postfix `_deflector` and use it as an alias. It's a reserved alias by Graylog.

During updates that should be created Streams that use custom indices, you must stop all Graylog Inputs.

## Performance tuning

### Typical symptoms of performance issues and common words

Graylog uses OpenSearch as backend storage for log data. Graylog itself acts as an incoming logs receiver and processor.
Graylog does not require many resources and in regular operations, it cannot be overloaded.
In most cases OpenSearch is a bottleneck - it cannot receive all logs from Graylog because of
a lack of resources.

OpenSearch is Disk speed greedy at first and RAM greedy at second.

If OpenSearch cannot handle all incoming log data - Graylog buffers grow, including disk journal.
Graylog began to utilize disk and CPU for serving journals which slowed down OpenSearch more and more.
As a result, the system falls into an unstable state.

The symptoms (from small overload to significant overload):

1. Low performance of search operations in Graylog
2. Graylog journal grows. Journal size 0-50k messages if fine. 50k-100k is worth. 500k+ is almost a disaster
3. Logs search does not show recent logs (because they are in Graylog's journal, not in OpenSearch)
4. Graylog UI slowness, random 500 and 503 errors
5. Graylog UI is down
6. CPU on the node hosting Graylog is fully utilised — Graylog pod becomes unresponsive, `kubectl exec` into it stalls

### Common performance principles

* First of all, check that the Graylog pod resource limits (`graylog.graylogResources` in the
  LoggingService CR / Helm values) and the OpenSearch deployment's resource limits and storage class
  match the expected load. The most important thing is disk speed on the OpenSearch volume; almost all
  performance issues can be solved by giving OpenSearch faster underlying storage.
* RAM and CPU are the second priority but they also matter.
* Graylog does not require much RAM. 4–8 GB is enough. Prefer to give more RAM to OpenSearch.

## Extra tips and tricks

### `graylog.conf` settings

Under the operator, these knobs live in the `LoggingService` CR (or the Helm values for chart-only
installs), which the operator renders into the Graylog ConfigMap. Do not edit the ConfigMap directly.

* `processbuffer_processors`, `outputbuffer_processors` — set to CPU count / 2.
* `ring_size` — set to 131072, or to 262144 if you have 4+ GB RAM allocated to Graylog. Higher values are not recommended.

### Crackdown for heavy loads

* Remove the `Logs Routing` pipeline from Graylog. It will save the CPU, but logs routing to streams will be lost.
* Disable disk journal in Graylog to prevent disk concurrency between Graylog and OpenSearch.
* Disable collection of system and audit-system logs on the FluentD side
