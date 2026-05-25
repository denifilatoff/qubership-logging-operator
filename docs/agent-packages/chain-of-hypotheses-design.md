# Chain-of-hypotheses model — design notes

Design notes for the L2 troubleshooting skill package
(`agent-packages/logging-l2-troubleshooting`). Captures the architectural
decisions behind the chain-of-hypotheses routing and signal-classification
model.

The L2 logging package is the first instance of this pattern. These notes
will feed a future meta-skill for authoring multi-component troubleshooting
packages for other knowledge areas (DB, networking, messaging). For now the
purpose is to preserve the milestones — what we chose, why, and what we
ruled out.

## The problem

A multi-component stack produces symptoms that don't uniquely identify
the component at fault. "Logs not arriving" can stem from FluentBit,
FluentD, Graylog, or OpenSearch. The agent has to walk candidates and
converge on the actual cause.

Approaches that don't work:

- **Single best guess.** Agent picks one area, recommends a fix, misses
  cascading causes. Pre-`66cc9a2` baseline: mean 0.82, high variance.
- **Run every area's diagnosis in parallel.** Multi-second sweeps × N
  zones is expensive; outputs contradict and re-merging is hard.
- **One big skill that knows everything.** Tightly coupled, untestable
  per zone, breaks if a backend is swapped.

We need a controlled walk with explicit advance signals.

## The model

Triage (`logging-l2-triage`) produces a ranked candidate list, then walks
it top-down via `Skill({"skill": <candidate>})`. Each leaf skill
(`fluentbit-troubleshoot`, `graylog-server-troubleshoot`, etc.) has one
of two outcomes:

- **`recommend`** — case closed, chain stops.
- **`hypothesis_refuted`** — chain advances; next hop derived from the
  refute body.

Refute carries a `signal_class`:

- `clean` — zone healthy; advance to the next candidate already in the
  list.
- `secondary_backpressure` — zone is buffering under outside pressure;
  insert immediate downstream of the refuted zone (per topology table)
  at the top of the remaining list.
- `secondary_quoted` — zone's logs cite an external trigger string;
  look up each cited string against the cited-string map, insert
  matches.

`primary` is the fourth class (signal explained by internal causes) but
it triggers a `recommend`, not a refute, so it doesn't appear in refute
output.

A step budget of 5 area-skill invocations caps the chain; most
real cases converge in 1–2 hops.

## Architectural separation

Two kinds of knowledge live in different files:

| Knowledge | Location | Why |
|---|---|---|
| **Zone pathology** — what FluentBit's OOM means, when a Graylog journal grows, what an OpenSearch shard-write rejection implies | Leaf SKILL ("Zone signal classification" section) | Domain-specific. Junior model needs concrete predicates per zone. |
| **Stack topology** — who's upstream of whom, which skill handles which area | Triage `signal-table.md` | Stack-specific (the Qubership stack uses Graylog/OpenSearch; another deployment could use Loki, Victoria Logs, Splunk). Naming the next-hop skill from a leaf would leak topology and break cross-stack reuse. |

Consequence: the same `fluentbit-troubleshoot` SKILL can live in a
Loki-stack package without changes — only the topology table in that
package's triage differs.

The earlier contract had leaves emit `likely_downstream_area` directly.
That worked for our single stack but coupled every leaf to the topology;
we removed it in favour of leaf-reports-evidence / triage-decides-routing.

## Signal classification as decision tree

Each leaf has a "Zone signal classification" section with a numbered
decision tree on observable predicates. The tree walks four classes in
order **CLEAN → QUOTED → BACKPRESSURE → PRIMARY**:

- The walk is **mechanical**, not judgmental. Junior models classify by
  checking AND-conditions, not by interpreting "spirit of the signal".
- `PRIMARY` is the **default fallback** — anything with a signal that
  doesn't hit a more specific class lands here and triggers a recommend.
- Order matters: CLEAN first (cheap absence-of-signals check); QUOTED
  next (cheap pattern match on log strings); BACKPRESSURE requires
  multiple AND-conditions and so loses to QUOTED on overlap; PRIMARY
  catches everything else.

