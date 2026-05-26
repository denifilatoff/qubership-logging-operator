# Ground truth — fluentbit-graylog-connection-refused

## Root cause

The `logging-fluentbit` ConfigMap's `output-graylog.conf` references a
Graylog Service hostname that does not resolve. FluentBit fails every
send with `connection refused` or DNS failure; messages back up locally
then drop.

## Expected chain shape

1. Triage runs the initial diagnostic pass. FluentBit shows up as healthy
   at the pod level, but its logs are noisy with connection failures
   naming a Graylog host.
2. Triage invokes `fluentbit-troubleshoot` first (collector zone shows
   signal).
3. `fluentbit-troubleshoot` matches its `fluentbit-connection-timeout-graylog`
   symptom from the catalogue, emits a `findings` entry whose `evidence`
   quotes the connection-refused log line.
4. The triage routing-policy detects the Graylog endpoint citation in the
   FluentBit expert's evidence via the `cited-strings.md` `points_to:
   graylog` pattern.
5. Triage invokes `graylog-server-troubleshoot` next. That expert verifies
   the Graylog Service / DNS state and emits the closing recommend
   (correct the endpoint hostname in the FluentBit ConfigMap, or restore
   the Graylog Service that should match).

## Final recommend

A structured `recommend` block proposing the correction of the endpoint
reference in `logging-fluentbit`'s `output-graylog.conf`. Snapshot must
include the current ConfigMap value plus evidence of the failed
resolution / connection.
