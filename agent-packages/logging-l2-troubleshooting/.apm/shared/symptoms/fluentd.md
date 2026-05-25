# FluentD — symptom catalogue

## FluentD worker killed by SIGKILL (OOM)

```yaml
id: fluentd-worker-sigkill-oom
match:
  log_grep:
    target: fluentd
    pattern: 'Worker \d+ exited unexpectedly with signal SIGKILL'
  k8s_state:
    pod_state: OOMKilled
evidence_template: |
  Quote the `Worker N exited unexpectedly with signal SIGKILL` line and the
  following `#N init workers logger` restart line. Include the pod's memory
  limit and (if available) the node `dmesg` line showing OOM for the `ruby`
  process. Also check host-side disk IO on the FluentD pod's node — sustained
  read throughput / IOPS is a common visible consequence (the worker rewinds
  buffers from disk before being killed).
proposed_fix: |
  Root cause: the FluentD container runs a supervisor plus two worker ruby
  processes (#0 and #1). Worker #1 carries the output buffer (hardcoded
  ~1 GB in most FluentD versions); with a pod memory limit of 1Gi the buffer
  cannot fit and worker #1 is OOM-killed and restarted.

  Two fixes:
  1. Raise the FluentD memory limit to ~1500Mi or 2Gi; or
  2. Lower the gelf store's `<buffer> total_limit_size` to e.g. 512Mb so the
     buffer fits inside the existing limit.

  Note: if you also see sustained DiskIO read load on the node hosting the
  FluentD pod, that's the same root cause (memory pressure causing buffer
  rewinds) — the fixes above resolve it too.
```

## FluentD failed to flush buffer (data too big, GELF UDP)

```yaml
id: fluentd-buffer-data-too-big-udp
match:
  log_grep:
    target: fluentd
    pattern: 'failed to flush the buffer.*Data too big.*would create more than 128 chunks'
evidence_template: |
  Quote the `failed to flush the buffer … Data too big (… bytes), would
  create more than 128 chunks!` line plus the surrounding
  `got unrecoverable error in primary and no secondary` line. Include the
  current `output-graylog.conf` showing whether transport is UDP or TCP and
  the `<buffer> chunk_limit_size` value.
proposed_fix: |
  GELF UDP caps a single message at 128 chunks × 1420 bytes ≈ 177 KB
  (`fluent-plugin-gelf-hs` uses gelf-rb's "WAN" mode).

  Preferred: switch FluentD → Graylog output to TCP.

  If UDP must stay, scale `logging-operator` to 0 first (`kubectl scale -n
  <ns> deployment logging-operator --replicas=0`) so it does not revert the
  edit, then `kubectl edit cm logging-fluentd -n <ns>` and set
  `<buffer> chunk_limit_size 176KB` inside the gelf store of
  `output-graylog.conf`. See FluentD buffer-section docs for the full set of
  parameters.
```

## Fluent container restarts after ConfigMap edit

```yaml
id: fluentd-configmap-parse-error
match:
  log_grep:
    target: fluentd
    pattern: 'Worker \d+ exited unexpectedly with status \d+|Fluent::ConfigParseError|parse_error!|unmatched end tag'
  k8s_state:
    pod_state: CrashLoopBackOff
evidence_template: |
  Quote the main fluentd container's last logs, including the
  `Fluent::ConfigParseError` line that names the failing file and
  line/column (e.g. `filter-add-hostname.conf line 6,12`).
proposed_fix: |
  Open the file named in the parse error, fix the unmatched tag / invalid
  directive, and wait for `configmap-reloader` to pick up the new content.
  No pod delete required if the reloader is running.
```
