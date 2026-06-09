#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib.sh"

require_backend graylog

GL_SVC="graylog-service"
SNAPSHOT="$STATE_DIR/graylog-gelf-input-size-too-small.snapshot.json"
MARKER_FILE="$STATE_DIR/graylog-gelf-input-size-too-small.marker"

[[ -f "$SNAPSHOT" ]] || die "no snapshot at $SNAPSHOT — was apply.sh ever run?"

# gl_curl (retrying ephemeral curl pod) and gl_wait_ready come from lib.sh.

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

gl_wait_ready
log "restoring input $INPUT_ID configuration"
gl_curl -H 'Content-Type: application/json' -X PUT -d "$PAYLOAD" \
    "http://${GL_SVC}:9000/api/system/inputs/${INPUT_ID}" >/dev/null

# Verify is a confirmation only — the PUT above is the load-bearing restore.
# A flaky GET (Graylog mid-roll) must not fail an otherwise-successful revert.
log "verify"
if body="$(gl_curl -H 'Accept: application/json' \
    "http://${GL_SVC}:9000/api/system/inputs/${INPUT_ID}")" &&
    size="$(printf '%s' "$body" |
        python3 -c "import json,sys; print(json.load(sys.stdin)['attributes']['max_message_size'])" 2>/dev/null)"; then
    log "max_message_size = $size"
else
    warn "verify GET failed (Graylog may be rolling); PUT restore already applied"
fi

rm -f "$SNAPSHOT" "$MARKER_FILE"
