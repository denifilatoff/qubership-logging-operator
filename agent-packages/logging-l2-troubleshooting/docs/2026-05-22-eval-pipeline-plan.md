# L2 Eval Pipeline v1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the v1 L2 eval pipeline described in `eval-pipeline-design.md`: two fixtures (F2 FluentBit OOM, F4 helm-bad-image), APM-install-based A/B, claude-agent-sdk for both agent and judge, local-only.

**Architecture:** An external bash orchestrator wraps `promptfoo eval`. Per fixture: orchestrator prepares two ephemeral workdirs (one with `apm install`, one empty), applies the cluster fixture via the existing `deploy/kind/fixtures/fixture.sh`, runs promptfoo with `--repeat 3`, reverts. `llm-rubric` scores transcripts against per-fixture `rubric.yaml` + `ground_truth.md` using Opus as judge. Final aggregator writes `summary.md` with `with-pkg vs no-pkg` deltas.

**Tech Stack:** bash, GNU make, promptfoo CLI, `@promptfoo/provider-claude-agent-sdk` (or built-in), Claude Code (local subscription), apm CLI, jq for aggregation, existing kind + helmfile baseline.

**Prerequisites (engineer-side, validated by Task 0):**
- kind cluster up; `helmfile -f deploy/kind/helmfile.yaml.gotmpl apply` ran with `BACKEND=victorialogs` (covers F2; F4 is backend-agnostic)
- `claude` CLI logged in (Claude Code subscription)
- `apm` CLI on PATH (verified at `/Users/denifilatov/.local/bin/apm`)
- `promptfoo` CLI installed (`npm i -g promptfoo` or via npx)
- `jq` available

---

## File map

Created under `agent-packages/logging-l2-troubleshooting/evals/`:

| File | Responsibility |
|---|---|
| `Makefile` | Entry points: `make eval`, `make eval-F2`, `make eval-F4`, `make report`, `make clean`, `make baseline-check` |
| `promptfooconfig.yaml` | Provider definitions, per-fixture `tests` block, assertions |
| `orchestrator.sh` | Serial loop over fixtures: prep workdirs → apply → promptfoo → revert; failure handling |
| `prep-workdir.sh` | Create one ephemeral workdir for `(fixture, variant)`; for `with-pkg` runs `apm install` |
| `judge-prompt.md` | Shared judge template, parameterised with ground truth + rubric + transcript |
| `aggregate.sh` | Read promptfoo JSON outputs, write `summary.md` with deltas |
| `providers/agent.yaml` | `claude-agent-sdk` provider, model haiku |
| `providers/judge.yaml` | `claude-agent-sdk` provider, model opus, tools restricted |
| `fixtures/F2-fluentbit-oom/{meta.yaml,prompt.txt,ground_truth.md,rubric.yaml}` | F2 fixture data |
| `fixtures/F4-helm-bad-image/{meta.yaml,prompt.txt,ground_truth.md,rubric.yaml}` | F4 fixture data |
| `.gitignore` | Ignores `.work/` and `results/` |
| `README.md` | How to run; prerequisites; troubleshooting |

Findings from Task 0 verifications are captured in `docs/eval-pipeline-design.md` §10 (open questions get answered there) and may flip small decisions (e.g. judge tools fallback). The plan keeps those decisions parameterised — adjustments stay local to provider files.

---

## Task 0: Pre-flight verifications

Resolve open questions from spec §10 before writing artifacts that depend on them.

**Files:**
- Modify: `agent-packages/logging-l2-troubleshooting/docs/eval-pipeline-design.md` (record findings under §10)

- [ ] **Step 1: Verify `apm install` from a local source path**

```bash
mkdir -p /tmp/apm-verify && cd /tmp/apm-verify
apm install /Users/denifilatov/Repos/qubership-logging-operator/agent-packages/logging-l2-troubleshooting --target claude --frozen --verbose
ls -la
ls -la .claude/skills/ 2>/dev/null || ls -la .claude/agents/ 2>/dev/null || find .claude -maxdepth 3 -type f | head
```

Expected: command succeeds; a `.claude/` (or equivalent) directory exists with the package's skills materialised. Note the exact paths produced — this informs the no-pkg variant's "what to *not* have" check.

If the `--frozen` flag fails because `apm.lock.yaml` is required, retry with `--update` once to generate the lock, then drop `--update`.

- [ ] **Step 2: Verify promptfoo + claude-agent-sdk provider with no API key**

```bash
cd /tmp && mkdir -p promptfoo-verify && cd promptfoo-verify
unset ANTHROPIC_API_KEY
cat > promptfooconfig.yaml <<'EOF'
description: smoke
providers:
  - id: claude-agent-sdk
    config:
      model: claude-haiku-4-5
prompts:
  - "Reply with the single word: pong"
tests:
  - assert:
    - type: equals
      value: pong
EOF
npx promptfoo@latest eval --no-cache
```

