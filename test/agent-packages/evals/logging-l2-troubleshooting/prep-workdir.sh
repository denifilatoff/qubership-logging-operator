#!/usr/bin/env bash
# prep-workdir.sh — prepare one ephemeral workdir for the eval pipeline.
#
# Usage: prep-workdir.sh <case-slug> <variant> <run-id>
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
  echo "usage: $0 <case-slug> <variant> <run-id>" >&2
  exit 2
fi

case_slug="$1"
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
workdir="$cache_root/$run_id/$case_slug/$variant"
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

  # APM bug workaround: `apm install` from a local path does not dereference
  # symlinks inside .apm/skills/<name>/references/ when integrating into
  # .claude/skills/<name>/references/, so those directories end up empty and
  # the agent reads broken references. Install from a remote (GitHub URL)
  # works correctly because the git fetch materializes targets before
  # integration. We work around by copying each symlink target (cp -L) from
  # the source package into the deployed skill tree.
  #
  # TODO: file an APM upstream bug — local-path install should dereference
  # symlinks the same way remote install does. Until that lands, this loop
  # stays.
  src_skills="$package_dir/.apm/skills"
  dst_skills="$workdir/.claude/skills"
  if [ -d "$dst_skills" ]; then
    while IFS= read -r -d '' link; do
      rel="${link#$src_skills/}"            # <skill>/references/<file>.md
      dst="$dst_skills/$rel"
      mkdir -p "$(dirname "$dst")"
      cp -L "$link" "$dst"
    done < <(find "$src_skills" -type l -name '*.md' -path '*/references/*' -print0)
  fi
fi

echo "$workdir"
