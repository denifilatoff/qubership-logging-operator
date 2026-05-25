# Graylog — symptom catalogue

## Unable to connect to Graylog via browser

```yaml
id: graylog-ui-unreachable
match:
  manual_review: true
evidence_template: |
  Capture `kubectl -n <ns> get pods,svc -l app.kubernetes.io/name=graylog -o wide`
  and `kubectl -n <ns> describe pod <graylog-pod>`. Note pod phase, restart
  count, and any non-Ready conditions. If the pods are healthy, attempt the
  HTTP probe `curl -sk https://<graylog>/api/system/lbstatus` from inside
  the cluster.
proposed_fix: |
  If pods are not `Running` (CrashLoopBackOff, OOMKilled, high restart
  count), route to the matching symptom (`graylog-pod-oom-killed`,
  `graylog-low-performance`, etc.). If pods are healthy but the UI is
  unreachable from the browser, the fault is in the path between the
  browser and the Service: inspect Ingress / Route, TLS, and any L7 load
  balancer in front of Graylog. The HTTP API at `https://<graylog>/api/...`
  is the canonical reachability probe.
```

## Unable to read log messages in Graylog

```yaml
id: graylog-unable-to-read-messages
match:
  manual_review: true
evidence_template: |
  Screenshot or text from the Graylog `System > Overview` tab showing the
  flagged errors. Include the FluentD pod health-check status in the
  logging namespace.
proposed_fix: |
  Open Graylog UI → `System > Overview` and act on each flagged error.
  Cross-check FluentD pods in the logging namespace; if any are unhealthy,
  route to the FluentD catalogue.
```

## Ingress/Route to Graylog cyclic redirect

```yaml
id: graylog-route-cyclic-redirect
match:
  manual_review: true
evidence_template: |
  Quote the HTTP response: a 302 from the Graylog Route pointing back to
  itself (`curl -sIk https://<route>`). Note that the cluster is on an
  OpenShift DR no-vIP topology with external HTTPS-terminating load
  balancers in front of the Route.
proposed_fix: |
  Applies only to the DR no-vIP OpenShift schema. The Route returns 302 to
  itself because external load balancers terminate HTTPS in front of it.
  Add the Route URL to the `os_sni_passthrough.map` file on the load
  balancers so the SNI request reaches the Route directly. Manual
  configuration on the LB hosts is required.
```

## Storage full (Graylog / OpenSearch PVC)

```yaml
id: graylog-opensearch-storage-full
match:
  api_check:
    path: /_cat/allocation?v
    expects: 'disk.percent >= 90 on at least one OpenSearch node'
  k8s_state:
    pod_state: CrashLoopBackOff
evidence_template: |
  Quote `kubectl -n <ns> get pvc` and `describe pvc` for the Graylog and
  OpenSearch PVCs. Capture node `DiskPressure` status and the OpenSearch
  `_cat/allocation?v` row showing `disk.percent`.
proposed_fix: |
  The on-PVC cleanup itself is **out of scope** for this skill (K8s-only
  execution surface; no destructive PVC writes). Escalate to the cluster
  operator: typical procedure is to scale the OpenSearch StatefulSet down,
  mount the PVC into a debug pod, remove the noisy node data, scale back
  up. Exact steps depend on the chart and the operator team's runbook.

  Once disk pressure is relieved, unlock indices if Graylog reports them as
  read-only — see `opensearch-index-read-only` for the unlock command.

  Logs that lived on the wiped node data are lost. Adjust Graylog's
  index-rotation policy so total rotation size fits the PVC; restore old
  logs from backup if one exists.
```

## Graylog pod OOM-killed

```yaml
id: graylog-pod-oom-killed
match:
  k8s_state:
    pod_state: OOMKilled
  log_grep:
    target: graylog
    pattern: 'OutOfMemoryError|java\.lang\.OutOfMemoryError'
evidence_template: |
  Capture `kubectl -n <ns> describe pod <graylog-pod>` showing
  `LastState.terminated.reason=OOMKilled` (or rising restart count).
  Quote the current `graylog.graylogResources.limits.memory` and
  `graylog.javaOpts` (`-Xmx`) values from the `LoggingService` CR or Helm
  values.
