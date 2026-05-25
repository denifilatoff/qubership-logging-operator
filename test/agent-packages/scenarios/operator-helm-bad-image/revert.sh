#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib.sh"

RELEASE="qubership-logging-operator"
NS="logging"

log "rolling back $RELEASE to previous revision"
helm --kube-context "$KCTX" -n "$NS" rollback "$RELEASE" 0   # 0 = previous

log "waiting for operator pod to become Ready"
"${KUBECTL[@]}" -n "$NS" rollout status deploy -l app.kubernetes.io/name=logging-operator --timeout=120s || true
"${KUBECTL[@]}" -n "$NS" get pods -l app.kubernetes.io/name=logging-operator