Expected: prompt succeeds, output cell contains "pong". If the provider id differs in this promptfoo version (e.g. `anthropic:claude-agent-sdk`), record the working id. If it demands `ANTHROPIC_API_KEY`, fall back: try `claude-code` provider, or shell-out to `claude -p "..."` via `exec:` provider. Whatever works without API key — record it.

- [ ] **Step 3: Verify `skill-used` assertion semantics**

```bash
cd /tmp/promptfoo-verify
npx promptfoo@latest eval --help 2>&1 | grep -i skill || true
# Then check docs:
echo "Reading promptfoo docs for skill-used assertion shape."
```

Read https://www.promptfoo.dev/docs/configuration/expected-outputs/ and https://www.promptfoo.dev/docs/integrations/agent-skill/ . Record:
- assertion type id (e.g. `skill-used`, `is-skill-used`)
- whether it takes a skill name or a list
- whether it requires the provider to emit a structured skill-call event

If the assertion does not exist in the installed promptfoo version, fall back to a `javascript:` or `python:` assertion that greps the transcript for the skill name pattern.

- [ ] **Step 4: Verify tools-off mode for the judge**

```bash
cd /tmp/promptfoo-verify
cat > judge-smoke.yaml <<'EOF'
description: judge tools off smoke
providers:
  - id: claude-agent-sdk
    config:
      model: claude-opus-4-7
      allowed_tools: []
prompts:
  - "Return strict JSON: {\"ok\": true}"
tests:
  - assert:
    - type: is-json
EOF
npx promptfoo@latest eval --config judge-smoke.yaml --no-cache
```

Expected: model replies with the JSON, no tool calls in the transcript. If `allowed_tools: []` is not supported, try `disallowed_tools: ['*']` or restrict via the SDK config keys for that provider version. If neither works, accept tools-on and constrain the judge through the prompt only.

- [ ] **Step 5: Record findings**

Open `docs/eval-pipeline-design.md` and under §10 replace each open question with a one-line "Resolved: …" stating the working syntax. Keep the verification scripts in `/tmp/` — they are throwaway.

- [ ] **Step 6: Commit**

```bash
cd /Users/denifilatov/Repos/qubership-logging-operator
git add agent-packages/logging-l2-troubleshooting/docs/eval-pipeline-design.md
git commit -m "docs(skills): resolve L2 eval pipeline open questions"
```

---

## Task 1: Scaffold `evals/` directory and gitignore

**Files:**
- Create: `agent-packages/logging-l2-troubleshooting/evals/.gitignore`
- Create: `agent-packages/logging-l2-troubleshooting/evals/README.md`
- Modify: `agent-packages/logging-l2-troubleshooting/README.md` (add one-line pointer to `evals/`)

- [ ] **Step 1: Create directory**

```bash
mkdir -p agent-packages/logging-l2-troubleshooting/evals/{providers,fixtures}
```

- [ ] **Step 2: Write `.gitignore`**

Path: `agent-packages/logging-l2-troubleshooting/evals/.gitignore`

```
# Ephemeral workdirs created by prep-workdir.sh
.work/

# Promptfoo and aggregator output
results/
```

- [ ] **Step 3: Write `README.md`**

Path: `agent-packages/logging-l2-troubleshooting/evals/README.md`

```markdown
# Eval pipeline — logging-l2-troubleshooting

Local-only v1 eval pipeline for the L2 skill package. See
`../docs/eval-pipeline-design.md` for design.

## Prerequisites

- kind cluster + helmfile baseline up (`BACKEND=victorialogs` covers v1 fixtures).
- `claude` CLI logged into the Claude Code subscription.
- `apm`, `promptfoo`, `jq` on PATH.

## Run

```bash
# Full v1: both fixtures, with-pkg vs no-pkg, --repeat 3
make eval

# Single fixture
make eval-F2
make eval-F4

# Aggregate the last run into summary.md
make report

# Wipe ephemeral workdirs and result trees
make clean
```

Cluster fixtures (apply/revert mechanics) live in `deploy/kind/fixtures/`.
The eval-fixture `fixtures/<id>/meta.yaml` links to a cluster fixture by id.
```

- [ ] **Step 4: Add one-line pointer to package README**

Edit `agent-packages/logging-l2-troubleshooting/README.md` and append (or insert near the top):

```
See `evals/` for the L2 eval pipeline and `docs/eval-pipeline-design.md` for its design.
```

- [ ] **Step 5: Commit**

