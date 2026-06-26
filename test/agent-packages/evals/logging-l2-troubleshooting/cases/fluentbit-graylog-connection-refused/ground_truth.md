# Ground truth — fluentbit-graylog-connection-refused

## Root cause

The Graylog GELF TCP input has been rebound off port 12201 (its `port`
configuration was changed to a different value via the Graylog REST API).
Graylog itself is healthy: the StatefulSet is running, the UI on port 9000
responds, and previously ingested logs are still searchable.

The `graylog-service` Kubernetes Service still maps port 12201 to the Graylog
pod, but nothing listens on 12201 inside the pod anymore, so every TCP send
from FluentBit to `graylog-service:12201` is refused. FluentBit's
output-graylog.conf is correct (Host `graylog-service`, Port `12201`).

The fix is in the Graylog zone — restore the GELF TCP input's listen port to
12201 (the input restarts and resumes accepting connections). FluentBit's own
config does not need changes.

## Expected chain shape

The case converges on `graylog-server-troubleshoot`, which matches its
`graylog-gelf-input-not-listening` symptom (Graylog healthy, but the GELF
input is bound to a port other than 12201) and emits the closing recommend.
The route there is path-agnostic — both of these pass:

- **Direct.** Triage reasons from the symptom (no new logs, Graylog UI up,
  old data searchable) that ingest is broken on the Graylog side and invokes
  `graylog-server-troubleshoot`, which finds the input on the wrong port.
- **Via the collector (cited-strings cascade).** Triage starts at
  `fluentbit-troubleshoot`; that expert emits a `findings` entry whose
  `evidence` quotes the `connection refused` / `no upstream connections
  available` line naming `graylog-service:12201`; the triage routing-policy
  detects the Graylog endpoint citation (`cited-strings.md` `points_to:
  graylog`) and redirects to `graylog-server-troubleshoot`.

The cascade is a valid bonus path, not a requirement. What matters is the
converging zone and a correct recommend — not the number of hops.

## Final recommend

A structured `recommend` block in the graylog-server-troubleshoot expert's
output proposing to restore the GELF TCP input's listen port to 12201 (via the
Graylog REST API, or by restarting the input with the correct configuration).
Snapshot must include the running Graylog pods and the input configuration
showing the wrong port.

The recommend must NOT propose editing FluentBit's ConfigMap — FluentBit's
config is correct.
