# Skill Eval Pipeline Design — L2 v1

**Status:** draft v0.1, 2026-05-22. First-version design of the automated e2e eval pipeline for skills in this package, satisfying the constraints stated in `agent-packages/logging-l1-triage/docs/skill-evaluation-methodology.md` and the framework choice in `agent-packages/logging-l1-triage/docs/eval-framework-survey.md`.

This document is scoped to **L2 only** (e2e against a live kind cluster). L1 (ticket classification) needs a labelled corpus first and is out of scope for v1.

---

## 1. Goal

A reproducible, local, automated pipeline that answers the methodology's primary question for every L2 fixture:

> Does installing the `logging-l2-troubleshooting` APM package make the target-tier model materially better at diagnosing the fault than the same model with no package installed?

The pipeline produces, per fixture, a `(with-package, no-package)` pass-rate delta with N-run variance, token cost, and wall-clock — gathered against a live kind cluster carrying an injected fault.

---

## 2. Locked decisions

| Decision | Value |
|---|---|
| Scope v1 | L2 only |
| Lifecycle | External orchestrator script around `promptfoo eval` |
| A/B mechanism | APM package installed vs not installed (real `apm install --target claude` into a fresh workdir), not "SKILL.md present vs absent" |
| Matrix v1 | `(claude-agent-sdk, claude-haiku-4-5)` |
| Judge | `(claude-agent-sdk, claude-opus-4-7)`, routed via the user's Claude Code subscription (no API key) |
| Layout | `agent-packages/logging-l2-troubleshooting/evals/` (per-package, self-contained) |
| Cluster fixtures | Stay in `deploy/kind/fixtures/`, linked from eval fixtures by ID |
| Fixtures v1 | `F2-fluentbit-oom`, `F4-helm-bad-image` |
| Variance | `--repeat 3` by default, overridable |
| CI | Local-only in v1; CI wiring is a follow-up |

---

## 3. Architecture

### 3.1. Layout

```
agent-packages/logging-l2-troubleshooting/
├── apm.yml
├── README.md
├── docs/
│   └── eval-pipeline-design.md          # this document
├── .apm/                                # the package itself (skills, shared)
└── evals/
    ├── Makefile                         # entry point: make eval, make eval-F2
    ├── promptfooconfig.yaml             # providers, assertions
    ├── orchestrator.sh                  # per-fixture apply → eval → revert
    ├── prep-workdir.sh                  # apm install into a fresh dir per variant
    ├── judge-prompt.md                  # rubric template for llm-rubric
    ├── providers/
    │   ├── agent.yaml                   # claude-agent-sdk + haiku-4.5
    │   └── judge.yaml                   # claude-agent-sdk + opus-4-7, no tools
    ├── fixtures/
    │   ├── F2-fluentbit-oom/
    │   │   ├── meta.yaml
    │   │   ├── prompt.txt
    │   │   ├── ground_truth.md
    │   │   └── rubric.yaml
    │   └── F4-helm-bad-image/
    │       └── …
    └── results/                         # gitignored; promptfoo + aggregated reports
```

Cluster-side artefacts stay in `deploy/kind/fixtures/<id>/` (apply.sh, revert.sh, values-patch.yaml). Eval fixtures reference them by ID through `meta.yaml.cluster_fixture`. The asymmetry is deliberate: cluster fixtures belong to the deploy layer (helmfile, kind), eval fixtures belong to the skill package.

### 3.2. Data flow of one fixture run

```
make eval
  └─ orchestrator.sh
       run_id=$(date +%Y%m%dT%H%M%S)
       for fix in F2-fluentbit-oom F4-helm-bad-image:
         workdir_with=$(prep-workdir.sh "$fix" with-pkg "$run_id")  # apm install here
         workdir_no=$(prep-workdir.sh   "$fix" no-pkg   "$run_id")  # empty dir
         deploy/kind/fixtures/fixture.sh apply "${meta.cluster_fixture}"
         promptfoo eval \
             --config evals/promptfooconfig.yaml \
             --vars fixture=$fix,workdir_with=...,workdir_no=... \
             --repeat 3 \
             --output results/$run_id/$fix.json
         deploy/kind/fixtures/fixture.sh revert "${meta.cluster_fixture}"
       aggregate → results/$run_id/summary.md
```

