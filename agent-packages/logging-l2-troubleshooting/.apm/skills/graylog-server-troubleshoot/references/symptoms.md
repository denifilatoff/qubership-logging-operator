# Graylog server — symptom catalog

Prose condensed from `docs/troubleshooting.md`. For each `symptom_id` the matcher returns, read its section, confirm the
condition holds, then write your analysis. Always also review the `Detection: manual` entries — the matcher never
returns them.

## graylog-ui-unreachable

**Detection: manual** **What:** Graylog is unreachable from the browser — the UI returns an error or times out, even
though the Graylog pod may be healthy. **Confirm:** Run
`kubectl -n <ns> get pods,svc -l app.kubernetes.io/name=graylog -o wide` and
`kubectl -n <ns> describe pod <graylog-pod>`. Note pod phase, restart count, and any non-Ready conditions. If the pods
are Running/Ready, probe the HTTP API from inside the cluster: `curl -sk https://<graylog>/api/system/lbstatus`. Quote
the pod state and the probe result. **Fix:** If pods are not Running (CrashLoopBackOff, OOMKilled, high restart count),
route to the matching symptom (`graylog-pod-oom-killed`, `graylog-low-performance`, etc.). If pods are healthy but the
UI is unreachable, the fault is in the path between the browser and the Service: inspect the Ingress/Route, TLS
termination, and any L7 load balancer in front of Graylog. The HTTP API at `https://<graylog>/api/...` is the canonical
reachability probe. Rollback: no state change — this is a diagnostic routing step.

## graylog-unable-to-read-messages

**Detection: manual** **What:** Graylog is reachable but log messages are not visible in search — the System > Overview
tab shows flagged errors. **Confirm:** Open Graylog UI → `System > Overview` and screenshot or capture the flagged
errors. Include `kubectl -n <ns> get pods -l app.kubernetes.io/name=fluentd -o wide` to show FluentD pod health in the
logging namespace. **Fix:** Act on each flagged error shown in `System > Overview`. Cross-check FluentD pods in the
logging namespace; if any are unhealthy, hand off to the FluentD expert. Rollback: no state change — this is an
investigative step. **Caveat / next:** if the FluentD pods are unhealthy, route to the FluentD expert rather than
pursuing Graylog-side fixes.

## graylog-route-cyclic-redirect

**Detection: manual** **What:** The Graylog Route in an OpenShift DR no-vIP topology returns HTTP 302 to itself, causing
an infinite redirect loop in the browser. **Confirm:** Quote the HTTP response: `curl -sIk https://<route>` showing a
302 redirect pointing back to the same Route URL. Confirm the cluster is on an OpenShift DR no-vIP topology with
external HTTPS-terminating load balancers in front of the Route. **Fix:** Add the Route URL to the
`os_sni_passthrough.map` file on the load balancers so the SNI request reaches the Route directly. Manual configuration
on the LB hosts is required. Rollback: remove the added entry from `os_sni_passthrough.map`. **Caveat / next:** this fix
applies only to the DR no-vIP OpenShift schema; in other topologies a 302 loop indicates a different ingress
misconfiguration.

## graylog-opensearch-storage-full

**What:** Disk pressure — an OpenSearch node's `disk.percent` is ≥ 90, or the Graylog/OpenSearch PVC is full, causing
the pod to CrashLoopBackOff and Graylog to stop processing logs. **Confirm:** Quote `kubectl -n <ns> get pvc` and
`kubectl -n <ns> describe pvc <pvc>` for the Graylog and OpenSearch PVCs. Capture `DiskPressure` conditions on cluster
nodes. Run `curl -sk -u <u>:<p> https://<opensearch>/_cat/allocation?v` and quote any row where `disk.percent` is ≥ 90.
The pod must be in CrashLoopBackOff or the OpenSearch API must confirm high disk usage. **Fix:** The on-PVC cleanup is
out of scope for this skill (K8s-only execution surface; no destructive PVC writes). Escalate to the cluster operator:
typical procedure is to scale the OpenSearch StatefulSet down, mount the PVC into a debug pod, remove the noisiest node
data, scale back up. Once disk pressure is relieved, unlock any read-only indices:
`curl -X PUT -u <u>:<p> -H "Content-Type: application/json" -d '{"index.blocks.read_only_allow_delete": null}' https://<opensearch>/_settings`.
Adjust Graylog's index-rotation policy so total rotation size stays below 85% of PVC capacity. Logs on the wiped node
data are lost; restore from backup if available. Rollback: the unlock command is safe to re-run; data deletion from the
PVC is irreversible. **Caveat / next:** also check `opensearch-troubleshoot` for the OpenSearch PVC if the issue
originates on the OpenSearch side.

