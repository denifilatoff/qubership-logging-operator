#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib.sh"

require_backend graylog

# Break GELF ingest WITHOUT taking Graylog down: rebind the GELF TCP input
# off port 12201. The graylog-service Service still maps 12201 -> pod:12201,
# but nothing listens there, so every FluentBit send gets `connection
# refused`. Graylog itself stays up (UI on 9000, old data searchable), so the
# symptom looks like a collector problem while the root cause is Graylog-zone.
GL_NS="logging"
GL_SVC="graylog-service"
FB_NS="logging"
SNAPSHOT="$STATE_DIR/fluentbit-graylog-connection-refused.snapshot.json"
WRONG_PORT=12299

# gl_curl (retrying ephemeral curl pod) and gl_wait_ready come from lib.sh.

gl_wait_ready
log "discovering GELF TCP input"
INPUT_ID="$(gl_curl -H 'Accept: application/json' \
    "http://${GL_SVC}:9000/api/system/inputs" |
    python3 -c "
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
    "http://${GL_SVC}:9000/api/system/inputs/${INPUT_ID}" >"$SNAPSHOT"

ORIG_PORT="$(python3 -c "import json;print(json.load(open('$SNAPSHOT'))['attributes']['port'])")"

# Build PUT payload: REST returns `attributes`, but PUT expects
# `configuration`. Same fields otherwise; only `port` changes.
PAYLOAD="$(python3 -c "
import json
with open('$SNAPSHOT') as f: d = json.load(f)
cfg = dict(d['attributes'])
cfg['port'] = $WRONG_PORT
print(json.dumps({
    'title': d['title'],
    'global': d['global'],
    'type': d['type'],
    'configuration': cfg,
}))
")"

log "rebinding GELF TCP input from port $ORIG_PORT to $WRONG_PORT (nothing will listen on 12201)"
gl_curl -H 'Content-Type: application/json' -X PUT -d "$PAYLOAD" \
    "http://${GL_SVC}:9000/api/system/inputs/${INPUT_ID}" >/dev/null

log "waiting up to 2 min for first FluentBit connection-refused log line"
deadline=$(($(date +%s) + 120))
while [[ $(date +%s) -lt $deadline ]]; do
    # FluentBit cites the failing Graylog endpoint: `connection refused` when
    # the port has no listener, or `no upstream connections available`. Either
    # is acceptable evidence for the cited-strings cascade.
    found="$("${KUBECTL[@]}" -n "$FB_NS" logs ds/logging-fluentbit --tail=200 -c logging-fluentbit 2>/dev/null |
        grep -cE 'connection refused|no upstream connections available|graylog-service' || true)"
    if [[ "${found:-0}" -gt 0 ]]; then
        log "FluentBit endpoint-failure log lines observed"
        break
    fi
    sleep 5
done

# editorconfig-checker-disable
cat <<NOTE

────────────────────────────────────────────────────────────
fluentbit-graylog-connection-refused active.

  GELF TCP input id     : $INPUT_ID
  port (was $ORIG_PORT) : $WRONG_PORT   ← nothing listens on 12201
  Graylog server        : UP (UI on :9000, old data searchable)

Skill probe commands:

  # 1) Graylog is up and reachable
  kubectl -n $GL_NS get pods -l app.kubernetes.io/name=graylog

  # 2) FluentBit cannot reach the GELF endpoint
  kubectl -n $FB_NS logs ds/logging-fluentbit --tail=20 -c logging-fluentbit

  # 3) GELF input bound to the wrong port — the smoking gun
  kubectl -n $GL_NS run gl-q-\$\$ --rm -i --restart=Never --quiet \\
    --image=curlimages/curl:8.10.1 --command -- \\
    curl -sS -u "$GL_AUTH" -H 'X-Requested-By: cli' \\
    http://${GL_SVC}:9000/api/system/inputs/${INPUT_ID}
────────────────────────────────────────────────────────────
NOTE
# editorconfig-checker-enable
