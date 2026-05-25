**Area:** fluentbit-troubleshoot

**Root cause:** The fluent-bit ConfigMap (`logging-fluentbit` in the
`logging` namespace) contains an invalid token at the top of its largest
config key. The configmap-reload sidecar picked up the change and signalled
fluent-bit to reload; fluent-bit could not parse the file and exited with
a parse error. The pod entered CrashLoopBackOff. Because the
`logging-operator` deployment was scaled to 0 before the edit (replicas
field in the deployment is 0, no pods present), the operator does not
reconcile the ConfigMap back to a healthy state — the broken content
persists.

The fixture seeds a unique marker line that makes the bad content obvious
on inspection: a line beginning with `@@@-fixture-broken-syntax-@@@`
prepended to the largest key in the ConfigMap's `data` map.

**Expected recommend:**
- type: configmap-restore
- target: ConfigMap `logging-fluentbit` in namespace `logging` (and
  the `logging-operator` deployment in the same namespace).
- change: restore the ConfigMap's affected data key to its pre-edit
  content (drop the `@@@-fixture-broken-syntax-@@@` line). The
  cluster fixture keeps a snapshot at
  `test/agent-packages/scenarios/.state/fluentbit-config-syntax.snapshot.yaml`
  that holds the original ConfigMap and is the natural restore source.
  Scaling `logging-operator` back to replicas=1 is a secondary action
  that allows future reconciliation but does not, on its own, fix
  this incident — the operator does not roll back arbitrary
  out-of-band ConfigMap edits.
- rollback: re-apply the snapshot. The fluent-bit DaemonSet picks up
  the corrected ConfigMap via the configmap-reload sidecar within
  ~30 s; no DaemonSet restart is required.

**Required snapshot fields attached to the recommend:**
- fluent-bit pod status (`kubectl get pods -n logging -l name=logging-fluentbit`)
  showing CrashLoopBackOff or repeated container restarts.
- fluent-bit container log lines naming the parse / syntax error, or
  the ConfigMap data showing the offending marker line — either form
  of direct evidence is acceptable.
- `logging-operator` deployment replica count = 0 (explains why the
  broken state persists; relevant for the rollback plan).
- ConfigMap last-modified timestamp (`metadata.annotations` or
  `metadata.managedFields[*].time`) — anchors the incident to a
  recent edit and rules out a long-standing bug.
