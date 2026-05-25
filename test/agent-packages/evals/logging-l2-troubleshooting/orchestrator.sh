#!/usr/bin/env bash
# orchestrator.sh — serial loop over L2 eval fixtures.
#
# Usage: orchestrator.sh [REPEATS] [fixture-id ...]
#   REPEATS  defaults to 3
#   fixtures default to all under fixtures/F*-*/
#
# Per fixture: clean-baseline check → prep both workdirs → apply cluster
# fixture → render promptfoo config → promptfoo eval → revert + DS restart.
# Failure handling per docs/eval-pipeline-design.md §6.

set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
cluster_fixtures="$repo_root/deploy/kind/fixtures"

repeats="${1:-3}"
shift || true

if [ $# -gt 0 ]; then
  fixtures=("$@")
else
  fixtures=()
  for d in "$script_dir"/fixtures/F*-*/; do
    fixtures+=("$(basename "$d")")
  done
fi

run_id="$(date -u +%Y%m%dT%H%M%SZ)"
results_dir="$script_dir/results/$run_id"
mkdir -p "$results_dir"
echo "run_id=$run_id"
echo "fixtures=${fixtures[*]}"
echo "repeats=$repeats"
echo "results=$results_dir"

# Pre-flight: clean baseline.
status_out="$("$cluster_fixtures/fixture.sh" status)"
if [ "$status_out" != "no fixtures active" ]; then
  echo "ERROR: baseline not clean. Active: $status_out" >&2
  echo "Revert the active fixture and rerun." >&2
  exit 1
fi

# One-time check: claude-agent-sdk available in this dir.
if [ ! -d "$script_dir/node_modules/@anthropic-ai/claude-agent-sdk" ]; then
  echo "ERROR: @anthropic-ai/claude-agent-sdk not installed locally." >&2
  echo "Run: (cd $script_dir && npm install --no-save @anthropic-ai/claude-agent-sdk)" >&2
  exit 1
fi

apply_revert_failed=0

for fix in "${fixtures[@]}"; do
  meta="$script_dir/fixtures/$fix/meta.yaml"
  if [ ! -f "$meta" ]; then
    echo "SKIP $fix: no meta.yaml" >&2
    continue
  fi
  cluster_fix="$(awk '/^cluster_fixture:/ {print $2}' "$meta")"
  if [ -z "$cluster_fix" ]; then
    echo "SKIP $fix: meta.yaml missing cluster_fixture" >&2
    continue
  fi

  echo "=== $fix → cluster fixture $cluster_fix ==="

  with=$("$script_dir/prep-workdir.sh" "$fix" with-pkg "$run_id")
  no=$( "$script_dir/prep-workdir.sh" "$fix" no-pkg   "$run_id")

  if ! "$cluster_fixtures/fixture.sh" apply "$cluster_fix"; then
    echo "APPLY FAILED for $cluster_fix — recording error and trying revert" >&2
    echo "{\"error\":\"apply-failed\",\"fixture\":\"$fix\"}" \
        > "$results_dir/$fix.json"
    "$cluster_fixtures/fixture.sh" revert "$cluster_fix" || true
    continue
  fi

  # Render the promptfoo config with three sets of substitutions
  # (per Task 7 findings): {{fixture_dir}}, {{fixture}}, {{workdir_*}}.
  # The rendered file MUST live in $script_dir so the claude-agent-sdk
  # provider resolves @anthropic-ai/claude-agent-sdk from the right
  # node_modules.
  rendered="$script_dir/.promptfooconfig.rendered.yaml"
  sed -e "s|{{fixture_dir}}|fixtures/$fix|g" \
      -e "s|{{fixture}}|$fix|g" \
      -e "s|{{workdir_with}}|$with|g" \
      -e "s|{{workdir_no}}|$no|g" \
      "$script_dir/promptfooconfig.yaml" > "$rendered"

  set +e
  ( cd "$script_dir" && \
    npx promptfoo@latest eval \
      --config "$rendered" \
      --var "fixture=$fix" \
      --var "workdir_with=$with" \
      --var "workdir_no=$no" \
      --repeat "$repeats" \
      --no-cache \
      --output "$results_dir/$fix.json" "$results_dir/$fix.html" )
  eval_rc=$?
  set -e

  # Revert and stabilise the DaemonSet (Task 7 finding: helm rollback
  # leaves pods scheduled with the old spec in CrashLoopBackOff).
  if ! "$cluster_fixtures/fixture.sh" revert "$cluster_fix"; then
    echo "FATAL: revert failed for $cluster_fix. Cluster dirty. Stopping." >&2
    apply_revert_failed=1
    break
  fi
  kubectl -n logging rollout restart ds/logging-fluentbit 2>/dev/null || true

  if [ $eval_rc -ne 0 ]; then
    echo "WARN: promptfoo returned $eval_rc for $fix (check $results_dir/$fix.json)" >&2
  fi
done

echo "$run_id" > "$script_dir/results/LAST_RUN"

if [ $apply_revert_failed -ne 0 ]; then
  exit 2
fi
echo "DONE: $results_dir"
