**Area:** none — out of package. The natural target area is
`logging-operator-troubleshoot`, which is listed under "Areas not covered
yet" in `logging-l2-triage/references/topology.md`. The triage must
hand back to the engineer with the observation, not route to a nearby
skill as a substitute.

**Root cause:** The `qubership-logging-operator` Helm release was upgraded
with a non-existent image tag
(`ghcr.io/netcracker/qubership-logging-operator:does-not-exist-deadbeef-f4`).
The operator pod is in `ImagePullBackOff` / `ErrImagePull` with the
registry returning `manifest unknown` / `not found`. The operator
deployment is therefore Not Ready and cannot reconcile downstream
components. `helm status` reports the release as deployed (Helm does not
gate on image existence); `helm history` shows the latest revision pinned
to the bad image tag with `--reuse-values` and a single
`operatorImage=<bad>` set value.

All other logging components (fluent-bit, Graylog, OpenSearch) are
running on their previous spec because no reconcile pass has run. They
will keep working as long as nothing requires the operator to push a new
change. The user-facing impact is delayed: the cluster is in a degraded
posture, not yet broken at the data path.

**Expected recommend:**

- type: `helm-rollback` (preferred) or `manual-diagnosis` (acceptable).
- target: the `qubership-logging-operator` Helm release in the
  `logging` namespace.
- change: `helm rollback qubership-logging-operator 0 -n logging`
  (revert to the previous revision, which carried a working image
  tag). Acceptable alternative: hand back to the engineer with the
  observation and let them choose between rollback, a follow-up
  upgrade with a valid tag, or contacting the team that pushed the
  broken release.
- rollback: re-`helm upgrade` to the broken revision is the inverse
  but is never desired; `helm rollback` is itself the desired
  direction.

**Required snapshot fields attached to the recommend:**

- operator pod status: `kubectl get pods -n logging -l app.kubernetes.io/name=logging-operator`
  showing `ImagePullBackOff` or `ErrImagePull`.
- pod events from `kubectl describe pod` showing the registry error
  (`manifest unknown` / `not found` against the broken tag).
- operator deployment image: `kubectl get deploy -n logging
  -l app.kubernetes.io/name=logging-operator -o jsonpath=
  '{.items[0].spec.template.spec.containers[0].image}'` showing the
  bad tag.
- `helm history qubership-logging-operator -n logging` showing the
  latest revision pinned to the bad image and the previous (healthy)
  revision available as a rollback target.

**Negative criteria (the agent must NOT do):**

- Do not recommend changes to fluent-bit, fluent-d, Graylog, or
  OpenSearch — none are at fault.
- Do not invoke `fluentbit-troubleshoot`, `fluentd-troubleshoot`,
  `graylog-server-troubleshoot`, `graylog-disk-usage-investigate`,
  or `opensearch-troubleshoot`. The symptom belongs to an area that
  has no skill in this package.
