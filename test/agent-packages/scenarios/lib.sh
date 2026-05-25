#!/usr/bin/env bash
# Common helpers for fixture apply/revert scripts.
# Sourced by fixture.sh and individual apply.sh/revert.sh.

set -euo pipefail

# Resolve repo paths regardless of caller cwd.
SCENARIOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

log()  { printf '\033[1;36m[fixture]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[fixture]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[fixture]\033[0m %s\n' "$*" >&2; exit 1; }

require_backend() {
  local want="$1"
  [[ "$BACKEND" == "$want" ]] || die "this fixture requires BACKEND=$want (current: $BACKEND)"
}

mark_active()   { touch "$STATE_DIR/$1.active"; }
mark_inactive() { rm -f  "$STATE_DIR/$1.active"; }
is_active()     { [[ -f "$STATE_DIR/$1.active" ]]; }
