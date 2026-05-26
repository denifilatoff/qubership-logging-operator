# FluentBit cannot reach Graylog endpoint

## Case

FluentBit's `output-graylog.conf` is configured to a Graylog Service
hostname that does not exist. FluentBit pods stay running and healthy by
their own standards (no OOM, no CrashLoop), but every send attempt fails
with `connection refused` or DNS resolution failure naming the Graylog
endpoint. Logs back up locally and eventually drop.

The cause is in the Graylog zone (endpoint / Service / DNS misconfig)
but only observable from FluentBit's perspective. This exercises the
cited-strings cascade routing path in the triage skill: FluentBit's
diagnostic pass surfaces a graylog-endpoint string in evidence, and
triage redirects the next hop to `graylog-server-troubleshoot`.

## Mechanics

`apply.sh` does `helm upgrade --reuse-values` with
`fluentbit.graylogHost=graylog-unreachable.logging.svc.cluster.local`.
The helm key was verified against
`charts/qubership-logging-operator/values.yaml` (top-level
`fluentbit.graylogHost`, rendered into the `logging-fluentbit`
ConfigMap's `output-graylog.conf` via
`controllers/fluentbit/fluentbit.configmap/conf.d/outputs/output-graylog.conf`).
`revert.sh` does `helm rollback`.