```bash
git add agent-packages/logging-l2-troubleshooting/evals/.gitignore \
        agent-packages/logging-l2-troubleshooting/evals/README.md \
        agent-packages/logging-l2-troubleshooting/README.md
git commit -m "feat(evals): scaffold L2 eval directory"
```

---

## Task 2: Provider configs (agent + judge)

**Files:**
- Create: `agent-packages/logging-l2-troubleshooting/evals/providers/agent.yaml`
- Create: `agent-packages/logging-l2-troubleshooting/evals/providers/judge.yaml`

Use the provider ids and tool-gating keys verified in Task 0.

- [ ] **Step 1: Write `providers/agent.yaml`**

```yaml
# Agent under test: Claude Code (claude-agent-sdk) on Haiku 4.5.
# cwd is set per-test via promptfoo template var; see promptfooconfig.yaml.
id: claude-agent-sdk
label: agent-claude-code-haiku-4-5
config:
  model: claude-haiku-4-5
  # cwd injected per test case
  cwd: "{{workdir}}"
  # Tools left at provider default — full Claude Code surface.
```

- [ ] **Step 2: Write `providers/judge.yaml`**

```yaml
# Judge: Claude Code (claude-agent-sdk) on Opus 4.7. Tools disabled where supported.
id: claude-agent-sdk
label: judge-claude-code-opus-4-7
config:
  model: claude-opus-4-7
  # Tools-off — replace this key with whatever Task 0 confirmed works.
  allowed_tools: []
```

If Task 0 step 4 found a different working flag, update the key in this file before continuing.

- [ ] **Step 3: Commit**

```bash
git add agent-packages/logging-l2-troubleshooting/evals/providers/
git commit -m "feat(evals): add agent + judge provider configs"
```

---

## Task 3: `prep-workdir.sh`

**Files:**
- Create: `agent-packages/logging-l2-troubleshooting/evals/prep-workdir.sh`

- [ ] **Step 1: Write the script**

Path: `agent-packages/logging-l2-troubleshooting/evals/prep-workdir.sh`

```bash
#!/usr/bin/env bash
# prep-workdir.sh — prepare one ephemeral workdir for the eval pipeline.
#
# Usage: prep-workdir.sh <fixture-id> <variant> <run-id>
#   variant: with-pkg | no-pkg
#
# with-pkg: runs `apm install <package> --target claude --frozen` inside the workdir.
# no-pkg:   leaves the workdir empty.
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
package_dir="$(cd "$script_dir/.." && pwd)"     # logging-l2-troubleshooting/

workdir="$script_dir/.work/$run_id/$fixture_id/$variant"
rm -rf "$workdir"
mkdir -p "$workdir"

if [ "$variant" = "with-pkg" ]; then
  ( cd "$workdir" \
    && apm install "$package_dir" --target claude --frozen \
       >"$workdir/.apm-install.log" 2>&1 )
fi

echo "$workdir"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x agent-packages/logging-l2-troubleshooting/evals/prep-workdir.sh
```

- [ ] **Step 3: Smoke verify with-pkg**

```bash
cd agent-packages/logging-l2-troubleshooting/evals
out=$(./prep-workdir.sh F2-fluentbit-oom with-pkg smoke-$(date +%s))
echo "workdir: $out"
ls -la "$out"
# Expect: .claude/ (or equivalent target dir from Task 0) exists with skills materialised.
test -d "$out/.claude" && echo OK || echo "FAIL: no .claude dir; check apm-install.log"
cat "$out/.apm-install.log" | tail -20
```

If Task 0 found that `apm install` lands files somewhere other than `.claude/`, adjust the smoke check accordingly.

- [ ] **Step 4: Smoke verify no-pkg**

```bash
out=$(./prep-workdir.sh F2-fluentbit-oom no-pkg smoke-$(date +%s))
ls -la "$out"
# Expect: directory exists, is empty.
[ -z "$(ls -A "$out")" ] && echo OK || echo "FAIL: no-pkg dir not empty"
```

- [ ] **Step 5: Clean smoke workdirs and commit**

```bash
rm -rf agent-packages/logging-l2-troubleshooting/evals/.work
git add agent-packages/logging-l2-troubleshooting/evals/prep-workdir.sh
git commit -m "feat(evals): add prep-workdir.sh for APM-install-based A/B"
```

---

## Task 4: F2 fixture data

**Files:**
- Create: `agent-packages/logging-l2-troubleshooting/evals/fixtures/F2-fluentbit-oom/meta.yaml`
- Create: `agent-packages/logging-l2-troubleshooting/evals/fixtures/F2-fluentbit-oom/prompt.txt`
- Create: `agent-packages/logging-l2-troubleshooting/evals/fixtures/F2-fluentbit-oom/ground_truth.md`
- Create: `agent-packages/logging-l2-troubleshooting/evals/fixtures/F2-fluentbit-oom/rubric.yaml`

