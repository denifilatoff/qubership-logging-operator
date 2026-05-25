# Expert-orchestration refactor — L2 logging package

**Date:** 2026-05-26
**Status:** Approved design, pending implementation plan.
**Scope:** `agent-packages/logging-l2-troubleshooting/` + supporting eval and docs.

## Goal

Restructure the L2 logging troubleshooting package so that:

- **Expert skills know only their technology**, not stack topology.
- **Domain extends via reference files**, not via expert SKILL.md edits.
- **All topology lives in the triage skill**, concentrated in one place that can be reviewed and fixed as a unit.
- **Maximum accuracy on a Junior model (Haiku) for minimum tokens.**

The current 4-class signal-classification model and the chain-of-hypotheses contract
leak topology semantics into experts, distribute routing logic across multiple files,
and force a six-file change for a single refinement. This refactor collapses experts
to a topology-free contract and concentrates routing in the triage skill.

## Architecture

### Expert skill (one per technology)

Example: `fluentbit-troubleshoot`.

```
fluentbit-troubleshoot/
├── SKILL.md
└── references/
    └── symptoms.md
```

`SKILL.md` contains exactly three things:

1. **Fixed base diagnostic pass.** A finite set of `kubectl` / log-fetch /
   config-read commands for this technology, runnable once per invocation. The
   diagnostic pass is deterministic and does not iterate over the symptom
   catalogue.
2. **Lookup procedure.** Take the diagnostic-pass output, match it against each
   entry in `references/symptoms.md`, collect matches.
3. **Output schema** (see below) plus the anti-fabrication rule.

`references/symptoms.md` is a catalogue. Each entry:

```
- id: oom-tight-limit
  match: <regex / keyword / value check over diagnostic-pass output>
  evidence_template: <what lines or values to quote>
  proposed_fix: <recommendation text>
```

Adding a new symptom means adding one entry to `symptoms.md`. SKILL.md is not
touched. The diagnostic pass does not change. The new symptom must be observable
in the existing diagnostic-pass output; if it requires a new probe, that is a
rare and explicit SKILL.md edit.

### Expert output schema (light)

```yaml
findings:
  - symptom_id: <id from catalogue, or "unrecognized">
    evidence: <quoted lines / values from diagnostic pass>
    proposed_fix: <string or null>
raw_diagnostic_pass: <short digest of diagnostic-pass output, for orchestrator fallback>
```

The schema carries no topology information. No `signal_class`,
no `cited_external_components`, no `clean` / `diagnosed` outcome, no reference
to a chain or to other skills.

**Anti-fabrication rule, restated in every expert SKILL.md:**

> If the diagnostic pass produces no recognized symptom, return `findings: []`
> and a non-empty `raw_diagnostic_pass` digest. Do not invent a `symptom_id`.
> Do not infer or speculate about causes. Do not propose fixes. An empty
> `findings` array is a valid and expected outcome.

### Triage skill (`logging-l2-triage`)

```
logging-l2-triage/
├── SKILL.md
└── references/
    ├── topology.md
    └── cited-strings.md
```

`SKILL.md` contains:

1. **Initial diagnostic pass** — short cluster-wide read-safe probe set
   (including current Graylog log grep for gelf-size fast-path detection).
2. **Candidate ranking** — from the initial diagnostic pass + `topology.md`,
   build a ranked list of experts to walk.
3. **Chain-walk loop** with step budget 5. For each candidate:
   - call the expert, receive structured `findings`,
   - apply routing-policy,
   - decide STOP / NEXT / FALLBACK.
4. **Routing-policy** operating on the light schema, not on prose. Apply in
   order; first match wins:
   - `findings == []` → NEXT per `topology.md` (next downstream node from the
     current expert).
   - `findings[].evidence` matches any pattern in `cited-strings.md` → NEXT to
     the `points_to` node of the matched pattern.
   - `raw_diagnostic_pass` matches any pattern in `cited-strings.md` → NEXT to
     the `points_to` node of the matched pattern. (Covers the case where the
     expert left the signal in `raw_diagnostic_pass` rather than in
     `findings[].evidence`, including `symptom_id == "unrecognized"`.)
   - otherwise → STOP, return the expert's `findings` as the final result.
5. **Fallback** to `manual-diagnosis` recommend when chain is exhausted.

`references/topology.md` is the stack map:

```
nodes:
  - id: fluentbit
    skill: fluentbit-troubleshoot
    downstream: [graylog]
    upstream: [app-pods]
  - id: graylog
    skill: graylog-server-troubleshoot
    downstream: [opensearch]
    upstream: [fluentbit, fluentd]
  ...
```

Topology change (e.g., adding Loki as alternative output) means editing
`topology.md` only. SKILL.md does not change.

`references/cited-strings.md` is the redirect table:

```
- pattern: "cluster_block_exception|FORBIDDEN/12/index read-only"
  points_to: opensearch
- pattern: "TooLongFrameException|gelf.*too large"
  points_to: graylog
- pattern: "connection refused.*:12201"
  points_to: graylog
```

Triage applies these patterns with regex match over `findings[].evidence`,
not over free prose.

### Shared contract

`agent-packages/logging-l2-troubleshooting/.apm/shared/shared-contract.md`
shrinks to ~20-30 lines covering only:

- Light output schema for experts (`findings[]`, `raw_diagnostic_pass`).
- Anti-fabrication rule.
- `symptom_id` naming convention.
- The principle that experts do not know about chain, triage, or topology.

