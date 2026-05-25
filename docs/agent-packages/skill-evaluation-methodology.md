# Skill Evaluation Methodology

**Status:** draft v0.1. Standalone draft; final home (this package, a sibling package, or repo-root `docs/`) to be decided.

This document defines how skills in this repository are evaluated. It is a sibling to `troubleshooting-methodology.md`: that one defines *what skills do*; this one defines *how we decide a skill is good enough to ship*.

---

## 1. Why we evaluate

A skill exists to make a weak model behave like a stronger one in a narrow area. Until that effect is demonstrated, a skill is a hypothesis, not a deliverable. Evaluation is part of skill authorship, not an external afterthought.

A passing run on a strong model with internet access tells us almost nothing: the strong model would likely have solved the case unaided. The interesting question is always *the delta the skill creates on the model that needs the help*.

---

## 2. Capability tier, not a specific model

Skills are tuned for and graded on the **lowest capability tier the platform must support** — a small, instruction-following model with web tools (`WebSearch`, `WebFetch`) disabled. The lowest tier today is **Claude Haiku 4.5 in Claude Code**; tomorrow it may be a 7B-class open-weights model (Qwen2.5-Coder, Llama, DeepSeek-Coder) in OpenCode, Codex, or another harness.

Skills, fixtures and the eval cycle are written against the *capability tier*, not against a specific `(model, harness)` pair. No vendor lock-in: a skill must not depend on Claude-only tool names, Anthropic-specific prompt-cache semantics, or any one harness's loader.

The web-tools disable approximates the customer environment where this stack typically runs (closed networks) and forces skills to carry their own knowledge instead of relying on online lookup.

Stronger models (Sonnet, Opus) may be used during authoring but are not the grading model — a skill that only works on Opus has not earned its place.

---

## 3. Primary measure — skill vs no-skill on the same model

Every fixture runs twice on the same target-tier model: once with the skill loaded, once with it absent. If the rubric cannot distinguish the two transcripts, the skill is not yet justified.

This is the load-bearing comparison; anything else is auxiliary. It is the only comparison that answers the question "did the skill help, or would the model have got there anyway?".

---

## 4. Dimensions

- **Effectiveness** — graded by a per-fixture rubric (4–6 binary checks: correct routing, correct area chosen, `recommend` produced, `recommend` matches ground truth, read-only discipline held, …). The rubric is scored by an **LLM-judge** against the captured transcript. The judge runs on a stronger model than the agent and never on the same model that produced the transcript.
- **Tokenomics** — total input + output tokens, cache-hit rate, wall-clock, tool-call count. Reported per fixture and per skill. A skill that doubles success rate while tripling token cost is a different trade-off than one that doubles success at flat cost; both numbers ship together.
- **Variance** — multiple runs per fixture (3–5) to surface non-determinism on the weak model. A skill that passes 5/5 on a strong model and 2/5 on the target tier is not yet stable.

---

## 5. Harness and model matrix

The eval is parameterised by `(harness, model)`. At minimum one pair from the lowest capability tier is active — today `(claude-code, haiku-4.5)`. As soon as a second harness or a local-model runtime is in regular use, that pair joins the matrix.

A change to a skill must pass on every active pair before merge. Adding a new pair means writing a runner adapter, not rewriting the skill or its fixtures.

---

## 6. Test execution

The eval cycle runs through an **off-the-shelf evaluation framework**, not a bespoke shell harness. Maintaining a custom runner — multi-provider auth, transcript capture, judge plumbing, variance loop, reporting — would compete for engineering time with the skills themselves.

The framework must:

- speak to multiple model providers (Anthropic API, OpenAI-compatible, local via ollama / llama.cpp);
- drive at least one supported harness end-to-end (today: Claude Code; later: also OpenCode or similar);
- record full transcripts including tool calls and token usage;
- support per-fixture rubrics scored by an LLM-judge;
- support N-run variance per fixture;
- keep fixture definitions portable enough to migrate between runners.

The exact framework (candidates include `inspect-ai`, `promptfoo`, `deepeval`) is the output of an industry survey and is committed in the eval-framework spec.

---

## 7. Different eval shapes for L1 and L2

- **L2 eval** is end-to-end. Input: a vague engineer complaint + a live cluster carrying an injected fault. Output: the agent's transcript ending in a `recommend`. Fixtures are reversible cluster manipulations paired with a ground-truth recommend. The chain `logging-l2-triage → <area>-troubleshoot` is graded as a chain, because the triage step is what selects the area-skill in production.
- **L1 eval** is classification. Input: the verbatim text of a historical ticket. Output: the L1 handoff envelope (scope axis, chosen area, outcome). Fixtures are a labelled corpus of past tickets; no cluster required. The rubric grades each field of the envelope against the human-marked label.

---

## 8. Out of scope

Implementation detail lives in a separate eval-framework spec: fixture format and storage, runner choice, LLM-judge prompts, CI integration, regression gating, the L1 ticket corpus, model-matrix CI cost. This methodology only fixes *what* is measured, *against what baseline*, and *which constraints* the framework must satisfy.
