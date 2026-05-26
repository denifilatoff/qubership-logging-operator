#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib.sh"

RELEASE="qubership-logging-operator"
NS="logging"
CHART="$KIND_DIR/../../charts/qubership-logging-operator"
BAD_HOST="graylog-unreachable.logging.svc.cluster.local"

# Helm key path verified against charts/qubership-logging-operator/values.yaml:
# the fluentbit Graylog output target is fluentbit.graylogHost (see lines ~1228
# and the operator template controllers/fluentbit/fluentbit.configmap/conf.d/
# outputs/output-graylog.conf, which renders {{ .Values.Fluentbit.GraylogHost }}).

log "current helm revision (revert.sh will rollback to it):"
helm --kube-context "$KCTX" -n "$NS" history "$RELEASE" | tail -3

log "upgrading $RELEASE with fluentbit graylog output pointed at unreachable host"
helm --kube-context "$KCTX" -n "$NS" upgrade "$RELEASE" "$CHART" \
  --reuse-values \
  --set "fluentbit.graylogHost=$BAD_HOST" \
  --wait=false

log "waiting up to 4 min for first connection-refused log line"
deadline=$(( $(date +%s) + 240 ))
while [[ $(date +%s) -lt $deadline ]]; do
  found="$("${KUBECTL[@]}" -n "$NS" logs ds/logging-fluentbit --tail=100 2>/dev/null \
    | grep -cE 'connection refused|no upstream connections|getaddrinfo.*graylog-unreachable' || true)"
  if [[ "${found:-0}" -gt 0 ]]; then
    log "connection-refused log lines observed"
    break
  fi
  sleep 5
done

"${KUBECTL[@]}" -n "$NS" logs ds/logging-fluentbit --tail=20
