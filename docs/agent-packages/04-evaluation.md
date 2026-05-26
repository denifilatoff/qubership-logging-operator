# 4. Evaluation

A skill exists to make a weak model behave like a stronger one in a narrow area. Until that effect is demonstrated, a
skill is a hypothesis, not a deliverable. Evaluation is part of skill authorship, not an external afterthought.

This document defines _what_ we measure, _against what baseline_, and the shape of the pipeline that runs the
measurement.

## 4.1. Capability tier, not a specific model

Skills are tuned for and graded on the **lowest capability tier the platform must support** — a small,
instruction-following model with web tools (`WebSearch`, `WebFetch`) disabled.

The lowest tier today is a small frontier model in a hosted coding-agent harness (e.g. Claude Haiku in Claude Code).
Tomorrow it may be a 7B-class open-weights model (Qwen2.5-Coder, Llama, DeepSeek-Coder) in OpenCode, Codex, or another
harness.

Skills, fixtures, and the eval cycle are written against the _capability tier_, not against a specific
`(model, harness)` pair. **No vendor lock-in:** a skill must not depend on Claude-only tool names, Anthropic-specific
prompt-cache semantics, or any one harness's loader.

The web-tools disable approximates the customer environment where this stack typically runs (closed networks) and forces
skills to carry their own knowledge instead of relying on online lookup.

Stronger models (Sonnet / Opus / GPT-5-class) may be used during _authoring_ but are not the grading model — a skill
that only works on a top-tier model has not earned its place.

## 4.2. Primary measure — skill vs no-skill on the same model

Every fixture runs twice on the same target-tier model: once with the skill package installed, once with it absent. If
the rubric cannot distinguish the two transcripts, the skill is not yet justified.

This is the load-bearing comparison; anything else is auxiliary. It is the only comparison that answers the question
"did the skill help, or would the model have got there anyway?". A passing run on a top-tier model with internet access
tells us almost nothing.

## 4.3. Dimensions

- **Effectiveness** — graded by a per-fixture rubric (4–6 binary checks: correct routing, correct area chosen,
  `recommend` produced, recommend matches ground truth, read-only discipline held, …). The rubric is scored by an
  **LLM-judge** against the captured transcript. Binary on purpose — keeps the judge from sliding into 0.6 / 1.0 partial
  scores. Fewer than 4 underspecifies; more than 6 means the judge drifts.
- **Tokenomics** — total input + output tokens, cache-hit rate, wall-clock, tool-call count. Reported per fixture and
  per skill. A skill that doubles success rate while tripling token cost is a different trade-off than one that doubles
  success at flat cost; both numbers ship together.
- **Variance** — multiple runs per fixture (3–5) to surface non-determinism on the weak model. A skill that passes 5/5
  on a strong model and 2/5 on the target tier is not yet stable.

## 4.4. Judge separation

The judge runs on a _stronger_ model than the agent under test and **never on the same model that produced the
transcript**. Same-model judging contaminates the score (the model is good at recognising its own reasoning patterns).

Practical pattern: agent on the target-tier model, judge on a top-tier model from the same or a different provider. The
judge receives only the captured transcript, the ground-truth document, and the rubric checks; it has no tools.

## 4.5. Harness × model matrix

The eval is parameterised by `(harness, model)`. At minimum one pair from the lowest capability tier is active. As soon
as a second harness or a local-model runtime is in regular use, that pair joins the matrix.

A change to a skill must pass on every active pair before merge. Adding a new pair means writing a runner adapter, not
rewriting the skill or its fixtures.

## 4.6. Eval shape differs by level

- **L2 eval is end-to-end.** Input: a vague engineer complaint + a live cluster carrying an injected fault. Output: the
  agent's transcript ending in a `recommend`. Fixtures are reversible cluster manipulations paired with a ground-truth
  recommend. The chain `<domain>-l2-triage → <expert>-troubleshoot` is graded as a chain, because the triage step is
  what selects the expert in production.
- **L1 eval is classification.** Input: the verbatim text of a historical ticket. Output: the L1 handoff envelope (scope
  axis, chosen area, outcome). Fixtures are a labelled corpus of past tickets; no cluster required. The rubric grades
  each field of the envelope against the human-marked label.