- [ ] **Step 1: `meta.yaml`**

```yaml
id: F2-fluentbit-oom
cluster_fixture: F2-fluent-oom
backend: victorialogs
expected_area: fluentbit-troubleshoot
expected_recommend_kind: resource-bump
description: >
  FluentBit DaemonSet OOMKilled because container memory limit is below
  the steady-state working set. Engineer-driven path: vague "logs went
  missing" complaint.
```

- [ ] **Step 2: `prompt.txt`**

```
Логи перестали приходить от части подов в кластере dev. Когда началось — не знаю,
заметил час назад. Помоги разобраться.
```

(Russian intentionally — the support tickets this skill targets are mixed-language; the agent has to cope. The skill itself works in English internally.)

- [ ] **Step 3: `ground_truth.md`**

```markdown
**Area:** fluentbit-troubleshoot

**Root cause:** FluentBit DaemonSet pods OOMKilled because the container
memory limit (50Mi) is below the steady-state working set of the
tail + forwarder pipeline under this log volume. Pods enter
CrashLoopBackOff; logs from nodes whose fluent-bit is down stop arriving.

**Expected recommend:**
- type: resource-bump
- target: DaemonSet/fluent-bit in namespace `logging`
- change: `spec.template.spec.containers[0].resources.limits.memory`
  50Mi → 256Mi (or higher; the exact number is not the point —
  raising the limit above the working set is)
- rollback: revert the helm values overlay

**Required snapshot fields attached to the recommend:**
- pod status of fluent-bit pods (all in OOMKilled or CrashLoopBackOff)
- last termination reason from `kubectl describe`
- current memory limit value (50Mi)
- memory request value if different
```

- [ ] **Step 4: `rubric.yaml`**

```yaml
checks:
  - id: triage-ran
    description: >
      Agent invoked logging-l2-triage before any area-specific skill.
  - id: area-correct
    description: >
      Triage selected fluentbit-troubleshoot, not fluentd / graylog /
      opensearch / logging-operator.
  - id: oom-identified
    description: >
      Transcript names OOMKilled or "memory limit reached" backed by
      explicit kubectl output (status / describe / events), not
      speculation.
  - id: recommend-emitted
    description: >
      A structured recommend block is the final output. Its type
      corresponds to a memory-limit increase on the fluent-bit
      DaemonSet.
  - id: read-before-recommend
    description: >
      The recommend block carries a read-safe snapshot covering at
      minimum pod status and current memory limit.
  - id: no-mutations
    description: >
      Zero mutating kubectl calls in the transcript (no apply, edit,
      delete, patch, scale, restart, or helm upgrade).
```

- [ ] **Step 5: Commit**

```bash
git add agent-packages/logging-l2-troubleshooting/evals/fixtures/F2-fluentbit-oom
git commit -m "feat(evals): add F2 FluentBit OOM fixture data"
```

---

## Task 5: Judge prompt template

**Files:**
- Create: `agent-packages/logging-l2-troubleshooting/evals/judge-prompt.md`

- [ ] **Step 1: Write the template**

```markdown
You are evaluating a transcript from an L2 troubleshooting skill against
a fixed rubric.

# Ground truth

{{ground_truth}}

# Rubric

Each check is binary (pass or fail). Do not give partial credit. Use
strict reading: if the transcript does not contain explicit evidence,
mark fail.

{{rubric_yaml}}

# Transcript

{{transcript}}

# Output

Return strict JSON. No prose outside the JSON. Schema:

{
  "checks": [
    {
      "id": "<rubric check id>",
      "pass": true | false,
      "evidence": "<one short verbatim quote from the transcript, or '' if pass=false>"
    }
  ],
  "overall_pass": true | false
}

overall_pass = true if and only if every check.pass is true.
```

- [ ] **Step 2: Commit**

```bash
git add agent-packages/logging-l2-troubleshooting/evals/judge-prompt.md
git commit -m "feat(evals): add shared judge prompt template"
```

---

## Task 6: `promptfooconfig.yaml`

**Files:**
- Create: `agent-packages/logging-l2-troubleshooting/evals/promptfooconfig.yaml`

- [ ] **Step 1: Write the config**

Use the assertion-type names confirmed in Task 0. Below assumes `skill-used`; replace with the verified id if different. The `provider:` line under `llm-rubric` points at the judge provider file.

