# Evaluation Framework for AI Coding-Agent Skills (qubership-monitoring-operator troubleshooting)

## TL;DR
- **Winner: Inspect AI (UKGovernmentBEIS/inspect_ai)** paired with the **inspect_swe** companion package and the **inspect_k8s_sandbox** plugin. It is the only off-the-shelf framework that satisfies every must-have: MIT-licensed, multi-provider (Anthropic, OpenAI-compatible, Ollama, llama.cpp, vLLM), drives Claude Code / Codex CLI / Gemini CLI / OpenCode / Mini-SWE-Agent as first-class solvers, captures multi-turn transcripts with per-turn token + cache_read/write counts, has a built-in `model_graded_qa` judge bound to a `grader` role distinct from the agent under test, runs N-trial variance via `epochs` with `mean`/`stderr`/`variance`/`pass_at` reducers, and natively supports both classification-style scorers and external-state verifier scripts (custom `Scorer` + Docker/Kubernetes sandbox).
- **Runner-up: Arize Phoenix + MLflow Evaluation** — strong observability, but Phoenix's Elastic License 2.0 is a hard pass for an internal-plus-OSS dual strategy, and neither product drives Claude Code or OpenCode as a turn-key harness; you would still write the agent-harness glue yourself.
- **Hard rejects: Promptfoo** (OpenAI is acquiring it as of March 2026, strategic risk), **DeepEval** (instrument-your-app model, not a harness driver; no cluster-state verifier idiom), **LangSmith** (closed-source platform, self-hosting is an Enterprise add-on that requires a license key and outbound egress to `beacon.langchain.com`), **Braintrust** (closed-source SaaS with hybrid-deployment-only self-host requiring a Brainstore license key), **Anthropic skill-creator** (Claude-only, no Kubernetes verifier, no multi-provider).

## Key Findings

### Why Inspect AI wins on every must-have

| Must-have | Inspect AI evidence |
|---|---|
| 1. Multi-provider (Anthropic + OpenAI-compat + local Ollama/llama.cpp) | Documented providers include Anthropic, OpenAI, OpenAI-compatible endpoints, Ollama (`ollama/<model>`), llama-cpp-python, vLLM, SGLang, Bedrock, Azure, Together, Groq, OpenRouter, Hugging Face. Selection is a CLI flag: `inspect eval task.py --model anthropic/claude-haiku-4-5` or `--model ollama/qwen2.5-coder`. |
| 2. Agent-loop harness integration (Claude Code priority, OpenCode within 6 months) | The `inspect_swe` package (MIT, Meridian Labs, latest release **0.2.55 on May 16 2026**, **30 PyPI releases between Nov 27 2025 and May 16 2026 — 27 stable plus 3 pre-releases**) ships `claude_code()`, `codex_cli()`, `gemini_cli()`, **`opencode()`**, and `mini_swe_agent()` solvers. Each runs the real CLI binary inside an Inspect sandbox and proxies model API calls back to Inspect, so model swaps and limits work transparently. |
| 3. Transcript capture incl. tool calls, token usage, cache read/write | `EvalLog` is a JSON/`.eval` (zstd) artifact with per-sample `events`, full `messages`, `ModelUsage` containing `input_tokens`, `output_tokens`, `input_tokens_cache_read`, `input_tokens_cache_write`, `reasoning_tokens`, plus optional `total_cost`. Read via `read_eval_log()` / `inspect log dump --json`. Format documented and stable, with `inspect log convert` for migration. |
| 4. LLM-judge with separate model | `model_graded_qa()` and `model_graded_fact()` scorers; the judge model is bound to the `grader` role via `model_roles={"grader": "openai/gpt-4o"}` while the solver uses the default model. The framework explicitly separates the two so judge-on-self is observable. |
| 5. N-trial variance | `Task(..., epochs=Epochs(5, reducer="mean"))` runs every sample N times. Built-in reducers: `mean`, `variance`, `stddev`, `bootstrap_stderr`, `pass_at(k)`, `at_least(k)`, `max`. The Inspect View log viewer can sort samples by epoch to expose per-trial variance directly. |
| 6a. Classification-style evals | Custom `@scorer` returning structured `Value` (dict of fields → CORRECT/INCORRECT/PARTIAL). Standard `accuracy()`, `f1`, `mean` metrics ship in `inspect_ai.scorer`. |
| 6b. End-to-end with live K8s + post-run verifier | `inspect_k8s_sandbox` (separate MIT package at github.com/UKGovernmentBEIS/inspect_k8s_sandbox) provisions a real K8s pod per sample; you inject the fault in the sample `setup` Solver, run the agent, then a custom `Scorer` execs `kubectl`/Helm checks against the live cluster and returns Score+explanation. The pattern is the same one AISI uses for cyber CTF evals. |
| 7. Portable fixtures | Datasets are plain JSON, JSONL, CSV, YAML, or HuggingFace datasets via `json_dataset()`, `csv_dataset()`, `hf_dataset()`. No proprietary DSL. Tasks are Python decorated with `@task`. |
| 8. Reproducibility primitives | `eval()` and Task record `model`, model version, `GenerateConfig` (temperature, top_p, seed where supported), git revision (`EvalRevision` now tracks `dirty` working-tree state), `epochs`, `metadata`, and per-sample `ModelEvent` request/response JSON. Caching by content hash. |

