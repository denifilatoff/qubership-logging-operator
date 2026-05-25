# Test & agent-package layout — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish the layout described in `docs/agent-packages/specs/2026-05-25-test-agent-packages-layout-design.md` — clean APM-distributable skill packages, unified test-infrastructure tree under `test/agent-packages/`, semantic scenario slugs, dedicated meta-docs home under `docs/agent-packages/`.

**Architecture:** Mostly mechanical: `git mv` operations with renames, narrow text edits in pipeline scripts to update relative paths and slug references, and a small set of new READMEs. Two manual sanity checks against a live kind cluster gate the destructive parts: one after scenario relocation, one after eval pipeline relocation.

**Tech Stack:** bash, git, helm, kubectl, `apm` CLI, `npx promptfoo`, kind cluster (BACKEND=graylog for the full sweep; BACKEND=victorialogs is sufficient for the lightweight sanity scenario chosen below).

**Plan file is ephemeral.** This file lives at `docs/agent-packages/plans/` for the duration of execution. The final task removes it so the squashed PR commit does not memorialize a migration that has no meaning to the target repo's history.

**Reference slug mapping (used only by this plan):**

| Source location                                | New slug under `test/agent-packages/scenarios/` |
|------------------------------------------------|--------------------------------------------------|
| `deploy/kind/fixtures/F1-fluent-config-syntax/` | `fluentbit-config-syntax/`                       |
| `deploy/kind/fixtures/F2-fluent-oom/`           | `fluentbit-oom/`                                 |
| `deploy/kind/fixtures/F3-disk-readonly/`        | `opensearch-flood-stage-readonly/`               |
| `deploy/kind/fixtures/F4-helm-bad-image/`       | `operator-helm-bad-image/`                       |
| `deploy/kind/fixtures/F5b-fluentbit-cpu-throttle/` | `fluentbit-cpu-throttle/`                     |
| `deploy/kind/fixtures/F7-gelf-input-size/`      | `graylog-gelf-input-size-too-small/`             |

Eval case directories under `test/agent-packages/evals/logging-l2-troubleshooting/cases/` use the same new slugs.

---

## Task 1: Skeleton — create target directories

**Files:**
- Create: `test/agent-packages/scenarios/` (directory)
- Create: `test/agent-packages/evals/logging-l2-troubleshooting/cases/` (directory)
- Create: `docs/agent-packages/archive/` (directory)

- [ ] **Step 1: Make directories**

Run from repo root:

```bash
mkdir -p test/agent-packages/scenarios
mkdir -p test/agent-packages/evals/logging-l2-troubleshooting/cases
mkdir -p docs/agent-packages/archive
```

- [ ] **Step 2: Verify**

```bash
ls -d test/agent-packages/scenarios test/agent-packages/evals/logging-l2-troubleshooting/cases docs/agent-packages/archive
```

Expected: three lines, one per directory.

