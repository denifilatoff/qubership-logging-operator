# Skill Eval Pipeline Design — L2

**Status:** 2026-05-23. Design of the automated e2e eval pipeline for skills in this package, satisfying the constraints stated in [skill-evaluation-methodology.md](skill-evaluation-methodology.md) and the framework choice in [eval-framework-survey.md](eval-framework-survey.md).

This document is scoped to **L2 only** (e2e against a live kind cluster). L1 (ticket classification) needs a labelled corpus first and is out of scope.

---

## 1. Goal

A reproducible, local, automated pipeline that answers the methodology's primary question for every L2 fixture:

> Does installing the `logging-l2-troubleshooting` APM package make the target-tier model materially better at diagnosing the fault than the same model with no package installed?

The pipeline produces, per fixture, a `(with-package, no-package)` pass-rate delta with N-run variance, token cost, and wall-clock — gathered against a live kind cluster carrying an injected fault.

---

## 2. Locked decisions

| Decision | Value |
|---|---|
| Scope | L2 only |
| Lifecycle | External orchestrator script around `promptfoo eval` |
| A/B mechanism | APM package installed vs not installed (real `apm install --target claude` into a fresh workdir), not "SKILL.md present vs absent" |
| Matrix | `(claude-agent-sdk, claude-haiku-4-5)` |
| Judge | `(claude-agent-sdk, claude-opus-4-7)`, routed via the user's Claude Code subscription (no API key) |
| Layout | `test/agent-packages/evals/logging-l2-troubleshooting/` (per-package, self-contained) |
| Cluster fixtures | Stay in `test/agent-packages/scenarios/`, linked from eval cases by ID |
| Fixtures | `fluentbit-config-syntax`, `fluentbit-oom`, `opensearch-flood-stage-readonly`, `operator-helm-bad-image` (negative-case), `fluentbit-cpu-throttle`, `graylog-gelf-input-size-too-small` |
| Prompt language | English. Engineer-driven prompts are written in English regardless of the source ticket language. |
| Variance | `--repeat 3` by default, overridable |
| CI | Local-only; CI wiring is a follow-up |

---

## 3. Architecture

### 3.1. Layout

```
agent-packages/logging-l2-troubleshooting/
├── apm.yml
├── README.md
└── .apm/                                # the package itself (skills, shared)

docs/agent-packages/
└── eval-pipeline-design.md              # this document

test/agent-packages/
├── scenarios/                           # cluster-side artefacts (apply.sh, revert.sh, values-patch.yaml)
│   ├── fluentbit-config-syntax/
│   ├── fluentbit-oom/
│   ├── opensearch-flood-stage-readonly/
│   ├── operator-helm-bad-image/
│   ├── fluentbit-cpu-throttle/
│   └── graylog-gelf-input-size-too-small/
└── evals/
    └── logging-l2-troubleshooting/
        ├── Makefile                     # entry point: make eval, make eval-<case>
        ├── promptfooconfig.yaml         # providers, assertions
        ├── orchestrator.sh              # per-case apply → eval → revert
        ├── prep-workdir.sh              # apm install into a fresh dir per variant
        ├── judge-prompt.txt             # rubric template for llm-rubric (.txt because promptfoo's processFileReference rejects .md)
        ├── aggregate.sh                 # results JSON → summary.md
        ├── providers/
        │   ├── agent.yaml               # claude-agent-sdk + haiku-4.5
        │   └── judge.yaml               # claude-agent-sdk + opus-4-7, no tools
        ├── cases/
        │   ├── fluentbit-config-syntax/
        │   │   ├── meta.yaml
        │   │   ├── prompt.txt
        │   │   ├── ground_truth.md
        │   │   └── rubric.yaml
        │   ├── fluentbit-oom/                       # (same four files)
        │   ├── opensearch-flood-stage-readonly/
        │   ├── operator-helm-bad-image/             # negative-case (see §4.6)
        │   ├── fluentbit-cpu-throttle/
        │   └── graylog-gelf-input-size-too-small/
        └── results/                                 # gitignored; promptfoo + aggregated reports
```

