#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib.sh"

require_backend graylog

OS_NS="opensearch"
OS_SVC="opensearch"

os_curl() {
    "${KUBECTL[@]}" -n "$OS_NS" run fixture-curl-$$ \
        --rm -i --restart=Never --quiet \
        --image=curlimages/curl:8.10.1 \
        --command -- curl -sS -u "$OS_AUTH" "$@"
}

log "clearing transient watermark overrides"
os_curl -X PUT "http://${OS_SVC}:9200/_cluster/settings" \
    -H 'Content-Type: application/json' \
    -d '{
        "transient": {
            "cluster.routing.allocation.disk.watermark.low":         null,
            "cluster.routing.allocation.disk.watermark.high":        null,
            "cluster.routing.allocation.disk.watermark.flood_stage": null
        }
    }' >/dev/null

log "removing read_only_allow_delete from all user indices"
# Mirror apply.sh: wildcard `*,-.*` (security plugin blocks `_all`), and
# set the value to "false" rather than null — while the block is active
# it rejects its own removal via null with the same 429 flood-stage
# message ("block does not allow lifting the block"). Setting false works.
os_curl -X PUT "http://${OS_SVC}:9200/*,-.*/_settings?expand_wildcards=open" \
    -H 'Content-Type: application/json' \
    -d '{"settings": {"index.blocks.read_only_allow_delete": "false"}}' >/dev/null

log "verifying"
os_curl "http://${OS_SVC}:9200/_cluster/health?pretty" || true
