# Eval Framework Survey for Skills

**Status:** draft v0.1. Companion to `skill-evaluation-methodology.md` — picks a concrete tool against the requirements stated there.

Goal: an off-the-shelf framework that satisfies `skill-evaluation-methodology.md §6`:

- multi-provider models (Anthropic API, OpenAI-compatible, local via ollama / llama.cpp);
- drives at least one supported agent harness end-to-end (today: Claude Code; later: OpenCode);
- records transcripts including tool calls and token usage;
- per-fixture rubrics scored by an LLM-judge;
- N-run variance per fixture;
- portable fixture format.

---

## 1. Candidates

Surveyed May 2026. Excluded: framework-specific tools (LangSmith), pure observability (Langfuse, Arize Phoenix — used in production tracing, not gating evals), commercial-only platforms (Braintrust).

| Tool | License | Harness driving | Multi-provider | LLM-judge | Variance | Skill-aware |
|---|---|---|---|---|---|---|
| **promptfoo** | MIT (OpenAI-owned since Mar 2026, core stays open) | First-class providers for Claude Agent SDK, Codex SDK, OpenCode SDK | Anthropic, OpenAI, Google, Bedrock, Azure, local (llama.cpp, Transformers.js) | `llm-rubric`, `g-eval`, `factuality`, multi-judge | `--repeat N` flag | **Yes** — `skill-used` / `not-skill-used` assertions; dedicated "Test Agent Skills" guide |
| **inspect-ai** (UK AISI) | MIT | External CLI agents (Claude Code, Codex CLI, Gemini CLI) via Agent Bridge | Anthropic, OpenAI, Google, Mistral, Bedrock, Azure, **vLLM, Ollama, llama-cpp-python** | `model_graded_fact`, custom scorers | Epochs supported, requires wiring | No skill-specific primitives — generic agent eval |
| **DeepEval** | Apache-2.0 (paid dashboard) | Pytest plugin, not a harness driver | Python-side, any provider via wrapper | 50+ metrics, G-Eval, tool-call correctness | Built-in | No |
| **skill-creator** (Anthropic) | Anthropic plugin | Drives Claude Code subagents directly | Anthropic-only | Custom grader subagent | Manual loop | Yes — but Claude-Code-locked |

---

## 2. Match against requirements

| Requirement | promptfoo | inspect-ai | DeepEval |
|---|---|---|---|
| Multi-provider (incl. local) | ✓ | ✓ | ✓ (wrapper) |
| Drives Claude Code | ✓ via `claude-agent-sdk` provider | ✓ via Agent Bridge | ✗ |
| Drives OpenCode | ✓ via `opencode` provider | △ (custom adapter needed) | ✗ |
| Skill-vs-no-skill A/B | ✓ — swap `SKILL.md` between fixture dirs; documented example | △ — wire two task variants by hand | △ |
| Routing assertion (which skill fired) | ✓ — `skill-used` is a first-class assertion type | ✗ — generic, must hand-roll | ✗ |
| LLM-judge with rubric | ✓ — `llm-rubric`, multi-judge | ✓ — `model_graded_fact` | ✓ — G-Eval |
| Variance / N-runs | ✓ — `--repeat N` | ✓ — epochs | ✓ |
| Token + latency capture | ✓ — built into output table | ✓ — model usage logs | ✓ |
| Portable fixtures (YAML) | ✓ | △ (Python `@task`) | ✗ (Python only) |
| Local-only (no SaaS) | ✓ | ✓ | ✓ |

---

## 3. Recommendation

**Pick `promptfoo` for the first version of the eval cycle.** Migration to `inspect-ai` remains a fallback if promptfoo direction changes post-acquisition.

Why promptfoo:

1. **Skill-aware primitives.** Promptfoo ships first-class providers for **Claude Agent SDK, OpenAI Codex SDK, and OpenCode SDK**, and a `skill-used` assertion that normalises across all three. Every other framework would need a custom adapter and a hand-rolled "which skill fired" check.
2. **The skill-comparison pattern is the eval pattern we already want.** The documented example keeps fixtures identical and swaps only `SKILL.md` between `v1/` and `v2/` directories. Skill-vs-no-skill (our §3 primary measure) is just "v1 = with-skill, v2 = no-skill" — same mechanism, no extra code.
3. **YAML config is reviewable.** A fixture is a YAML file; a skill change PR diff shows directly which assertions moved. Inspect-ai's Python `@task` decorators are more powerful but worse for review.
4. **Multi-provider matrix is one config block.** Running the same fixture set against `(claude-agent-sdk, haiku-4.5)` and `(opencode, qwen2.5-coder-via-ollama)` is a list of providers, not two separate runners.
5. **OpenAI acquisition risk is bounded.** Core remains MIT and the team has publicly committed to keep it model-agnostic. We pin a version and own the fixture files.