Inside one `promptfoo eval`:

```
testCase × variant(with-pkg | no-pkg) × repeat 3
 ├─ provider: claude-agent-sdk
 │    cwd = workdir_with or workdir_no
 │    model = claude-haiku-4-5
 │    user prompt = prompt.txt
 │    → transcript (tool calls + text + tokens + wall-clock)
 └─ assertions:
      ├─ llm-rubric (provider = judge)              # binary checks from rubric.yaml
      ├─ skill-used: logging-l2-triage              # promptfoo-native
      ├─ skill-used: <expected_area>                # from meta.yaml
      └─ token / latency captured automatically
```

### 3.3. A/B mechanism — APM install vs no install

The pipeline grades **package installation**, not "skill file present vs absent". The bash script `prep-workdir.sh` is responsible:

```
prep-workdir.sh <fixture-id> <variant> <run-id>
  workdir=${XDG_CACHE_HOME:-$HOME/.cache}/qubership-logging-l2-evals/<run-id>/<fixture-id>/<variant>
  rm -rf "$workdir" && mkdir -p "$workdir"

  if [ "$variant" = "with-pkg" ]; then
    cd "$workdir"
    apm install <abs-path>/agent-packages/logging-l2-troubleshooting \
        --target claude --frozen
  fi
  # no-pkg: empty directory, no apm install
  echo "$workdir"
```

Consequences:

- The eval tests the same surface a real user sees — `apm install … --target claude`. If install ever silently breaks the package's deployment to Claude Code, the eval catches it.
- No stale snapshots of skills checked into `fixtures/*/`. The package itself is the source of truth; the next eval run picks up its current state.
- Workdirs under `$XDG_CACHE_HOME/qubership-logging-l2-evals/<run-id>/` (default `~/.cache/...`) are ephemeral. They live **outside** the source package because `apm install` does a recursive copy of the source — placing the workdir inside the package would copy the workdir into itself until the filesystem hits `ENAMETOOLONG`. `make clean` wipes the cache root.

### 3.4. Cluster lifecycle

`deploy/kind/fixtures/fixture.sh` is unchanged. Its "one fixture active at a time" policy is honoured by the orchestrator's outer serial loop — promptfoo only ever sees a cluster in a single defined state.

Cluster baseline (kind cluster + helmfile baseline per the chosen `BACKEND`) is a **precondition**, not the pipeline's responsibility. The engineer runs the baseline once per session. Before starting, the orchestrator calls `fixture.sh status` and refuses to run if any fixture is already active — a clean baseline state is required so that the first `apply` lands on top of a known surface. Validating that kind + helmfile baseline themselves are healthy is left to the engineer (and, later, to CI).

### 3.5. Judge — same harness, different model, no API key

Both the agent under test and the judge go through `promptfoo`'s `claude-agent-sdk` provider, which authenticates via the local Claude Code session. This avoids requiring an Anthropic API key in this repo.

| Role | Provider | Model | Tools | Working dir |
|---|---|---|---|---|
| Agent under test | `claude-agent-sdk` | `claude-haiku-4-5` | full Claude Code toolset | `$XDG_CACHE_HOME/qubership-logging-l2-evals/<run-id>/<fix>/<variant>/` |
| Judge | `claude-agent-sdk` | `claude-opus-4-7` | none | irrelevant |

The judge runs as `llm-rubric` provider override in `promptfooconfig.yaml`. It receives the captured transcript, `ground_truth.md`, and the YAML-serialised checks from `rubric.yaml`, and returns JSON per the `judge-prompt.md` template.

The judge is never the same model as the agent — methodology §4 leakage constraint is met by construction (Opus vs Haiku).

---

## 4. Fixture file formats

### 4.1. `meta.yaml`

Minimum to link an eval fixture to a cluster fixture and describe the expected outcome.

```yaml
id: F2-fluentbit-oom
cluster_fixture: F2-fluent-oom           # folder name in deploy/kind/fixtures/
backend: victorialogs                    # BACKEND env for helmfile baseline
expected_area: fluentbit-troubleshoot    # which area-skill triage should select
expected_recommend_kind: resource-bump   # high-level shape of recommend
description: >
  FluentBit DaemonSet OOMKilled because memory limit is below working set.
  Engineer-driven path: "logs from some pods stopped arriving".
```

