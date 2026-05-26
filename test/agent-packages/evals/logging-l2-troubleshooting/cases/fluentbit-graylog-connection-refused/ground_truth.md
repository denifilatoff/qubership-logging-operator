# Ground truth — fluentbit-graylog-connection-refused

## Root cause

Graylog StatefulSet has been scaled to 0 replicas. The `graylog-service` Kubernetes Service exists but has no backing pods. FluentBit's output-graylog.conf is correct (Host `graylog-service`, Port `12201`), but every TCP connection attempt to `graylog-service:12201` is refused because there are no endpoints.

The fix is in the Graylog zone — restore the StatefulSet to its previous replica count. FluentBit's own config does not need changes.

## Expected chain shape

1. Triage runs the initial diagnostic pass. FluentBit pods are running but their logs are noisy with `connection refused` / `no upstream connections available` to `graylog-service`. Graylog pods are absent.
2. Triage invokes `fluentbit-troubleshoot` first (collector zone shows signal).
3. `fluentbit-troubleshoot` matches its `fluentbit-connection-timeout-graylog` symptom from the catalogue, emits a `findings` entry whose `evidence` quotes the connection-refused log line (or `no upstream connections available`) and names `graylog-service:12201` as the unreachable endpoint.
4. The triage routing-policy detects the Graylog endpoint citation in the FluentBit expert's evidence via the `cited-strings.md` `points_to: graylog` pattern (pattern `connection refused.*:12201` or `no upstream connections available`).
5. Triage invokes `graylog-server-troubleshoot` next. That expert observes `kubectl get pods -l app.kubernetes.io/name=graylog` returns empty, `kubectl get endpoints graylog-service` is empty, and emits the closing recommend.

## Final recommend

A structured `recommend` block in the graylog-server-troubleshoot expert's output proposing to scale the Graylog StatefulSet back up (e.g. via `helm upgrade --set graylog.replicas=1` or by reverting the LoggingService CR's `graylog.replicas`). Snapshot must include the absent graylog pods and the empty endpoints list.

The recommend must NOT propose editing FluentBit's ConfigMap — FluentBit's config is correct.
