#!/usr/bin/env bash
# Driver for skill-test fixtures.
#
#   ./fixture.sh list
#   ./fixture.sh status
#   ./fixture.sh apply  <id>
#   ./fixture.sh revert <id>
#   ./fixture.sh info   <id>   # prints the fixture's README.md
#
# Each fixture lives in ./<id>/ with apply.sh, revert.sh, README.md.
# Only one fixture is meant to be active at a time (v1 policy).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

cmd_list() {
  for d in "$SCRIPT_DIR"/*/; do
    local id; id="$(basename "$d")"
    [[ "$id" == ".state" ]] && continue
    local mark="  "
    is_active "$id" && mark="* "
    local desc=""
    [[ -f "$d/README.md" ]] && desc="$(awk '/^# /{sub(/^# /,""); print; exit}' "$d/README.md")"
    printf '%s%-32s %s\n' "$mark" "$id" "$desc"
  done
}

cmd_status() {
  local any=0
  for f in "$STATE_DIR"/*.active; do
    [[ -e "$f" ]] || continue
    any=1
    printf 'active: %s\n' "$(basename "$f" .active)"
  done
  [[ $any -eq 0 ]] && echo "no fixtures active"
}

assert_id() {
  local id="$1"
  [[ -d "$SCRIPT_DIR/$id" ]] || die "unknown fixture: $id (try: ./fixture.sh list)"
}

cmd_apply() {
  local id="$1"; assert_id "$id"
  for f in "$STATE_DIR"/*.active; do
    [[ -e "$f" ]] || continue
    local other; other="$(basename "$f" .active)"
    [[ "$other" == "$id" ]] && die "$id is already active — revert first"
    die "fixture '$other' is active — revert it before applying '$id' (v1: one at a time)"
  done
  log "applying $id"
  bash "$SCRIPT_DIR/$id/apply.sh"
  mark_active "$id"
  log "applied $id — see $id/README.md for expected symptoms and ground truth"
}

cmd_revert() {
  local id="$1"; assert_id "$id"
  log "reverting $id"
  bash "$SCRIPT_DIR/$id/revert.sh"
  mark_inactive "$id"
  log "reverted $id"
}

cmd_info() {
  local id="$1"; assert_id "$id"
  cat "$SCRIPT_DIR/$id/README.md"
}

[[ $# -ge 1 ]] || usage
sub="$1"; shift || true
case "$sub" in
  list)   cmd_list ;;
  status) cmd_status ;;
  apply)  [[ $# -eq 1 ]] || usage; cmd_apply  "$1" ;;
  revert) [[ $# -eq 1 ]] || usage; cmd_revert "$1" ;;
  info)   [[ $# -eq 1 ]] || usage; cmd_info   "$1" ;;
  *) usage ;;
esac
