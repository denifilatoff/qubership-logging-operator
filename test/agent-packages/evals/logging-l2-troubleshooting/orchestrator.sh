#!/usr/bin/env bash
# orchestrator.sh — serial loop over L2 eval cases.
#
# Usage: orchestrator.sh [REPEATS] [case-slug ...]
#   REPEATS  defaults to 3
#   cases    default to all under cases/*/
#
# Per case: clean-baseline check → prep both workdirs → apply scenario
# (slug is shared between eval case and scenario) → render promptfoo
# config → promptfoo eval → revert + DS restart.

set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/../../../.." && pwd)"
scenarios_dir="$repo_root/test/agent-packages/scenarios"

repeats="${1:-3}"
shift || true

if [ $# -gt 0 ]; then
  cases=("$@")
else
  cases=()
  for d in "$script_dir"/cases/*/; do
    cases+=("$(basename "$d")")
  done
fi

run_id="$(date -u +%Y%m%dT%H%M%SZ)"
results_dir="$script_dir/results/$run_id"
mkdir -p "$results_dir"
echo "run_id=$run_id"
echo "cases=${cases[*]}"
echo "repeats=$repeats"
echo "results=$results_dir"

status_out="$("$scenarios_dir/fixture.sh" status)"
if [ "$status_out" != "no fixtures active" ]; then
  echo "ERROR: baseline not clean. Active: $status_out" >&2
  echo "Revert the active scenario and rerun." >&2
  exit 1
fi

if [ ! -d "$script_dir/node_modules/@anthropic-ai/claude-agent-sdk" ]; then
  echo "ERROR: @anthropic-ai/claude-agent-sdk not installed locally." >&2
  echo "Run: (cd $script_dir && npm install --no-save @anthropic-ai/claude-agent-sdk)" >&2
  exit 1
fi

apply_revert_failed=0

for case_slug in "${cases[@]}"; do
  case_dir="$script_dir/cases/$case_slug"
  if [ ! -d "$case_dir" ]; then
    echo "SKIP $case_slug: no case directory" >&2
    continue
  fi

  echo "=== $case_slug ==="

  with=$("$script_dir/prep-workdir.sh" "$case_slug" with-pkg "$run_id")
  no=$( "$script_dir/prep-workdir.sh" "$case_slug" no-pkg   "$run_id")

  if ! "$scenarios_dir/fixture.sh" apply "$case_slug"; then
    echo "APPLY FAILED for $case_slug — recording error and trying revert" >&2
    echo "{\"error\":\"apply-failed\",\"case\":\"$case_slug\"}" \
        > "$results_dir/$case_slug.json"
    "$scenarios_dir/fixture.sh" revert "$case_slug" || true
    continue
  fi

  rendered="$script_dir/.promptfooconfig.rendered.yaml"
  sed -e "s|{{case_dir}}|cases/$case_slug|g" \
      -e "s|{{case}}|$case_slug|g" \
      -e "s|{{workdir_with}}|$with|g" \
      -e "s|{{workdir_no}}|$no|g" \
      "$script_dir/promptfooconfig.yaml" > "$rendered"

  set +e
  ( cd "$script_dir" && \
    npx promptfoo@latest eval \
      --config "$rendered" \
      --var "case=$case_slug" \
      --var "workdir_with=$with" \
      --var "workdir_no=$no" \
      --repeat "$repeats" \
      --no-cache \
      --output "$results_dir/$case_slug.json" "$results_dir/$case_slug.html" )
  eval_rc=$?
  set -e

  if ! "$scenarios_dir/fixture.sh" revert "$case_slug"; then
    echo "FATAL: revert failed for $case_slug. Cluster dirty. Stopping." >&2
    apply_revert_failed=1
    break
  fi
  kubectl -n logging rollout restart ds/logging-fluentbit 2>/dev/null || true

  if [ $eval_rc -ne 0 ]; then
    echo "WARN: promptfoo returned $eval_rc for $case_slug (check $results_dir/$case_slug.json)" >&2
  fi
done

echo "$run_id" > "$script_dir/results/LAST_RUN"

if [ $apply_revert_failed -ne 0 ]; then
  exit 2
fi
echo "DONE: $results_dir"