## graylog-pod-oom-killed

**What:** The Graylog container is OOMKilled — its JVM heap or pod memory limit is too small for the current load.
**Confirm:** Quote `kubectl -n <ns> describe pod <graylog-pod>` showing `Last State: Terminated  Reason: OOMKilled` (or
a rising restart count). Quote the current `graylog.graylogResources.limits.memory` and `graylog.javaOpts` (`-Xmx`)
values from the `LoggingService` CR or Helm values. Check Graylog logs for `OutOfMemoryError` or
`java.lang.OutOfMemoryError`. **Fix:** Do not edit pod specs or container env directly — the operator reconciles them
back. Adjust via the `LoggingService` CR or Helm values: raise `graylog.graylogResources.{requests,limits}.memory`
(chart defaults 1536Mi/2048Mi) and `graylog.javaOpts` — keep `-Xmx` ≤ ~75% of the pod memory limit so off-heap and
JVM-internal allocations fit (chart default `-Xms1024m -Xmx1024m`). If the MongoDB sidecar is OOMing, raise
`graylog.mongoResources.{requests,limits}.memory` (chart default 256Mi). The operator rolls the Graylog StatefulSet
after CR/values changes; force a rollout if needed: `kubectl -n <ns> rollout restart sts/graylog`. Sizing reference:
`docs/installation.md` ships a Small/Medium/Large hardware-requirements table calibrated to messages-per-second.
Rollback: restore the previous limit values in the CR/Helm values. **Caveat / next:** this skill does not manage
OpenSearch lifecycle; for OpenSearch OOM, adjust heap and pod limits in the operator/chart that deploys OpenSearch.

## graylog-low-performance

**What:** Graylog is under journal pressure — the journal utilization is too high or the journal is almost full, causing
slow search and missing recent logs. **Confirm:** Quote the matching Graylog log line
(`Journal utilization is too high`, `journal is (almost )?full`). Capture `/api/system/journal` (uncommitted entries,
utilization) and quote the values. Include `kubectl -n <ns> top pod -l 'app.kubernetes.io/name in (graylog,opensearch)'`
and `kubectl top nodes`. Note whether the bottleneck is CPU, RAM, or disk IOPS. **Fix:** OpenSearch is almost always the
bottleneck — disk speed is the single biggest lever. In order: (1) verify Graylog and OpenSearch pod limits and storage
class match the expected load; (2) increase the constrained resource via `LoggingService.graylog.graylogResources` and
`graylog.javaOpts` (heap) — OpenSearch lifecycle is managed by its own operator/chart; (3) tune `graylog.conf` knobs via
the `LoggingService` CR or Helm values (never edit the ConfigMap directly): `processbuffer_processors` and
`outputbuffer_processors` to CPU count / 2; `ring_size` to 131072, or 262144 if Graylog has ≥ 4 GB RAM; (4) last-resort
crackdown options: remove the `Logs Routing` pipeline (saves CPU; routing to streams is lost), disable the Graylog disk
journal to prevent disk-IO contention with OpenSearch, disable system/audit-system log collection on the FluentD side.
If a restart is needed: `kubectl -n <ns> rollout restart sts/graylog`; after restart, go to `/system/inputs` in Graylog
UI, stop each input, wait for the input buffer to drain and journal utilization to fall to 0–5%, then re-enable the
inputs. Progression of symptoms (small to severe): slow search → journal grows (0–50k fine, 50–100k worrying, 500k+
disaster) → recent logs missing from search → Graylog UI slow, random 500/503 → Graylog UI down → node CPU pinned and
`kubectl exec` stalls. Rollback: restore the previous resource values and `graylog.conf` knobs in the CR/Helm values.

## graylog-not-processing-messages

