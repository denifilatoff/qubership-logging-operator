# Routing redesign proposal — simplified leaf, smarter triage

## Status

Proposal, not yet implemented. Builds on (and would partially supersede)
the 4-class signal-classification model documented in
[chain-of-hypotheses-design.md](chain-of-hypotheses-design.md).
Implementation gated on a baseline sweep with the current model — see
"Sequencing" below.

## Motivation

The current 4-class signal-classification model
(`clean / primary / secondary_backpressure / secondary_quoted`) was an
attempt to make leaf classification mechanical. In practice it has
shown architectural strain:

- A single refinement — "BACKPRESSURE requires a positive
  output-retry signal in addition to OOM + tight limit + reachable
  output" — touched six files: `shared-contract.md`,
  `signal-table.md`, one leaf SKILL, the triage SKILL, the design
  doc, and two rubrics. That is the smell.
- Routing logic is split across three locations: leaf decision
  trees, the topology table in triage's signal-table, and the
  cited-string map. When any of them drifts, all need to be checked.
- The four classes leak topology semantics into leaves. The
  `secondary_*` classes presume a cascade model the leaf doesn't
  actually know about.
- The decision-tree predicates are fragile. The canonical example
  is FluentBit OOM at a tight memory limit: indistinguishable from
  inside FluentBit between "primary memory misconfig" and
  "backpressure from a silently rejecting downstream". To
  distinguish them, the leaf would have to observe evidence the
  zone may not produce at all.

The proposal is to collapse leaf semantics to two outcomes and move
all routing judgment into the triage skill.

## The proposal

### Leaf contract — two outcomes

Each leaf has exactly two outcomes:

- **`clean`** — sweep found no failure signal in this zone. Leaf
  reports the sweep evidence to demonstrate the absence (so triage
  can confirm the check was thorough, not just a vacuous pass).
- **`diagnosed`** — sweep matched one or more entries from the
  symptom catalogue. Leaf emits a `recommend` block per the existing
  schema (unchanged), with `evidence` containing whatever observable
  signals it relied on, including any verbatim log quotes.

No `signal_class`. No `cited_external_components` field. No
per-zone decision tree mapping observables to classes. The leaf
does what it always did locally — sweep, match against the symptom
catalogue, propose a fix — and surfaces the raw evidence it used.

### Triage contract — trust or try next

Triage walks the ranked candidate list. For each leaf invocation:

- **Leaf returned `clean`** → advance to the next candidate already
  in the ranked list.
- **Leaf returned `diagnosed`** → apply trust criteria (below) to
  decide: STOP with this recommend as final, or TRY NEXT via the
  topology table / cited-string lookup.

The triage skill carries the trust criteria, the topology map, and
the cited-string lookup. All routing decisions live in one file,
evaluable as one piece.

### Trust criteria

A leaf's `diagnosed` outcome is **trusted as final** when all hold:

1. The recommend's `evidence` accounts for every concrete symptom
   the triage initial sweep surfaced. No orphan signal from the
   sweep is left unexplained.
2. The recommend's `evidence` does not quote or name an
   in-stack-but-out-of-zone component as the trigger. Examples that
   would NOT be trusted on first hop:
   `connection refused to <graylog-host>`,
   `cluster_block_exception`, `FORBIDDEN/12/index read-only`,
   `TooLongFrameException`, any reference to a known external
   component from the cited-string map.
3. The recommend is not a "narrow local patch" (raise a limit,
   restart a pod, edit a single config field) issued in a context
   where the initial sweep showed observable signal in a downstream
   or upstream zone.

A `diagnosed` outcome triggers **try next** when any of these fail.
The next candidate is derived as follows:

- Criterion-2 failure → cited-string lookup picks the next-hop skill.
- Criterion-1 or criterion-3 failure → topology table picks the
  next-hop skill (downstream of the current leaf for collector
  zones; upstream for terminal stores).

This is the same logic the current model distributes across leaf
decision trees + cited-string map — just expressed as triage's
evaluation of the leaf's output rather than as the leaf's
self-classification.

## What disappears

- `signal_class` field in refute output.
- `cited_external_components` field in refute output (raw quotes
  remain inside `evidence`; triage parses them there).
- The per-leaf "Zone signal classification" decision tree (40-50
  lines per leaf).
- The 4-class definitional block in `shared-contract.md`.
- The `secondary_backpressure` / `secondary_quoted` routing rules
  in `signal-table.md`.

## What stays

