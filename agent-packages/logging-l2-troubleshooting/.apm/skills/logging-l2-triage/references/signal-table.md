# L2 triage signal table

Maps observations from the initial read-safe sweep to the knowledge-area skill that should run next.

Each row carries a **prior**: SME-observed base rate that this signal corresponds to the listed cause. Rank candidates by `match strength × prior`, not by match alone. Priors are seeded by SME estimate and will be recalibrated as real cases close — treat the current values as starting points, not ground truth.

Use this table only after the [initial sweep](../SKILL.md#initial-read-safe-sweep) has produced concrete observations. Do **not** match against ticket text here — that is L1's job; L2 matches against what the cluster actually shows.

## Seed table (v0.1)

| Runtime signal observed | Detected by command | Target skill | Prior |
|---|---|---|---|
| FluentBit pod in `CrashLoopBackOff`, `Error`, or repeatedly restarting | `kubectl get pods -n <ns> -l app.kubernetes.io/name=fluentbit` | `fluentbit-troubleshoot` | high |
| FluentBit pod recently `OOMKilled` or `Evicted` | `kubectl describe pod` → `LastState.terminated.reason` | `fluentbit-troubleshoot` | high |
| FluentBit logs show `[upstream] connection ... timed out` / `getaddrinfo ... Timeout` / `no upstream connections available` | `kubectl logs <fluentbit-pod>` | `fluentbit-troubleshoot` | high |
| FluentBit pod healthy, no errors, but Graylog reports no incoming messages | Graylog API `/api/system/inputs` + FluentBit logs clean | `fluentbit-troubleshoot` | medium |
| FluentD worker exited `SIGKILL`, supervisor restarting workers | `kubectl logs <fluentd-pod>` → `Worker N exited unexpectedly with signal SIGKILL` | `fluentd-troubleshoot` | high |
| FluentD pod OOMKilled with memory limit ~1Gi | `kubectl describe pod` + `kubectl get pod -o jsonpath='{...resources}'` | `fluentd-troubleshoot` | high |
| FluentD `failed to flush the buffer ... Data too big ... more than 128 chunks` | `kubectl logs <fluentd-pod>` | `fluentd-troubleshoot` | high |
| Fluent\* container restarts immediately after a configmap edit | `kubectl describe pod` (recent restart) + configmap mod-time | `fluentd-troubleshoot` or `fluentbit-troubleshoot` (per workload) | high |
| Graylog UI inaccessible, pod running but returns 502 / 504 | `curl <graylog-url>` + `kubectl get pod` | `graylog-server-troubleshoot` | medium |
| Graylog `journal` size > 100k and growing, "unprocessed messages" climbing | `curl /api/system/journal` | `graylog-server-troubleshoot` (downstream-store sub-funnel) | high |
| Graylog UI shows "Deflector exists as an index and is not an alias" | Graylog UI Overview or API failures | `graylog-server-troubleshoot` | high |
| Graylog widget error mentioning `fielddata=true` / `Text fields are not optimized` | Widget UI or Graylog logs | `graylog-server-troubleshoot` | high |
| Graylog UI: System → Nodes shows OpenSearch nodes info unavailable, click reveals TLS / cert error | Graylog UI / Graylog logs | `graylog-server-troubleshoot` (TLS path) | medium |
| Graylog logs `Active write index for index set ... doesn't exist yet` | `kubectl logs <graylog-pod>` | `graylog-server-troubleshoot` (deflector case) | medium |
| Graylog/OpenSearch PVC ≥95% full, or node-level `DiskPressure=True` on the node hosting Graylog/OpenSearch | `kubectl describe pvc` / `kubectl get nodes` conditions | `graylog-server-troubleshoot` → then `graylog-disk-usage-investigate` for the breakdown | high |
| Engineer asks "which microservice is filling our logs", "who's the noisiest producer" — independent of any failure | engineer's question, no failure required | `graylog-disk-usage-investigate` directly | high |
| OpenSearch cluster status RED or YELLOW with unassigned shards | `curl /_cluster/health` | `opensearch-troubleshoot` | high |
| OpenSearch logs `Limit of total fields [1000] in index [...] has been exceeded` | `kubectl logs <opensearch-pod>` | `opensearch-troubleshoot` | high |
| Index settings show `index.blocks.read_only_allow_delete: true` on one or more indices | `curl /<index>/_settings` | `opensearch-troubleshoot` | high |
| OpenSearch JVM `heap_max` configured above ~32 GB and OOM/perf complaints | `curl /_nodes/jvm` | `opensearch-troubleshoot` | medium |
| OpenSearch logs noisy `no such index [.opendistro-ism-config]` errors and engineer worried | OpenSearch logs | `opensearch-troubleshoot` (will explain it is harmless) | low |

## Routing rules

Triage always emits a **ranked list of candidates** (length ≥ 1), not a single pick. The primary is the top candidate; the rest are refutation successors that fire only if a downstream skill returns `hypothesis_refuted` (see [logging-l2-triage SKILL.md](../SKILL.md#chain-of-hypotheses)).

- **One row fires** → ranked list of length 1. Case is overdetermined; primary is unique; no fallback.
- **Multiple rows, same target** → length 1, raise confidence.
- **Multiple rows, different targets** → length ≥ 2, ranked by `match × prior`. Primary first; the rest are successors.
- **No row fires** after a complete sweep → don't invent a target. Apply a **class-level fallback chain** (next section) if the symptom matches one; otherwise emit a `recommend` for manual diagnosis with the sweep attached and stop.
- **Sweep partially blocked** (RBAC, endpoint down) → escalate to the engineer; the read-before-recommend rule applies to triage too.

## Downstream-error-in-upstream-log

When a collector or facade logs a quoted error message that names a **downstream component or downstream concept** (write block, watermark, refused connection from address X, "queue full on Y"), treat that as a positive routing signal toward the **named downstream area**, not toward the component that logged the message. The component logging the error is the messenger.

Concrete instances (non-exhaustive — the principle is the rule, not the list):

| Quoted message surface | Logged by | Route to |
|---|---|---|
| `disk usage exceeded flood-stage watermark`, `cluster_block_exception`, `FORBIDDEN/12/index read-only` | Graylog, FluentBit, FluentD | `opensearch-troubleshoot` |
| `connection refused` / `getaddrinfo` naming the Graylog host | FluentBit, FluentD | `graylog-server-troubleshoot` |
| `Data too big`, `more than 128 chunks` referencing OpenSearch | FluentD | `opensearch-troubleshoot` (heap / shard limits), then `fluentd-troubleshoot` |
| MongoDB connection errors quoted from Graylog | Graylog | mongodb area (no skill yet — escalate per "Areas not covered yet") |

This is in addition to the row-based table above: a downstream-error quote can fire even when the matching row in the seed table requires a probe the agent hasn't run yet. The downstream area's skill is the one that confirms; triage just routes.

## Class-level fallback chains

When the symptom is **ambiguous by class** (no single signal-table row fires but the symptom class is recognised), emit a pre-defined fallback chain. The chain is the ranked list; the chain-of-hypotheses loop in the triage SKILL walks it until one skill confirms or all refute.

| Symptom class | Chain (ordered) |
|---|---|
| "No logs arriving in Graylog / search backend", collectors look healthy, no quoted downstream error | `fluentbit-troubleshoot` → `fluentd-troubleshoot` (if FluentD is deployed) → `graylog-server-troubleshoot` → `opensearch-troubleshoot` |
| "Search/UI is slow", no health-alert | `graylog-server-troubleshoot` → `opensearch-troubleshoot` |
| "Disk filling on logging PVCs" | `graylog-disk-usage-investigate` → `opensearch-troubleshoot` |

Skip steps in the chain whose component isn't deployed in this cluster (e.g. no FluentD layer). The chain-of-hypotheses loop is bounded by the triage SKILL's step budget; the fallback chain doesn't override it.

## Areas not covered yet

The following appear in the L2 methodology (§3) but have no skill in this package yet, because their reference guide is empty. If the sweep clearly indicates one of these, hand back to the engineer with the observation and stop — do **not** route to a nearby skill as a substitute:

- `victoria-logs-troubleshoot`
- `mongodb-troubleshoot` — common signals: Graylog logs full of MongoDB connection errors, Mongo container restarting.
- `monitoring-troubleshoot` — Prometheus exporters, Grafana dashboards.
- `backup-troubleshoot`
- `argocd-deployment-troubleshoot` / `jenkins-deployment-troubleshoot` / `logging-operator-troubleshoot` — deployment-time failures.

## Updating the table

Add new rows as new patterns become real (a recurring ticket, a new SME-confirmed signature). New rows must:

1. Be produced by a `read-safe` command, not by ticket text alone.
2. Carry a prior — `high` / `medium` / `low` — sourced from the SME owner of the target area.
3. Name an existing skill in this package (or be flagged as "no skill yet").
