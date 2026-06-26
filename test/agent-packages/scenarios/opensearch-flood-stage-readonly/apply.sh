#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib.sh"

require_backend graylog

SNAPSHOT="$STATE_DIR/opensearch-flood-stage-readonly.snapshot.json"
OS_NS="opensearch"
OS_SVC="opensearch" # ClusterIP svc inside the opensearch namespace

# Run curl from inside the cluster via an ephemeral pod — avoids needing a
# port-forward and works regardless of the operator's auth config.
os_curl() {
    "${KUBECTL[@]}" -n "$OS_NS" run fixture-curl-$$ \
        --rm -i --restart=Never --quiet \
        --image=curlimages/curl:8.10.1 \
        --command -- curl -sS -u "$OS_AUTH" "$@"
}

log "snapshotting current cluster settings → $SNAPSHOT"
os_curl "http://${OS_SVC}:9200/_cluster/settings" >"$SNAPSHOT"

# Flood-stage triggers when disk usage ≥ watermark. In kind the data dir is
# an overlay on the host disk, so we set watermarks BELOW current usage —
# typically 10%/15%/20% — to make the cluster perceive itself as past
# flood-stage. This puts `_cluster/settings` and `_cat/allocation` into the
# state the skill is expected to read.
log "lowering disk watermarks (low=10%, high=15%, flood_stage=20%)"
os_curl -X PUT "http://${OS_SVC}:9200/_cluster/settings" \
    -H 'Content-Type: application/json' \
    -d '{
        "transient": {
            "cluster.routing.allocation.disk.watermark.low":         "10%",
            "cluster.routing.allocation.disk.watermark.high":        "15%",
            "cluster.routing.allocation.disk.watermark.flood_stage": "20%"
        }
    }' >/dev/null

# OpenSearch only checks disk on its periodic interval. Rather than wait and
# hope the auto-apply kicks in (and rely on the kind overlay reporting usage
# correctly), we apply the read-only block directly to every index. This is
# the same end state a real flood-stage produces, and is what FluentBit /
# Graylog will hit when writing.
log "applying index.blocks.read_only_allow_delete=true to all user indices"
# Two OpenSearch quirks rolled into one call:
#  1) Wrap the setting in {"settings": {...}} with the value as a string
#     "true". The bare form {"index.blocks.read_only_allow_delete": true}
#     is silently re-routed to `index.blocks.write` — produces FORBIDDEN/8
#     (api write block), not the flood-stage signature the skill expects.
#  2) Use index pattern `*,-.*` (all, minus dotted) instead of `_all`. The
#     security plugin refuses bulk PUT to `_all/_settings` for this key
#     with "no permissions for []" — because system indices (e.g.
#     .opendistro_security) cannot be settings-updated this way. The
#     wildcard with negative pattern excludes them and applies the block
#     to every user index in one call, regardless of how many exist.
os_curl -X PUT "http://${OS_SVC}:9200/*,-.*/_settings?expand_wildcards=open" \
    -H 'Content-Type: application/json' \
    -d '{"settings": {"index.blocks.read_only_allow_delete": "true"}}' >/dev/null

log "waiting 5s for block to propagate"
sleep 5

log "current cluster settings:"
os_curl "http://${OS_SVC}:9200/_cluster/settings?pretty&flat_settings=true" || true

log "blocked indices:"
os_curl "http://${OS_SVC}:9200/_settings?flat_settings=true" |
    python3 -c "
import json, sys
d = json.load(sys.stdin)
for idx, s in sorted(d.items()):
    v = s.get('settings', {}).get('index.blocks.read_only_allow_delete')
    if v == 'true':
        print(f'  {idx}')
" || true