**Detection: manual** **What:** Graylog's disk journal contains a large and growing number of unprocessed messages (>
100,000), meaning OpenSearch is not accepting payload from Graylog. **Confirm:** Open `http://<graylog>/system/nodes`
and quote `The journal contains X unprocessed messages`. Verify X > 100,000 and growing across two readings ~1 minute
apart. Capture OpenSearch cluster health (`GET /_cluster/health`) and PVC utilization. Also check `/api/system/journal`
for `uncommitted_journal_entries`. **Fix:** Root cause is that OpenSearch is not accepting payload. Walk these
possibilities in order: (1) PVC at capacity → route to `graylog-opensearch-storage-full`; (2) Graylog pod OOMing → route
to `graylog-pod-oom-killed`; (3) resource-bound Graylog or OpenSearch → route to `graylog-low-performance`; (4)
OpenSearch itself stuck — try `kubectl -n <ns> rollout restart sts/opensearch` and monitor journal utilization.
Rollback: the rollout restart is reversible by scaling back or rolling back the StatefulSet. **Caveat / next:** this
symptom is a cascade indicator — confirm and treat the underlying cause from the list above before treating it in
isolation.

## graylog-index-oversized

**Detection: manual** **What:** One or more OpenSearch indices exceed the configured `Max index size` in the Index Set,
causing unexpectedly high PVC utilization. **Confirm:** Quote
`curl -X GET -u <u>:<p> -sk https://<graylog>/api/system/indexer/indices` showing an index size greater than the
configured `Max index size`. Cross-check PVC utilization behind Graylog/OpenSearch. **Fix:** This is a rare Graylog
indexer bug; a manual workaround applies. Take a backup first. Delete the oversized index via the Graylog API:
`curl -X DELETE -u <u>:<p> -H "X-Requested-By: graylog" https://<graylog>/api/system/indexer/indices/<index_name>`.
Rollback: deleted indices cannot be restored except from backup — ensure a backup exists before deleting.

## graylog-negative-unprocessed-messages

**Detection: manual** **What:** The Graylog `Disk Journal` section shows a negative unprocessed-messages counter,
meaning the journal directory was partially cleared while Graylog kept its in-memory counters. **Confirm:** Screenshot
or API output from the `Disk Journal` section showing a negative unprocessed-messages counter. Note the Graylog pod's
PVC name and recent events on it. **Fix:** Stop Graylog, completely empty the journal directory on its PVC, then start
Graylog again. In-flight messages in the journal at cleanup time are lost; messages buffered upstream in
FluentD/FluentBit get re-delivered. The on-PVC cleanup is out of scope (K8s-only execution surface). Escalate to the
cluster operator: typical sequence is `kubectl -n <ns> scale sts graylog --replicas=0`, mount the PVC into a debug pod,
`rm -rf` the journal directory, scale back up. To disable the journal permanently, set `message_journal_enabled=false`
via the `LoggingService` CR or Helm values — do not edit the ConfigMap directly, the operator reconciles it back.
Rollback: the journal directory deletion is irreversible; scale back up after cleanup.

## graylog-incorrect-timestamps

**Detection: manual** **What:** Log entries show different time values across the `message`, `time`, and `timestamp`
fields, indicating a timezone mismatch between Graylog/nodes and the expected UTC. **Confirm:** Quote one log entry
showing divergent values in the `message`, `time`, and `timestamp` fields. Capture `date` and timezone configuration on
the Kubernetes nodes hosting Graylog and FluentD/FluentBit. **Fix:** Set every node's timezone to UTC. Alternatively,
change the timezone in the Graylog user settings to match the timezone set on the nodes — but note this does not alter
the time embedded inside the `message` field (it stays UTC). Rollback: revert the timezone setting in Graylog user
settings if changed manually.

## graylog-opensearch-node-info-tls

**Detection: manual** **What:** Graylog UI `System -> Nodes` shows OpenSearch node information as unavailable, caused by
an expired or misconfigured TLS certificate on the Graylog side. **Confirm:** Screenshot of Graylog UI `System -> Nodes`
with OpenSearch info empty. Click the Graylog node name and capture the TLS/certificate error in the node-details panel.
Quote the certificate's `notAfter` and SAN list:
`openssl s_client -connect <graylog>:<port> -showcerts </dev/null | openssl x509 -noout -dates -ext subjectAltName`.
**Fix:** Verify the Graylog TLS certificate is not expired and that its SANs cover the in-cluster Service name (for
example `graylog-service.logging.svc` for namespace `logging`). If self-signed, regenerate it following the Qubership
platform's TLS/certificate procedure for Graylog and update the deployment. Rollback: restore the previous certificate
if the new one causes connectivity issues. **Caveat / next:** if OpenSearch itself is down or unreachable (not just a
certificate problem), hand off to `opensearch-troubleshoot`.

## graylog-widget-fielddata-text-field

