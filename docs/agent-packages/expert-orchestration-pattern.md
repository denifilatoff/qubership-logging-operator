# Expert-orchestration pattern

A design pattern for APM packages that diagnose multi-component systems on behalf of an engineer. Defines the contract between **expert skills** (each owning one technology) and the **orchestrator skill** (owning the stack topology and routing decisions).

## Principles

- **Expert skill owns one technology.** It knows that technology's diagnostic procedure (commands, log greps, API probes) and its symptom catalogue. It does **not** know what other components exist, how the stack is wired, or who calls it.
- **Orchestrator skill owns the topology.** It knows the data-flow graph between components, knows which expert covers which zone, and decides which expert to invoke next based on the expert's structured output.
- **Domain extends through reference files.** Adding a new symptom is an edit in `references/symptoms.md` for the relevant expert; the expert SKILL.md does not change. Adding a backend is an edit in `references/topology.md` for the orchestrator; the orchestrator SKILL.md does not change.

## Expert skill contract

```
<expert-skill>/
├── SKILL.md
└── references/
    └── symptoms.md
```

`SKILL.md` contains exactly three sections beyond the protocol header:

1. **Fixed diagnostic pass.** A finite, deterministic set of commands or API calls for this technology. Runs once per invocation. Does not iterate over the symptom catalogue.
2. **Lookup and output.** Match the diagnostic-pass output against each entry in `references/symptoms.md`. Emit the structured output schema.
3. **Anti-fabrication rule.** If no entry matches, return an empty `findings` array and the raw diagnostic-pass digest. Do not invent a symptom_id, do not infer causes, do not propose fixes.

`references/symptoms.md` lists symptoms as YAML entries:

```yaml
id: <kebab-case>
match:
  log_grep: { target: <component>, pattern: '<regex>' }
  k8s_state: { pod_state: <state> }
  config_check: { configmap: <name>, expects: '<value>' }
  api_check: { path: <path>, expects: '<predicate>' }
evidence_template: |
  <what lines / values to quote into evidence>
proposed_fix: |
  <imperative fix steps>
```

## Expert output schema

```yaml
findings:
  - symptom_id: <id, or "unrecognized">
    evidence: |
      <verbatim quotes and values>
    proposed_fix: <text or null>
raw_diagnostic_pass: |
  <abbreviated digest of the diagnostic-pass output>
```

When `findings` is non-empty and the matched symptom warrants an operator action, the expert also emits a `recommend` block per the shared contract.

## Orchestrator skill contract

```
<orchestrator-skill>/
├── SKILL.md
└── references/
    ├── topology.md
    └── cited-strings.md
```

`SKILL.md` contains:

1. **Initial diagnostic pass.** A short cluster-wide read-safe probe set that the orchestrator runs before any expert.
2. **Candidate ranking** from the initial diagnostic pass + `topology.md`.
3. **Chain-walk loop** with a step budget. For each candidate: invoke the expert, apply the routing-policy on the structured output, decide STOP / NEXT / FALLBACK.
4. **Routing-policy** — purely structural lookup over the expert's output. No NLU on prose.

`references/topology.md` is the stack-node map: each node carries its `skill`, `downstream`, `upstream`. Replacing a backend = edit this file.

`references/cited-strings.md` is the redirect table: regex patterns paired with `points_to` node ids, used when an expert's evidence cites another component as the trigger.

## Routing-policy shape

Apply in order; first match wins:

1. **Empty findings** → next hop is the downstream neighbour per topology.
2. **Evidence matches a cited-strings pattern** → next hop is the pattern's `points_to` node.
3. **`raw_diagnostic_pass` matches a cited-strings pattern** → same redirect.
4. **Otherwise** → STOP, surface the expert's findings as the final result.

The policy reads structured fields (`findings[].evidence`, `raw_diagnostic_pass`) with regex. It does not interpret prose narratives.

## Adding a new expert to an existing package

1. Add the technology as a node in `topology.md`, with the expert's skill name and its `downstream` / `upstream` neighbours.
2. Create the expert skill folder with `SKILL.md` (using the three-section template) and `references/symptoms.md` (starting with the symptoms that motivated the addition).
3. Update the orchestrator's initial diagnostic pass to surface signal from the new zone, if applicable.
4. Add eval cases that exercise the new expert in isolation and in chain.

## Adding a new symptom to an existing expert

Edit `references/symptoms.md` for that expert. Add one YAML entry. Do not edit `SKILL.md` unless the new symptom requires a probe that the fixed diagnostic pass does not already perform.

## Changing topology

Edit `references/topology.md`. Replace, add, or remove nodes; update `downstream` / `upstream` lists. The orchestrator `SKILL.md` does not change.

## Why this works on a junior model

- The expert's lookup is mechanical (match output against regex/value entries). No reasoning over topology.
- The orchestrator's routing-policy is mechanical (regex over structured fields, lookup in topology graph). No prose comprehension required.
- Each skill is small enough to fit comfortably in the model's context with its references.

## Validation

