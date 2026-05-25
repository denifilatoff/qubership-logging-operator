#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib.sh"

require_backend graylog

GL_NS="logging"
GL_SVC="graylog-service"
LG_NS="log-generator"
LG_SVC="qubership-log-generator-service"
SNAPSHOT="$STATE_DIR/F7-gelf-input-size.snapshot.json"
MARKER_FILE="$STATE_DIR/F7-gelf-input-size.marker"
NEW_LIMIT=1024
MARKER="F7-$(date +%s)-$RANDOM"

# REST calls go through an ephemeral pod so we don't depend on a
# port-forward and the X-Requested-By header (Graylog CSRF guard) is
# applied uniformly.
gl_curl() {
  "${KUBECTL[@]}" -n "$GL_NS" run "gl-curl-$RANDOM" \
    --rm -i --restart=Never --quiet \
    --image=curlimages/curl:8.10.1 \
    --command -- curl -sS -u admin:admin -H 'X-Requested-By: cli' "$@"
}
lg_curl() {
  "${KUBECTL[@]}" -n "$LG_NS" run "lg-curl-$RANDOM" \
    --rm -i --restart=Never --quiet \
    --image=curlimages/curl:8.10.1 \
    --command -- curl -sS "$@"
}

log "discovering GELF TCP input"
INPUT_ID="$(gl_curl -H 'Accept: application/json' \
  "http://${GL_SVC}:9000/api/system/inputs" \
  | python3 -c "
import json, sys
d = json.load(sys.stdin)
for i in d.get('inputs', []):
    if i.get('type') == 'org.graylog2.inputs.gelf.tcp.GELFTCPInput':
        print(i['id']); break
")"
[[ -n "$INPUT_ID" ]] || die "no GELF TCP input found via REST"
log "  → input id: $INPUT_ID"

log "snapshotting input config → $SNAPSHOT"
gl_curl -H 'Accept: application/json' \
  "http://${GL_SVC}:9000/api/system/inputs/${INPUT_ID}" > "$SNAPSHOT"

# Build PUT payload: REST returns `attributes`, but PUT expects
# `configuration`. Same fields otherwise.
PAYLOAD="$(python3 -c "
import json, sys
with open('$SNAPSHOT') as f: d = json.load(f)
cfg = dict(d['attributes'])
cfg['max_message_size'] = $NEW_LIMIT
print(json.dumps({
  'title': d['title'],
  'global': d['global'],
  'type': d['type'],
  'configuration': cfg,
}))
")"

log "lowering max_message_size to $NEW_LIMIT bytes (was $(python3 -c "import json;print(json.load(open('$SNAPSHOT'))['attributes']['max_message_size'])"))"
gl_curl -H 'Content-Type: application/json' -X PUT -d "$PAYLOAD" \
  "http://${GL_SVC}:9000/api/system/inputs/${INPUT_ID}" >/dev/null

# Build a ~4 KB message carrying the marker.
BIG_MSG="$(python3 -c "print('${MARKER} ' + 'X'*4000)")"
LG_BODY="$(python3 -c "
import json
print(json.dumps({'message': '''$BIG_MSG''', 'numberOfRep': 3}))
")"

log "POSTing oversized message (~$(printf %d ${#BIG_MSG}) bytes, marker=$MARKER) to log-generator"
lg_curl -H 'Content-Type: application/json' -X POST -d "$LG_BODY" \
  "http://${LG_SVC}.${LG_NS}:8080/editor/editLogs" >/dev/null

echo "$MARKER" > "$MARKER_FILE"

cat <<NOTE

────────────────────────────────────────────────────────────
F7 active.

  Graylog GELF TCP input id : $INPUT_ID
  max_message_size          : $NEW_LIMIT bytes
  Marker for this run       : $MARKER

Skill probe commands:

  # 1) Marker is in the source pod's stdout
  kubectl -n $LG_NS logs deploy/qubership-log-generator --tail=20 | grep $MARKER

  # 2) Graylog input config — the smoking gun
  kubectl -n $GL_NS run gl-q-\$\$ --rm -i --restart=Never --quiet \\
    --image=curlimages/curl:8.10.1 --command -- \\
    curl -sS -u admin:admin -H 'X-Requested-By: cli' \\
    http://${GL_SVC}:9000/api/system/inputs/${INPUT_ID}
────────────────────────────────────────────────────────────
NOTE
