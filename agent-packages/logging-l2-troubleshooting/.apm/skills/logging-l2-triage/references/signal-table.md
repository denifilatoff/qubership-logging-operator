# L2 triage signal table

Maps observations from the initial read-safe sweep to the knowledge-area skill that should run next.

Each row carries a **prior**: SME-observed base rate that this signal corresponds to the listed cause. Rank candidates by `match strength × prior`, not by match alone. Priors are seeded by SME estimate and will be recalibrated as real cases close — treat the current values as starting points, not ground truth.

Use this table only after the [initial sweep](../SKILL.md#initial-read-safe-sweep) has produced concrete observations. Do **not** match against ticket text here — that is L1's job; L2 matches against what the cluster actually shows.

## Seed table (v0.1)

| Runtime signal observed | Detected by command | Target skill | Prior |
|---|---|---|---|
| FluentBit pod in `CrashLoopBackOff`, `Error`, or repeatedly restarting | `kubectl get pods -n <ns> -l app.kubernetes.io/name=fluentbit` | `troubleshoot-fluentbit` | high |
| FluentBit pod recently `OOMKilled` or `Evicted` | `kubectl describe pod` → `LastState.terminated.reason` | `troubleshoot-fluentbit` | high |
| FluentBit logs show `[upstream] connection ... timed out` / `getaddrinfo ... Timeout` / `no upstream connections available` | `kubectl logs <fluentbit-pod>` | `troubleshoot-fluentbit` | high |
| FluentBit pod healthy, no errors, but Graylog reports no incoming messages | Graylog API `/api/system/inputs` + FluentBit logs clean | `troubleshoot-fluentbit` | medium |
| FluentD worker exited `SIGKILL`, supervisor restarting workers | `kubectl logs <fluentd-pod>` → `Worker N exited unexpectedly with signal SIGKILL` | `troubleshoot-fluentd` | high |
| FluentD pod OOMKilled with memory limit ~1Gi | `kubectl describe pod` + `kubectl get pod -o jsonpath='{...resources}'` | `troubleshoot-fluentd` | high |
| FluentD `failed to flush the buffer ... Data too big ... more than 128 chunks` | `kubectl logs <fluentd-pod>` | `troubleshoot-fluentd` | high |
| Fluent\* container restarts immediately after a configmap edit | `kubectl describe pod` (recent restart) + configmap mod-time | `troubleshoot-fluentd` or `troubleshoot-fluentbit` (per workload) | high |
| Graylog UI inaccessible, container running but returns 502 / 504 | `curl <graylog-url>` + `docker ps` / `kubectl get pod` | `troubleshoot-graylog-server` | medium |
| Graylog `journal` size > 100k and growing, "unprocessed messages" climbing | `curl /api/system/journal` | `troubleshoot-graylog-server` (downstream-store sub-funnel) | high |
| Graylog UI shows "Deflector exists as an index and is not an alias" | Graylog UI Overview or API failures | `troubleshoot-graylog-server` | high |
| Graylog widget error mentioning `fielddata=true` / `Text fields are not optimized` | Widget UI or Graylog logs | `troubleshoot-graylog-server` | high |
| Graylog UI: System → Nodes shows OpenSearch nodes info unavailable, click reveals TLS / cert error | Graylog UI / Graylog logs | `troubleshoot-graylog-server` (TLS path) | medium |
| Graylog logs `Active write index for index set ... doesn't exist yet` | `kubectl logs` / `docker logs graylog_graylog_1` | `troubleshoot-graylog-server` (deflector case) | medium |
| Graylog VM disk at ≥95% on `/srv/docker/graylog` | `df -h` via SSH | `troubleshoot-graylog-server` → then `investigate-graylog-disk-usage` for the breakdown | high |
| Engineer asks "which microservice is filling our logs", "who's the noisiest producer" — independent of any failure | engineer's question, no failure required | `investigate-graylog-disk-usage` directly | high |
| OpenSearch cluster status RED or YELLOW with unassigned shards | `curl /_cluster/health` | `troubleshoot-opensearch` | high |
| OpenSearch logs `Limit of total fields [1000] in index [...] has been exceeded` | `kubectl logs <opensearch-pod>` or `docker logs graylog_storage_1` | `troubleshoot-opensearch` | high |
| Index settings show `index.blocks.read_only_allow_delete: true` on one or more indices | `curl /<index>/_settings` | `troubleshoot-opensearch` | high |
| OpenSearch JVM `heap_max` configured above ~32 GB and OOM/perf complaints | `curl /_nodes/jvm` | `troubleshoot-opensearch` | medium |
| OpenSearch logs noisy `no such index [.opendistro-ism-config]` errors and engineer worried | OpenSearch logs | `troubleshoot-opensearch` (will explain it is harmless) | low |

## Ambiguity rules

- If two rows fire and they point to **the same skill**, pick that skill — the case is over-determined.
- If two rows fire and point to **different skills**, return both as `target_skill` candidates ranked by `match × prior`, with the top one as primary and the rest as refutation successors. The downstream skill returns `hypothesis_refuted` if its sweep doesn't confirm; you re-rank and try the next one.
- If **no row fires** after a complete sweep, do not invent a target. Emit a `recommend` for manual diagnosis with the sweep output attached, and stop.
- If the cluster cannot be read (RBAC, network, endpoints down), escalate to the engineer before guessing. The methodology's read-before-recommend rule applies to triage too: don't route blind.

## Areas not covered yet

The following appear in the L2 methodology (§3) but have no skill in this package yet, because their reference guide is empty. If the sweep clearly indicates one of these, hand back to the engineer with the observation and stop — do **not** route to a nearby skill as a substitute:

- `troubleshoot-victoria-logs`
- `troubleshoot-mongodb` — common signals: Graylog logs full of MongoDB connection errors, Mongo container restarting.
- `troubleshoot-monitoring` — Prometheus exporters, Grafana dashboards.
- `troubleshoot-backup`
- `troubleshoot-argocd-deployment` / `troubleshoot-jenkins-deployment` / `troubleshoot-ansible-vm-installer` / `troubleshoot-logging-operator` — deployment-time failures.

## Updating the table

Add new rows as new patterns become real (a recurring ticket, a new SME-confirmed signature). New rows must:

1. Be produced by a `read-safe` command, not by ticket text alone.
2. Carry a prior — `high` / `medium` / `low` — sourced from the SME owner of the target area.
3. Name an existing skill in this package (or be flagged as "no skill yet").