Why not inspect-ai (yet):

- More general, fewer batteries for *our specific* problem ("did this skill fire and was its output right").
- Agent Bridge for external CLIs is documented but lower-level — we'd build the skill-vs-no-skill scaffolding ourselves.
- Stronger choice if we eventually need adversarial / safety-style evals; weaker for routine skill-iteration runs.

Why not Anthropic's skill-creator:

- Violates §2 (vendor lock-in to Claude Code).
- The pattern (Executor / Comparator / Grader / Analyzer + benchmark mode) is exactly right; we reproduce that pattern *on top of promptfoo*, not adopt the tool itself.

---

## 4. First-version plan (sketch, not a commitment)

Lives in `evals/` alongside skills:

```
evals/
├── promptfooconfig.yaml          # providers + matrix
├── fixtures/
│   ├── l2-fluentbit-oom/
│   │   ├── fault.yaml            # cluster perturbation
│   │   ├── revert.yaml
│   │   ├── prompt.txt            # vague engineer complaint
│   │   ├── ground_truth.md       # expected recommend
│   │   └── rubric.yaml           # 4-6 binary checks for llm-rubric
│   └── ...
└── README.md
```

Provider matrix in `promptfooconfig.yaml`:

```yaml
providers:
  - id: anthropic:claude-agent-sdk
    label: claude-code+haiku
    config:
      model: claude-haiku-4-5
      working_dir: ./fixtures/<id>/with-skill
      skills: ['logging-l2-triage']
  - id: anthropic:claude-agent-sdk
    label: claude-code+haiku NO-SKILL
    config:
      model: claude-haiku-4-5
      working_dir: ./fixtures/<id>/no-skill   # SKILL.md absent
```

Run: `promptfoo eval --repeat 5` → table of pass-rate / tokens / latency per `(harness, model, with-skill?)`.

Implementation of the actual cycle (CI wiring, cluster lifecycle for L2 fixtures, the L1 ticket corpus, judge prompt content) lives in a separate spec.

---

## 5. Open questions

- **L2 cluster lifecycle.** Promptfoo doesn't know about kind / kubectl. A pre-test hook or a wrapper script applies `fault.yaml`; a teardown hook reverts. Hook surface to be confirmed against current promptfoo docs.
- **OpenCode + local model on customer-realistic hardware.** Need to validate that a 7B-class model in OpenCode can actually drive the L2 triage chain at all, before treating that pair as a serious matrix cell.
- **Judge model leakage.** Judge must not be the same model that produced the transcript. Easiest constraint: judge = strong cloud model (Opus / GPT-5-class) regardless of which model produced the transcript.
- **Cost of the matrix.** N fixtures × M providers × 5 repeats × (with-skill + no-skill) × judge tokens. A small back-of-envelope is needed before turning on CI.

## Sources

- [Inspect AI — UK AISI](https://inspect.aisi.org.uk/)
- [Inspect AI agents documentation](https://inspect.aisi.org.uk/agents.html)
- [Promptfoo — Test Agent Skills guide](https://www.promptfoo.dev/docs/guides/test-agent-skills/)
- [Promptfoo — Agent Skills integration](https://www.promptfoo.dev/docs/integrations/agent-skill/)
- [Promptfoo — Claude Agent SDK provider](https://www.promptfoo.dev/docs/providers/claude-agent-sdk/)
- [Anthropic — Improving skill-creator: Test, measure, and refine Agent Skills](https://claude.com/blog/improving-skill-creator-test-measure-and-refine-agent-skills)
- [Top 5 AI Agent Eval Tools After Promptfoo's Exit (DEV)](https://dev.to/thedailyagent/top-5-ai-agent-eval-tools-after-promptfoos-exit-576i)
- [DeepEval alternatives 2026 (Braintrust)](https://www.braintrust.dev/articles/deepeval-alternatives-2026)
