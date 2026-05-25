**Area:** fluentbit-troubleshoot

**Root cause:** The fluent-bit DaemonSet's CPU limit is set to **5 m**
(chart default 200 m), with `requests.cpu` lowered to **1 m** in tandem.
Under sustained load from `qubership-log-generator` (~10 000 msg/s on
`/editor/editLogs`), the fluent-bit container's cgroup is throttled
roughly 95% of the time on the node that hosts the load generator. The
input-tail plugin reads only ~60 records/s and the GELF output ships
only ~3 records/s — versus ~10 000 records/s incoming. Containerd
rotates the underlying log files faster than fluent-bit can consume
them, so 95%+ of messages are silently dropped before they reach
fluent-bit's input buffer.

The pod looks healthy on the surface: `kubectl get pods` shows Running
2/2 (both fluent-bit and the configmap-reload sidecar Ready), no
restarts, no errors in `kubectl logs`, no retries or drops in
`/api/v1/metrics`. The only direct signal is one of:

- cgroup `cpu.stat` inside the fluent-bit container shows
  `nr_throttled` ≈ `nr_periods` (i.e. nearly every scheduling period
  is throttled).
- `kubectl top pod` (if metrics-server is available) shows the pod
  pinned at its 5 m CPU limit while the workload is active.
- `/api/v1/metrics` polled twice shows the input/output record
  counters advancing by single digits per second under sustained
  load — far below the producer rate.

Only the fluent-bit pod on the **same node** as
`qubership-log-generator` is throttled. The other nodes carry
negligible traffic and their fluent-bit pods are quiet, which masks
the issue if the agent looks at cluster-wide averages instead of
per-pod data.

**Expected recommend:**
- type: resource-bump
- target: `DaemonSet/logging-fluentbit` in namespace `logging`.
- change: raise `spec.template.spec.containers[?(@.name==
  "logging-fluentbit")].resources.limits.cpu` from the observed 5 m
  back to a value that absorbs the workload (chart default 200 m is
  the natural restore target). `requests.cpu` must be raised to the
  same value or kept below the new limit — Kubernetes rejects
  DaemonSet updates where `requests.cpu > limits.cpu`, and the
  fixture lowered both deliberately to avoid that validation error.
- rollback: `helm rollback qubership-logging-operator 0 -n logging`
  (the apply path was `helm upgrade --reuse-values`).

**Required snapshot fields attached to the recommend:**
- current `resources` on the fluent-bit container, showing
  `limits.cpu=5m` and `requests.cpu=1m`.
- per-pod throttling evidence: cgroup `cpu.stat` with high
  `nr_throttled`, `kubectl top` saturated at the limit, or
  `/api/v1/metrics` deltas under load.
- pod state proving the surface signals look healthy: Running 2/2,
  zero restarts, no errors in the fluent-bit container log — to
  justify why the more common diagnoses (CrashLoop, OOM, upstream
  connection failures) are ruled out.
- node-locality observation: the throttle is on the fluent-bit pod
  co-located with `qubership-log-generator`; other pods on the
  DaemonSet are quiet.