The mechanical-predicates discipline replaces the earlier "Zone clean
checklist" pattern, which required the model to judge what counted as
clean. Judgment is unreliable in junior models; predicates aren't.

### Why decision tree, not signal_class tags in the catalogue

We considered annotating each entry in `symptoms.md` with a
`signal_class:` tag and having leaves look up by entry. Rejected because:

- It clutters human-facing docs (the catalogue is also user
  documentation for engineers).
- It moves classification from "shape of observed pathology" (which
  generalises to unknown symptoms) to "memorise the catalogue" (which
  doesn't).
- New symptoms not yet in the catalogue would have no class.

A shape-based decision tree generalises across symptoms; a per-entry tag
does not.

## Cascade-refute — the motivating case

The eval scenario `graylog-gelf-input-size-too-small` is a cascade:

1. Graylog GELF input frame size is configured too small.
2. Graylog drops oversized GELF frames at the input parser.
3. FluentBit can't deliver, its buffer grows.
4. FluentBit OOMs on its (small) memory limit.

Pre-cascade chain: walks to `fluentbit-troubleshoot` first (FluentBit is
the first thing the symptom surface points at). FluentBit sees its own
real OOM signal, has no way to distinguish "I'm the cause" from "I'm
buffering because downstream rejects", classifies as primary, recommends
"raise memory limit". Chain stops at a legitimate-but-wrong fix.
Eval result on this case before the fix: 0.92 → 0.72 regression.

### Two paths to the fix, chosen one

We initially planned to have FluentBit refute as `secondary_backpressure`
when it sees OOM + tight limit + reachable output. Drafting the leaf
decision tree exposed a problem: those three predicates also hold in the
`fluentbit-oom` case (primary OOM at a too-low limit, no downstream
problem). The two cases are indistinguishable from inside FluentBit
without a positive backpressure signal (output retries climbing, dropped
records, connection errors).

For gelf-size specifically, FluentBit gets no such signal — Graylog's
GELF input parser drops oversized TCP frames silently; FluentBit logs
nothing, retries nothing.

So the BACKPRESSURE tree predicate was tightened to **require a positive
backpressure signal in addition to OOM + tight limit + reachable
output**. The cost: FluentBit can no longer detect gelf-size as a
cascade from its own zone — the predicate correctly returns PRIMARY for
both `fluentbit-oom` and the FluentBit view of gelf-size.

The gelf-size fix moved to a **triage-side fast path**: the initial
sweep now greps `kubectl logs <graylog-pod>` for `TooLongFrameException`
and similar input-drop warnings; the signal-table has a high-prior seed
row routing that signal directly to `graylog-server-troubleshoot`,
which classifies as `primary` and recommends the GELF input fix.
FluentBit isn't invoked at all in the happy path.

This is the design's overall principle (leaf-vs-triage separation)
applied to the cascade case: the cascade is detected on the Graylog
side, where it leaves a clear observable; FluentBit-side ambiguity is
not forced into the cascade-detection role.

### When the cascade-refute mechanism still earns its place

`secondary_backpressure` and `secondary_quoted` remain meaningful for
cascades where the originating zone *does* produce an observable
signal that names or implies the downstream:

- A collector with visible output retries to a Graylog that's healthy
  on its own probes (no input drops, journal stable) — the collector
  refutes as `secondary_backpressure`, triage walks one hop downstream.
- A collector that quotes `connection refused` or
  `cluster_block_exception` in its own logs — `secondary_quoted`,
  triage looks up the cited string.

The current eval suite does not exercise either path crisply — see
"Coverage gap" under Known limits below. Adding a scenario that
produces visible output retries from a collector zone is a planned
follow-up.

## Maintenance model

Two artefacts grow at different rates:

| Artefact | When it changes | Frequency |
|---|---|---|
| `docs/troubleshooting/<area>.md` (= `.apm/shared/symptoms/<area>.md` via symlink) | Each new known symptom: pattern + root cause + fix | Often |
| Leaf SKILL's "Zone signal classification" tree | New buffering semantics, new memory-limit threshold to treat as "tight", new stack component, new external-citation shape | Rare — structural changes |

Most new symptoms are `primary` (internal causes). They slot into the
catalogue and the tree's PRIMARY branch catches them automatically.
Maintainers don't touch the tree.

When they do need to touch the tree:

- A new component enters the stack (also requires a new SKILL +
  topology-table update — big change).
- A typical "tight" memory-limit threshold changes for an existing
  component.
- A genuinely new pathology shape appears (deadlock unrelated to buffer,
  novel IPC failure mode).

This separation keeps the tree small and stable while the catalogue
grows freely.

### Maintainer guidance — where it lives

Earlier draft put this guidance as an HTML comment at the top of each
`symptoms.md`. Reverted: HTML comments are not invisible to the agent
(LLMs read raw text, comments occupy context every time the catalogue
is read). The guidance belongs in design docs like this one and in the
package's own README, not in agent-facing files.

## Known limits

- **Threshold values are stack-defaults, not absolutes.** "≤ 128Mi
  memory for FluentBit forwarder" is the typical Qubership-stack tight
  threshold. A customised values.yaml with a different forwarder
  profile might invalidate the predicate. The trees frame it as "tight
  for the workload" with example thresholds, not hard rules — but
  unusual deployments will produce misclassifications.
- **`secondary_backpressure` on terminal stores is degenerate.** OS as
  the terminal of the data path rarely has a meaningful downstream to
  route to. The tree notes the class is rare on OS; the default is
  `primary`.
- **The chain has a step budget of 5.** Genuinely ambiguous cases that
  need more hops escalate. Most cases converge in 1–2 hops; budgets >5
  trade noise for coverage.
- **API flakes inflate single-run variance.** ~1 in 36 runs in the last
  sweep hit Claude SDK socket errors and zeroed a case. Don't chase a
  single-run regression without a re-run.
- **Coverage gap on `secondary_backpressure`.** After the predicate was
  tightened to require a positive output-retry / dropped-records signal,
  none of the current six eval scenarios crisply exercises the
  BACKPRESSURE class. gelf-size is now triage-side fast-path;
  fluentbit-oom / -config / -cpu are all primary. Need a scenario where
  a collector OOMs *with* visible output retries against a downstream
  that's healthy on its own probes — synthetic but representative.

## What this informs

When we synthesise a meta-skill for authoring knowledge-area packages,
these are the load-bearing decisions to bring forward:

- The chain-of-hypotheses pattern (ranked candidates + leaf-or-refute
  outcomes + advance signals).
- The leaf-vs-triage separation (zone pathology vs stack topology) and
  the cross-stack-reuse argument behind it.
- Signal classification as a 4-class decision tree on observable
  predicates, with `primary` as default fallback.
- Cascade-refute via `secondary_backpressure` / `secondary_quoted`
  and a topology-table-driven next-hop rule.
- The two-rate maintenance model — catalogue grows freely, tree changes
  rarely.

Open questions still unresolved:

- How to bootstrap a topology table for a new stack — currently
  hand-authored from architectural knowledge; could it be derived from
  a stack manifest?
- How to choose granularity of zones — we chose 4–5 leaves for logging;
  some stacks may need fewer (collapse FluentBit + FluentD?) or more
  (split Graylog server / journal / indexer alias).
- How to validate that a leaf's tree is shape-classifying correctly,
  not catalogue-matching by accident. Probably an eval-suite property,
  not a static check.

## Related documents

- [package-layering-model.md](package-layering-model.md) — how L1, L2,
  and topic-specific packages stack.
- [troubleshooting-methodology.md](troubleshooting-methodology.md) —
  domain knowledge that informs the L1 and L2 skills.
- [skill-evaluation-methodology.md](skill-evaluation-methodology.md) —
  how we measure whether changes like cascade-refute actually help.
