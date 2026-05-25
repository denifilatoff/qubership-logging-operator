#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib.sh"

NS="logging"
SNAPSHOT="$STATE_DIR/fluentbit-config-syntax.snapshot.yaml"

[[ -f "$SNAPSHOT" ]] || die "no snapshot at $SNAPSHOT — was apply.sh ever run?"

# Always scale operator back to 1, even if the CM restore fails. Leaving the
# operator at 0 replicas is the worst possible state to bail out in.
restore_operator() {
  "${KUBECTL[@]}" -n "$NS" scale deploy \
    -l app.kubernetes.io/name=logging-operator --replicas=1 >/dev/null 2>&1 || true
}
trap 'restore_operator' EXIT

log "restoring ConfigMap from $SNAPSHOT"
"${KUBECTL[@]}" -n "$NS" apply -f "$SNAPSHOT"

log "scaling logging-operator back to 1"
restore_operator
"${KUBECTL[@]}" -n "$NS" rollout status deploy \
  -l app.kubernetes.io/name=logging-operator --timeout=120s || true

log "waiting for fluent-bit to recover"
"${KUBECTL[@]}" -n "$NS" rollout status ds -l name=logging-fluentbit --timeout=120s || true
"${KUBECTL[@]}" -n "$NS" get pods -l name=logging-fluentbit

rm -f "$SNAPSHOT"
