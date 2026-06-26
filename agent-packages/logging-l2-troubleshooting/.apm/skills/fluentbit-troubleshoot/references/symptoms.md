# FluentBit — symptom catalog

Prose condensed from `docs/troubleshooting.md`. For each `symptom_id` the matcher returns, read its section, confirm the
condition holds, then write your analysis. Always also review the `Detection: manual` entries — the matcher never
returns them.

## fluentbit-connection-timeout-graylog

**What:** FluentBit cannot reach the Graylog GELF input; connections time out and the gelf output reports no upstream.
**Confirm:** quote the matching log lines (`connection #-1 to tcp://… timed out`, `getaddrinfo(... Timeout)`,
`no upstream connections available`). Read the pod's CPU request/limit
(`kubectl get pod <pod> -o jsonpath='{.spec.containers[*].resources}'`) and prove the CPU ceiling is the bottleneck:
`kubectl top pod <pod>` shows CPU pinned at the limit, or the container's cgroup `cpu.stat` shows `nr_throttled` rising
toward `nr_periods`. Also read the SERVICE and OUTPUT-gelf stanzas of the `logging-fluentbit` ConfigMap. **Fix:** the
error usually appears when FluentBit hits its CPU limit, so raise CPU back to a working size — set both
`fluentbit.resources.requests.cpu` and `fluentbit.resources.limits.cpu` to at least the chart defaults (request `50m`,
limit `200m`); a low request alone leaves the pod throttle-prone under node contention, so do not raise the limit by
itself. For a heavy fan-in forwarder go higher (e.g. `500m`/`1`). Add to the `logging-fluentbit` ConfigMap: SERVICE
`HC_Errors_Count 5`, `HC_Retry_Failure_Count 5`, `HC_Period 5`; OUTPUT gelf `net.connect_timeout 20s`,
`net.max_worker_connections 35`, `net.dns.mode TCP`, `net.dns.resolver LEGACY`. Recreate all `logging-fluentbit-*` pods
to apply. Rollback: revert the chart values / CR and the ConfigMap, then recreate the pods. **Caveat / next:** if the
Graylog pods are not Running/Ready, the timeout is downstream — hand off to `graylog-server-troubleshoot`.

## fluentbit-configmap-parse-error

**What:** the FluentBit container crash-loops right after a ConfigMap edit because the new config has a syntax error.
**Confirm:** quote the most recent `kubectl logs` from the restarting pod showing the parser error (file name and
line/column), and the offending fragment of the `logging-fluentbit` ConfigMap. Confirm the pod is in `CrashLoopBackOff`
and the restarts began at the edit. **Fix:** the `configmap-reloader` sidecar restarts the container on every ConfigMap
edit, so repeated restarts straight after an edit point at a syntax error. Revert the offending ConfigMap change, or fix
the flagged syntax, and let the reloader pick up the corrected config on its next poll. Rollback: restore the previous
ConfigMap content. **Caveat / next:** if the crash predates any ConfigMap edit, this is not the case — look for OOM or
image issues instead.

## fluentbit-oomkilled-tight-limit

**What:** the FluentBit pod is OOMKilled against a memory limit that is too tight for its fan-in. **Confirm:** quote the
OOMKilled state from `kubectl describe pod <pod>` (`Last State: Terminated; Reason: OOMKilled`), the configured memory
limit (`kubectl get pod <pod> -o jsonpath='{.spec.containers[*].resources}'`), and the restart count. Threshold to
check: limit ≤ 128Mi for the forwarder DaemonSet, ≤ 512Mi for the aggregator StatefulSet. **Fix:** raise
`fluentbit.resources.limits.memory` to the next tier — 256Mi for forwarder DaemonSet pods, 1Gi for aggregator
StatefulSet pods. If the workload is bursty (large fan-in, high cardinality), bump CPU limits in the same change. Do not
edit the pod spec directly — the operator reconciles it back; patch the chart values or the LoggingService CR. Rollback:
restore the previous limit values. **Caveat / next:** none.

## fluentbit-stuck-no-output

**Detection: manual** **What:** FluentBit is Running but stuck — inputs receive records while the gelf output emits
zero, and no error is logged. **Confirm:** capture FluentBit metrics from inside the pod
(`curl http://localhost:2020/api/v1/metrics`) showing inputs receiving records but the gelf output at zero. Quote the
last log lines and the current `filter-log-parser.conf` and `output-graylog.conf` stanzas of the `logging-fluentbit`
ConfigMap. **Fix:** first verify the cluster is on the latest Logging release — this is a known upstream FluentBit issue
the newer operator templates fix. Temporary manual workaround: scale `logging-operator` to 0 so it does not revert
edits; in `logging-fluentbit`, remove the trailing `[FILTER] Name rewrite_tag … Emitter_Mem_Buf_Limit 10M` block from
`filter-log-parser.conf` and change `Match parsed.**` to `Match_Regex (raw|parsed).**` in `output-graylog.conf`;
recreate the `logging-fluentbit-*` pods. Rollback: scale the operator back up — it reverts these edits on the next
reconcile; upgrade is the only durable fix. **Caveat / next:** if the gelf output shows non-zero emits, the pipeline is
not stuck — check `fluentbit-connection-timeout-graylog` instead.