License: MIT, verified on PyPI metadata and `LICENSE` on GitHub. Active maintenance is overwhelming — `inspect_ai 0.3.222` was released on May 18 2026 and v0.3.223 followed on May 20 2026, with weekly minor releases throughout 2026.

### Why this matters operationally for the qubership-monitoring-operator skills

- The "tomorrow" target is 7B-class open-weights coding models in OpenCode. Inspect SWE's `opencode()` solver and Ollama provider mean a single fixture file like `troubleshoot-prom-target-down.yaml` can be swept across `anthropic/claude-haiku-4-5`, `ollama/qwen2.5-coder:7b`, `ollama/deepseek-coder:6.7b`, and a vLLM-served Llama, without rewriting the fixture. Tool emulation is supported on Ollama for models with weak native tool calls (`-M emulate_tools=true`).
- The K8s sandbox provider mounts a per-sample namespace, so you can deploy a broken qubership-monitoring-operator chart, let the agent run kubectl/helm/promtool commands via Claude Code's Bash tool, and then a verifier scorer asserts e.g. "the `monitoring-collector` DaemonSet now has `status.numberReady == status.desiredNumberScheduled`" — exactly the "deterministic verifier checking cluster state AFTER the run" requirement.
- Anti-pattern detection (|Δ| < 5pp; σ > 0.3): not built in by name, but trivially expressible because the `samples_df` / `evals_df` dataframe APIs expose all per-trial scores. A 30-line Pandas notebook covers it; this remains a custom analytical layer rather than framework-native.

### Runner-up: Arize Phoenix (+ MLflow scorers)

Phoenix is OpenTelemetry-native, has solid tracing, a strong eval/experiments UX, and an Apache-2.0-licensed evaluator skill, but:
- **License is Elastic License 2.0**, not Apache or MIT. ELv2 forbids offering Phoenix "as a hosted or managed service" — a real blocker if the skills product line ever needs to embed evaluation in a hosted offering, and many internal procurement processes treat ELv2 as non-OSI-open-source.
- **No turn-key Claude Code / OpenCode driver.** You instrument the agent yourself with OpenInference; long agent transcripts render as a span tree, not as a first-class "run the CLI in a sandbox" loop.
- **Online evals and the Alyx copilot are paywalled in Arize AX.**
- Best fit if you wanted to instrument the existing Claude Code workflows in production; weaker for the "synthetic fixtures + matrix sweep" use case here.

### Rejection table

