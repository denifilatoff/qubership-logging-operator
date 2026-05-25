#!/usr/bin/env bash
# aggregate.sh — turn the last promptfoo run into results/<run>/summary.md.
#
# Reads results/LAST_RUN, walks results/<run-id>/*.json (one per fixture),
# emits per-fixture mean score (with-pkg vs no-pkg), the X/N check-count
# differential parsed from the judge's reason string, and the skill-used
# pass-rate.
#
# Note on per-check (per-id) pass-rates: the judge returns a structured
# {pass, score, reason, checks[]} object (commit d3dcbae), but promptfoo
# does NOT preserve the raw judge output in its result JSON — only the
# aggregate `score` and the `reason` summary survive. So per-id rates
# would require re-running the judge with output capture; this script
# reports the X/N count from `reason` instead, which is what's available.

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
last="$script_dir/results/LAST_RUN"
if [ ! -f "$last" ]; then
  echo "no LAST_RUN; run orchestrator.sh first" >&2
  exit 1
fi
run_id="$(cat "$last")"
run_dir="$script_dir/results/$run_id"
out="$run_dir/summary.md"

if ! ls "$run_dir"/*.json >/dev/null 2>&1; then
  echo "no result JSON in $run_dir" >&2
  exit 1
fi

# Parse "overall_pass=... (X/N checks passed)" into "X N", or "" if unparseable.
# Reads from stdin. Uses sed for portability across awk variants.
parse_xn() {
  sed -nE 's|.*\(([0-9]+)/([0-9]+) checks passed\).*|\1 \2|p'
}

# Mean of a stream of numbers, formatted to 2 decimals; "n/a" if empty.
mean_fmt() {
  awk '
    { s += $1; n++ }
    END { if (n>0) printf "%.2f", s/n; else print "n/a" }
  '
}

{
  echo "# Eval run $run_id"
  echo
  echo "## Mean score by fixture (with-pkg vs no-pkg)"
  echo
  echo "| Fixture | with-pkg score | no-pkg score | delta | repeats |"
  echo "|---|---|---|---|---|"

  for f in "$run_dir"/*.json; do
    [ -e "$f" ] || continue
    fix="$(basename "$f" .json)"
    if jq -e '.error == "apply-failed"' "$f" >/dev/null 2>&1; then
      echo "| $fix | (apply-failed) | (apply-failed) | - | 0 |"
      continue
    fi

    with_scores=$(jq -r '.results.results[]? | select(.provider.label=="with-pkg") | .score' "$f")
    no_scores=$(  jq -r '.results.results[]? | select(.provider.label=="no-pkg")   | .score' "$f")
    n_with=$(printf '%s\n' "$with_scores" | grep -c . || true)
    n_no=$(  printf '%s\n' "$no_scores"   | grep -c . || true)
    with_mean=$(printf '%s\n' "$with_scores" | mean_fmt)
    no_mean=$(  printf '%s\n' "$no_scores"   | mean_fmt)

    if [ "$with_mean" != "n/a" ] && [ "$no_mean" != "n/a" ]; then
      delta=$(python3 -c "print(f'{$with_mean - $no_mean:+.2f}')")
    else
      delta="-"
    fi
    echo "| $fix | $with_mean | $no_mean | $delta | with=$n_with no=$n_no |"
  done

  echo
  echo "## Rubric check counts (parsed from judge \`reason\`)"
  echo
  echo "Judge \`reason\` has the form \`overall_pass=… (X/N checks passed)\`."
  echo "Below: mean X / N across all repeats per branch. Per-check (per-id)"
  echo "rates aren't available from the stored result JSON; promptfoo drops"
  echo "the raw judge JSON (including \`checks[]\`) after parsing its score."
  echo
  echo "| Fixture | with-pkg mean X/N | no-pkg mean X/N |"
  echo "|---|---|---|"

  for f in "$run_dir"/*.json; do
    [ -e "$f" ] || continue
    fix="$(basename "$f" .json)"
    if jq -e '.error == "apply-failed"' "$f" >/dev/null 2>&1; then
      echo "| $fix | (apply-failed) | (apply-failed) |"
      continue
    fi

    branch_xn() {
      local label="$1"
      jq -r --arg L "$label" '
        .results.results[]? | select(.provider.label==$L)
        | .gradingResult.componentResults[]?
        | select(.assertion.type=="llm-rubric")
        | .reason
      ' "$f" | while IFS= read -r line; do
        printf '%s\n' "$line" | parse_xn
      done
    }

    with_pairs=$(branch_xn "with-pkg")
    no_pairs=$(branch_xn "no-pkg")

    fmt_pairs() {
      awk '
        NF==2 { sx+=$1; sn+=$2; c++ }
        END {
          if (c>0) printf "%.1f/%.1f", sx/c, sn/c
          else print "n/a"
        }
      '
    }
    with_fmt=$(printf '%s\n' "$with_pairs" | fmt_pairs)
    no_fmt=$(  printf '%s\n' "$no_pairs"   | fmt_pairs)
    echo "| $fix | $with_fmt | $no_fmt |"
  done

  echo
  echo "## skill-used (\`logging-l2-triage\`)"
  echo
  echo "Pass/fail of the skill-used assertion per branch (total passes / total runs)."
  echo
  echo "| Fixture | with-pkg passes | no-pkg passes |"
  echo "|---|---|---|"
  for f in "$run_dir"/*.json; do
    [ -e "$f" ] || continue
    fix="$(basename "$f" .json)"
    if jq -e '.error == "apply-failed"' "$f" >/dev/null 2>&1; then continue; fi
    with_pass=$(jq '[.results.results[]? | select(.provider.label=="with-pkg") | .gradingResult.componentResults[]? | select(.assertion.type=="skill-used") | .pass] | map(select(.)) | length' "$f")
    with_total=$(jq '[.results.results[]? | select(.provider.label=="with-pkg") | .gradingResult.componentResults[]? | select(.assertion.type=="skill-used")] | length' "$f")
    no_pass=$(jq    '[.results.results[]? | select(.provider.label=="no-pkg")   | .gradingResult.componentResults[]? | select(.assertion.type=="skill-used") | .pass] | map(select(.)) | length' "$f")
    no_total=$(jq   '[.results.results[]? | select(.provider.label=="no-pkg")   | .gradingResult.componentResults[]? | select(.assertion.type=="skill-used")] | length' "$f")
    echo "| $fix | $with_pass/$with_total | $no_pass/$no_total |"
  done

  echo
  echo "## Cost per fixture (USD)"
  echo
  echo "Per-fixture cost summed across all repeats per branch. \`costUSD\` is"
  echo "promptfoo's own per-call computation from model token rates (includes"
  echo "cached-input pricing). Agent cost is the troubleshooting session; judge"
  echo "cost is the llm-rubric evaluation."
  echo
  echo "| Fixture | with-pkg agent | with-pkg judge | no-pkg agent | no-pkg judge | row total |"
  echo "|---|---|---|---|---|---|"

  # Sum costUSD across all modelUsage entries for the given provider label.
  branch_cost_agent() {
    jq -r --arg L "$1" '
      [.results.results[]?
       | select(.provider.label==$L)
       | .response.metadata.modelUsage // {}
       | to_entries[]?
       | .value.costUSD // 0
      ] | add // 0
    ' "$2"
  }
  branch_cost_judge() {
    jq -r --arg L "$1" '
      [.results.results[]?
       | select(.provider.label==$L)
       | .gradingResult.componentResults[]?
       | select(.assertion.type=="llm-rubric")
       | .metadata.modelUsage // {}
       | to_entries[]?
       | .value.costUSD // 0
      ] | add // 0
    ' "$2"
  }
  branch_turns_sum() {
    jq -r --arg L "$1" '
      [.results.results[]?
       | select(.provider.label==$L)
       | .response.metadata.numTurns // 0
      ] | add // 0
    ' "$2"
  }
  branch_count() {
    jq -r --arg L "$1" '
      [.results.results[]? | select(.provider.label==$L)] | length
    ' "$2"
  }

  total_cost="0"
  total_score="0"
  total_runs=0
  for f in "$run_dir"/*.json; do
    [ -e "$f" ] || continue
    fix="$(basename "$f" .json)"
    if jq -e '.error == "apply-failed"' "$f" >/dev/null 2>&1; then
      echo "| $fix | (apply-failed) | - | (apply-failed) | - | - |"
      continue
    fi
    wa=$(branch_cost_agent "with-pkg" "$f")
    wj=$(branch_cost_judge "with-pkg" "$f")
    na=$(branch_cost_agent "no-pkg"   "$f")
    nj=$(branch_cost_judge "no-pkg"   "$f")
    row=$(python3 -c "print(f'{$wa+$wj+$na+$nj:.4f}')")
    total_cost=$(python3 -c "print(f'{$total_cost+$wa+$wj+$na+$nj:.4f}')")

    score_sum=$(jq '[.results.results[]?.score // 0] | add // 0' "$f")
    run_count=$(jq '[.results.results[]?.score] | length' "$f")
    total_score=$(python3 -c "print($total_score + $score_sum)")
    total_runs=$((total_runs + run_count))

    printf '| %s | $%.4f | $%.4f | $%.4f | $%.4f | $%.4f |\n' \
      "$fix" "$wa" "$wj" "$na" "$nj" "$row"
  done

  echo
  printf '**Total cost across all fixtures: $%s** (across %d runs)\n' \
    "$total_cost" "$total_runs"
  if [ "$total_runs" -gt 0 ]; then
    mean_score=$(python3 -c "print(f'{$total_score/$total_runs:.3f}')")
    cost_per_score=$(python3 -c "print(f'{$total_cost / max($total_score, 0.001):.4f}')")
    echo
    echo "Mean score per run: $mean_score. Cost per score-unit (lower is better): \$$cost_per_score."
    echo "Score-unit = one fully-passed run; partial-pass runs contribute their fractional score."
  fi

  echo
  echo "## Chain efficiency (mean turns per case)"
  echo
  echo "\`numTurns\` is the agent-side session length (one turn = one assistant"
  echo "message). Shorter means faster convergence; a chain that loops on refute"
  echo "or revisits zones inflates this number."
  echo
  echo "| Fixture | with-pkg mean turns | no-pkg mean turns |"
  echo "|---|---|---|"

  for f in "$run_dir"/*.json; do
    [ -e "$f" ] || continue
    fix="$(basename "$f" .json)"
    if jq -e '.error == "apply-failed"' "$f" >/dev/null 2>&1; then
      echo "| $fix | (apply-failed) | (apply-failed) |"
      continue
    fi
    wt=$(branch_turns_sum "with-pkg" "$f")
    nt=$(branch_turns_sum "no-pkg"   "$f")
    nw=$(branch_count     "with-pkg" "$f")
    nn=$(branch_count     "no-pkg"   "$f")
    wm=$(python3 -c "n=$nw; print(f'{$wt/n:.1f}' if n else 'n/a')")
    nm=$(python3 -c "n=$nn; print(f'{$nt/n:.1f}' if n else 'n/a')")
    echo "| $fix | $wm | $nm |"
  done
} > "$out"

echo "wrote $out"
