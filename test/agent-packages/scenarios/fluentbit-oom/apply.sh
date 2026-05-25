#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib.sh"

RELEASE="qubership-logging-operator"
NS="logging"
CHART="$KIND_DIR/../../charts/qubership-logging-operator"
NEW_MEM_LIMIT="12Mi"
NEW_MEM_REQUEST="8Mi"

log "current helm revision (revert.sh will rollback to it):"
helm --kube-context "$KCTX" -n "$NS" history "$RELEASE" | tail -3

# Both must be lowered: Kubernetes rejects DaemonSet updates where
# requests.memory > limits.memory. Without this, the operator reconcile
# loop fails with a validation error and the DaemonSet keeps its old
# memory limit — fixture would not reproduce the OOMKill.
log "upgrading $RELEASE with fluentbit.resources.limits.memory=$NEW_MEM_LIMIT, requests.memory=$NEW_MEM_REQUEST"
helm --kube-context "$KCTX" -n "$NS" upgrade "$RELEASE" "$CHART" \
  --reuse-values \
  --set "fluentbit.resources.limits.memory=$NEW_MEM_LIMIT" \
  --set "fluentbit.resources.requests.memory=$NEW_MEM_REQUEST" \
  --wait=false

log "waiting up to 4 min for first OOMKilled event"
deadline=$(( $(date +%s) + 240 ))
while [[ $(date +%s) -lt $deadline ]]; do
  reason="$("${KUBECTL[@]}" -n "$NS" get pods -l name=logging-fluentbit \
    -o jsonpath='{range .items[*].status.containerStatuses[*]}{.lastState.terminated.reason}{"\n"}{end}' 2>/dev/null || true)"
  if echo "$reason" | grep -q OOMKilled; then
    log "OOMKilled observed"
    break
  fi
  sleep 5
done

"${KUBECTL[@]}" -n "$NS" get pods -l name=logging-fluentbit