(No commit — empty directories aren't tracked by git. The directories will appear in commits as soon as files land in them.)

---

## Task 2: Move scenario directories with rename

**Files:**
- Move: 6 scenario directories from `deploy/kind/fixtures/` to `test/agent-packages/scenarios/` (with rename per the mapping table)
- Move: `deploy/kind/fixtures/{fixture.sh,lib.sh,README.md,.gitignore}` → `test/agent-packages/scenarios/`

- [ ] **Step 1: Move scenario directories with rename**

Run from repo root:

```bash
git mv deploy/kind/fixtures/F1-fluent-config-syntax       test/agent-packages/scenarios/fluentbit-config-syntax
git mv deploy/kind/fixtures/F2-fluent-oom                  test/agent-packages/scenarios/fluentbit-oom
git mv deploy/kind/fixtures/F3-disk-readonly               test/agent-packages/scenarios/opensearch-flood-stage-readonly
git mv deploy/kind/fixtures/F4-helm-bad-image              test/agent-packages/scenarios/operator-helm-bad-image
git mv deploy/kind/fixtures/F5b-fluentbit-cpu-throttle     test/agent-packages/scenarios/fluentbit-cpu-throttle
git mv deploy/kind/fixtures/F7-gelf-input-size             test/agent-packages/scenarios/graylog-gelf-input-size-too-small
```

- [ ] **Step 2: Move helper files**

```bash
git mv deploy/kind/fixtures/fixture.sh   test/agent-packages/scenarios/
git mv deploy/kind/fixtures/lib.sh       test/agent-packages/scenarios/
git mv deploy/kind/fixtures/README.md    test/agent-packages/scenarios/
git mv deploy/kind/fixtures/.gitignore   test/agent-packages/scenarios/
```

- [ ] **Step 3: Remove stale local `.state/`**

The runtime state directory tracks which scenario is active. After move, the old `.state/` (under the original location, gitignored) is dead. Recreate at the new location on first apply.

```bash
rm -rf deploy/kind/fixtures/.state
rmdir deploy/kind/fixtures
```

`rmdir` should succeed — directory must be empty after the moves. If it isn't, `ls deploy/kind/fixtures` and resolve before continuing.

- [ ] **Step 4: Verify tree**

```bash
ls test/agent-packages/scenarios/
```

Expected: 6 scenario directories (new names), plus `fixture.sh`, `lib.sh`, `README.md`. The `.gitignore` is hidden (`ls -a` to see it).

```bash
ls deploy/kind/
```

Expected: no `fixtures/` entry.

- [ ] **Step 5: Commit**

```bash
git add -A test/agent-packages/scenarios deploy/kind/fixtures
git commit -m "move scenarios to test/agent-packages/scenarios with semantic slugs"
```

---

## Task 3: Fix `lib.sh` path resolution

**Files:**
- Modify: `test/agent-packages/scenarios/lib.sh`

The script computes `KIND_DIR` relative to its own location. Old location was `deploy/kind/fixtures/lib.sh` → `KIND_DIR = ../` (one up to `deploy/kind/`). New location is `test/agent-packages/scenarios/lib.sh` → `KIND_DIR` must climb three levels to repo root then descend into `deploy/kind/`.

- [ ] **Step 1: Edit `KIND_DIR` computation**

In `test/agent-packages/scenarios/lib.sh`, replace:

```bash
FIXTURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIND_DIR="$(cd "$FIXTURES_DIR/.." && pwd)"
STATE_DIR="$FIXTURES_DIR/.state"
```

With:

```bash
SCENARIOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIND_DIR="$(cd "$SCENARIOS_DIR/../../../deploy/kind" && pwd)"
STATE_DIR="$SCENARIOS_DIR/.state"
```

(`FIXTURES_DIR` → `SCENARIOS_DIR` rename is local to this file — `fixture.sh` only sources `lib.sh`, no other scripts reference `FIXTURES_DIR`. Grep to confirm: `grep -rn FIXTURES_DIR test/agent-packages/scenarios` should match only this one definition after the edit.)

- [ ] **Step 2: Verify path resolution**

```bash
cd test/agent-packages/scenarios
bash -c 'source ./lib.sh && echo "KIND_DIR=$KIND_DIR" && echo "STATE_DIR=$STATE_DIR"'
```

Expected:

```
KIND_DIR=/Users/.../qubership-logging-operator/deploy/kind
STATE_DIR=/Users/.../qubership-logging-operator/test/agent-packages/scenarios/.state
```

The script will also assert `CLUSTER_NAME` and `BACKEND` are set (from `deploy/kind/.env`). If your `.env` is populated, no errors. If not, the script dies with a clear message — that's expected behaviour.

- [ ] **Step 3: Verify scenario CHART path is still correct (no edit needed)**

The three helm-aware scenarios (`fluentbit-oom`, `fluentbit-cpu-throttle`, `operator-helm-bad-image`) compute `CHART="$KIND_DIR/../../charts/qubership-logging-operator"` in their `apply.sh`. Since `KIND_DIR` is recomputed to point at the same absolute `deploy/kind/` location, this relative jump is unchanged. Spot-check:

```bash
grep -n 'CHART=' test/agent-packages/scenarios/fluentbit-oom/apply.sh
```

Expected: `CHART="$KIND_DIR/../../charts/qubership-logging-operator"` (unchanged).

- [ ] **Step 4: Commit**

```bash
git add test/agent-packages/scenarios/lib.sh
git commit -m "lib.sh: resolve KIND_DIR from new scenarios location"
```

---

## Task 4: Manual sanity — scenarios still work

**Files:** none modified. This is a verification gate before touching the eval pipeline.

Prereqs: kind cluster up, `deploy/kind/.env` populated, baseline applied (`helmfile -f deploy/kind/helmfile.yaml.gotmpl apply`). `BACKEND=victorialogs` is sufficient — the chosen sanity scenario is backend-agnostic.

- [ ] **Step 1: List scenarios with new names**

```bash
cd test/agent-packages/scenarios
./fixture.sh list
```

Expected output: 6 scenarios, listed by new slug (`fluentbit-config-syntax`, `fluentbit-oom`, `fluentbit-cpu-throttle`, `opensearch-flood-stage-readonly`, `operator-helm-bad-image`, `graylog-gelf-input-size-too-small`).

- [ ] **Step 2: Apply a lightweight scenario**

`fluentbit-config-syntax` is pure-kubectl (no helm, no curl-into-cluster), backend-agnostic, and reverts cleanly in seconds.

```bash
./fixture.sh apply fluentbit-config-syntax
```

Expected: log lines about scaling the operator down, patching the configmap, and observing FluentBit pods CrashLoopBackOff.

- [ ] **Step 3: Verify the scenario reproduced**

```bash
kubectl --context "kind-$(grep ^CLUSTER_NAME /Users/$(whoami)/Repos/qubership-logging-operator/deploy/kind/.env | cut -d= -f2)" -n logging get pods -l name=logging-fluentbit
```

(Or simpler, with `KCTX` from `lib.sh` shell:)

```bash
bash -c 'source ./lib.sh && "${KUBECTL[@]}" -n logging get pods -l name=logging-fluentbit'
```

Expected: at least one FluentBit pod in `CrashLoopBackOff` or `Error`.

- [ ] **Step 4: Revert**

```bash
./fixture.sh revert fluentbit-config-syntax
```

Expected: log lines about restoring the configmap and scaling the operator back up. After ~30s FluentBit pods stabilise.

- [ ] **Step 5: Confirm clean state**

```bash
./fixture.sh status
```

Expected: `no fixtures active`.

No commit (verification only). If anything fails, stop and diagnose before continuing. The most likely failure mode is `lib.sh` path resolution — re-check Task 3.

---

## Task 5: Move eval tree and rename case directories

**Files:**
- Move: `agent-packages/logging-l2-troubleshooting/evals/` → `test/agent-packages/evals/logging-l2-troubleshooting/`
- Move: 6 case directories from `evals/fixtures/F*-*/` → `evals/cases/<new-slug>/`
- Delete: empty `fixtures/` dir, working-tree `node_modules/` and `results/`

- [ ] **Step 1: Move evals tree wholesale**

```bash
git mv agent-packages/logging-l2-troubleshooting/evals test/agent-packages/evals/logging-l2-troubleshooting
```

Verify:

```bash
ls test/agent-packages/evals/logging-l2-troubleshooting/
```

Expected: `Makefile`, `README.md`, `aggregate.sh`, `fixtures/`, `judge-prompt.txt`, `orchestrator.sh`, `prep-workdir.sh`, `promptfooconfig.yaml`, `providers/` and possibly `node_modules/` / `results/` (which are working-tree only).

- [ ] **Step 2: Rename case directories under a new `cases/` parent**

```bash
cd test/agent-packages/evals/logging-l2-troubleshooting
mkdir cases
git mv fixtures/F1-fluentbit-config-syntax       cases/fluentbit-config-syntax
git mv fixtures/F2-fluentbit-oom                  cases/fluentbit-oom
git mv fixtures/F3-opensearch-readonly            cases/opensearch-flood-stage-readonly
git mv fixtures/F4-helm-bad-image                 cases/operator-helm-bad-image
git mv fixtures/F5b-fluentbit-cpu-throttle        cases/fluentbit-cpu-throttle
git mv fixtures/F7-gelf-input-size                cases/graylog-gelf-input-size-too-small
rmdir fixtures
cd ../../../..
```

`rmdir fixtures` should succeed — empty after the six moves.

- [ ] **Step 3: Clean up untracked working-tree artifacts**

`node_modules/` and `results/` are gitignored but may have been left behind from local runs.

```bash
rm -rf test/agent-packages/evals/logging-l2-troubleshooting/node_modules
rm -rf test/agent-packages/evals/logging-l2-troubleshooting/results
```

- [ ] **Step 4: Verify tree**

```bash
ls test/agent-packages/evals/logging-l2-troubleshooting/
ls test/agent-packages/evals/logging-l2-troubleshooting/cases/
ls agent-packages/logging-l2-troubleshooting/
```

Expected:
- Top of evals: `Makefile`, `README.md`, `aggregate.sh`, `cases/`, `judge-prompt.txt`, `orchestrator.sh`, `prep-workdir.sh`, `promptfooconfig.yaml`, `providers/` (no `fixtures/`, no `node_modules/`, no `results/`).
- `cases/`: 6 new-slug directories.
- `agent-packages/logging-l2-troubleshooting/`: `.apm/`, `apm.yml`, `README.md`, and possibly leftover `docs/` (handled in Task 9).

- [ ] **Step 5: Commit**

```bash
git add -A test/agent-packages/evals agent-packages/logging-l2-troubleshooting
git commit -m "move l2 evals to test/agent-packages/evals; rename cases to slug"
```

---

## Task 6: Drop redundant slug mapping from `meta.yaml`

**Files:**
- Modify: `test/agent-packages/evals/logging-l2-troubleshooting/cases/*/meta.yaml` (6 files)

Each `meta.yaml` carries `id:` (eval case id) and `cluster_fixture:` (the kind fixture slug). After rename, both equal the directory name. Drop `cluster_fixture:` entirely; rewrite `id:` to the new slug.

- [ ] **Step 1: Update each meta.yaml**

The 6 files, with the two replacements per file:

`cases/fluentbit-config-syntax/meta.yaml`
- Replace `id: F1-fluentbit-config-syntax` → `id: fluentbit-config-syntax`
- Delete the line `cluster_fixture: F1-fluent-config-syntax`

`cases/fluentbit-oom/meta.yaml`
- Replace `id: F2-fluentbit-oom` → `id: fluentbit-oom`
- Delete the line `cluster_fixture: F2-fluent-oom`

`cases/opensearch-flood-stage-readonly/meta.yaml`
- Replace `id: F3-opensearch-readonly` → `id: opensearch-flood-stage-readonly`
- Delete the line `cluster_fixture: F3-disk-readonly`

`cases/operator-helm-bad-image/meta.yaml`
- Replace `id: F4-helm-bad-image` → `id: operator-helm-bad-image`
- Delete the line `cluster_fixture: F4-helm-bad-image`

`cases/fluentbit-cpu-throttle/meta.yaml`
- Replace `id: F5b-fluentbit-cpu-throttle` → `id: fluentbit-cpu-throttle`
- Delete the line `cluster_fixture: F5b-fluentbit-cpu-throttle`

`cases/graylog-gelf-input-size-too-small/meta.yaml`
- Replace `id: F7-gelf-input-size` → `id: graylog-gelf-input-size-too-small`
- Delete the line `cluster_fixture: F7-gelf-input-size`

- [ ] **Step 2: Verify**

```bash
grep -nH '^cluster_fixture:' test/agent-packages/evals/logging-l2-troubleshooting/cases/*/meta.yaml
```

Expected: no output (zero matches).

```bash
grep -nH '^id:' test/agent-packages/evals/logging-l2-troubleshooting/cases/*/meta.yaml
```

Expected: 6 lines, each `id:` matches the parent directory name.

- [ ] **Step 3: Commit**

```bash
git add test/agent-packages/evals/logging-l2-troubleshooting/cases
git commit -m "meta.yaml: drop redundant cluster_fixture; align id with slug"
```

---

## Task 7: Update pipeline scripts for new paths and case naming

**Files:**
- Modify: `test/agent-packages/evals/logging-l2-troubleshooting/Makefile`
- Modify: `test/agent-packages/evals/logging-l2-troubleshooting/orchestrator.sh`
- Modify: `test/agent-packages/evals/logging-l2-troubleshooting/prep-workdir.sh`
- Modify: `test/agent-packages/evals/logging-l2-troubleshooting/promptfooconfig.yaml`

Three things change: scenario script path (`deploy/kind/fixtures` → `test/agent-packages/scenarios`), case directory name (`fixtures/<id>` → `cases/<slug>`), and the eval target naming (`eval-F1` → `eval-<slug>`).

- [ ] **Step 1: Rewrite Makefile**

Replace the entire file `test/agent-packages/evals/logging-l2-troubleshooting/Makefile` with:

```makefile
SCENARIOS_DIR := ../../scenarios

CASES := \
  fluentbit-config-syntax \
  fluentbit-oom \
  opensearch-flood-stage-readonly \
  operator-helm-bad-image \
  fluentbit-cpu-throttle \
  graylog-gelf-input-size-too-small

EVAL_TARGETS := $(addprefix eval-,$(CASES))

.PHONY: eval $(EVAL_TARGETS) report clean baseline-check setup

REPEATS ?= 3

setup:
	@if [ ! -d node_modules/@anthropic-ai/claude-agent-sdk ]; then \
	  echo "installing @anthropic-ai/claude-agent-sdk locally"; \
	  npm install --no-save @anthropic-ai/claude-agent-sdk; \
	fi

baseline-check:
	@status="$$($(SCENARIOS_DIR)/fixture.sh status)"; \
	if [ "$$status" != "no fixtures active" ]; then \
	  echo "baseline not clean: $$status"; \
	  echo "revert active scenario first."; \
	  exit 1; \
	fi

eval: setup baseline-check
	./orchestrator.sh $(REPEATS)
	$(MAKE) report

$(EVAL_TARGETS): eval-%: setup baseline-check
	./orchestrator.sh $(REPEATS) $*
	$(MAKE) report

report:
	./aggregate.sh

clean:
	rm -rf results .promptfooconfig.rendered.yaml
	rm -rf "$${XDG_CACHE_HOME:-$$HOME/.cache}/qubership-logging-l2-evals"
```

- [ ] **Step 2: Rewrite orchestrator.sh**

Replace the entire file `test/agent-packages/evals/logging-l2-troubleshooting/orchestrator.sh` with:

```bash
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
```

Changes from previous version:
- `repo_root` climbs 4 levels (`../../../..`) instead of 3
- `cluster_fixtures` → `scenarios_dir` pointing at `test/agent-packages/scenarios`
- Reads from `cases/*/` not `fixtures/F*-*/`
- No `meta.yaml` lookup for `cluster_fixture` — the case slug IS the scenario slug
- All variable names switched from `fix`/`fixture` to `case_slug`/`case`
- Sed substitutions match the renamed templates in `promptfooconfig.yaml` (Step 4)

- [ ] **Step 3: Update prep-workdir.sh**

In `test/agent-packages/evals/logging-l2-troubleshooting/prep-workdir.sh`, replace:

```bash
script_dir="$(cd "$(dirname "$0")" && pwd)"
package_dir="$(cd "$script_dir/.." && pwd)"  # logging-l2-troubleshooting/
```

With:

```bash
script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/../../../.." && pwd)"
package_dir="$repo_root/agent-packages/logging-l2-troubleshooting"
```

Also update the usage comment header — the `--force` rationale referring to `evals/node_modules` no longer applies (the package no longer contains evals). Replace the comment block:

```bash
  # --force: the source package contains evals/node_modules with binary deps,
  # which `apm install` flags as "critical hidden characters". The skills under
  # .apm/skills/ are the actual deliverable and are vetted; we override the
  # heuristic for this eval-only install path.
```

With:

```bash
  # Install from the local package source via apm. After the layout fix,
  # the package directory holds only .apm/ + apm.yml + README.md so audit
  # should not flag it; --force is kept as a belt-and-braces hedge while
  # the local pipeline matures.
```

- [ ] **Step 4: Update promptfooconfig.yaml**

In `test/agent-packages/evals/logging-l2-troubleshooting/promptfooconfig.yaml`, find these lines (under `tests:`):

```yaml
  - description: "{{fixture}}"
    vars:
      fixture_dir: "fixtures/{{fixture}}"
      ground_truth: file://fixtures/{{fixture}}/ground_truth.md
      rubric_yaml: file://fixtures/{{fixture}}/rubric.yaml
```

Replace with:

```yaml
  - description: "{{case}}"
    vars:
      case_dir: "cases/{{case}}"
      ground_truth: file://cases/{{case}}/ground_truth.md
      rubric_yaml: file://cases/{{case}}/rubric.yaml
```

Also at the top of the file, change the `prompts:` block:

```yaml
prompts:
  - file://{{fixture_dir}}/prompt.txt
```

To:

```yaml
prompts:
  - file://{{case_dir}}/prompt.txt
```

If any other `{{fixture}}` or `{{fixture_dir}}` references appear in this file (description fields, comments), rename consistently to `{{case}}` / `{{case_dir}}`.

- [ ] **Step 5: Verify no leftover references**

```bash
grep -rn 'F[0-9][a-z]*-' test/agent-packages/evals/logging-l2-troubleshooting/{Makefile,orchestrator.sh,prep-workdir.sh,promptfooconfig.yaml,aggregate.sh} 2>/dev/null
grep -rn 'fixtures/' test/agent-packages/evals/logging-l2-troubleshooting/{Makefile,orchestrator.sh,prep-workdir.sh,promptfooconfig.yaml,aggregate.sh} 2>/dev/null
grep -rn 'deploy/kind/fixtures' test/agent-packages/evals/logging-l2-troubleshooting/ 2>/dev/null
grep -rn '{{fixture' test/agent-packages/evals/logging-l2-troubleshooting/{Makefile,orchestrator.sh,prep-workdir.sh,promptfooconfig.yaml,aggregate.sh} 2>/dev/null
```

Expected: all four greps produce no output.

- [ ] **Step 6: Commit**

```bash
git add test/agent-packages/evals/logging-l2-troubleshooting/{Makefile,orchestrator.sh,prep-workdir.sh,promptfooconfig.yaml}
git commit -m "eval pipeline: switch to scenarios dir, cases naming, case slug vars"
```

---

## Task 8: Manual sanity — eval pipeline runs end-to-end

**Files:** none modified.

Prereqs: kind cluster up, baseline applied, `BACKEND=victorialogs` is sufficient (the chosen sanity case is backend-agnostic).

- [ ] **Step 1: Install eval SDK locally (one-time)**

```bash
cd test/agent-packages/evals/logging-l2-troubleshooting
make setup
```

Expected: either "installing @anthropic-ai/claude-agent-sdk locally" followed by npm install, or silent if already installed.

- [ ] **Step 2: Run one lightweight eval**

```bash
make eval-fluentbit-config-syntax REPEATS=1
```

Expected behaviour:
- Baseline check passes ("no fixtures active").
- Two workdirs prepared under `$XDG_CACHE_HOME/qubership-logging-l2-evals/<run-id>/fluentbit-config-syntax/{with-pkg,no-pkg}`. The `with-pkg` install runs `apm install` against the local package.
- Scenario applies (operator scaled down, configmap broken, FluentBit pods crashing).
- promptfoo runs two agents (with-pkg, no-pkg), grading each.
- Scenario reverts.
- `report` produces `results/<run-id>/summary.md`.

The eval may complete in 5-20 minutes depending on agent runtime. Watch for FATAL or APPLY FAILED messages.

- [ ] **Step 3: Confirm clean state**

```bash
../../scenarios/fixture.sh status
```

Expected: `no fixtures active`.

- [ ] **Step 4: Cleanup eval artifacts**

The run leaves a `results/<run-id>/` directory and ephemeral workdirs under XDG cache. Both are fine to keep; clean if you want a tidy tree:

```bash
make clean
```

No commit (verification only). If the eval fails at the apm-install step inside `with-pkg`, that's a strong signal Task 5 / Task 9 left something broken — diagnose before continuing.

---

## Task 9: Move meta-docs to `docs/agent-packages/`

**Files:**
- Move: 6 docs from `agent-packages/logging-l*/docs/` → `docs/agent-packages/`
- Move + rename: 1 compass artifact → `docs/agent-packages/archive/compass-artifact-eval-framework.md`
- Delete: empty `docs/` directories under both skill packages

- [ ] **Step 1: Move the design doc from l2**

```bash
git mv agent-packages/logging-l2-troubleshooting/docs/eval-pipeline-design.md docs/agent-packages/
```

- [ ] **Step 2: Move the five methodology / research docs from l1**

```bash
git mv agent-packages/logging-l1-triage/docs/eval-framework-survey.md         docs/agent-packages/
git mv agent-packages/logging-l1-triage/docs/skill-evaluation-methodology.md  docs/agent-packages/
git mv agent-packages/logging-l1-triage/docs/package-layering-model.md         docs/agent-packages/
git mv agent-packages/logging-l1-triage/docs/reference-documents.md            docs/agent-packages/
git mv agent-packages/logging-l1-triage/docs/troubleshooting-methodology.md    docs/agent-packages/
```

- [ ] **Step 3: Move + rename the compass artifact**

```bash
git mv agent-packages/logging-l1-triage/docs/compass_artifact_wf-70e06cfc-1de1-428e-858f-331dee7db464_text_markdown.md \
       docs/agent-packages/archive/compass-artifact-eval-framework.md
```

- [ ] **Step 4: Remove the now-empty docs/ directories**

```bash
rmdir agent-packages/logging-l1-triage/docs
rmdir agent-packages/logging-l2-troubleshooting/docs
```

Both `rmdir`s should succeed. If either fails, `ls` the directory to find the straggler and resolve before continuing.

- [ ] **Step 5: Verify**

```bash
ls docs/agent-packages/
ls docs/agent-packages/archive/
ls agent-packages/logging-l1-triage/
ls agent-packages/logging-l2-troubleshooting/
```

Expected:
- `docs/agent-packages/`: `eval-framework-survey.md`, `eval-pipeline-design.md`, `package-layering-model.md`, `plans/`, `reference-documents.md`, `skill-evaluation-methodology.md`, `specs/`, `troubleshooting-methodology.md`, `archive/`. README.md will be added in Task 10.
- `docs/agent-packages/archive/`: `compass-artifact-eval-framework.md`.
- Each skill package: `.apm/`, `apm.yml`, `README.md` (and nothing else).

- [ ] **Step 6: Commit**

```bash
git add -A docs/agent-packages agent-packages/logging-l1-triage agent-packages/logging-l2-troubleshooting
git commit -m "move meta-docs out of skill packages to docs/agent-packages"
```

---

## Task 10: Write `docs/agent-packages/README.md` (index)

**Files:**
- Create: `docs/agent-packages/README.md`

- [ ] **Step 1: Write the index**

Create `docs/agent-packages/README.md` with the following content:

```markdown
# Agent packages — internal docs

Cross-cutting documentation for our AI-skill packages. Audience: us,
working on the skills themselves. Not part of any skill's distribution.

## Layout

- `specs/` — implementation design specs (`YYYY-MM-DD-<slug>-design.md`).
- `plans/` — ephemeral implementation plans; removed after execution.
- `archive/` — superseded or historical material we keep for reference.

## Documents

- [eval-pipeline-design.md](eval-pipeline-design.md) — promptfoo-based pipeline for grading skill behaviour against scenarios on a live cluster.
- [eval-framework-survey.md](eval-framework-survey.md) — comparison of promptfoo / inspect-ai / others for our use case.
- [skill-evaluation-methodology.md](skill-evaluation-methodology.md) — what we mean by "evaluating" a skill, what we measure, and why.
- [package-layering-model.md](package-layering-model.md) — how the L1 / L2 / topic-specific skill packages stack.
- [troubleshooting-methodology.md](troubleshooting-methodology.md) — domain knowledge that informs the L1 and L2 skills.
- [reference-documents.md](reference-documents.md) — index of external references we draw on.

## Sibling product docs

`docs/` (the parent directory) holds operator user-facing documentation
— `api.md`, `architecture.md`, `cookbook/`, CRDs. Different audience,
different lifecycle.
```

- [ ] **Step 2: Verify links resolve**

```bash
for link in eval-pipeline-design.md eval-framework-survey.md skill-evaluation-methodology.md package-layering-model.md troubleshooting-methodology.md reference-documents.md; do
  test -f "docs/agent-packages/$link" || echo "MISSING: $link"
done
```

Expected: no "MISSING" output.

- [ ] **Step 3: Commit**

```bash
git add docs/agent-packages/README.md
git commit -m "docs/agent-packages: add index README"
```

---

## Task 11: Write `test/agent-packages/README.md`

**Files:**
- Create: `test/agent-packages/README.md`

- [ ] **Step 1: Write the tree-level README**

Create `test/agent-packages/README.md` with:

```markdown
# Tests for agent packages

Test infrastructure for the AI-skill packages under
`agent-packages/`. Not shipped to APM consumers — internal to this
repository.

## Layout

- `scenarios/` — reproducible failures on a running logging stack
  (`apply.sh` / `revert.sh` per scenario). Shared across skills.
- `evals/<skill-package>/` — per-skill evaluation harness (promptfoo
  config, prompts, ground truth, rubrics, runner scripts). One
  subdirectory per skill being evaluated.

## Mental model

- One scenario reproduces one cluster failure.
- One eval is a (skill, scenario) pair — same scenario can feed evals
  for multiple skills.
- The scenario slug and the matching eval case slug are identical, so
  the orchestrator does not need a separate mapping.

## See also

- `scenarios/README.md` — runtime contract scenarios assume.
- `evals/logging-l2-troubleshooting/README.md` — current eval pipeline.
- `docs/agent-packages/eval-pipeline-design.md` — design background.
```

- [ ] **Step 2: Commit**

```bash
git add test/agent-packages/README.md
git commit -m "test/agent-packages: add tree-level README"
```

---

## Task 12: Write `test/agent-packages/scenarios/README.md`

**Files:**
- Modify: `test/agent-packages/scenarios/README.md` (replace existing content)

The existing README (moved from `deploy/kind/fixtures/README.md`) uses the old slug names and describes the workflow in terms of `cd deploy/kind/fixtures`. Rewrite as a forward-looking contract + usage doc.

- [ ] **Step 1: Replace README content**

Overwrite `test/agent-packages/scenarios/README.md` with:

```markdown
# Scenarios

Each subdirectory reproduces one failure on a running logging stack.

| Scenario                                | Component   | Backend       | What breaks                                                       |
|-----------------------------------------|-------------|---------------|-------------------------------------------------------------------|
| `fluentbit-config-syntax`               | fluentbit   | any           | Broken ConfigMap → FluentBit CrashLoopBackOff                     |
| `fluentbit-oom`                         | fluentbit   | any           | Memory limit too low → FluentBit OOMKilled                        |
| `fluentbit-cpu-throttle`                | fluentbit   | graylog       | CPU limit too low → throughput collapse, messages lost            |
| `opensearch-flood-stage-readonly`       | opensearch  | graylog       | Flood-stage trip → indices read-only                              |
| `graylog-gelf-input-size-too-small`     | graylog     | graylog       | GELF input `max_message_size` too small → big logs dropped        |
| `operator-helm-bad-image`               | operator    | any           | Bad image tag → operator ImagePullBackOff                         |

## Runtime contract

Scenarios assume a running logging stack with:

- Cluster reachable via context `$KCTX` (`lib.sh` derives it from
  `deploy/kind/.env`).
- Namespaces: `logging`, plus `opensearch` / `graylog` /
  `log-generator` as needed.
- Services with `helmfile.yaml.gotmpl`-equivalent names:
  `opensearch-cluster.opensearch`, `graylog-service.logging`,
  `log-generator-svc.log-generator`.
- Operator running in `logging` as helm release
  `qubership-logging-operator` (only required for scenarios that do
  `helm upgrade --reuse-values`: `fluentbit-oom`,
  `fluentbit-cpu-throttle`, `operator-helm-bad-image`).

`deploy/kind/` is one way to satisfy this contract.

## Workflow

```bash
# bring up baseline (one-time, from repo root)
cd deploy/kind
set -a && source .env && set +a
helmfile -f helmfile.yaml.gotmpl apply

# operate scenarios
cd ../../test/agent-packages/scenarios
./fixture.sh list
./fixture.sh apply  fluentbit-oom
# ... run the skill / eval against the cluster ...
./fixture.sh revert fluentbit-oom
```

**Policy**: one scenario active at a time. `apply` refuses if another is
already active — `revert` it first. State is tracked in `.state/`.

## Per-scenario layout

```
<scenario-slug>/
  README.md        case description and injection mechanics
  apply.sh         introduces the failure
  revert.sh        restores baseline
```
```

- [ ] **Step 2: Commit**

```bash
git add test/agent-packages/scenarios/README.md
git commit -m "scenarios: rewrite README around contract and new slugs"
```

---

## Task 13: Write `test/agent-packages/evals/logging-l2-troubleshooting/README.md`

**Files:**
- Modify: `test/agent-packages/evals/logging-l2-troubleshooting/README.md`

The existing README uses old paths (`agent-packages/logging-l2-troubleshooting/evals`) and old slugs (`F1`..`F7`).

- [ ] **Step 1: Replace README content**

Overwrite `test/agent-packages/evals/logging-l2-troubleshooting/README.md` with:

```markdown
# Eval pipeline — logging-l2-troubleshooting

Local eval pipeline for the L2 skill package. See
`docs/agent-packages/eval-pipeline-design.md` for design.

## Prerequisites

- kind cluster + helmfile baseline up. `BACKEND=graylog` is required
  for `opensearch-flood-stage-readonly`, `fluentbit-cpu-throttle`,
  `graylog-gelf-input-size-too-small`; the others work on either
  backend.
- `claude` CLI logged into the Claude Code subscription (the
  `anthropic:claude-agent-sdk` provider routes through this session).
- `apm`, `node` / `npx`, `jq` on PATH. `promptfoo` is invoked via
  `npx promptfoo@latest`.
- One-time setup in this directory:

  ```bash
  cd test/agent-packages/evals/logging-l2-troubleshooting
  make setup
  ```

  Installs `@anthropic-ai/claude-agent-sdk` into a local `node_modules/`
  (gitignored).

## Run

```bash
# Full sweep: all cases, with-pkg vs no-pkg, --repeat 3
make eval

# Single case
make eval-fluentbit-oom
make eval-fluentbit-config-syntax
make eval-opensearch-flood-stage-readonly
# ... one target per case ...
```

`make eval` and `make eval-<case>` both run a baseline-clean check
before starting and abort if a scenario is already active.

## Layout

- `promptfooconfig.yaml` — promptfoo eval config (templated).
- `Makefile` — entry points: `eval`, `eval-<case>`, `report`, `clean`.
- `orchestrator.sh` — serial loop over cases: apply scenario → run
  promptfoo → revert.
- `prep-workdir.sh` — prepares a workdir per (case, variant).
- `aggregate.sh` — collapses the last run's JSON outputs into
  `results/<run-id>/summary.md`.
- `cases/<case-slug>/` — one directory per evaluation case:
  - `prompt.txt` — what the agent is asked.
  - `ground_truth.md` — expected diagnosis + recommendation.
  - `rubric.yaml` — checks the judge evaluates.
  - `meta.yaml` — case metadata (backend, expected area, etc.).
- `providers/` — promptfoo provider definitions.
- `judge-prompt.txt` — system prompt for the LLM judge.
- `results/` — per-run output (gitignored).

The case slug equals the scenario slug — no mapping needed.
```

- [ ] **Step 2: Commit**

```bash
git add test/agent-packages/evals/logging-l2-troubleshooting/README.md
git commit -m "l2 evals README: update paths and case naming"
```

---

## Task 14: Update cross-references inside moved docs

**Files:**
- Modify (as needed): the 7 docs moved in Task 9

Docs moved out of `agent-packages/<pkg>/docs/` may carry relative paths that no longer resolve. Sweep and fix.

- [ ] **Step 1: Find broken relative references**

```bash
grep -rn -E '\]\(\.\./|\]\(\.\.\.\./|\]\(docs/|file://|deploy/kind/fixtures|agent-packages/[a-z-]+/(evals|docs)/' docs/agent-packages/*.md docs/agent-packages/archive/*.md
```

Expected: a list of suspicious links. For each match, determine whether the link still resolves from the new location and fix if not.

- [ ] **Step 2: Apply edits per match**

For each suspicious match, replace with the correct path **as it should be referenced from the new location**. Common rewrites:

- `../evals/...` → `../../test/agent-packages/evals/logging-l2-troubleshooting/...` (or whichever path applies)
- `deploy/kind/fixtures/<old-slug>` → `test/agent-packages/scenarios/<new-slug>` per the mapping in this plan's header
- `../skills/...` → `../../agent-packages/<pkg>/.apm/skills/...`
- Any reference to a sibling doc that's also in `docs/agent-packages/` becomes a same-directory link, e.g. `[design](eval-pipeline-design.md)`.

If a doc uses old `F1..F7` slugs in prose (not as links), replace per the mapping table at the top of this plan.

- [ ] **Step 3: Re-verify**

Re-run the grep from Step 1. Remaining matches must be either: (a) intentional references to product docs in the parent `docs/` directory (keep), (b) external URLs (keep), or (c) confirmed-valid relative links that still resolve.

- [ ] **Step 4: Commit**

```bash
git add docs/agent-packages
git commit -m "docs/agent-packages: fix cross-references after move"
```

If Step 1 found zero suspicious links and no edits were made, skip Steps 2-4 — there is nothing to commit.

---

## Task 15: Verify clean APM install

**Files:** none modified.

Final acceptance check from the spec's "Verification" section.

- [ ] **Step 1: Pick a clean temp project**

```bash
TMP=$(mktemp -d)
cd "$TMP"
apm init --yes
```

- [ ] **Step 2: Install the local package**

```bash
apm install /Users/$(whoami)/Repos/qubership-logging-operator/agent-packages/logging-l2-troubleshooting --target claude
```

(Adjust `/Users/$(whoami)/Repos/...` to wherever you have the repo cloned.)

Expected:
- `[*] Installed 1 APM dependency` line, no `[x] Blocked` line.
- No `[!] N critical security finding(s)` warning.
- Install completes without `--force`.

- [ ] **Step 3: Inspect the installed tree**

```bash
ls -la "$TMP/apm_modules/_local/logging-l2-troubleshooting/"
```

Expected contents (no more, no less):

- `.apm/` (directory)
- `apm.yml`
- `README.md`

If `evals/`, `docs/`, `node_modules/`, or `results/` appears, the corresponding task above failed to move/clean — diagnose before declaring done.

- [ ] **Step 4: Also check l1-triage**

```bash
apm install /Users/$(whoami)/Repos/qubership-logging-operator/agent-packages/logging-l1-triage --target claude
ls -la "$TMP/apm_modules/_local/logging-l1-triage/"
```

Same expectation: only `.apm/`, `apm.yml`, `README.md`.

- [ ] **Step 5: Cleanup**

```bash
rm -rf "$TMP"
cd /Users/$(whoami)/Repos/qubership-logging-operator
```

No commit (verification only).

---

## Task 16: Remove the plan file

**Files:**
- Delete: `docs/agent-packages/plans/2026-05-25-test-agent-packages-layout-plan.md`

The plan is an execution-time artifact. Remove it so the squashed commit does not carry mid-migration narrative into the target repo.

- [ ] **Step 1: Delete the plan**

```bash
git rm docs/agent-packages/plans/2026-05-25-test-agent-packages-layout-plan.md
rmdir docs/agent-packages/plans 2>/dev/null || true
```

(The `rmdir` may or may not succeed depending on whether other plans exist.)

- [ ] **Step 2: Commit**

```bash
git commit -m "remove ephemeral implementation plan"
```

---

## Plan complete

Verification gates passed (Task 4, Task 8, Task 15), all destructive moves committed, plan file removed. The branch is ready to be squashed into a single PR commit.