| Framework | License | Disqualifier | Evidence |
|---|---|---|---|
| **promptfoo** | MIT (today) | **Acquired by OpenAI, announced March 9 2026 — pending close.** Per Ian Webster's own announcement, "More than 350,000 developers have run evals with Promptfoo, 130,000 are active each month, and teams at more than 25% of the Fortune 500 have adopted it." Promptfoo raised $23M total, including an $18.4M Series A (July 2025, led by Insight Partners with Andreessen Horowitz participating) at an $86M post-money valuation. Multi-turn agent support is via the `simulated-user` provider and the OpenAI Agents SDK provider — bolted on, not framework-native, and JS-first. | openai.com/index/openai-to-acquire-promptfoo/; promptfoo.dev/blog/promptfoo-joining-openai; techcrunch.com/2026/03/09/openai-acquires-promptfoo-to-secure-its-ai-agents/; promptfoo.dev/docs/providers/openai-agents/ |
| **DeepEval** | Apache-2.0 | **No agent harness driver.** DeepEval expects you to instrument an existing app (`@observe`, callback handlers for LangChain/CrewAI/Agno) and emit traces — it doesn't run Claude Code or OpenCode for you. No first-class cluster-state verifier idiom; cluster checks would be ad-hoc Python in custom metrics. Confident AI cloud bolted on top. | deepeval.com/docs/getting-started; deepeval.com/guides/guides-ai-agent-evaluation |
| **LangSmith** | Closed-source SaaS (SDK MIT) | **Self-host is Enterprise add-on, requires a license key, and requires outbound egress to `https://beacon.langchain.com` for "Billing telemetry — License verification and subscription/usage reporting (required)."** Strongest with LangGraph; running Claude Code or OpenCode end-to-end requires custom wrapping. | docs.langchain.com/langsmith/self-host-egress; docs.langchain.com/langsmith/self-hosted |
| **Braintrust** | Closed-source platform (some SDKs Apache-2.0) | **Self-hosting requires an Enterprise "hybrid deployment" contract with a Brainstore license key**; the platform itself is not OSS. Best as a CI-eval-regression product, not an agent driver. | laminar.sh/article/braintrust-alternatives-2026; braintrust.dev/docs/guides/self-hosting/aws |
| **Arize Phoenix** | **Elastic License 2.0** (source-available, not OSI open-source) | License blocks hosted-service redistribution; no built-in coding-agent harness driver; agent-eval features in AX are paywalled. | github.com/Arize-ai/phoenix/blob/main/LICENSE; mlflow.org/arize-phoenix-alternative |
| **Weights & Biases Weave** | Apache-2.0 SDK | **Backend is W&B Cloud (SaaS).** Self-hosting Weave's full UI means W&B Server, which is enterprise-licensed. Same instrument-your-app pattern as DeepEval. | github.com/wandb/weave; wandb.ai/site/weave/ |
| **LangChain openevals / agentevals** | MIT | Library of evaluator functions, not a harness or runner. No N-trial primitive, no sandbox, no cluster-state verifier idiom — it would still need to live inside another framework. Useful as a source of judge prompts. | github.com/langchain-ai/openevals |
| **OpenAI Evals** | MIT | OpenAI-centric; multi-provider support is via shims, no agent-harness driver, no Kubernetes sandbox. | github.com/openai/evals |
| **Anthropic skill-creator 2.0** | Apache-2.0 (anthropics/skills) | Claude-only by design; the eval harness is four sub-agents (executor/grader/comparator/analyzer) that work inside Claude Code. **Cannot drive a 7B Qwen-coder in OpenCode** under the same fixture format, no Kubernetes sandbox, no per-trial variance reducer beyond what its own grader.md does. Useful for authoring SKILL.md content, not for the platform-grade matrix sweep this question asks about. | github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md |
| **Helicone** | Apache-2.0 | Proxy/observability tool; not an eval framework with rubrics, N-trial, or cluster-state verifiers. Per Helicone's own announcement (helicone.ai/blog/joining-mintlify, Mar 3 2026): "Helicone has been acquired by Mintlify… Helicone's services will remain live for the foreseeable future in maintenance mode." | helicone.ai/blog/joining-mintlify |
| **Ragas / TruLens** | Apache-2.0 / MIT | Out of scope (RAG-quality metric libraries, not agent harnesses). | mlflow.org/top-5-agent-evaluation-frameworks/ |
| **Galileo / Patronus / Vellum / Humanloop** | Closed-source SaaS | Bound to vendor cloud; fails self-host + license requirements. | vendor docs |
| **SWE-bench / agent-eval / autogen-bench** | Various | Benchmark-specific harnesses; fixture model and verifier are tied to SWE-bench tasks. Not a generic skill-evaluation framework. | github.com/SWE-bench |

## Details

### Architecture of the proposed setup

```
  fixtures/                       # YAML / JSON datasets, portable
    triage_classification.jsonl   # 20+ should_trigger boolean prompts (eval shape A)
    prom_target_down.yaml         # vague task + injected fault recipe   (eval shape B)
    alertmanager_silenced.yaml
    ...
  skills/
    monitoring-triage/SKILL.md    # the procedural-knowledge bundle under test
  tasks/
    triage_task.py                # @task wrapping fixtures with classification scorer
    k8s_task.py                   # @task wrapping fixtures with K8s sandbox + verifier
  verifiers/
    check_target_up.py            # kubectl/promtool assertions, returns Score
  configs/
    cells.yaml                    # matrix: models × harnesses × skill on/off
```

