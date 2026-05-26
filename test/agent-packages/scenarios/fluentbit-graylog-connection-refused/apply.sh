#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib.sh"

RELEASE="qubership-logging-operator"
NS="logging"
CHART="$KIND_DIR/../../charts/qubership-logging-operator"

log "current helm revision (revert.sh will rollback to it):"
helm --kube-context "$KCTX" -n "$NS" history "$RELEASE" | tail -3

log "upgrading $RELEASE with graylog.replicas=0 (scale graylog StatefulSet to 0, leaving Service with no endpoints)"
helm --kube-context "$KCTX" -n "$NS" upgrade "$RELEASE" "$CHART" \
  --reuse-values \
  --set "graylog.replicas=0" \
  --wait=false

log "waiting up to 4 min for graylog pod to disappear"
deadline=$(( $(date +%s) + 240 ))
while [[ $(date +%s) -lt $deadline ]]; do
  count="$("${KUBECTL[@]}" -n "$NS" get pods -l app.kubernetes.io/name=graylog -o name 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "${count:-1}" == "0" ]]; then
    log "graylog pods gone (Service graylog-service now has no endpoints)"
    break
  fi
  sleep 5
done

log "waiting up to 2 min for first FluentBit connection-refused log line"
deadline=$(( $(date +%s) + 120 ))
while [[ $(date +%s) -lt $deadline ]]; do
  # Look for FluentBit lines citing graylog endpoint failure. The "no upstream
  # connections available" message appears generically; "connection refused"
  # appears when the Service has no endpoints. Either is acceptable evidence
  # for the cited-strings cascade.
  found="$("${KUBECTL[@]}" -n "$NS" logs ds/logging-fluentbit --tail=200 -c logging-fluentbit 2>/dev/null \
    | grep -cE 'connection refused|no upstream connections available|graylog-service' || true)"
  if [[ "${found:-0}" -gt 0 ]]; then
    log "FluentBit endpoint-failure log lines observed"
    break
  fi
  sleep 5
done

"${KUBECTL[@]}" -n "$NS" get pods -l app.kubernetes.io/name=graylog 2>&1 || true
"${KUBECTL[@]}" -n "$NS" get endpoints graylog-service 2>&1 || true
"${KUBECTL[@]}" -n "$NS" logs ds/logging-fluentbit --tail=20 -c logging-fluentbit 2>&1 || true