proposed_fix: |
  Heap and pod-memory limits live in the `LoggingService` CR (or Helm
  values for chart-only installs). Do **not** edit pod specs or container
  env directly — the operator reconciles them back.

  Adjust:
  - `graylog.graylogResources.{requests,limits}.memory` (chart defaults
    1536Mi / 2048Mi).
  - `graylog.javaOpts` — keep `-Xmx` ≤ ~75% of the pod memory limit so
    off-heap and JVM-internal allocations fit (chart default `-Xms1024m
    -Xmx1024m`).
  - `graylog.mongoResources.{requests,limits}.memory` if the MongoDB
    sidecar is OOMing (chart default 256Mi).

  This operator does **not** manage OpenSearch lifecycle — for OpenSearch
  OOM, adjust heap and pod limits in whatever operator / chart deploys
  OpenSearch.

  The operator rolls the Graylog StatefulSet on its own after CR / values
  changes. Force a rollout with `kubectl -n <ns> rollout restart sts/graylog`
  if it doesn't pick up automatically.

  Sizing reference: `docs/installation.md` in this repo ships a
  Small/Medium/Large hardware-requirements table calibrated to
  messages-per-second; grep it for the table.
```

## Low Graylog performance / journal pressure

```yaml
id: graylog-low-performance
match:
  api_check:
    path: /api/system/journal
    expects: 'uncommitted_journal_entries > 50000 or journal utilization sustained'
  log_grep:
    target: graylog
    pattern: 'Journal utilization is too high|journal is (almost )?full'
evidence_template: |
  Quote `/api/system/journal` (uncommitted entries, utilization). Include
  `kubectl -n <ns> top pod -l 'app.kubernetes.io/name in (graylog,opensearch)'`,
  `kubectl top nodes`, and the node-level CPU/Memory/Disk pressure
  conditions. Note whether the bottleneck is CPU, RAM, or disk IOPS.
proposed_fix: |
  Graylog under journal pressure is both CPU- and disk-heavy; OpenSearch is
  disk-IO greedy. In practice, OpenSearch is almost always the bottleneck.

  1. Verify Graylog pod limits and OpenSearch limits and storage class
     match the expected load. OpenSearch disk speed is the single biggest
     lever — most performance issues are solved by faster underlying
     storage. RAM and CPU are second priority but matter; Graylog itself
     rarely needs more than 4–8 GB RAM, so prefer giving more RAM to
     OpenSearch.
  2. Increase the constrained resource via `LoggingService.graylog.graylogResources`
     and `graylog.javaOpts` (heap). OpenSearch lifecycle is not managed by
     this operator — adjust it via whatever operator / chart deploys
     OpenSearch.
  3. Graylog-internal tuning (`graylog.conf` knobs) lives under
     `LoggingService` CR or Helm values; do not edit the ConfigMap
     directly. Useful knobs:
     - `processbuffer_processors`, `outputbuffer_processors` — set to
       CPU count / 2.
     - `ring_size` — 131072, or 262144 if Graylog has ≥4 GB RAM. Higher
       values not recommended.
  4. Heavy-load crackdown options (last resort):
     - Remove the `Logs Routing` pipeline (saves CPU; routing to streams
       is lost).
     - Disable the Graylog disk journal to prevent disk-IO contention with
       OpenSearch.
     - Disable collection of system/audit-system logs on the FluentD side.
  5. If a restart is needed to apply a ConfigMap-loaded change that did
     not pick up:
     `kubectl -n <ns> rollout restart sts/graylog`. After restart, go to
     `/system/inputs` in Graylog UI, `Stop input` for each input, wait for
     the input buffer to drain and journal utilization to fall to 0–5%,
     then re-enable the inputs.

  Progression of symptoms (small to severe): slow search → journal grows
  (0–50k fine, 50–100k worrying, 500k+ disaster) → recent logs missing
  from search → Graylog UI slow, random 500/503 → Graylog UI down → node
  CPU pinned and `kubectl exec` into Graylog stalls.