```yaml
description: L2 troubleshooting skill eval — fixture passed as CLI var.

prompts:
  - file://{{fixture_dir}}/prompt.txt

# Both providers are claude-agent-sdk on haiku; they differ only in cwd and label.
# Inlined here (rather than via file://providers/agent.yaml) so we can override
# config per provider in a syntactically simple way. providers/*.yaml exist as
# the canonical reference; if you change model or auth there, mirror it here.
providers:
  - id: claude-agent-sdk
    label: with-pkg
    config:
      model: claude-haiku-4-5
      cwd: "{{workdir_with}}"
  - id: claude-agent-sdk
    label: no-pkg
    config:
      model: claude-haiku-4-5
      cwd: "{{workdir_no}}"

tests:
  - description: "{{fixture}}"
    vars:
      fixture_dir: "fixtures/{{fixture}}"
      ground_truth: "file://fixtures/{{fixture}}/ground_truth.md"
      rubric_yaml: "file://fixtures/{{fixture}}/rubric.yaml"
    assert:
      - type: llm-rubric
        # Use the judge provider definition for grading.
        provider:
          id: claude-agent-sdk
          label: judge-claude-code-opus-4-7
          config:
            model: claude-opus-4-7
            allowed_tools: []   # mirror Task 0 finding if the key differs
        rubricPrompt: file://judge-prompt.md
      - type: skill-used
        value: logging-l2-triage
        # If Task 0 found `skill-used` does not work as a separate
        # assertion, swap this for a javascript: assertion that greps
        # the transcript.
```

`providers/agent.yaml` and `providers/judge.yaml` (Task 2) become a reference for humans and a single source of truth for model ids — but the actual run-time provider blocks are inlined above because promptfoo's external-provider include doesn't cleanly support per-cell config overrides across versions. If you change model or auth in one place, mirror it in the other.

The `--vars` flag passed by the orchestrator binds `fixture`, `workdir_with`, `workdir_no` at run time.

- [ ] **Step 2: Quick syntax check**

```bash
cd agent-packages/logging-l2-troubleshooting/evals
npx promptfoo@latest validate --config promptfooconfig.yaml \
  --vars fixture=F2-fluentbit-oom,workdir_with=/tmp/x,workdir_no=/tmp/y
```

Expected: validation reports no schema errors. If `validate` is unavailable in the installed version, run `npx promptfoo@latest eval --config promptfooconfig.yaml --vars ... --dry-run` instead.

- [ ] **Step 3: Commit**

```bash
git add agent-packages/logging-l2-troubleshooting/evals/promptfooconfig.yaml
git commit -m "feat(evals): add promptfoo config with agent/judge providers"
```

---

## Task 7: Single-fixture smoke (F2, repeat 1)

End-to-end smoke against the live cluster before writing the orchestrator. Confirms providers, prep-workdir, fixture data, and judge wiring all line up.

**Files:** none created in this task; it is verification only.

- [ ] **Step 1: Verify baseline clean**

```bash
cd deploy/kind/fixtures && ./fixture.sh status
```

Expected: `no fixtures active`. If something is active, revert it first.

- [ ] **Step 2: Apply F2**

```bash
cd deploy/kind/fixtures && ./fixture.sh apply F2-fluent-oom
sleep 30   # let pods settle into OOMKilled
kubectl -n logging get pods -l app.kubernetes.io/name=fluent-bit
# Expect: pods in OOMKilled / CrashLoopBackOff
```

- [ ] **Step 3: Prepare workdirs**

```bash
cd /Users/denifilatov/Repos/qubership-logging-operator/agent-packages/logging-l2-troubleshooting/evals
run_id=smoke-$(date +%s)
with=$(./prep-workdir.sh F2-fluentbit-oom with-pkg "$run_id")
no=$(./prep-workdir.sh   F2-fluentbit-oom no-pkg   "$run_id")
echo "with=$with"; echo "no=$no"
```

- [ ] **Step 4: Run promptfoo on F2 only, --repeat 1**

```bash
mkdir -p results/$run_id
npx promptfoo@latest eval \
  --config promptfooconfig.yaml \
  --vars fixture=F2-fluentbit-oom,workdir_with=$with,workdir_no=$no \
  --repeat 1 \
  --output results/$run_id/F2-fluentbit-oom.json
```

Expected: command finishes; JSON output exists; both providers produced transcripts. Open results JSON and confirm at least one cell has `assertions[].pass` populated from the judge.

- [ ] **Step 5: Revert F2**

```bash
cd /Users/denifilatov/Repos/qubership-logging-operator/deploy/kind/fixtures
./fixture.sh revert F2-fluent-oom
./fixture.sh status   # expect: no fixtures active
```

- [ ] **Step 6: If anything is miswired, fix in place**

