# Graylog — Troubleshooting

This section describes common problems with Graylog (server, web UI, deflector/indices, connection paths) and how to troubleshoot them.

## Problems with Connection to Graylog

### Unable to Connect to Graylog via Browser

To identify the root cause:

Connect via SSH to the virtual machine with Graylog deployed.

To see the information about `STATUS` of Graylog Docker containers, execute the following command.

```bash
docker ps -f "name=graylog"
```

The normal output contains four running containers with `STATUS` field equal to "UP N days.".
The four running containers include `graylog_web_1`, `graylog_graylog_1`, `graylog_storage_1`, and `graylog_mongo_1`.

In case the output contains a lesser number of containers, or their status differs from the norm,
then try to restart the container with the problem.

If you are unable to connect to the virtual machine using SSH, check the network connection using the `ping` command.

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

### HDD Full on Graylog VM

**Symptoms:**

* Graylog does not process any new messages.
* Search in logs shows various errors (for example, HTTP 500).
* OpenSearch is down, container constantly restarting.

**How to check:**

1. Log in to Graylog VM via SSH and execute `df -h`.
2. It shows you the information about the HDD utilization.

**How to fix:**

1. Log in to Graylog VM via SSH as root.
2. Execute the following commands:

   ```bash
   docker stop \
        graylog_web_1 \
        graylog_graylog_1 \
        graylog_storage_1 \
        graylog_mongo_1

   rm -rf /srv/docker/graylog/opensearch/nodes/

   docker start \
         graylog_mongo_1 \
         graylog_storage_1 \
         graylog_graylog_1 \
         graylog_web_1
   ```

3. If after cleaning up disk space you see 'index read-only' warnings in the Graylog Web UI,
   execute the following command on Graylog VM via SSH to unlock the index:

   ```bash
   curl -X PUT -u <username>:<password> -H "Content-Type: application/json" -d '{"index.blocks.read_only_allow_delete": null}' http://localhost:9200/_settings
   ```

   or command for usage in cloud Graylog:

   ```bash
   curl -X GET -u <username>:<password> -H "Content-Type: application/json" -d '{"index.blocks.read_only_allow_delete": null}' opensearch.opensearch-service:9200/_settings
   ```

   **Note**: All the existing logs are lost. To prevent it in the future, you need to adjust the indices
   rotation policy in Graylog according to the available HDD size. You can restore old logs from the backup.

   For checking blocked indices use the next command:

   ```bash
   curl -X GET -u <username>:<password> -H "Content-Type: application/json" opensearch.opensearch-graylog:9200/index_name
   ```

   If some index has `"read_only_allow_delete": "true"` it means that this index is blocked and new data
   can't be store in it. So you should unlock this index.

### Graylog Container OOM Killed (out of RAM)

**Symptoms:**

Graylog Web UI is not accessible or displays a 504 error.

**How to check:**

1. Login on Graylog VM via SSH and execute `docker ps`
2. It shows the container's status. If Graylog/opensearch containers are constantly restarting
   then it could be memory related issue

**How to fix:**

You can use any one of the following options to change the memory settings:

**Using Jenkins job:**

Run the redeploy of the Logging service procedure with the corrected `graylog_heap_size` and `es_heap_size` parameters.

**In manual mode:**

1. Log in to Graylog VM via SSH as root.
2. Execute the following command and remember the ID of the container with Graylog:

   ```bash
   docker inspect --format '{{.Id}}' graylog_graylog_1
   ```

3. Execute the following command and remember the ID of the container with OpenSearch:

   ```bash
   docker inspect --format '{{.Id}}' graylog_storage_1
   ```

4. Stop the Docker service using the following command:

   ```bash
   service docker stop
   ```

5. Change the memory parameter for the container with Graylog:
   In the `/var/lib/docker/containers/<container_id>/config.v2.json` file, find the `GRAYLOG_SERVER_JAVA_OPTS`
   parameter and correct its value.

   For example, it was 2GB:

   ```bash
   GRAYLOG_SERVER_JAVA_OPTS = -Xms2048m -Xmx2048m
   ```

   Corrected to 4GB:

   ```bash
   GRAYLOG_SERVER_JAVA_OPTS = -Xms4096m -Xmx4096m
   ```

6. Change the memory parameter for the container with OpenSearch:

   In the `/var/lib/docker/containers/<container_id>/config.v2.json` file, find the `ES_JAVA_OPTS`
   parameter and correct its value.

   By analogy with Graylog (step 5).