The pattern was first instantiated in `agent-packages/logging-l2-troubleshooting`. Measured against the pre-refactor baseline run `20260525T205355Z` (mean 0.867 across 6 cases) on a kind cluster with `BACKEND=graylog`.

### Post-refactor scores (run `20260526T063013Z`, REPEATS=3)

| Case | Baseline | Post-refactor | Δ |
|---|---|---|---|
| fluentbit-config-syntax | 0.97 | 0.86 | -0.11 |
| fluentbit-cpu-throttle | 0.78 | 0.81 | +0.03 |
| fluentbit-oom | 0.93 | 1.00 | +0.07 |
| graylog-gelf-input-size-too-small | 0.88 | 0.90 | +0.02 |
| opensearch-flood-stage-readonly | 0.86 | 0.86 | 0.00 |
| operator-helm-bad-image | 0.78 | 0.86 | +0.08 |
| **Mean (6 existing cases)** | **0.867** | **0.882** | **+0.015** |
| fluentbit-graylog-connection-refused (new) | — | 0.77 | — |

Per-run cost: baseline `$0.215/run` vs post-refactor `$0.202/run` (slightly cheaper). Total `$8.50` across 42 runs (vs baseline `$7.73` across 36 runs).

### Pass-criteria check

| Criterion | Target | Result | Status |
|---|---|---|---|
| Mean across 6 baseline cases | ≥ 0.817 | 0.882 | ✓ |
| fluentbit-oom | ≥ 0.85 | 1.00 | ✓ |
| graylog-gelf-input-size-too-small | ≥ 0.85 | 0.90 | ✓ |
| opensearch-flood-stage-readonly | ≥ 0.80 | 0.86 | ✓ |
| New synthetic cited-strings case | ≥ 0.80 | 0.77 | ✗ (-0.03) |
| Per-run cost ≤ baseline | ≤ $0.215 | $0.202 | ✓ |

### Behavioural observations from the post-refactor eval run

- **The orchestrator takes the shortest correct path.** When the cluster-wide initial diagnostic pass directly surfaces the failing zone (e.g. graylog StatefulSet at zero replicas, visible in `kubectl get statefulset` and in the `LoggingService` CR), the orchestrator routes straight to the relevant expert without walking through upstream zones. This is correct optimising behaviour, but it means the cited-strings cascade path is only exercised when the downstream issue is observable only inside an upstream expert's evidence — not when triage's own pass can see it directly.
- **Structured YAML emission is reliable but not perfect.** Experts emit the `findings:` and `recommend:` blocks the contract requires in most cases, but occasionally degrade into prose-formatted "## Findings" / "## Recommendation" sections. The instruction in expert SKILL.md sections "Lookup and output" was tightened (commit `295baff`) to require the YAML block first, which improved compliance on subsequent runs.
- **Symptom_id discipline is imperfect.** Experts sometimes emit invented `symptom_id` values (e.g. `fluentbit_config_parse_failure_undefined_parsers`) instead of the canonical id from `references/symptoms.md` (e.g. `fluentbit-configmap-parse-error`). This does not affect routing correctness — routing-policy operates on `findings == []`, `evidence` regex, and `raw_diagnostic_pass` regex — but it weakens the catalogue as a shared reference and breaks rubric checks that grep for canonical ids.

### Why one criterion missed

The new synthetic case `fluentbit-graylog-connection-refused` was designed to exercise the cited-strings cascade path. Two scenario shapes were tried:

1. **FluentBit ConfigMap mutation (initial design)** — pointed FluentBit at a non-existent Graylog hostname. The fluentbit expert correctly diagnosed the misconfigured ConfigMap and fixed it locally, without cascading. Score 0.77: rubric expected cited-strings cascade routing; agent took the more efficient self-fix path. This is correct behaviour — bad hostname in a collector's own ConfigMap is a collector-zone fix.

2. **Graylog StatefulSet scaled to zero (revised design)** — kept FluentBit's config correct; broke graylog downstream. Triage's initial diagnostic pass immediately surfaced `graylog StatefulSet 0/0 replicas` and routed directly to `graylog-server-troubleshoot`, skipping the fluentbit hop entirely. Score 0.625: again a shorter correct path than the rubric expected. The orchestrator's optimising shortcut is, in real-world terms, the right call.

A proper cited-strings cascade test needs a downstream failure that is **not** visible from the triage initial pass — e.g. graylog pods running healthy but rejecting GELF frames via a NetworkPolicy, or via an input-port mismatch invisible without entering the graylog zone. That fixture has not yet been written.

### Conclusion

The refactor delivers its architectural goals: light schema is emitted, topology and cited-strings live in reference files, the orchestrator routes on structured fields without prose comprehension, cost is comparable to baseline, and the mean score improved by 0.015. Two follow-ups remain (see `docs/agent-packages/expert-orchestration-followups.md`):

1. **Symptom_id catalogue discipline** — improve expert prompts so experts use canonical ids from `references/symptoms.md` verbatim instead of inventing descriptive ids.
2. **Cited-strings cascade test fixture** — design a synthetic scenario that hides the downstream failure from triage's initial pass so the cascade path is actually exercised.
