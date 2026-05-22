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
    ├── .work/                           # gitignored; ephemeral run workdirs
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
  workdir=evals/.work/<run-id>/<fixture-id>/<variant>
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
- Workdirs under `evals/.work/<run-id>/` are ephemeral. Keep across runs for debugging or wipe.

### 3.4. Cluster lifecycle

`deploy/kind/fixtures/fixture.sh` is unchanged. Its "one fixture active at a time" policy is honoured by the orchestrator's outer serial loop — promptfoo only ever sees a cluster in a single defined state.

Cluster baseline (kind cluster + helmfile baseline per the chosen `BACKEND`) is a **precondition**, not the pipeline's responsibility. The engineer runs the baseline once per session. Before starting, the orchestrator calls `fixture.sh status` and refuses to run if any fixture is already active — a clean baseline state is required so that the first `apply` lands on top of a known surface. Validating that kind + helmfile baseline themselves are healthy is left to the engineer (and, later, to CI).

### 3.5. Judge — same harness, different model, no API key

Both the agent under test and the judge go through `promptfoo`'s `claude-agent-sdk` provider, which authenticates via the local Claude Code session. This avoids requiring an Anthropic API key in this repo.

| Role | Provider | Model | Tools | Working dir |
|---|---|---|---|---|
| Agent under test | `claude-agent-sdk` | `claude-haiku-4-5` | full Claude Code toolset | `.work/<run-id>/<fix>/<variant>/` |
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

## 10. Open questions

- **`apm install` of a local source.** `apm install <abs-path-to-package>` is the assumed syntax for installing from a local directory; the exact form to be confirmed against the running APM CLI before the implementation plan lands.
- **promptfoo `claude-agent-sdk` and Claude Code session pickup.** Needs to be verified that promptfoo's provider does pick up the local subscription session and does not require `ANTHROPIC_API_KEY`. If it falls back to API key, we either set the key for the eval and accept the cost, or switch to a small adapter that shells out to `claude` CLI.
- **`skill-used` assertion shape.** Promptfoo's `skill-used` assertion is mentioned in the survey; the exact semantics ("any skill" vs "this specific skill") to be confirmed before writing assertions.
- **Disabling tools for the judge.** The judge entry assumes `claude-agent-sdk` lets us run a model with all tools disabled (or only `Read` enabled). If the provider does not expose tool-gating, the judge falls back to plain Anthropic Messages via the same session token, or to a tools-allowed but prompt-restricted call.
- **Workdir cleanup policy.** Wipe `.work/<run-id>/` after each run, keep last N, or keep all? Default to "keep all, gitignored" for v1.
