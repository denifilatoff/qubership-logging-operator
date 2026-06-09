#!/usr/bin/env bash
# Common helpers for scenario apply/revert scripts.
# Sourced by fixture.sh and individual scenario apply.sh/revert.sh.

set -euo pipefail

# Resolve repo paths regardless of caller cwd.
SCENARIOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Hop: scenarios/ → agent-packages/ → test/ → repo root → deploy/kind
KIND_DIR="$(cd "$SCENARIOS_DIR/../../../deploy/kind" && pwd)"
STATE_DIR="$SCENARIOS_DIR/.state"
mkdir -p "$STATE_DIR"

# Load .env from deploy/kind/.env — same file helmfile uses.
if [[ -f "$KIND_DIR/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$KIND_DIR/.env"
    set +a
fi

: "${CLUSTER_NAME:?CLUSTER_NAME not set — populate deploy/kind/.env}"
: "${BACKEND:?BACKEND not set — populate deploy/kind/.env}"

KCTX="kind-${CLUSTER_NAME}"
KUBECTL=(kubectl --context "$KCTX")

log() { printf '\033[1;36m[fixture]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[fixture]\033[0m %s\n' "$*" >&2; }
die() {
    printf '\033[1;31m[fixture]\033[0m %s\n' "$*" >&2
    exit 1
}

require_backend() {
    local want="$1"
    [[ "$BACKEND" == "$want" ]] || die "this fixture requires BACKEND=$want (current: $BACKEND)"
}

mark_active() { touch "$STATE_DIR/$1.active"; }
mark_inactive() { rm -f "$STATE_DIR/$1.active"; }
is_active() { [[ -f "$STATE_DIR/$1.active" ]]; }

# Block until the stack is Ready again. Called by fixture.sh after revert so the
# revert contract guarantees a clean baseline on return (absorbs the eval-layer
# baseline gate the orchestrator used to run before each case).
wait_baseline_ready() {
    "${KUBECTL[@]}" -n logging rollout restart ds/logging-fluentbit >/dev/null 2>&1 || true
    # 3-pod DaemonSet with a configmap-reloader sidecar; a rolling restart routinely
    # needs more than 180s to report Ready, so the gate timed out spuriously at 180s.
    "${KUBECTL[@]}" -n logging rollout status ds/logging-fluentbit --timeout=300s ||
        warn "fluent-bit not Ready after revert"
    "${KUBECTL[@]}" -n logging rollout status deploy/logging-operator --timeout=120s 2>/dev/null || true
    "${KUBECTL[@]}" -n logging rollout status statefulset/graylog --timeout=180s 2>/dev/null ||
        warn "Graylog not Ready after revert"
}

# --- Graylog REST helpers (graylog-backend scenarios) -------------------------
# Graylog restarts (liveness, OOM) roll the pod and refuse REST connections
# mid-run. These helpers retry so a transient restart does not abort apply or,
# worse, revert — a failed revert leaves the cluster dirty and stops the suite.
GL_NS="${GL_NS:-logging}"
GL_SVC="${GL_SVC:-graylog-service}"

# Local-dev REST credentials for Graylog and OpenSearch. These are the kind
# baseline defaults, not secrets; override via deploy/kind/.env if your cluster
# differs.
GL_AUTH="${GL_AUTH:-admin:admin}"
OS_AUTH="${OS_AUTH:-admin:admin}"

# Ephemeral curl pod against the Graylog REST API, retried on transient
# failure. Same call signature as a bare curl (extra args after the implicit
# auth and CSRF headers). Echoes the response body on success.
gl_curl() {
    local attempt out
    for attempt in 1 2 3 4 5; do
        if out="$("${KUBECTL[@]}" -n "$GL_NS" run "gl-curl-$RANDOM" \
            --rm -i --restart=Never --quiet \
            --image=curlimages/curl:8.10.1 \
            --command -- curl -fsS -u "$GL_AUTH" -H 'X-Requested-By: cli' "$@" 2>/dev/null)"; then
            printf '%s' "$out"
            return 0
        fi
        warn "gl_curl attempt $attempt/5 failed — Graylog may be restarting; retrying in 5s"
        sleep 5
    done
    return 1
}

# Block until Graylog answers its load-balancer status endpoint, or time out.
# Call before REST mutations so we do not fire at a pod that is mid-restart.
# Never fails the caller: on timeout it warns and returns 0, leaving gl_curl's
# own retry to cover the residual window.
gl_wait_ready() {
    local deadline
    deadline=$(($(date +%s) + 180))
    while [[ $(date +%s) -lt $deadline ]]; do
        if "${KUBECTL[@]}" -n "$GL_NS" run "gl-ready-$RANDOM" --rm -i --restart=Never --quiet \
            --image=curlimages/curl:8.10.1 --command -- \
            curl -fsS -o /dev/null -u "$GL_AUTH" -H 'X-Requested-By: cli' \
            "http://${GL_SVC}:9000/api/system/lbstatus" 2>/dev/null; then
            return 0
        fi
        sleep 5
    done
    warn "Graylog not ready after 180s — proceeding anyway"
    return 0
}