Cluster-side artefacts live in `test/agent-packages/scenarios/<id>/` (apply.sh, revert.sh, values-patch.yaml). Eval cases reference them by sharing the same `<id>` directory name. The split is deliberate: scenarios are reusable cluster fault injectors (also driveable by hand), eval cases are the harness wiring (prompt, rubric, ground truth) for one skill package.

### 3.2. Data flow of one fixture run

```
make eval
  └─ orchestrator.sh
       run_id=$(date +%Y%m%dT%H%M%S)
       for case in cases/*/:
         workdir_with=$(prep-workdir.sh "$case" with-pkg "$run_id")  # apm install here
         workdir_no=$(prep-workdir.sh   "$case" no-pkg   "$run_id")  # empty dir
         test/agent-packages/scenarios/fixture.sh apply "${meta.id}"
         promptfoo eval \
             --config promptfooconfig.yaml \
             --vars case=$case,workdir_with=...,workdir_no=... \
             --repeat 3 \
             --output results/$run_id/$case.json
         test/agent-packages/scenarios/fixture.sh revert "${meta.id}"
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
      ├─ skill-used: <expected_area>                # from meta.yaml; dropped when expected_area=none (operator-helm-bad-image)
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
- No stale snapshots of skills checked into `cases/*/`. The package itself is the source of truth; the next eval run picks up its current state.
- Workdirs under `$XDG_CACHE_HOME/qubership-logging-l2-evals/<run-id>/` (default `~/.cache/...`) are ephemeral. They live **outside** the source package because `apm install` does a recursive copy of the source — placing the workdir inside the package would copy the workdir into itself until the filesystem hits `ENAMETOOLONG`. `make clean` wipes the cache root.

### 3.4. Cluster lifecycle

`test/agent-packages/scenarios/fixture.sh` is unchanged. Its "one scenario active at a time" policy is honoured by the orchestrator's outer serial loop — promptfoo only ever sees a cluster in a single defined state.

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

Minimum to link an eval case to a cluster scenario and describe the expected outcome. The case directory and scenario directory share the same `id` — no separate `cluster_fixture` field.

```yaml
id: fluentbit-oom                        # also the folder name in test/agent-packages/scenarios/
backend: victorialogs                    # BACKEND env for helmfile baseline
expected_area: fluentbit-troubleshoot    # which area-skill triage should select
expected_recommend_kind: resource-bump   # high-level shape of recommend
description: >
  FluentBit DaemonSet OOMKilled because memory limit is below working set.
  Engineer-driven path: "logs from some pods stopped arriving".
```

### 4.2. `prompt.txt`

Plain text, English, one paragraph at most. Engineer-driven path from `troubleshooting-methodology.md §2.2` — a vague complaint, not a structured handoff. No hints, no leading wording that gives away the area.

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

### 4.6. Negative-case fixtures

A case whose natural target area lies outside this package is encoded as a negative case. The current example is `operator-helm-bad-image`: the symptom belongs to `logging-operator-troubleshoot`, which is listed under "Areas not covered yet" in the L2 triage signal table. The expected behaviour is for triage to **hand back to the engineer with the observation and stop**, not to route into a nearby area-skill as a substitute.

Shape:

- `meta.yaml` sets `expected_area: none`. The rendered promptfoo config drops the second `skill-used` assertion when this value is `none`; `skill-used: logging-l2-triage` still applies.
- `rubric.yaml` replaces the positive `area-correct` check with an inverted `no-misroute` check (pass if no area-specific skill was invoked after triage), and replaces `<symptom>-identified` with a check anchored to the negative case's smoking gun (e.g. `operator-image-pull-identified` for `operator-helm-bad-image`).
- `ground_truth.md` carries a "Negative criteria" section listing the skills and recommends the agent must NOT produce. The judge anchors the negative checks to that section.

---

## 5. Variance, repeats, cost

Default `--repeat 3`, overridable via `make eval REPEATS=5`. Methodology §4 calls for 3–5; 3 is the lower bound that still surfaces non-determinism without tripling cost.

Per full run:

- 6 fixtures × 2 variants × 3 repeats = **36 agent transcripts**
- 36 judge invocations
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

The orchestrator passes both a `.json` and a `.html` path to `promptfoo eval --output`. Per fixture this produces:

- `results/<run-id>/<fix>.json` — raw per-fixture result, consumed by `aggregate.sh`.
- `results/<run-id>/<fix>.html` — static, self-contained `(variant × repeat) → pass/fail, tokens, latency` table for that fixture. Open directly in a browser; no server needed.

The orchestrator adds, on top:

- `results/<run-id>/summary.md` — pass-rate `with-pkg` vs `no-pkg` per fixture and the delta. This is the methodology's primary measure (§3): the number that justifies the skill's existence.

For cross-run browsing (any historical eval, sortable / filterable), use the local promptfoo viewer:

```bash
cd test/agent-packages/evals/logging-l2-troubleshooting
npx promptfoo@latest view   # serves http://localhost:15500, reads ~/.promptfoo/promptfoo.db
```

---

## 8. Vendor-lock-in boundary

Methodology §2 forbids vendor-lock-in. The pipeline isolates the locked surface in one place:

- `providers/agent.yaml` and `providers/judge.yaml` — the only files that name a specific harness and model.
- Adding `(opencode, qwen-2.5-coder)` is a new `providers/opencode.yaml` entry; no fixture file changes.
- The bash script's `apm install --target claude` becomes `--target opencode` for that provider; the fixtures, rubrics, ground truth, and judge prompt stay identical.

---

## 9. Out of scope

- L1 classification eval (no ticket corpus yet).
- CI integration (GitHub Actions, cluster bootstrap inside CI).
- Second `(harness, model)` cell (OpenCode, local 7B).
- Multi-judge majority vote. One Opus judge is enough until we see disagreement noise.
- Parallel fixture execution across multiple kind clusters.
- Cost/budget gating. Track tokens; do not gate yet.
- Regression gating against baseline pass-rates (the "did this PR regress the skill?" question).

---

## 10. Resolved questions

Verified against apm 0.14.1 and promptfoo (latest via `npx promptfoo@latest`).

- **Resolved: `apm install` of a local source.** `apm install <abs-path>/agent-packages/logging-l2-troubleshooting --target claude --frozen --verbose` works from any empty cwd; auto-creates `apm.yml`. `--frozen` requires `apm.lock.yaml`, so the first call in a fresh workdir must use `--update` (deprecated in favour of `apm update`, but accepted) to generate the lock — `prep-workdir.sh` does this on its first invocation, then subsequent runs use `--frozen`. Output layout: `.claude/skills/<skill-id>/SKILL.md` (one dir per skill) and `.claude/rules/<instruction>.md` for the package instruction file. `apm_modules/` is auto-added to `.gitignore`. For the no-pkg variant, leave the workdir empty (no `.claude/`).
- **Resolved: promptfoo `claude-agent-sdk` provider with Claude Code session.** Provider id is `anthropic:claude-agent-sdk` (the bare `claude-agent-sdk` id is not recognised). The provider requires the `@anthropic-ai/claude-agent-sdk` npm package to be resolvable from the cwd (`npm install @anthropic-ai/claude-agent-sdk` in the eval root once). To skip `ANTHROPIC_API_KEY`, set `config.apiKeyRequired: false` — the provider then routes through the local Claude Code session (`~/.claude/.credentials.json` / macOS keychain). Verified by a `pong` round-trip against `claude-haiku-4-5` with `ANTHROPIC_API_KEY` unset.
- **Resolved: `skill-used` assertion.** Type id is `skill-used` (negated: `not-skill-used`). Value is a skill name string, or an object `{pattern: '<glob>', min: N}`. It reads `metadata.skillCalls` populated by the provider — for `anthropic:claude-agent-sdk` this is derived from `Skill` tool invocations (`deriveSkillCalls` in `claude-agent-sdk-*.js`, filters `toolCall.name === "Skill"` and extracts `input.skill`). Errored skill attempts surface in metadata but do not satisfy the assertion. No extra provider config required beyond the standard `anthropic:claude-agent-sdk` setup.
- **Resolved: disabling tools for the judge.** Use `config.custom_allowed_tools: []` on the `anthropic:claude-agent-sdk` provider. (Source: `claude-agent-sdk-*.js` — `custom_allowed_tools` is the override key; `disallowed_tools` is the deny-list; `allow_all_tools` is the escape hatch.) Verified: with `custom_allowed_tools: []`, `claude-opus-4-7` returned `{"ok": true}` and `is-json` passed. No need to fall back to plain Messages.
- **Decision: workdir cleanup policy.** Keep all `$XDG_CACHE_HOME/qubership-logging-l2-evals/<run-id>/` directories. Manual cleanup only (`make clean` or `rm -rf` the cache root) — small footprint per run, valuable for post-mortem of failed evals. The cache lives outside the source package because `apm install` does a recursive copy of the source.

---

## 11. Observed performance

Latest reference numbers from `make eval REPEATS=3` against the current fixture set.
Matrix: `(claude-agent-sdk, claude-haiku-4-5)` agent, `(claude-agent-sdk, claude-opus-4-7)` judge.

| Fixture | with-pkg | no-pkg | delta | with-pkg mean X/N | triage-ran (with / no) |
|---|---|---|---|---|---|
| fluentbit-config-syntax            | 0.83 | 0.03 | +0.80 | 4.0/6 | 3/3 vs 0/3 |
| fluentbit-oom                      | 0.83 | 0.00 | +0.83 | 4.0/6 | 3/3 vs 0/3 |
| opensearch-flood-stage-readonly    | 0.69 | 0.03 | +0.66 | 2.3/6 | 3/3 vs 0/3 |
| operator-helm-bad-image            | 0.94 | 0.11 | +0.83 | 5.3/6 | 3/3 vs 0/3 |
| fluentbit-cpu-throttle             | 0.75 | 0.08 | +0.67 | 3.0/6 | 3/3 vs 0/3 |
| graylog-gelf-input-size-too-small  | 0.75 | 0.00 | +0.75 | 3.0/6 | 3/3 vs 0/3 |

Notes:

- Every fixture shows a clear positive delta; with-pkg always beats no-pkg, on every repeat, on every fixture.
- `skill-used: logging-l2-triage` fires deterministically per branch. No-pkg invariably falls back to `superpowers:systematic-debugging`.
- `operator-helm-bad-image` (negative-case) earns the highest with-pkg score — the package keeps triage from misrouting into a covered area-skill.
- `opensearch-flood-stage-readonly` has the largest gap to full pass (2.3/6 with-pkg). The OpenSearch path requires combining `_cluster/settings` evidence with per-index `read_only_allow_delete` evidence; missing either drops two checks. Worth targeted rubric or skill-content review.
- The eval is not saturating at haiku-tier — headroom remains on every case except `operator-helm-bad-image`, which is by design coarse (hand-back is binary).

### Known limitations

- Per-check `pass-rate` from the judge's `checks[]` array is not surfaced in the aggregator. Promptfoo keeps only the `reason` string from the judge response, so we recover only mean X/N from the reason text via regex. To get per-check rates we need a custom assertion that side-writes the judge JSON, or a promptfoo patch.
- `tokenUsage` and `cost` are reported per provider call, but the judge component's `cost` field is `0` on the agent-sdk path; reported cost is agent-only.

### Follow-ups

- Capture per-check pass-rates via a custom assertion that side-writes the judge JSON, then teach `aggregate.sh` to emit a per-check table. Required before targeted rubric tuning is meaningful.
- Add the `logging-operator-troubleshoot` skill. When it exists, swap `operator-helm-bad-image`'s expected handling from `no-misroute` to a positive `area-correct` against the new skill, and drop the negative-case shape from §4.6.
- Add a second `(harness, model)` cell once OpenCode + a local model is on the workstation. The locked surface is isolated to `providers/*.yaml`, so this is a single-file change per cell.
- Wire CI bootstrap (kind + helmfile) and a regression-gating threshold. Suggested initial gate: with-pkg mean ≥ 0.6 and delta ≥ +0.5 on every fixture.