## 4.7. Pipeline architecture

A pipeline that satisfies §4.2–4.6 has the following moving parts. The specific framework choice is secondary; the
architecture is not.

### Off-the-shelf framework, not a bespoke runner

Maintaining a custom runner — multi-provider auth, transcript capture, judge plumbing, variance loop, reporting — would
compete for engineering time with the skills themselves. Use an existing evaluation framework that supports
multi-provider models, agent-harness drivers (Claude Code, OpenCode, Codex), LLM-judge with portable rubrics, N-run
variance, transcript capture with tool calls and token usage, and portable fixture formats.

This repo currently uses `promptfoo` for these reasons. The choice is revisitable; the architecture below does not
depend on it. (The survey that produced the choice is in git history.)

### Scenarios vs cases — two-level split

```text
test/agent-packages/
├── scenarios/                # reusable cluster failure injectors
│   └── <slug>/
│       ├── apply.sh          # introduces the failure
│       ├── revert.sh         # restores baseline
│       └── README.md         # what breaks, mechanics
└── evals/<package>/          # per-package eval harness
    └── cases/<slug>/         # one case per scenario this package covers
        ├── meta.yaml         # scenario id, expected area, expected recommend kind
        ├── prompt.txt        # vague engineer complaint
        ├── ground_truth.md   # expected diagnosis + recommend
        └── rubric.yaml       # 4-6 binary checks
```

**Why split:** a scenario is a cluster manipulation; multiple skill packages can grade themselves against the same
scenario. The case slug equals the scenario slug — no mapping needed. The scenarios can also be driven by hand for
engineer-led debugging.

### A/B mechanism: package install vs no install

The agent under test runs in a workdir prepared per case and per variant:

- **with-pkg** — `apm install <package-path>` into an empty workdir.
- **no-pkg** — empty workdir, no `apm install`.

This grades **package installation**, not "SKILL.md file present vs absent". Consequences:

- The eval tests the same surface a real user sees. If install ever silently breaks the package's deployment to the
  target harness, the eval catches it.
- No stale snapshots of skills checked into the eval directory. The package itself is the source of truth; the next eval
  run picks up its current state.
- Workdirs live in a cache outside the source package — `apm install` does a recursive copy of the source, so a workdir
  _inside_ the package would recursively copy itself.

### Cluster lifecycle as precondition

Bringing up the cluster baseline (kind, helmfile, or equivalent) is the engineer's responsibility, not the pipeline's.
The pipeline asserts the baseline is clean before starting, applies one scenario at a time (serial; "one scenario
active" is enforced by the scenario runner), runs the eval, reverts the scenario, and moves on.

```text
make eval
  └─ for each case:
       prep workdir (with-pkg)   ← apm install
       prep workdir (no-pkg)     ← empty
       fixture.sh apply <slug>
       eval framework runs:
         testCase × variant × repeat
           agent transcript captured
           judge graded against rubric
       fixture.sh revert <slug>
     aggregate → summary
```

### Reporting

Per fixture: pass-rate `with-pkg` vs `no-pkg`, the delta, tokens, latency, per-variant transcripts. The delta is the
load-bearing number — the one that justifies the skill's existence.

### Vendor-lock-in boundary

The locked surface is isolated to a small number of provider-config files (one per `(harness, model)` cell). Adding
`(opencode, qwen-2.5-coder)` is a new provider file; fixtures, rubrics, ground truth, and judge prompt stay identical.
Anything else in the pipeline that names a specific harness or model is a bug.

## 4.8. Failure handling

| Failure                                 | Behaviour                                                                                                    |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| Scenario `apply` fails                  | Mark the case `error: apply-failed`. Skip the eval for it. **Always** call `revert` (idempotent). Move on.   |
| Agent crashes or exceeds timeout        | Recorded as `error`. Continue with remaining variants and revert at the end.                                 |
| Judge times out or returns invalid JSON | Graded `error`, not `fail`. Surfaces in the report distinctly from "skill failed".                           |
| `revert` fails                          | Stop the world. Cluster is dirty; further cases would compound the error. Leave state for manual inspection. |

Serial execution is preserved by the "one scenario active" invariant. Parallelism would require either multiple clusters
or namespace-level scenario isolation, which the scenario runner does not currently support.
