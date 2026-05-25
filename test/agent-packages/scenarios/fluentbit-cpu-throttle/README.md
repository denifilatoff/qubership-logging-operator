# FluentBit CPU throttling: ingest backlog, messages lost

**Backend required**: `graylog`

## Case

FluentBit's CPU limit is set to **5 m** (chart default is 200 m), with
`requests.cpu` lowered to **1 m** in tandem (Kubernetes rejects DaemonSet
updates where `requests > limits`).

Under sustained load (~10 000 msg/s driven by `qubership-log-generator`'s
`/editor/editLogs` endpoint), the FluentBit container's cgroup is throttled
~95% of the time. The input-tail plugin reads ~60 records/s and the GELF
output ships ~3 records/s — versus ~10 000 records/s incoming. Containerd
rotates the underlying log files faster than FluentBit can consume them, so
95%+ of messages are silently lost before ingest.

FluentBit itself looks healthy on the surface: pods are `Running 2/2`, no
restarts, no errors in `kubectl logs`, and no retries/drops in
`/api/v1/metrics`. The pipeline appears fine end-to-end — only the
throughput is off.

Only the FluentBit pod on the **same node** as `qubership-log-generator`
shows full starvation. The other two nodes see no real traffic and their
FluentBit pods are quiet.

The cluster runs FluentBit only (FluentD is `install: false`). FluentD is
not involved in this fixture.

## Mechanics

`apply.sh`:

1. `helm upgrade --reuse-values` with both
   `fluentbit.resources.limits.cpu=5m` and
   `fluentbit.resources.requests.cpu=1m`.
2. Wait for the DaemonSet rollout (CPU-starved pods take ~30 s each to
   become Ready, so total ~90 s).
3. POST a sustained 10 000 msg/s x 300 s load to
   `qubership-log-generator`'s `/editor/editLogs` endpoint. The load
   pushes the FluentBit pod on the same node deep into throttle.

`revert.sh` does `helm rollback <release> 0`. The log-generator stress
job continues for the remainder of its `genTime` but no longer matters —
FluentBit at the restored 200 m CPU absorbs it easily.
