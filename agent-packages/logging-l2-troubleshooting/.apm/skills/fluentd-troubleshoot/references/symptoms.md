# FluentD — symptom catalog

Prose condensed from `docs/troubleshooting.md`. For each `symptom_id` the matcher returns, read its section, confirm the
condition holds, then write your analysis. Always also review the `Detection: manual` entries — the matcher never
returns them.

## fluentd-worker-sigkill-oom

**What:** the FluentD worker process is killed by SIGKILL (OOMKiller) because the hardcoded ~1 GB output buffer cannot
fit inside the pod's memory limit. **Confirm:** quote the `Worker N exited unexpectedly with signal SIGKILL` line and
the following `#N init workers logger` restart line from FluentD logs. Confirm `OOMKilled` in
`kubectl describe pod <pod>` (`Last State: Terminated; Reason: OOMKilled`). Read the pod's memory limit
(`kubectl get pod <pod> -o jsonpath='{.spec.containers[*].resources}'`). Threshold to check: limit ≤ 1Gi makes this
highly likely. If available, include the node `dmesg` line showing OOM for the `ruby` process. **Fix:** two options —
(1) raise the FluentD memory limit to `1500Mi` or `2Gi` via the chart values or LoggingService CR; or (2) lower the gelf
store's `<buffer> total_limit_size` to e.g. `512Mb` in `logging-fluentd` ConfigMap so the buffer fits inside the
existing limit (scale `logging-operator` to 0 first with
`kubectl scale -n <ns> deployment logging-operator --replicas=0` to prevent reconcile revert). Rollback: restore the
previous memory limit value or revert the ConfigMap change and scale the operator back up. **Caveat / next:** if you
also see sustained DiskIO read load on the node hosting the FluentD pod, that is the same root cause (memory pressure
causing buffer rewinds from disk) — the fixes above resolve it too.

## fluentd-buffer-data-too-big-udp

**What:** FluentD cannot flush the buffer because a single log record exceeds the GELF UDP 128-chunk limit (~177 KB),
causing unrecoverable errors. **Confirm:** quote the
`failed to flush the buffer … Data too big (… bytes), would create more than 128 chunks!` line and the surrounding
`got unrecoverable error in primary and no secondary` line. Read the `output-graylog.conf` stanza of `logging-fluentd`
ConfigMap to confirm transport is UDP and to capture the current `<buffer> chunk_limit_size` value. **Fix:** the
preferred fix is to switch FluentD → Graylog output to TCP. If UDP must stay, scale `logging-operator` to 0 first
(`kubectl scale -n <ns> deployment logging-operator --replicas=0`), then edit `kubectl edit cm logging-fluentd -n <ns>`
and set `<buffer> chunk_limit_size 176KB` inside the gelf store of `output-graylog.conf`. Rollback: revert
`chunk_limit_size` to its previous value (or remove it) and scale the operator back up. **Caveat / next:** none.

## fluentd-configmap-parse-error

**What:** the FluentD container crash-loops right after a ConfigMap edit because the new config has a syntax error that
the `configmap-reloader` sidecar picks up and applies, triggering a restart. **Confirm:** quote the main fluentd
container's last logs including the `Fluent::ConfigParseError` line that names the failing file and line/column (e.g.
`unmatched end tag at filter-add-hostname.conf line 6,12`). Confirm the pod is in `CrashLoopBackOff` and the restarts
began at the edit. **Fix:** open the file named in the parse error, fix the unmatched tag or invalid directive, and wait
for `configmap-reloader` to pick up the corrected config on its next poll. No pod delete is required if the reloader is
running. Rollback: restore the previous ConfigMap content. **Caveat / next:** if the crash predates any ConfigMap edit,
this is not the case — look for OOM or image issues instead.