- The chain-of-hypotheses pattern (ranked candidate list, walk
  top-down, step budget of 5).
- The leaf-vs-triage separation principle (zone pathology vs stack
  topology). Stronger after the redesign: leaf knows less, triage
  knows more.
- The stack topology table in `signal-table.md`.
- The cited-string lookup table (becomes part of triage's trust
  reasoning).
- Triage's initial sweep — including the Graylog log grep we just
  added for gelf-size fast-path detection.
- The `recommend` block schema.
- The symptom catalogue files (`shared/symptoms/*.md`).
- The action-tiers contract (`read-safe / read-heavy / recommend`).

## What gets harder

The trust criteria require LLM judgment. The current 4-class model
uses observable predicates ("memory limit ≤ 128Mi") that are
mechanical. The new model uses inferential predicates ("recommend's
evidence accounts for every sweep symptom") that need reading
comprehension over the leaf's output.

Risk profile for Haiku in the triage role:

- May trust a partial recommend that misses a downstream signal
  from the sweep.
- May distrust a complete recommend whose vocabulary differs from
  the sweep's wording.
- May loop unnecessarily on near-miss trust evaluations,
  consuming step budget.

Mitigations:

- Trust criteria written as a numbered checklist, each criterion
  an observable predicate over `recommend.evidence` + sweep output.
- Explicit examples in triage SKILL for canonical cases (gelf-size
  fast path, fluentbit-oom local fix, opensearch-flood
  downstream-quoted recovery).
- Sonnet-level judge in evals catches the gap when Haiku makes a
  wrong trust call. Wrong trust calls show as score regressions on
  cases that previously passed.

## File-by-file impact

| File | Change |
|---|---|
| `agent-packages/logging-l2-troubleshooting/.apm/shared/shared-contract.md` | Replace "Signal classification & refute contract" section with two-outcome leaf contract + trust criteria for triage. |
| `fluentbit-troubleshoot/SKILL.md` | Remove "Zone signal classification" decision tree. Keep sweep + symptom catalogue + recommend behaviour. |
| `fluentd-troubleshoot/SKILL.md` | Same as above. |
| `graylog-server-troubleshoot/SKILL.md` | Same as above. |
| `opensearch-troubleshoot/SKILL.md` | Same as above. |
| `logging-l2-triage/SKILL.md` | Add Trust criteria section. Rewrite chain-of-hypotheses loop to "diagnosed → trust check → stop or try next". |
| `logging-l2-triage/references/signal-table.md` | Topology table and cited-string map stay (now consumed by trust criteria). Remove `Routing on a refute (signal_class → next hop)` section. |
| `test/agent-packages/evals/logging-l2-troubleshooting/cases/*/rubric.yaml` (6 cases) | Remove `signal_class` greps from cascade-refute checks. Replace with "leaf emitted recommend" / "leaf returned clean" predicates. |
| `test/agent-packages/evals/logging-l2-troubleshooting/judge-prompt.txt` | Update the schemas block: refute schema collapses to a `clean` outcome with no `signal_class` field. |
| `docs/agent-packages/chain-of-hypotheses-design.md` | Once the redesign lands: archive or fold surviving content (chain-of-hypotheses pattern, leaf-vs-triage separation rationale, motivation) into this proposal as the new current-state doc. |

## Open questions to settle before implementing

1. **Exact leaf output shape for `clean`.** Current refute carries
   `sweep_evidence` + `reason`. Keep those without the class fields,
   confirm there's nothing else triage needs to make a confident
   advance decision.

2. **Mechanical wording for criterion 1 (no orphan symptoms).** The
   formulation "every concrete symptom from the initial sweep is
   accounted for in the recommend's evidence" is fine for a human
   reader but too soft for Haiku. Candidates for a sharper form:
   - Enumerate sweep findings as a list before invoking the leaf;
     after the leaf returns, check each finding appears (by
     name / quoted phrase) in `recommend.evidence`.
   - Restrict to "any error/warn line from the sweep grep" as the
     symptom set, since those are the canonical orphan candidates.
   - Both.

3. **External-component detection — explicit map or general predicate?**
   The current cited-string map enumerates known patterns
   (`TooLongFrameException`, `cluster_block_exception`, etc.). For
   the trust criterion 2, two options:
   - Keep the explicit map. Mechanical, but each new failure mode
     needs a map update.
   - General predicate ("does `evidence` contain a hostname,
     port number, exception class, or HTTP error message naming
     another in-stack component?"). Robust to unseen errors but
     judgment-heavy.
   - Likely answer: explicit map for the cases we know +
     general fallback predicate for the unknown.

4. **Token cost target and measurement.** Triage will do more
   reasoning per case (read leaf output, apply trust criteria).
   Acceptable ceiling: per-run cost ≤ 2× the current baseline.
   Need to add token-usage capture to `aggregate.sh` to measure
   this honestly (already on the P2 list from the eval-redesign
   conversation).

5. **Fallback when triage exhausts the chain.** Current model has
   the `manual-diagnosis` recommend as the terminal fallback. The
   new model can keep this verbatim — it doesn't depend on the
   refute schema.

6. **Coverage gap for true in-leaf cascade signals.** No current
   eval scenario produces an in-zone signal that names a downstream
   (e.g. FluentBit logs explicit `connection refused to graylog`).
   The trust-check logic would route correctly on such a case via
   the cited-string map, but it's untested. Need a synthetic
   scenario before we claim cascade-refute is functionally
   equivalent to today.

7. **Rubric migration strategy.** The current rubrics' cascade
   checks grep for `signal_class: secondary_backpressure` literals.
   In the new model, those literals don't exist. Two options:
   - Rewrite each check to grep for the corresponding outcome
     (e.g. "leaf emitted recommend with evidence quoting
     `cluster_block_exception` → next hop went to OS").
   - Accept that the cascade checks become "did chain end at the
     right area" (area-correct) without per-hop semantic checks.
     Loses some signal but is simpler.

8. **Naming.** "Diagnosed" vs "recommend-emitted" vs other terms.
   Probably collapse to the existing `recommend` block being the
   outcome — no new outcome name needed. Confirm.

## Sequencing — what to do before this lands

1. **Baseline sweep with the current state.** Run the eval suite as
   it stands after the cascade-refute + tightened-BACKPRESSURE
   changes. Capture: mean score per case, per-run token totals
   (need aggregate.sh token capture first), failure modes if any.
   This is the "before" picture for the redesign comparison.

2. **Resolve open questions** above, especially #2 (orphan-signal
   predicate) and #3 (cited-string detection). These are the
   load-bearing details that determine whether the redesign
   actually simplifies things or just moves complexity into triage
   prose. A short follow-up review pass on this document, then
   freeze the design.

3. **Stage the redesign on a branch.** One PR for the SKILL package
   changes (shared-contract, 4 leaves, triage, signal-table). A
   second PR for the eval system (rubrics, judge-prompt) — so the
   eval rolls forward together with the package being measured.

4. **Run sweep on the redesign** with the same scenarios + REPEATS=3
   minimum. Compare against the step-1 baseline.

   Pass criteria:
   - Mean score not worse than baseline by more than 0.05.
   - fluentbit-oom and gelf-size remain at full / near-full score
     (these are the canonical cases the current model was designed
     for; regression on them would mean the redesign broke the
     architecture's intent).
   - Per-run token cost not worse than 2× baseline.
   - No new failure modes (manual review of any case that lost
     points).

5. **If pass**: land the redesign, archive
   `chain-of-hypotheses-design.md`, fold its surviving content
   (motivation, leaf-vs-triage rationale, chain-of-hypotheses
   pattern) into this proposal as the new current-state doc.

6. **If fail**: keep the current 4-class model. Document in this
   file's "Status" header what specifically broke. Return to
   incremental refinement on the existing model.

## Why this matters beyond the L2 logging package

The L2 logging package is the first instance of the broader
multi-component troubleshooting pattern. The decisions here will
inform a future meta-skill for authoring knowledge-area packages
(databases, networking, messaging, distributed systems).

The principle the redesign codifies — **leaves describe what they
see; the orchestrator interprets** — generalises to those domains
better than per-zone signal classifications do, because each domain
will have its own observable predicates but the orchestrator's
reasoning shape stays similar.

Getting this architecture right is therefore a small investment
that compounds across future packages.

## Related

- [chain-of-hypotheses-design.md](chain-of-hypotheses-design.md) —
  the current model this proposal would replace.
- [package-layering-model.md](package-layering-model.md) — L1 / L2
  / topic-specific stack layout. Unchanged by this proposal.
- [skill-evaluation-methodology.md](skill-evaluation-methodology.md)
  — measurement framework for the baseline + comparison sweeps.
- [eval-pipeline-design.md](eval-pipeline-design.md) — the
  promptfoo-based eval mechanics that step 4 above runs against.