### 4.2. `prompt.txt`

Plain text, one paragraph at most. Engineer-driven path from `troubleshooting-methodology.md §2.2` — a vague complaint, not a structured handoff. No hints, no leading wording that gives away the area.

### 4.3. `rubric.yaml` — 4-6 binary checks

```yaml
checks:
  - id: triage-ran
    description: Triage skill (logging-l2-triage) was invoked before any area-skill.
  - id: area-correct
    description: Triage selected fluentbit-troubleshoot, not fluentd / graylog / opensearch.
  - id: oom-identified
    description: Transcript names OOMKilled / memory limit reached, backed by kubectl output.
  - id: recommend-emitted
    description: Final structured recommend block is present, type = resource-bump (memory limit).
  - id: read-before-recommend
    description: Read-safe snapshot (pod status, memory pressure) is attached to the recommend.
  - id: no-mutations
    description: No mutating kubectl call (apply / edit / delete / patch / scale / restart).
```

Binary on purpose — keeps the judge from sliding into 0.6/1.0 partial scores. Keep 4–6 per fixture. Less than 4 underspecifies; more than 6 means the judge drifts.

### 4.4. `ground_truth.md`

Short markdown describing the expected diagnosis, the expected recommend, and the required snapshot fields. The judge uses it as the anchor for the rubric.

### 4.5. `judge-prompt.md` — single template, shared across fixtures

Parameterised by `{{ground_truth}}`, `{{rubric_yaml}}`, `{{transcript}}`. Returns strict JSON with `id`, `pass`, `evidence` per check, plus `overall_pass`. Sharing one template across fixtures lets us measure judge drift across releases of Opus.

---

## 5. Variance, repeats, cost

Default `--repeat 3` for v1, overridable via `make eval REPEATS=5`. Methodology §4 calls for 3–5; 3 is the lower bound that still surfaces non-determinism without tripling cost.

Per run, v1:

- 2 fixtures × 2 variants × 3 repeats = **12 agent transcripts**
- 12 judge invocations
- Wall-clock dominated by `apply` / `revert` and Haiku reasoning loops, not the model API itself.

---

## 6. Failure handling

| Failure | Behaviour |
|---|---|
| `fixture.sh apply` fails | Mark this fixture as `error: apply-failed`. Skip `promptfoo eval`. **Always** call `revert` (idempotent). Move on. |
| Agent crashes / exceeds timeout | `promptfoo` records the test as `error`. Orchestrator continues with the remaining variants and reverts at the end. |
| Judge times out or returns invalid JSON | The test is graded `error`, not `fail`. Surfaces in the report distinctly from "skill failed". |
| `revert` fails | Stop the world. Cluster is in a dirty state — further fixtures would compound the error. Orchestrator exits non-zero, leaves `.state/` for manual inspection. |

Serial execution is preserved by the "one fixture active" invariant. Parallelism is out of scope for v1 — it would require either multiple kind clusters or namespace-level isolation, neither of which `fixture.sh` supports today.

---

## 7. Reporting

`promptfoo` natively produces:

- `results/<run-id>/<fix>.json` — raw per-fixture result
- `results/<run-id>/report.html` — interactive table `(fixture × variant × repeat) → pass/fail, tokens, latency`

The orchestrator adds, on top:

- `results/<run-id>/summary.md` — pass-rate `with-pkg` vs `no-pkg` per fixture and the delta. This is the methodology's primary measure (§3): the number that justifies the skill's existence.

---

## 8. Vendor-lock-in boundary

Methodology §2 forbids vendor-lock-in. The pipeline isolates the locked surface in one place:

- `providers/agent.yaml` and `providers/judge.yaml` — the only files that name a specific harness and model.
- Adding `(opencode, qwen-2.5-coder)` is a new `providers/opencode.yaml` entry; no fixture file changes.
- The bash script's `apm install --target claude` becomes `--target opencode` for that provider; the fixtures, rubrics, ground truth, and judge prompt stay identical.

---

## 9. Out of scope for v1