`inspect eval tasks/k8s_task.py --model anthropic/claude-haiku-4-5 --model-role grader=openai/gpt-4o --epochs 5 --sandbox k8s` runs the full matrix; rerun with `--model ollama/qwen2.5-coder:7b --solver inspect_swe/opencode` to sweep the open-weights/OpenCode cell. `--log-dir s3://...` or local `./logs` retains every transcript.

### The judge-model separation primitive

```python
from inspect_ai import Task, task, eval
from inspect_ai.scorer import model_graded_qa
from inspect_swe import claude_code

@task
def triage_skill() -> Task:
    return Task(
        dataset=json_dataset("fixtures/triage_classification.jsonl"),
        solver=claude_code(),                                     # agent under test
        scorer=model_graded_qa(),                                 # uses get_model(role="grader")
        epochs=5,
        sandbox=("docker", "Dockerfile.monitoring"),
    )

eval(triage_skill(), model="anthropic/claude-haiku-4-5",
     model_roles={"grader": "openai/gpt-4o"})
```

`model_graded_qa()` calls `get_model(role="grader")` internally — when no grader role is bound, it falls back to the default model and the eval log will surface this, so judge-on-self contamination is observable.

### Cluster-state verifier shape

```python
from inspect_ai.scorer import Scorer, scorer, accuracy, stderr, Score, CORRECT, INCORRECT
from inspect_ai.util import sandbox

@scorer(metrics=[accuracy(), stderr()])
def target_recovered() -> Scorer:
    async def score(state, target):
        result = await sandbox().exec(
            ["kubectl", "get", "prometheusrule", "-n", "monitoring",
             "-o", "jsonpath={.items[*].status.observedGeneration}"]
        )
        ok = "qubership-target-down" not in result.stdout and result.success
        return Score(value=CORRECT if ok else INCORRECT,
                     explanation=result.stdout + result.stderr)
    return score
```

This is a pattern used in `inspect_evals` cyber and SWE-bench evals already; the K8s sandbox provider runs each sample in an isolated namespace.

### Two confirmed risks for the winner

1. **`inspect_k8s_sandbox` is officially "a useful example of a complex Sandbox Environment provider"** per its own GitHub README, designed within AISI's infrastructure and that "may require further tailoring and adaptation" for other Kubernetes environments. Expect to spend the first sprint stabilising it against your cluster (RBAC, image registry, network policy).
2. **The OpenCode solver is shipped but new**: it appeared as a built-in solver in `inspect_swe` and has had weekly releases through May 2026, but it has many fewer documented production users than the `claude_code()` solver. The docs landing page even links the word "OpenCode" to `github.com/anomalyco/opencode`, which is suspicious enough that you should verify against the source tree before betting fixtures on it. Fall-back: `mini_swe_agent()` is a thin, stable harness that you can use with any Inspect-provider model including Ollama.

### Anti-pattern detection (|Δ| < 5pp, σ > 0.3) — not built in

Inspect does not natively flag low-discrimination or high-variance fixtures. You get the data, but the heuristic is a custom step:

```python
from inspect_ai.analysis import samples_df
df = samples_df("./logs")
agg = df.groupby(["task","sample_id","cell"])["score"].agg(["mean","std"])
flag = (agg.xs("with_skill",level="cell")["mean"]
        - agg.xs("baseline",level="cell")["mean"]).abs() < 0.05
hi_var = agg["std"] > 0.3
```

Treat this as a known gap rather than a disqualifier — every framework in this space delegates the same step to the analyst.

## Recommendations

