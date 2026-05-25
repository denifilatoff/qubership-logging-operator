#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib.sh"

RELEASE="qubership-logging-operator"
NS="logging"
BAD_IMAGE="ghcr.io/netcracker/qubership-logging-operator:does-not-exist-deadbeef-f4"
CHART="$KIND_DIR/../../charts/qubership-logging-operator"

log "current helm revision (revert.sh will rollback to it):"
helm --kube-context "$KCTX" -n "$NS" history "$RELEASE" | tail -3

log "upgrading $RELEASE with operatorImage=$BAD_IMAGE"
helm --kube-context "$KCTX" -n "$NS" upgrade "$RELEASE" "$CHART" \
  --reuse-values \
  --set "operatorImage=$BAD_IMAGE" \
  --wait=false

log "waiting up to 90s for ImagePullBackOff"
for _ in $(seq 1 18); do
  state="$("${KUBECTL[@]}" -n "$NS" get pods -l app.kubernetes.io/name=logging-operator \
    -o jsonpath='{range .items[*].status.containerStatuses[*]}{.state.waiting.reason}{"\n"}{end}' 2>/dev/null || true)"
  if echo "$state" | grep -qE 'ImagePullBackOff|ErrImagePull'; then
    log "fault confirmed: $state"
    break
  fi
  sleep 5
done

"${KUBECTL[@]}" -n "$NS" get pods -l app.kubernetes.io/name=logging-operator
