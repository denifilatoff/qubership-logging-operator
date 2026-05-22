**Area:** fluentbit-troubleshoot

**Root cause:** FluentBit DaemonSet pods OOMKilled because the container
memory limit is below the steady-state working set of the
tail + forwarder pipeline under this log volume. Pods enter
CrashLoopBackOff; logs from nodes whose fluent-bit is down stop arriving.

**Expected recommend:**
- type: resource-bump
- target: DaemonSet/fluent-bit in namespace `logging`
- change: raise `spec.template.spec.containers[0].resources.limits.memory`
  above the working set. The cluster fixture currently sets
  `limits.memory=12Mi` and `requests.memory=8Mi` via helm
  `--reuse-values`; raising the limit to a realistic value
  (~128–256Mi for this workload) eliminates the OOMKill. Note that
  `requests.memory` must be raised alongside or kept below the new
  limit — Kubernetes rejects DaemonSet updates where
  `requests.memory > limits.memory`.
- rollback: `helm rollback` the operator release to the prior revision
  (the apply path was `helm upgrade --reuse-values`).

**Required snapshot fields attached to the recommend:**
- pod status of fluent-bit pods (all in OOMKilled or CrashLoopBackOff)
- last termination reason from `kubectl describe`
- current memory limit value (12Mi in this fixture)
- memory request value if different (8Mi in this fixture)
