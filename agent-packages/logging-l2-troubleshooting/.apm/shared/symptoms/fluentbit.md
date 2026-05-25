# FluentBit — symptom catalogue

## Connection timeout to Graylog

```yaml
id: fluentbit-connection-timeout-graylog
match:
  log_grep:
    target: fluentbit
    pattern: 'connection #-?\d+ to tcp://.*timed out|getaddrinfo.*(Timeout|Name or service not known|nodename nor servname)|no upstream connections available'
evidence_template: |
  Quote the matching log lines verbatim. Include the FluentBit pod's CPU
  request/limit (`kubectl get pod -o jsonpath='{.spec.containers[*].resources}'`)
  and the relevant stanzas of the `logging-fluentbit` ConfigMap
  (`fluent-bit.conf` SERVICE section, `output-graylog.conf` OUTPUT section).
proposed_fix: |
  1. Raise `fluentbit.resources.limits.cpu` to "1" if currently lower —
     the error usually appears when FluentBit hits its CPU limit.
  2. Add health-check and network tuning to the `logging-fluentbit` ConfigMap:
     - SERVICE: `HC_Errors_Count 5`, `HC_Retry_Failure_Count 5`, `HC_Period 5`.
     - OUTPUT gelf: `net.connect_timeout 20s`, `net.max_worker_connections 35`,
       `net.dns.mode TCP`, `net.dns.resolver LEGACY`.
  3. Manually delete all `logging-fluentbit-*` pods to apply the new ConfigMap.
```

## FluentBit stuck and stopped sending logs to Graylog

```yaml
id: fluentbit-stuck-no-output
match:
  manual_review: true
evidence_template: |
  Capture FluentBit input/output metrics (`curl http://localhost:2020/api/v1/metrics`
  from inside the pod) showing inputs receiving records but the gelf output
  emitting zero. Quote the last log lines from the pod and the current
  `filter-log-parser.conf` and `output-graylog.conf` stanzas of the
  `logging-fluentbit` ConfigMap.
proposed_fix: |
  First, verify the cluster is on the latest Logging release; this is a known
  upstream FluentBit issue and the operator's newer templates fix it.

  Temporary manual workaround:
  1. Scale `logging-operator` down so it does not revert ConfigMap edits:
     `kubectl scale -n <ns> deployment logging-operator --replicas=0`.
  2. Edit `kubectl edit -n <ns> cm logging-fluentbit`:
     - In `filter-log-parser.conf`, remove the trailing
       `[FILTER] Name rewrite_tag … Emitter_Mem_Buf_Limit 10M` block.
     - In `output-graylog.conf`, replace `Match   parsed.**` with
       `Match_Regex (raw|parsed).**`.
  3. Delete all `logging-fluentbit-*` pods so they restart with the new config.
  4. Once stable, scale `logging-operator` back up — but expect it to revert
     these edits on the next reconcile; upgrade is the only durable fix.
```

## Fluent container restarts after ConfigMap edit

```yaml
id: fluentbit-configmap-parse-error
match:
  log_grep:
    target: fluentbit
    pattern: 'parse_error|ConfigParseError|unmatched end tag|Invalid (config|indentation)'
  k8s_state:
    pod_state: CrashLoopBackOff
evidence_template: |
  Quote the most recent `kubectl logs` from the restarting pod showing the
  parser-side error (file name and line/column). Include the offending
  fragment of the `logging-fluentbit` ConfigMap.
proposed_fix: |
  The `configmap-reloader` sidecar restarts the container on every ConfigMap
  edit. Repeated restarts right after an edit point at a syntax error in the
  new content. Revert the offending ConfigMap change (or fix the syntax
  flagged in the parser error) and let the reloader pick up the corrected
  config on its next poll.
```