7. Start the Docker and restart the containers:

   ```bash
   service docker start

   docker restart \
        graylog_web_1 \
        graylog_graylog_1 \
        graylog_storage_1 \
        graylog_mongo_1

   ```

### Low Graylog Performance

**Symptoms:**

1. Graylog Web UI is very slow
2. Graylog doesn't show any messages in search within the last 5-15 minutes
3. There is a notification "Journal utilization is too high" in the UI

**How to check:**

1. Log in to Graylog VM via SSH as root
2. Navigate to `top`
3. Check the resource consumption. You can also check resource consumption using System Monitoring if available.
   Define what kind of resource (CPU/RAM/HDD IOPS) is not enough according to the
   [documentation](../installation.md#hwe).

**How to fix:**

Add missing resources to the target VM.

See the section [Performance tuning](#performance-tuning) for additional information
about Graylog's tiny performance tuning aspects

Restart Graylog by executing the following commands:

```bash
docker restart \
    graylog_web_1 \
    graylog_graylog_1 \
    graylog_storage_1 \
    graylog_mongo_1
```

After restart go to `/system/inputs` in the Graylog UI and stop input messages by button `Stop input`.
This helps to prevent repeated Graylog flooding.

Go to detailed information about node by /system/nodes and button `Details`.

Wait for the input buffer to be freed. This will mean that Graylog has processed the messages.

Wait for journal utilization will reduce to values 0-5%. After that, you can run input.

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

* [HDD Full on Graylog VM](#hdd-full-on-graylog-vm)
* [Graylog container OOM killed (out of RAM)](#graylog-container-oom-killed-out-of-ram)
* [Low Graylog Performance](#low-graylog-performance)
* OpenSearch issue. Restarting the containers can help in this case. For more information, see [Low Graylog performance](#low-graylog-performance).

### Index Oversized

**Symptoms:**

* The HDD space utilization on the Logging VM is high. It exceeds the maximum possible utilization configured
  in the indices rotation policies.
* The size of one of the indices in OpenSearch is very big, more than what is configured
  in the `Max index size` parameter on the Index Set configuration.

You can check the indices size using the following command on Logging VM:

```bash
curl -X GET -u <username>:<password> -sk https://localhost/api/system/indexer/indices
```

**Root cause:**

Graylog indexer bug. It is a rare cause. A manual workaround can be applied if this issue occurs.

**How to fix:**

**Note**: Take a backup prior to deleting.

Delete an oversized index manually by executing the following command on the Logging VM:

```bash
curl -X DELETE -u <username>:<password> -H "X-Requested-By: graylog" https://localhost/api/system/indexer/indices/<index name>
```

### Negative number of Unprocessed Messages

If you have a negative number of unprocessed messages in the `Disk Journal` section it means that
you clean the journal directory but not completely.

**How to fix:**

Stop Graylog container:

```bash
docker stop graylog_graylog_1
```

Completely remove the directory:

```bash
{{ graylog_volume }}/graylog/data/journal/*
```

where `{{ graylog_volume }}` by default has the value `/srv/docker/graylog`, so to remove you need to execute a command:

```bash
rm -rf /srv/docker/graylog/graylog/data/journal/*
```

Start Graylog container:

```bash
docker start graylog_graylog_1
```

If you'd like to switch off the journal messages, you should also update `/srv/docker/graylog/graylog/config/graylog.conf`
and set parameter `message_journal_enabled=false`.

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

If you are faced with such a problem during the update of the Logging VM it means that before the update
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
6. Graylog VM CPU is fully utilized, VM became unresponsive even via SSH

### Common performance principles

* First of all, check the hardware resources of your Graylog instance according to the [table](../installation.md#hwe).
  The most important thing is disk speed and almost all performance issues can be solved by increasing it.
* Use `sysbench` to measure disk speed
* RAM and CPU are the second priority but it is also important
* Graylog does not require much RAM. 4-8 GB is enough. Better give more RAM to OpenSearch

## Extra tips and tricks

### `/srv/docker/graylog/graylog/config/graylog.conf`

* `processbuffer_processors`, `outputbuffer_processors` - set to CPU count / 2.
* `ring_size` - set to 131072 or to 262144 if you have 4+ RAM for Graylog. Higher values are not recommended

### Crackdown for heavy loads

* Remove the `Logs Routing` pipeline from Graylog. It will save the CPU, but logs routing to streams will be lost.
* Disable disk journal in Graylog to prevent disk concurrency between Graylog and OpenSearch.
* Disable collection of system and audit-system logs on the FluentD side
