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

This pattern was first instantiated in `agent-packages/logging-l2-troubleshooting`. Validation results — pre-refactor baseline vs post-refactor sweep, mean scores per case, cost comparison — to be filled in after the post-refactor eval sweep completes.