Likely fix points: provider ids, assertion type names, prompt-template rendering of file://, judge JSON parsing. Fix the files, re-run steps 1–5, commit the fixes:

```bash
git add agent-packages/logging-l2-troubleshooting/evals
git commit -m "fix(evals): smoke-test corrections for F2"
```

If smoke passes first try, no commit is needed for this task.

---

## Task 8: `orchestrator.sh`

**Files:**
- Create: `agent-packages/logging-l2-troubleshooting/evals/orchestrator.sh`

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# orchestrator.sh — serial loop over L2 eval fixtures.
#
# Usage: orchestrator.sh [REPEATS] [fixture-id ...]
#   REPEATS  defaults to 3
#   fixtures default to all under fixtures/F*-*/
#
# Per fixture: clean-baseline check → prep both workdirs → apply cluster
# fixture → promptfoo eval → revert. Failure handling per
# docs/eval-pipeline-design.md §6.

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

  set +e
  npx promptfoo@latest eval \
    --config "$script_dir/promptfooconfig.yaml" \
    --vars "fixture=$fix,workdir_with=$with,workdir_no=$no" \
    --repeat "$repeats" \
    --output "$results_dir/$fix.json"
  eval_rc=$?
  set -e

  if ! "$cluster_fixtures/fixture.sh" revert "$cluster_fix"; then
    echo "FATAL: revert failed for $cluster_fix. Cluster dirty. Stopping." >&2
    apply_revert_failed=1
    break
  fi

  if [ $eval_rc -ne 0 ]; then
    echo "WARN: promptfoo returned $eval_rc for $fix (check $results_dir/$fix.json)" >&2
  fi
done

echo "$run_id" > "$script_dir/results/LAST_RUN"

if [ $apply_revert_failed -ne 0 ]; then
  exit 2
fi
echo "DONE: $results_dir"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x agent-packages/logging-l2-troubleshooting/evals/orchestrator.sh
```

- [ ] **Step 3: Smoke verify with F2 only, --repeats 1**

```bash
cd agent-packages/logging-l2-troubleshooting/evals
./orchestrator.sh 1 F2-fluentbit-oom
# Expect: results/<run-id>/F2-fluentbit-oom.json created; cluster reverted at end.
cat results/LAST_RUN
```

After the run, manually verify:

```bash
cd /Users/denifilatov/Repos/qubership-logging-operator/deploy/kind/fixtures
./fixture.sh status   # expect: no fixtures active
```

- [ ] **Step 4: Commit**

```bash
git add agent-packages/logging-l2-troubleshooting/evals/orchestrator.sh
git commit -m "feat(evals): add serial orchestrator with failure handling"
```

---

## Task 9: `Makefile`

**Files:**
- Create: `agent-packages/logging-l2-troubleshooting/evals/Makefile`

- [ ] **Step 1: Write Makefile**

Note: use tabs for recipe indentation (Make is strict).

```make
.PHONY: eval eval-F2 eval-F4 report clean baseline-check

REPEATS ?= 3

eval: baseline-check
	./orchestrator.sh $(REPEATS)
	$(MAKE) report

eval-F2: baseline-check
	./orchestrator.sh $(REPEATS) F2-fluentbit-oom
	$(MAKE) report

eval-F4: baseline-check
	./orchestrator.sh $(REPEATS) F4-helm-bad-image
	$(MAKE) report

report:
	./aggregate.sh

baseline-check:
	@status="$$(../../../deploy/kind/fixtures/fixture.sh status)"; \
	if [ "$$status" != "no fixtures active" ]; then \
	  echo "baseline not clean: $$status"; \
	  echo "revert active fixture first."; \
	  exit 1; \
	fi

clean:
	rm -rf .work results