Removed: 4-class block, `signal_class`, `cited_external_components`,
trust-criteria text (now lives in triage SKILL.md as routing-policy).

`agent-packages/logging-l2-troubleshooting/.apm/shared/symptoms/*.md` remain as
the storage location for catalogues, reachable from experts via the existing
symlinks into `references/symptoms.md`. Their internal format changes to match
the new entry shape (`id`, `match`, `evidence_template`, `proposed_fix`).

## What disappears

- `signal_class` field from refute output.
- `cited_external_components` field from refute output.
- Per-expert "Zone signal classification" decision tree (~40-50 lines per expert).
- 4-class definitional block in `shared-contract.md`.
- `secondary_backpressure` / `secondary_quoted` routing rules in
  `signal-table.md` (file itself is replaced by `topology.md` + `cited-strings.md`).
- `clean` / `diagnosed` outcome vocabulary in experts.
- Trust-criteria as a separate concept; replaced by routing-policy operating
  on the structured schema.
- `docs/agent-packages/routing-redesign-proposal.md` (deleted; its purpose
  ends with this refactor).
- `docs/agent-packages/chain-of-hypotheses-design.md` (deleted; describes
  superseded architecture).

## What stays

- Chain-walk pattern (ranked candidates, top-down, step budget 5).
- Expert / triage separation principle (sharper after refactor: expert knows
  technology only, triage knows topology only).
- Initial diagnostic pass in triage (including the gelf-size grep).
- Symptom catalogue files in `shared/symptoms/`.
- Action-tiers contract (`read-safe` / `read-heavy` / `recommend`).
- `manual-diagnosis` terminal fallback.
- Existing eval pipeline mechanics (`runner.sh`, `aggregate.sh`, per-fixture
  cost capture).

## Guidance doc

`docs/agent-packages/expert-orchestration-pattern.md` (new, self-contained,
no cross-references to deleted docs). Covers:

- Principle: expert = technology + symptom catalogue, no topology knowledge.
  Orchestrator = topology + routing-policy, no domain knowledge.
- Light output schema as the standard.
- Anti-fabrication rule.
- Checklists: "add a new expert", "extend symptoms", "change topology".
- Validation section — populated after the post-refactor eval sweep with
  measured outcomes vs baseline.

## Evals

### Rubric changes

`test/agent-packages/evals/logging-l2-troubleshooting/cases/*/rubric.yaml`
(6 cases):

- Remove all `signal_class: secondary_*` greps.
- Replace with: (a) grep for expected `symptom_id` in expert output, (b) grep
  asserting the final `recommend` came from the topologically-correct expert.

### Judge-prompt changes

`test/agent-packages/evals/logging-l2-troubleshooting/judge-prompt.txt`:

- Update the schemas block to show the new light schema and triage
  routing-policy inputs.
- Remove all 4-class vocabulary.

### New synthetic case

Add one new case: an in-expert cascade signal where FluentBit logs explicitly
contain `connection refused.*:12201`. This exercises the cited-strings
redirect path, which has no current coverage. Target score ≥ 0.80.

### Baseline

Use the existing 205355Z sweep as the baseline (mean 0.867). Do not re-run
the baseline; it is stable and recorded. ("Sweep" in this context refers to
the eval-batch sweep, not to the per-skill diagnostic pass.)

### Pass criteria

1. Mean score ≥ 0.817 across the 6 existing cases (within 0.05 of baseline).
2. `fluentbit-oom` ≥ 0.85, `gelf-size` ≥ 0.85 (canonical cases).
3. `opensearch-flood` ≥ 0.80 (cited-strings cascade case).
4. New synthetic cited-string case ≥ 0.80.
5. **Per-run cost ≤ baseline cost** (not 2× — the redesign must simplify
   triage, not make it more expensive).
6. No new failure-mode classes (manual review of any case that lost points).

REPEATS ≥ 3 for the comparison sweep.

## Rollout

- **One branch.** Continue on `initial-logging-skills`. No second branch.
- **One thematic commit set**, partitioned for readable `git log`:
  1. Shrink `shared-contract.md`.
  2. Rewrite the 4 expert SKILL.md files + their `references/symptoms.md` format.
  3. Rewrite `logging-l2-triage/SKILL.md` and split `signal-table.md` into
     `topology.md` + `cited-strings.md`.
  4. Update rubrics + judge-prompt; add new synthetic case.
  5. Write `expert-orchestration-pattern.md`.
  6. Delete `routing-redesign-proposal.md` and `chain-of-hypotheses-design.md`.
- **Implementation uses the `apm-authoring` skill** for all skill-package edits.
- **Validation:** run the eval sweep against the 205355Z baseline.
  - On pass: fill the validation section of the guidance doc, update MEMORY.
  - On fail: `git revert` the commit range, leave a short note in
    `expert-orchestration-pattern.md` Status header explaining what regressed,
    iterate.

## Open items deferred to implementation plan

- Exact wording of the anti-fabrication rule per expert (one shared phrasing
  vs technology-specific examples).
- Exact format for `match` field in symptoms.md (raw regex, structured rule
  object, or both).
- Whether `proposed_fix: null` is a permitted shape or absent field — settle
  during expert rewrite.
- New synthetic case fixture: which existing case to clone as scaffolding,
  which logs to inject.

These do not change the architecture; they are surface details for the
implementer.