```

## Graylog not processing messages

```yaml
id: graylog-not-processing-messages
match:
  api_check:
    path: /api/system/journal
    expects: 'uncommitted_journal_entries > 100000 and growing'
evidence_template: |
  Open `http://<graylog>/system/nodes` and quote
  `The journal contains X unprocessed messages`. Verify X > 100000 and
  growing across two snapshots a minute apart. Capture OpenSearch cluster
  health (`GET /_cluster/health`) and PVC utilisation.
proposed_fix: |
  Root cause: OpenSearch is not accepting payload from Graylog. Walk these
  possibilities in order:
  1. PVC at capacity → `graylog-opensearch-storage-full`.
  2. Graylog pod OOMing → `graylog-pod-oom-killed`.
  3. Resource-bound Graylog or OpenSearch → `graylog-low-performance`.
  4. OpenSearch itself stuck — try
     `kubectl -n <ns> rollout restart sts/opensearch`; see also
     `graylog-low-performance` for the broader resource picture.
```

## Index oversized (exceeds rotation max)

```yaml
id: graylog-index-oversized
match:
  api_check:
    path: /api/system/indexer/indices
    expects: 'one or more indices exceed the Index Set Max-index-size'
evidence_template: |
  Quote `curl -X GET -u <u>:<p> -sk https://<graylog>/api/system/indexer/indices`
  showing index size > the configured `Max index size`. Cross-check PVC
  utilisation behind Graylog/OpenSearch.
proposed_fix: |
  Rare Graylog indexer bug; manual workaround. **Take a backup first.**

  Delete the oversized index via the Graylog API:
  `curl -X DELETE -u <u>:<p> -H "X-Requested-By: graylog" https://<graylog>/api/system/indexer/indices/<index_name>`.
```

## Negative number of unprocessed messages

```yaml
id: graylog-negative-unprocessed-messages
match:
  api_check:
    path: /api/system/journal
    expects: 'uncommitted_journal_entries < 0'
evidence_template: |
  Screenshot or API output from `Disk Journal` showing a negative
  unprocessed-messages counter. Note the Graylog pod's PVC name and recent
  events on it.
proposed_fix: |
  Means the journal directory on persistent storage was cleared partially
  while Graylog kept its in-memory counters.

  Recovery: stop Graylog, completely empty the journal directory on its
  PVC, start Graylog again. In-flight messages in the journal at cleanup
  time are lost; messages buffered upstream in FluentD/FluentBit get
  re-delivered.

  The on-PVC cleanup itself is **out of scope** (K8s-only execution
  surface). Escalate to the cluster operator: typical sequence is
  `kubectl -n <ns> scale sts graylog --replicas=0`, mount the PVC into a
  debug pod, `rm -rf` the journal directory, scale back up. Exact mechanic
  depends on the chart and operator runbook.

  To disable the journal entirely, set `message_journal_enabled=false` via
  the `LoggingService` CR (or Helm values) — do not edit the ConfigMap
  directly, the operator reconciles it back.
```

## Incorrect timestamps in Graylog

```yaml
id: graylog-incorrect-timestamps
match:
  manual_review: true
evidence_template: |
  Quote one log entry showing divergent values in `message`, `time`, and
  `timestamp` fields. Capture `date` / timezone configuration on the
  Kubernetes nodes hosting Graylog and FluentD/FluentBit.
proposed_fix: |
  Set every node's timezone to UTC. Alternatively, change the timezone in
  the Graylog user settings to match the nodes — but note this does not
  alter the time embedded inside the `message` field (it stays UTC).
```

## OpenSearch node info unavailable in Graylog UI

```yaml
id: graylog-opensearch-node-info-tls
match:
  manual_review: true
evidence_template: |
  Screenshot of Graylog UI `System -> Nodes` with OpenSearch info empty;
  click the Graylog node name and capture the TLS / certificate error in
  the node-details panel. Quote the certificate's `notAfter` and SAN list
  (`openssl s_client -connect <graylog>:<port> -showcerts </dev/null |
  openssl x509 -noout -dates -ext subjectAltName`).