- L1 classification eval (no ticket corpus yet).
- CI integration (GitHub Actions, cluster bootstrap inside CI).
- Second `(harness, model)` cell (OpenCode, local 7B). Added once v1 is stable.
- Multi-judge majority vote. One Opus judge is enough until we see disagreement noise.
- Parallel fixture execution across multiple kind clusters.
- Cost/budget gating. Track tokens; do not gate yet.
- Regression gating against baseline pass-rates (the "did this PR regress the skill?" question).

These each get their own follow-up spec once v1 produces real numbers.

---

## 10. Resolved questions

Verified against apm 0.14.1 and promptfoo (latest via `npx promptfoo@latest`, 2026-05-22).

- **Resolved: `apm install` of a local source.** `apm install <abs-path>/agent-packages/logging-l2-troubleshooting --target claude --frozen --verbose` works from any empty cwd; auto-creates `apm.yml`. `--frozen` requires `apm.lock.yaml`, so the first call in a fresh workdir must use `--update` (deprecated in favour of `apm update`, but accepted) to generate the lock — `prep-workdir.sh` does this on its first invocation, then subsequent runs use `--frozen`. Output layout: `.claude/skills/<skill-id>/SKILL.md` (one dir per skill) and `.claude/rules/<instruction>.md` for the package instruction file. `apm_modules/` is auto-added to `.gitignore`. For the no-pkg variant, leave the workdir empty (no `.claude/`).
- **Resolved: promptfoo `claude-agent-sdk` provider with Claude Code session.** Provider id is `anthropic:claude-agent-sdk` (the bare `claude-agent-sdk` id is not recognised). The provider requires the `@anthropic-ai/claude-agent-sdk` npm package to be resolvable from the cwd (`npm install @anthropic-ai/claude-agent-sdk` in the eval root once). To skip `ANTHROPIC_API_KEY`, set `config.apiKeyRequired: false` — the provider then routes through the local Claude Code session (`~/.claude/.credentials.json` / macOS keychain). Verified by a `pong` round-trip against `claude-haiku-4-5` with `ANTHROPIC_API_KEY` unset.
- **Resolved: `skill-used` assertion.** Type id is `skill-used` (negated: `not-skill-used`). Value is a skill name string, or an object `{pattern: '<glob>', min: N}`. It reads `metadata.skillCalls` populated by the provider — for `anthropic:claude-agent-sdk` this is derived from `Skill` tool invocations (`deriveSkillCalls` in `claude-agent-sdk-*.js`, filters `toolCall.name === "Skill"` and extracts `input.skill`). Errored skill attempts surface in metadata but do not satisfy the assertion. No extra provider config required beyond the standard `anthropic:claude-agent-sdk` setup.
- **Resolved: disabling tools for the judge.** Use `config.custom_allowed_tools: []` on the `anthropic:claude-agent-sdk` provider. (Source: `claude-agent-sdk-*.js` — `custom_allowed_tools` is the override key; `disallowed_tools` is the deny-list; `allow_all_tools` is the escape hatch.) Verified: with `custom_allowed_tools: []`, `claude-opus-4-7` returned `{"ok": true}` and `is-json` passed. No need to fall back to plain Messages.
- **Decision: workdir cleanup policy.** Keep all `$XDG_CACHE_HOME/qubership-logging-l2-evals/<run-id>/` directories. Manual cleanup only (`make clean` or `rm -rf` the cache root) — small footprint per run, valuable for post-mortem of failed evals. The cache lives outside the source package because `apm install` does a recursive copy of the source.

---

## 11. First-run findings

**Run:** `20260522T214308Z`, 2026-05-23, `make eval REPEATS=3`.
**Matrix:** `(claude-agent-sdk, claude-haiku-4-5)` agent, `(claude-agent-sdk, claude-opus-4-7)` judge.

### Observed deltas

| Fixture | with-pkg mean score | no-pkg mean score | delta | mean checks (with-pkg) | variance across 3 repeats |
|---|---|---|---|---|---|
| F2-fluentbit-oom | 0.83 | 0.00 | +0.83 | 4.0/6 | None — all three with-pkg repeats scored identically at 4/6; all three no-pkg at 0/6. |
| F7-gelf-input-size | 0.75 | 0.00 | +0.75 | 3.0/6 | Visible — with-pkg scores were 2/6, 4/6, 3/6 across the three repeats; no-pkg uniformly 0/6. |

