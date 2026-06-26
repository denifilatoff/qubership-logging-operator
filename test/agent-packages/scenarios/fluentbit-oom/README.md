# FluentBit OOMKilled

## Case

FluentBit's memory limit is set far below its working set under sustained
log ingestion. The log-generator produces continuous traffic; FluentBit's
memory consumption exceeds the 12 MiB limit and the kernel OOM-kills the
container. The pod cycles through `OOMKilled` with a climbing restart
count every ~30 seconds.

Both `limits.memory` and `requests.memory` are lowered together (to 12 MiB
and 8 MiB respectively) because Kubernetes rejects DaemonSet updates where
`requests > limits`.

The cluster runs FluentBit only (FluentD is `install: false`). FluentD is
not involved in this fixture.

## Mechanics

`apply.sh` does `helm upgrade --reuse-values` with both
`fluentbit.resources.limits.memory=12Mi` and
`fluentbit.resources.requests.memory=8Mi`.
`revert.sh` does `helm rollback`.