```

- [ ] **Step 2: Verify Make targets parse**

```bash
cd agent-packages/logging-l2-troubleshooting/evals
make -n baseline-check
make -n eval-F2 REPEATS=1
```

Expected: dry-run prints commands without error.

- [ ] **Step 3: Commit**

```bash
git add agent-packages/logging-l2-troubleshooting/evals/Makefile
git commit -m "feat(evals): add Makefile entrypoints"
```

---

## Task 10: `aggregate.sh`

**Files:**
- Create: `agent-packages/logging-l2-troubleshooting/evals/aggregate.sh`

Reads promptfoo JSON outputs from the most recent run and writes `summary.md` with the methodology's primary measure: with-pkg vs no-pkg pass-rate per fixture, plus per-check breakdown.

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# aggregate.sh — turn the last promptfoo run into results/<run>/summary.md.
#
# Reads results/LAST_RUN, walks results/<run-id>/*.json (promptfoo output),
# emits per-fixture pass rate (with-pkg vs no-pkg) and per-check rate.

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

{
  echo "# Eval run $run_id"
  echo
  echo "## Pass rate by fixture (overall_pass from llm-rubric)"
  echo
  echo "| Fixture | with-pkg | no-pkg | delta |"
  echo "|---|---|---|---|"

  for f in "$run_dir"/*.json; do
    [ -e "$f" ] || continue
    fix="$(basename "$f" .json)"

    # promptfoo JSON layout: results.results[].provider.label gives 'with-pkg' / 'no-pkg';
    # .success boolean reflects overall assertion outcome. Adjust the jq paths if the
    # installed promptfoo version uses different field names — verify against the smoke
    # output from Task 7.
    with_total=$(jq '[.results.results[]? | select(.provider.label=="with-pkg")] | length' "$f")
    with_pass=$(jq  '[.results.results[]? | select(.provider.label=="with-pkg" and .success)] | length' "$f")
    no_total=$(jq   '[.results.results[]? | select(.provider.label=="no-pkg")] | length' "$f")
    no_pass=$(jq    '[.results.results[]? | select(.provider.label=="no-pkg" and .success)] | length' "$f")

    with_rate="0"; no_rate="0"; delta="-"
    if [ "$with_total" -gt 0 ]; then
      with_rate=$(python3 -c "print(f'{$with_pass/$with_total:.2f}')")
    fi
    if [ "$no_total" -gt 0 ]; then
      no_rate=$(python3 -c "print(f'{$no_pass/$no_total:.2f}')")
    fi
    if [ "$with_total" -gt 0 ] && [ "$no_total" -gt 0 ]; then
      delta=$(python3 -c "print(f'{$with_pass/$with_total - $no_pass/$no_total:+.2f}')")
    fi

    echo "| $fix | $with_pass/$with_total ($with_rate) | $no_pass/$no_total ($no_rate) | $delta |"
  done

  echo
  echo "## Tokens and latency"
  echo
  echo "See \`results/$run_id/*.json\` (or open the promptfoo-generated HTML if present)."
} > "$out"

echo "wrote $out"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x agent-packages/logging-l2-troubleshooting/evals/aggregate.sh
```

- [ ] **Step 3: Smoke verify against Task 7's run**

```bash
cd agent-packages/logging-l2-troubleshooting/evals
./aggregate.sh
cat results/$(cat results/LAST_RUN)/summary.md
```

Expected: table prints; rates parsed correctly. If the `jq` field paths are wrong because the installed promptfoo emits a different JSON shape, inspect a `*.json` from the smoke run, adjust the jq queries, repeat.

- [ ] **Step 4: Commit**

```bash
git add agent-packages/logging-l2-troubleshooting/evals/aggregate.sh
git commit -m "feat(evals): add aggregator for summary.md"
```

---

## Task 11: F4 fixture data

**Files:**
- Create: `agent-packages/logging-l2-troubleshooting/evals/fixtures/F4-helm-bad-image/meta.yaml`
- Create: `agent-packages/logging-l2-troubleshooting/evals/fixtures/F4-helm-bad-image/prompt.txt`
- Create: `agent-packages/logging-l2-troubleshooting/evals/fixtures/F4-helm-bad-image/ground_truth.md`
- Create: `agent-packages/logging-l2-troubleshooting/evals/fixtures/F4-helm-bad-image/rubric.yaml`

- [ ] **Step 1: Inspect the cluster fixture to confirm what F4 actually breaks**

```bash
cat deploy/kind/fixtures/F4-helm-bad-image/README.md
cat deploy/kind/fixtures/F4-helm-bad-image/apply.sh
```

Use this to ground the fixture data below in reality. Adjust wording if details differ.

- [ ] **Step 2: `meta.yaml`**

```yaml
id: F4-helm-bad-image
cluster_fixture: F4-helm-bad-image
backend: victorialogs
expected_area: logging-operator-troubleshoot
expected_recommend_kind: helm-rollback-or-image-fix
description: >
  Bad image tag in helm values → operator pod ImagePullBackOff.
  Engineer-driven path: "operator не поднимается после деплоя".
```

- [ ] **Step 3: `prompt.txt`**

```
Только что задеплоили обновление logging-стека, под logging-operator в неймспейсе
logging не стартует. Помоги понять, что пошло не так.
```

- [ ] **Step 4: `ground_truth.md`**

```markdown
**Area:** logging-operator-troubleshoot

**Root cause:** The Deployment for `logging-operator` references an image
tag that does not exist in the registry. Pods stay in ImagePullBackOff /
ErrImagePull; the operator never reconciles the LoggingService CR.

**Expected recommend:**
- type: helm-rollback-or-image-fix
- target: Deployment/logging-operator in namespace `logging`
- change: either rollback the helm release to the previous good revision,
  or correct the image tag in the values overlay
- rollback: re-apply the previous helm release

**Required snapshot fields attached to the recommend:**
- pod status of logging-operator (ImagePullBackOff or ErrImagePull)
- container image reference currently configured
- helm history / current release status
- events showing the pull failure
```

