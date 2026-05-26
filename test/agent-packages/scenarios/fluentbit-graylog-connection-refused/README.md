# FluentBit cited-strings cascade — Graylog unreachable

## Case

Graylog StatefulSet is scaled to 0 replicas. The `graylog-service` Kubernetes Service still exists but has no endpoints. FluentBit's `output-graylog.conf` is unchanged and still points at the correct host (`graylog-service:12201`), but every send fails with `connection refused` (or the post-retry `no upstream connections available` message).

The cause is in the Graylog zone (no graylog pods to receive logs), not in the FluentBit zone — FluentBit's own config is fine. This exercises the cited-strings cascade routing path in the triage skill: FluentBit's diagnostic pass surfaces a `connection refused.*:12201` evidence line, and the triage routing-policy redirects the next hop to `graylog-server-troubleshoot` via the `cited-strings.md` `points_to: graylog` pattern.

## Mechanics

`apply.sh` does `helm upgrade --reuse-values --set graylog.replicas=0`. The qubership-logging-operator reconciles the LoggingService CR to scale the Graylog StatefulSet down. `revert.sh` does `helm rollback`, restoring the previous replica count.

## Why this is a cited-strings cascade test (not a fluentbit-zone test)

A previous version of this scenario broke FluentBit's ConfigMap (pointed it at a non-existent hostname). That produced DNS-failure logs but the correct fix was inside the FluentBit zone (restore the hostname). The fluentbit expert solved it locally without cascading — useful, but not what this case is meant to test.

The current scenario keeps FluentBit's config correct and breaks the downstream zone. The fluentbit expert sees endpoint failures it cannot fix from its own zone; routing-policy must redirect to graylog-server-troubleshoot.
