#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib.sh"

RELEASE="qubership-logging-operator"
NS="logging"

log "rolling back $RELEASE to previous revision"
helm --kube-context "$KCTX" -n "$NS" rollback "$RELEASE" 0

log "waiting for fluent-bit rollout"
"${KUBECTL[@]}" -n "$NS" rollout status ds -l name=logging-fluentbit --timeout=120s || true
"${KUBECTL[@]}" -n "$NS" get pods -l name=logging-fluentbit