proposed_fix: |
  Verify the Graylog TLS certificate is not expired and that its SANs
  cover the in-cluster Service name (e.g.
  `graylog-service.logging.svc` for namespace `logging`). If self-signed,
  regenerate it following the Qubership platform's TLS / certificate
  procedure for Graylog and update the deployment.
```

## Widgets show errors / "fielddata is disabled" (text field used for aggregation)

```yaml
id: graylog-widget-fielddata-text-field
match:
  log_grep:
    target: graylog
    pattern: 'illegal_argument_exception.*Text fields are not optimized.*fielddata=true'
evidence_template: |
  Quote the widget error or Graylog log line including the offending field
  name. Then capture the field's mapping:
  `GET /<index_name>/_mapping/field/<field>` (or `GET /_mapping/field/<field>`
  if the index name is unknown).
proposed_fix: |
  OpenSearch dynamic typing picked the wrong type (often `text` when
  Graylog needs `keyword` or `date`) for an undeclared field in a custom
  index.

  1. Identify the field from the error (e.g. `timestamp`).
  2. Inspect its mapping with
     `GET /_mapping/field/<field>` or `GET /<index>/_mapping/field/<field>`,
     and the index template with `GET /_index_template/<index_name>`.
  3. Fix the index mapping: declare the field with the correct type (e.g.
     `date` for `timestamp`).

  Prevention: always declare all fields explicitly for custom OpenSearch
  indices instead of relying on dynamic typing.
```

## Deflector exists as an index, not an alias

```yaml
id: graylog-deflector-not-alias
match:
  log_grep:
    target: graylog
    pattern: 'Deflector exists as an index and is not an alias|Active write index for index set ".*" doesn''t exist yet'
evidence_template: |
  Quote the Graylog UI Overview error `Deflector exists as an index and is
  not an alias` and the matching Graylog log line
  `Active write index for index set "<name>" doesn't exist yet`. From
  OpenSearch, quote the
  `MetadataCreateIndexService … <name>_deflector creating index, cause [auto(bulk api)]`
  line confirming OpenSearch auto-created the deflector as a real index.
proposed_fix: |
  Two root causes:
  - Somebody manually created an OpenSearch index whose name ends in
    `_deflector` (this suffix is reserved by Graylog for its write/read
    alias).
  - During an upgrade, a Stream pointed at a not-yet-created custom index;
    OpenSearch received a save request first and auto-created the
    deflector as an index before Graylog could create it as an alias.

  Fix:
  1. If you manually created an index with `_deflector` suffix, remove it
     and pick a different name.
  2. If hit during a logging-stack upgrade, before retrying the upgrade
     **stop all Graylog inputs**: Graylog UI → `System -> Inputs` →
     `Stop input` on each. Re-enable them after the upgrade completes.

  Prevention: never create OpenSearch indices with `_deflector` suffix; on
  upgrades that introduce Streams with custom indices, stop all Graylog
  Inputs first.
```

## Graylog GELF input drops oversized frames

```yaml
id: graylog-gelf-input-frame-size
match:
  log_grep:
    target: graylog
    pattern: 'TooLongFrameException|HTTP body exceeds maximum allowed size|frame too large|gelf.*frame.*(?:too|exceeds)'
  api_check:
    path: /api/system/inputs
    expects: 'GELF input has max_message_size below the size FluentBit/FluentD frames currently send (default ~2MB-12MB depending on collector config)'
evidence_template: |
  Quote the netty/jetty exception line from `kubectl logs <graylog-pod>
  --tail=500 | grep -iE 'TooLongFrame|max_message_size'`, plus the input's
  current `max_message_size` from `GET /api/system/inputs` (look at the
  GELF input's `attributes.max_message_size`).
proposed_fix: |
  Raise `max_message_size` on the GELF input that's dropping frames.
  Current chart default is 2097152 (~2MB); set to 12582912 (~12MB) to
  match FluentBit's default chunk size, or higher if the collector
  config legitimately produces larger frames. Apply via
  `PUT /api/system/inputs/<input-id>` or by editing the input's
  configuration in Graylog UI. Do not edit Graylog directly via API in
  production — use the LoggingService CR's input section so the change
  is reconciled.
```
