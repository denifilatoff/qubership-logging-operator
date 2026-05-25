# F4 — Helm: bad image tag on logging-operator

## Case

The operator's Helm release is upgraded with a non-existent image tag
(`ghcr.io/netcracker/qubership-logging-operator:does-not-exist-deadbeef-f4`).
The `qubership-logging-operator` deployment never becomes Ready: pods show
`ImagePullBackOff` / `ErrImagePull` with `manifest unknown` or `not found`.

`helm status` reports the release as deployed and `helm history` shows the
revision pinned to the broken values. All other chart configuration is
valid; the failure is purely an image pull issue.

## Mechanics

`apply.sh` does `helm upgrade --reuse-values --set operatorImage=<bad>`,
then polls for `ImagePullBackOff` / `ErrImagePull` on the operator pod.
`revert.sh` does `helm rollback <release> 0` (to previous revision).