### Stage 1 — First week (validation spike)
1. `uv pip install "inspect-ai>=0.3.222" "inspect-swe>=0.2.55"` in a clean venv.
2. Set `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, install Docker. Skip Ollama and K8s until step 4.
3. Build one classification fixture (`fixtures/triage_classification.jsonl`, 20 prompts with `should_trigger` boolean) and run:
   `inspect eval tasks/triage_task.py --model anthropic/claude-haiku-4-5 --model-role grader=openai/gpt-4o --epochs 3`
   Open `inspect view` and confirm you see per-turn token usage, cache_read/write, and per-epoch scores.
4. Stand up one end-to-end fixture against a local kind/minikube cluster using a Dockerfile-based sandbox first; promote to `inspect_k8s_sandbox` only after that works. Use Claude Code as the harness.
5. Add an Ollama provider line to `.env` and re-run the same task with `--model ollama/qwen2.5-coder:7b --solver inspect_swe/opencode -M emulate_tools=true`. If tool calls succeed, the multi-tier requirement is locked in.

### Stage 2 — within 4 weeks
- Produce a 20-fixture corpus for the classification eval shape and 6–10 for the K8s eval shape.
- Add a `cell` field to sample metadata (`skill_on`, `skill_off`, `model_tier`) and write the Pandas anti-pattern script.
- Wire `--log-dir s3://...` and use `inspect log convert` to standardise on `.eval` (zstd) for storage.

### Stage 3 — within 3 months
- Add a CI workflow that runs the classification eval set on every skill PR; gate on per-fixture mean ≥ baseline + 5pp with σ ≤ 0.3.
- Begin evaluating LangChain Open SWE or a Mini-SWE-Agent variant as the open-weights harness if `opencode()` proves immature.

### Signals that would force a migration
- `inspect_swe`'s `opencode()` solver becomes unmaintained (no release for > 90 days) and OpenCode itself ships breaking changes — fall back to `mini_swe_agent()` first; only migrate frameworks if that also fails.
- AISI moves Inspect to a non-MIT license (low probability; it's a UK-government open-source project, but watch the `LICENSE` file).
- The internal/OSS product strategy needs a hosted multi-tenant eval product (Inspect is a library, not a hosted backend) — then re-evaluate Braintrust hybrid or MLflow's evaluation surface.

### First-week plan, concretely
- Docs to keep open: https://inspect.aisi.org.uk/ (framework), https://meridianlabs-ai.github.io/inspect_swe/ (coding-agent solvers), https://k8s-sandbox.aisi.org.uk/ (cluster sandbox), https://ukgovernmentbeis.github.io/inspect_evals/ (200+ reference evals to copy patterns from).
- Reference repo to clone for cluster-state-verifier patterns: `inspect_evals` cyber suite (uses Docker sandboxes and bash-tool verifiers in the same shape you'll need).
- VS Code: install the Inspect VS Code extension; it surfaces the eval log viewer inline and is the fastest way to inspect a 50-turn Claude Code transcript.

## Caveats

- **Last verification was May 2026.** All commit dates, release numbers, and license states reported here were checked against PyPI metadata and GitHub LICENSE files; `inspect_ai 0.3.222` was uploaded to PyPI on May 18 2026 and `0.3.223` on May 20 2026, with `inspect_swe 0.2.55` on May 16 2026. If you read this more than 90 days after publication, re-verify.
- **The "OpenCode" link inconsistency in the inspect_swe docs is real and unresolved at the time of writing.** The docs nav lists `opencode()` as a solver but the in-text hyperlink points to `github.com/anomalyco/opencode`, not the canonical `github.com/sst/opencode`. Before committing fixtures to this solver, confirm against `src/inspect_swe/opencode.py` in the repo.
- **Inspect's Inspect View is for human debugging; it is not a production observability tool.** For long-term storage of agent traces in production you would still want OTel and a separate observability stack (Arize Phoenix or Laminar both work); Inspect is the *evaluation harness*, not the prod monitoring layer.
- **`inspect_k8s_sandbox` is a "useful example" provider per its own README** — UK AISI is candid that other organisations may need to tailor it. Budget engineering time.
- **No native cost-tracking dashboard.** Token usage is captured per turn; dollar costs require a `model_cost_config` YAML or a notebook. Adequate, but not as turnkey as Braintrust or Langfuse.
- **Anti-pattern flagging (|Δ| < 5pp, σ > 0.3) is custom code, not a framework feature.** Plan for a ~30-line Pandas notebook step in your CI pipeline.
- **Promptfoo's status is shifting fast.** The OpenAI acquisition was announced March 9, 2026 and is "subject to customary closing conditions." OpenAI has committed to keeping the open-source CLI maintained, but a re-evaluation of promptfoo in 6 months is appropriate if you care about long-term direction independence.