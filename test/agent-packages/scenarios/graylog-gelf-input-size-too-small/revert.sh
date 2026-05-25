#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib.sh"

require_backend graylog

GL_NS="logging"
GL_SVC="graylog-service"
SNAPSHOT="$STATE_DIR/F7-gelf-input-size.snapshot.json"
MARKER_FILE="$STATE_DIR/F7-gelf-input-size.marker"

[[ -f "$SNAPSHOT" ]] || die "no snapshot at $SNAPSHOT — was apply.sh ever run?"

gl_curl() {
  "${KUBECTL[@]}" -n "$GL_NS" run "gl-curl-$RANDOM" \
    --rm -i --restart=Never --quiet \
    --image=curlimages/curl:8.10.1 \
    --command -- curl -sS -u admin:admin -H 'X-Requested-By: cli' "$@"
}

INPUT_ID="$(python3 -c "import json; print(json.load(open('$SNAPSHOT'))['id'])")"
PAYLOAD="$(python3 -c "
import json
with open('$SNAPSHOT') as f: d = json.load(f)
print(json.dumps({
  'title': d['title'],
  'global': d['global'],
  'type': d['type'],
  'configuration': d['attributes'],
}))
")"

log "restoring input $INPUT_ID configuration"
gl_curl -H 'Content-Type: application/json' -X PUT -d "$PAYLOAD" \
  "http://${GL_SVC}:9000/api/system/inputs/${INPUT_ID}" >/dev/null

log "verify"
gl_curl -H 'Accept: application/json' \
  "http://${GL_SVC}:9000/api/system/inputs/${INPUT_ID}" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('max_message_size =', d['attributes']['max_message_size'])"

rm -f "$SNAPSHOT" "$MARKER_FILE"