**What:** Dashboard widgets show errors stating that text fields are not optimized for aggregation (`fielddata=true`),
caused by OpenSearch dynamic typing assigning the wrong type to an undeclared field in a custom index. **Confirm:**
Quote the widget error or Graylog log line including the offending field name and the `illegal_argument_exception` text
(`Text fields are not optimized for operations that require per-document field data...fielddata=true on [<field>]`).
Capture the field's mapping: `GET /<index_name>/_mapping/field/<field>` (or `GET /_mapping/field/<field>` if the index
name is unknown). **Fix:** Identify the field from the error (for example `timestamp`). Inspect its mapping with
`GET /_mapping/field/<field>` or `GET /<index>/_mapping/field/<field>`, and the index template with
`GET /_index_template/<index_name>`. Fix the index mapping by declaring the field with the correct type (for example
`date` for `timestamp`). Prevention: always declare all fields explicitly for custom OpenSearch indices instead of
relying on dynamic typing. Rollback: revert the index mapping change if it breaks existing queries.

## graylog-deflector-not-alias

**What:** Graylog reports `Deflector exists as an index and is not an alias` — OpenSearch has a real index named
`<index_set>_deflector` instead of the alias Graylog expects, blocking writes. **Confirm:** Quote the Graylog UI
Overview error `Deflector exists as an index and is not an alias` and the matching Graylog log line
`Active write index for index set "<name>" doesn't exist yet`. From OpenSearch, quote the
`MetadataCreateIndexService … <name>_deflector creating index, cause [auto(bulk api)]` line confirming OpenSearch
auto-created the deflector as a real index. **Fix:** Two root causes: (1) if the index with `_deflector` suffix was
manually created, delete it and never use that name pattern again; (2) if hit during a logging-stack upgrade, before
retrying the upgrade stop all Graylog inputs: Graylog UI → `System -> Inputs` → `Stop input` on each. Re-enable them
after the upgrade completes. Prevention: never create OpenSearch indices with the `_deflector` suffix; on upgrades that
introduce Streams with custom indices, always stop all Graylog Inputs first. Rollback: re-enable stopped inputs after
the upgrade.

## graylog-gelf-input-frame-size

**What:** The Graylog GELF input drops oversized frames because its `max_message_size` is smaller than the frames
FluentBit or FluentD sends. **Confirm:** Quote the netty/jetty exception line from
`kubectl logs <graylog-pod> --tail=500 | grep -iE 'TooLongFrame|max_message_size'` (`TooLongFrameException`,
`frame too large`, or similar). Quote the input's current `max_message_size` from `GET /api/system/inputs` (look at the
GELF input's `attributes.max_message_size`). **Fix:** Raise `max_message_size` on the GELF input that is dropping
frames. The current chart default is 2097152 (~2 MB); set to 12582912 (~12 MB) to match FluentBit's default chunk size,
or higher if the collector config legitimately produces larger frames. Apply via `PUT /api/system/inputs/<input-id>`
with the corrected configuration, or by editing the input in Graylog UI. Prefer the `LoggingService` CR's input section
so the change is reconciled rather than editing via API in production. Rollback: restore the previous `max_message_size`
value via `PUT /api/system/inputs/<input-id>`.

## graylog-gelf-input-not-listening

**What:** The Graylog GELF input is not accepting connections on its configured port (default 12201) — it is bound to
the wrong port, stopped, or failed to start — while the Graylog server itself is healthy. Collectors get
`connection refused` even though their own output configuration is correct. **Confirm:** First confirm Graylog itself is
healthy: `kubectl -n <ns> get pods -l app.kubernetes.io/name=graylog` (Running, Ready) and
`curl -sk https://<graylog>/api/system/lbstatus` (200/ALIVE). Then quote the GELF input's `attributes.port` from
`GET /api/system/inputs` and its state from `GET /api/system/inputstates`, alongside a collector error line citing the
target endpoint — for example FluentBit `no upstream connections available` / `connection refused` to
`graylog-service:12201`. **Fix:** Restore the input to its configured port and restart it: set `attributes.port` back to
12201 via `PUT /api/system/inputs/<input-id>` with the corrected configuration, or Stop then Start the input in Graylog
UI → `System > Inputs`. Prefer the `LoggingService` CR's input section so the change is reconciled rather than editing
via API in production. Do not change the collectors' output port — their configuration is correct. Rollback: revert the
`attributes.port` change if the input fails to start on the restored port. **Caveat / next:** if `connection refused` or
`no upstream connections available` appears in FluentBit logs and the GELF input is Running on the correct port, the
fault is on the network path or in FluentBit's output configuration — hand off to `fluentbit-troubleshoot`.