If Step 1 revealed that F4 breaks something different (e.g. fluent-bit image, not operator image), adjust both `expected_area` and the ground truth wording.

- [ ] **Step 5: `rubric.yaml`**

```yaml
checks:
  - id: triage-ran
    description: >
      Agent invoked logging-l2-triage before any area-specific skill.
  - id: area-correct
    description: >
      Triage selected logging-operator-troubleshoot (the deployment-area
      skill), not an operational area like fluentbit / fluentd / graylog.
  - id: image-pull-identified
    description: >
      Transcript explicitly names ImagePullBackOff or ErrImagePull
      backed by kubectl output (get pods / describe pod / events).
  - id: recommend-emitted
    description: >
      A structured recommend block is the final output, proposing either
      a helm rollback or a corrected image tag.
  - id: read-before-recommend
    description: >
      The recommend carries a read-safe snapshot covering pod status,
      configured image reference, and helm release state.
  - id: no-mutations
    description: >
      Zero mutating kubectl or helm calls in the transcript.
```

- [ ] **Step 6: Smoke F4 alone**

```bash
cd agent-packages/logging-l2-troubleshooting/evals
./orchestrator.sh 1 F4-helm-bad-image
./aggregate.sh
cat results/$(cat results/LAST_RUN)/summary.md
```

Confirm F4 runs end-to-end. If the agent reliably misroutes F4 to an operational skill, that's a finding worth recording in the spec's §10 — it suggests triage rules need work. Not a plan failure; that is exactly the signal the eval exists to surface.

- [ ] **Step 7: Commit**

```bash
git add agent-packages/logging-l2-troubleshooting/evals/fixtures/F4-helm-bad-image
git commit -m "feat(evals): add F4 helm bad image fixture data"
```

---

## Task 12: Full v1 run and minor tuning

**Files:** none created; possibly small edits to fixture rubrics / prompts based on findings.

- [ ] **Step 1: Verify clean baseline**

```bash
cd deploy/kind/fixtures && ./fixture.sh status
```

- [ ] **Step 2: Run full pipeline**

```bash
cd agent-packages/logging-l2-troubleshooting/evals
make eval REPEATS=3
```

Expected wall-clock: roughly 10–30 minutes depending on Haiku reasoning loop length.

- [ ] **Step 3: Inspect `summary.md`**

```bash
cat results/$(cat results/LAST_RUN)/summary.md
```

Look for:
- `with-pkg` pass-rate strictly higher than `no-pkg` on both fixtures (the methodology's primary measure)
- Suspicious per-check pass-rates (e.g. `read-before-recommend` always failing → rubric wording too strict)
- Variance within `with-pkg` (e.g. 1/3, 2/3, 3/3) — expected on a Haiku-tier model

- [ ] **Step 4: Tune rubric wording if obviously miscalibrated**

If a check fails 0/3 with-pkg AND 0/3 no-pkg, the rubric wording is likely demanding something the skill never produces. Loosen wording, not the bar. If a check passes 3/3 with-pkg AND 3/3 no-pkg, it does not discriminate — make it stricter, or replace it.

Commit any tuning changes with a clear message:

```bash
git add agent-packages/logging-l2-troubleshooting/evals/fixtures
git commit -m "tune(evals): rubric tweaks from first full v1 run"
```

- [ ] **Step 5: Record one-paragraph findings in spec §11**

Open `docs/eval-pipeline-design.md` and add a new short section "11. First-run findings" with: dates, observed deltas, surprises, what to follow up on. This is the first piece of real data the project has.

```bash
git add agent-packages/logging-l2-troubleshooting/docs/eval-pipeline-design.md
git commit -m "docs(skills): record first v1 eval-run findings"
```

---

## Self-review notes (left to executor)

1. Task 0 outputs may force small edits to Tasks 2, 3, 6. That's intended — do not skip Task 0 just because Tasks 1–6 are template-ready.
2. The `jq` paths in `aggregate.sh` (Task 10) are best-guess against the documented promptfoo JSON shape. If your installed version emits a different shape, adjust paths from a real `*.json` and re-commit.
3. The plan does not gate merges on a pass-rate threshold. That belongs in a follow-up spec (regression gating).
4. CI integration is intentionally out of scope. Once Task 12's findings stabilise, draft a follow-up plan for GitHub Actions with cluster bootstrap.