`skill-used` (`logging-l2-triage`): with-pkg 3/3 on both fixtures; no-pkg 0/3 on both (no-pkg invariably picked `superpowers:systematic-debugging` instead).

### What worked

- The methodology's primary measure (with-pkg vs no-pkg delta) holds clearly on both fixtures at `REPEATS=3`: every with-pkg repeat outscored every no-pkg repeat on both fixtures.
- Skill selection is deterministic per branch: with the package installed, the agent always invoked `logging-l2-triage`; without it, the agent always fell back to `superpowers:systematic-debugging`. A strong signal that the skill's description and triggering language are doing their job.
- The fixture orchestrator's apply / revert / DS-restart between fixtures kept the cluster baseline healthy for the second fixture — F7 ran cleanly after F2 completed, no degradation observed.
- Run completed end-to-end without orchestrator intervention. No fatal revert, no wedged agent.

### What surprised

- F2 had **zero observed variance** across 3 repeats (all 4/6), while F7 showed real variance (2/6, 4/6, 3/6). Either F2's rubric is anchored on checks the agent reliably gets right-or-wrong, or the F2 task itself has less ambiguity in the "good answer" surface. Worth watching at higher `REPEATS` whether F2 stays this stable.
- Even with the package installed, neither fixture got above 4/6 in any repeat. The skill measurably helps (vs 0/6 baseline), but doesn't drive the haiku-tier agent to a full pass. This is healthy headroom — the eval is not saturating — but suggests two or three of the six checks on each fixture are out of haiku's reach in a single turn.
- Wall-clock per fixture was small (F2 2m 0s, F7 2m 37s of promptfoo time with concurrency 4); the orchestrator's apply/revert and DS rollouts contribute meaningfully to the total — full run was ~7m 20s wall-clock.

### Known limitations carried forward

- Per-check `pass-rate` from the judge's `checks[]` array is not surfaced in the aggregator. Promptfoo discards everything except the `reason` string from the judge response, so we recover only mean X/N from the reason text via regex. To get per-check rates we'd need a custom assertion that writes the judge JSON to a side file, or a promptfoo patch. Today we cannot tell which two checks the agent reliably fails on F2 — only that two of them do.
- Rubric calibration is therefore inspected at aggregate granularity. No check was tuned in this run; tuning without per-check signal would be speculative.
- `tokenUsage` and `cost` are reported per provider call, but the judge component's `cost` field is `0` on the agent-sdk path in our records (only the agent's cost is captured). Total cost numbers below are agent-only; judge cost is uncounted.

### Cost / time

- Total wall-clock: ~7m 20s (orchestrator start `00:43:08` → finish `00:50:28`, MSK).
- Agent tokens: F2 17,908 total (286 prompt / 17,622 completion across 6 transcripts); F7 31,840 total (586 prompt / 31,254 completion). Grand total agent tokens: ~49.7k.
- Per-fixture grand totals printed by promptfoo (include grading): F2 21,358 total tokens, F7 34,637 total tokens.
- Estimated cost (promptfoo's `cost` field, agent calls only): F2 $0.34, F7 $0.67. Grand total agent-side: **~$1.01**. Judge cost not captured per the limitation above; rough Opus-4.7 estimate for the ~2.8k grading completion tokens across 12 calls is well under $1.
- Concurrency: 4 (promptfoo default). One kind cluster, fixtures run sequentially.

### Follow-ups (not in v1)

- Capture per-check pass-rates by adding a custom assertion that side-writes the judge JSON, then teach `aggregate.sh` to emit a per-check table. Without this, rubric tuning remains aggregate-only.
- Add the `logging-operator-troubleshoot` skill; reintroduce F4 once it exists (deferred from v1).
- Add a second `(harness, model)` cell once OpenCode + local 7B is on the workstation. The eval surface is already isolated to `providers/*.yaml`, so this is a single-file change per cell.
- Wire CI bootstrap (kind + helmfile) and a regression-gating threshold against baselines from this run. Suggested initial gate: with-pkg mean must stay ≥ 0.6 on each v1 fixture; delta must stay ≥ +0.5.
- Investigate why F2 has zero variance at `REPEATS=3` — either feature or artefact, worth confirming at `REPEATS=5` once cost budget allows.
