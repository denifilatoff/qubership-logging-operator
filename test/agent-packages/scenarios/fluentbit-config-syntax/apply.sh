#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib.sh"

NS="logging"
SNAPSHOT="$STATE_DIR/fluentbit-config-syntax.snapshot.yaml"

# If anything below fails, restore the operator so the cluster does not get
# stuck with replicas=0. The CM may still be broken — that's recoverable, an
# offline operator is not.
restore_operator() {
  "${KUBECTL[@]}" -n "$NS" scale deploy \
    -l app.kubernetes.io/name=logging-operator --replicas=1 >/dev/null 2>&1 || true
}
trap 'rc=$?; [[ $rc -ne 0 ]] && { warn "apply failed (rc=$rc) — restoring operator"; restore_operator; }' EXIT

log "discovering fluent-bit ConfigMap"
CM_NAME="$("${KUBECTL[@]}" -n "$NS" get cm -l name=logging-fluentbit \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
[[ -n "$CM_NAME" ]] || die "no ConfigMap with label name=logging-fluentbit in ns $NS"
log "  → $CM_NAME"

log "scaling logging-operator to 0 so it won't reconcile our edit back"
"${KUBECTL[@]}" -n "$NS" scale deploy -l app.kubernetes.io/name=logging-operator --replicas=0
"${KUBECTL[@]}" -n "$NS" wait --for=delete pod \
  -l app.kubernetes.io/name=logging-operator --timeout=60s || true

log "snapshotting ConfigMap → $SNAPSHOT"
# Strip server-side metadata so revert can re-apply on top of the live object
# without hitting `Conflict: the object has been modified`.
"${KUBECTL[@]}" -n "$NS" get cm "$CM_NAME" -o json \
  | python3 -c "
import json, sys, yaml
d = json.load(sys.stdin)
m = d.get('metadata', {})
for k in ('resourceVersion', 'uid', 'creationTimestamp', 'managedFields', 'generation'):
    m.pop(k, None)
anns = m.get('annotations', {}) or {}
anns.pop('kubectl.kubernetes.io/last-applied-configuration', None)
if anns:
    m['annotations'] = anns
else:
    m.pop('annotations', None)
d.pop('status', None)
yaml.safe_dump(d, sys.stdout, default_flow_style=False)
" > "$SNAPSHOT"

# Pick the largest config key and inject a broken line near the top — guarantees
# parse error regardless of which file fluent-bit reads first.
KEY="$("${KUBECTL[@]}" -n "$NS" get cm "$CM_NAME" -o json \
  | python3 -c 'import json,sys; d=json.load(sys.stdin)["data"]; print(max(d, key=lambda k: len(d[k])))')"
log "injecting broken token into key '$KEY'"

# Replace the first newline with a syntactically invalid token. Works for both
# fluent-bit classic syntax (.conf) and YAML config — either way, parser rejects.
"${KUBECTL[@]}" -n "$NS" get cm "$CM_NAME" -o json \
  | python3 -c "
import json, sys
d = json.load(sys.stdin)
k = '$KEY'
d['data'][k] = '@@@-fixture-broken-syntax-@@@\n' + d['data'][k]
print(json.dumps(d))
" | "${KUBECTL[@]}" -n "$NS" apply -f -

log "waiting for fluent-bit to crashloop (configmap-reload picks up changes in ~30s)"
deadline=$(( $(date +%s) + 180 ))
while [[ $(date +%s) -lt $deadline ]]; do
  state="$("${KUBECTL[@]}" -n "$NS" get pods -l name=logging-fluentbit \
    -o jsonpath='{range .items[*].status.containerStatuses[*]}{.state.waiting.reason}{" "}{.lastState.terminated.reason}{"\n"}{end}' 2>/dev/null || true)"
  if echo "$state" | grep -qE 'CrashLoopBackOff|Error'; then
    log "fault confirmed: $state"
    break
  fi
  sleep 10
done

"${KUBECTL[@]}" -n "$NS" get pods -l name=logging-fluentbit

cat <<'NOTE'

────────────────────────────────────────────────────────────
NOTE: logging-operator is scaled to 0. revert.sh will restore
it. Do not run `helmfile apply` while this fixture is active —
it will reset the deployment replicas and undo step 1.
────────────────────────────────────────────────────────────
NOTE
