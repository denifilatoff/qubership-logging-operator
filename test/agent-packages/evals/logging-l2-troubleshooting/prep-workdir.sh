#!/usr/bin/env bash
# prep-workdir.sh — prepare one ephemeral workdir for the eval pipeline.
#
# Usage: prep-workdir.sh <fixture-id> <variant> <run-id>
#   variant: with-pkg | no-pkg
#
# with-pkg: runs `apm install <package> --target claude` inside the workdir.
# no-pkg:   leaves the workdir empty.
#
# The workdir lives outside the source package — under
# ${XDG_CACHE_HOME:-$HOME/.cache}/qubership-logging-l2-evals/ — because
# `apm install` does a recursive copy of the source package and would
# otherwise copy the workdir into itself ad infinitum.
#
# Echoes the absolute workdir path on success.

set -euo pipefail

if [ $# -ne 3 ]; then
  echo "usage: $0 <fixture-id> <variant> <run-id>" >&2
  exit 2
fi

fixture_id="$1"
variant="$2"
run_id="$3"

case "$variant" in
  with-pkg|no-pkg) ;;
  *) echo "variant must be with-pkg or no-pkg, got: $variant" >&2; exit 2 ;;
esac

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/../../../.." && pwd)"
package_dir="$repo_root/agent-packages/logging-l2-troubleshooting"

cache_root="${XDG_CACHE_HOME:-$HOME/.cache}/qubership-logging-l2-evals"
workdir="$cache_root/$run_id/$fixture_id/$variant"
rm -rf "$workdir"
mkdir -p "$workdir"

if [ "$variant" = "with-pkg" ]; then
  # Install from the local package source via apm. After the layout fix,
  # the package directory holds only .apm/ + apm.yml + README.md so audit
  # should not flag it; --force is kept as a belt-and-braces hedge while
  # the local pipeline matures.
  ( cd "$workdir" \
    && apm install "$package_dir" --target claude --force --verbose \
       >"$workdir/.apm-install.log" 2>&1 )
fi

echo "$workdir"
