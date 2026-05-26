# 3. Package internals

This document covers the inside of one Layer 2 package: how the orchestrator and the experts split responsibility, the
structured contract between them, and the shapes of the reference documents they both consume. The patterns here are why
a Layer 2 package can grow new technologies or new symptoms without touching its `SKILL.md` files.

## 3.1. The expert / orchestrator pattern

A Layer 2 troubleshooting package consists of one **orchestrator skill** and several **expert skills**. The split is
strict:

- **Expert skill — owns one technology.** Knows that technology's diagnostic procedure (commands, log greps, API probes)
  and its symptom catalogue. It does **not** know what other components exist, how the stack is wired, or who calls it.

- **Orchestrator skill — owns the topology.** Knows the data-flow graph between components, knows which expert covers
  which zone, and decides which expert to invoke next based on the expert's structured output.

- **Domain extends through reference files.** Adding a new symptom is an edit in `references/symptoms.md` for the
  relevant expert; the expert's `SKILL.md` does not change. Adding a backend is an edit in `references/topology.md` for
  the orchestrator; the orchestrator's `SKILL.md` does not change.

### Expert skill contract

```text
<expert-skill>/
├── SKILL.md
└── references/
    └── symptoms.md
```

`SKILL.md` contains exactly three sections beyond the protocol header:

1. **Fixed diagnostic pass.** A finite, deterministic set of commands or API calls for this technology. Runs once per
   invocation. Does _not_ iterate over the symptom catalogue.
2. **Lookup and output.** Match the diagnostic-pass output against each entry in `references/symptoms.md`. Emit the
   structured output schema.
3. **Anti-fabrication rule.** If no entry matches, return an empty `findings` array and the raw diagnostic-pass digest.
   Do not invent a `symptom_id`, do not infer causes, do not propose fixes.

`references/symptoms.md` lists symptoms as YAML entries:

```yaml
id: <kebab-case>
match:
  log_grep:    { target: <component>, pattern: '<regex>' }
  k8s_state:   { pod_state: <state> }
  config_check:{ configmap: <name>, expects: '<value>' }
  api_check:   { path: <path>,      expects: '<predicate>' }
evidence_template: |
  <what lines / values to quote into evidence>
proposed_fix: |
  <imperative fix steps>
```

The expert's `symptom_id` **must be the literal `id:` from the matched catalogue entry**, not paraphrased or coined per
invocation. Coined ids weaken the catalogue as a shared knowledge base, even though routing itself does not depend on
them.

### Expert output schema

```yaml
findings:
  - symptom_id: <id, or "unrecognized">
    evidence: |
      <verbatim quotes and values>
    proposed_fix: <text or null>
raw_diagnostic_pass: |
  <abbreviated digest of the diagnostic-pass output>
```

When `findings` is non-empty and the matched symptom warrants an operator action, the expert also emits a `recommend`
block per the shared action-tier contract (the proposed mutation, why it is needed, the risk, and how to roll back; the
orchestrator never executes it).

### Orchestrator skill contract

```text
<orchestrator-skill>/
├── SKILL.md
└── references/
    ├── topology.md
    └── cited-strings.md
```

`SKILL.md` contains:

1. **Initial diagnostic pass.** A short cluster-wide read-safe probe set that the orchestrator runs before any expert.
2. **Candidate ranking** from the initial diagnostic pass + `topology.md`.
3. **Chain-walk loop** with a step budget. For each candidate: invoke the expert, apply the routing-policy on the
   structured output, decide STOP / NEXT / FALLBACK.
4. **Routing-policy** — purely structural lookup over the expert's output. No NLU on prose.

`references/topology.md` is the stack-node map: each node carries its `skill`, `downstream`, `upstream`. Replacing a
backend = edit this file.

`references/cited-strings.md` is the redirect table: regex patterns paired with `points_to` node ids, used when an
expert's evidence cites another component as the trigger.

### Routing policy

Apply in order; first match wins:

1. **Empty findings** → next hop is the downstream neighbour per topology.
2. **Evidence matches a cited-strings pattern** → next hop is the pattern's `points_to` node.
3. **`raw_diagnostic_pass` matches a cited-strings pattern** → same redirect.
4. **Otherwise** → STOP, surface the expert's findings as the final result.

The policy reads structured fields (`findings[].evidence`, `raw_diagnostic_pass`) with regex. It does not interpret
prose narratives.

### Adding to an existing package

- **New symptom for an existing expert.** Edit `references/symptoms.md`. Add one YAML entry. Do not edit `SKILL.md`
  unless the new symptom needs a probe that the fixed diagnostic pass does not already perform.
- **New expert (new technology).** Add the node to `topology.md` with `downstream` / `upstream` neighbours; create the
  expert folder with the three-section `SKILL.md`; update the orchestrator's initial diagnostic pass if a new zone needs
  surfacing; add eval cases for the new expert in isolation and in chain.
- **Topology change.** Edit `references/topology.md`. The orchestrator's `SKILL.md` does not change.

### Why this pattern works on a weak model

The expert's lookup is mechanical: match output against regex/value entries. No reasoning over topology. The
orchestrator's routing-policy is mechanical: regex over structured fields, lookup in a topology graph. No prose
comprehension required. Each skill is small enough to fit comfortably in the model's context together with its
references.

### Known shortcomings

Two open items worth keeping in mind when designing new packages around this pattern:

- **Symptom-id discipline is imperfect.** Experts sometimes emit invented `symptom_id` values instead of the canonical
  id from the catalogue. Routing is unaffected (it reads `findings`, `evidence` regex, and `raw_diagnostic_pass`), but
  the catalogue weakens as shared knowledge and rubric checks that grep for canonical ids fail. Mitigation: an explicit
  "MUST use the literal `id:` from the matched entry" instruction in each expert's `SKILL.md`, plus an "id enumeration"
  block listing current ids inline.
- **Cited-strings cascade is hard to test.** A cascade fires only when the downstream failure is _not_ visible to the
  orchestrator's initial pass. Most realistic faults are visible upstream and the orchestrator takes the shortest
  correct path, bypassing the cascade. Designing a fixture that exercises cascade routing requires hiding the failure
  from the initial pass (e.g. a NetworkPolicy that blocks traffic without breaking pod state).

## 3.2. Reference documents

Reference documents are the runbooks, lookup tables, and structured catalogues that skills load on demand. The shape
they take is what makes the grep-not-retrieval invariant (no vector store, no embedding index, agents search references
at runtime with their own tools) work in practice.

### Why grep, not retrieval

No vector store, no embedding index, no offline preprocessing. References are searched at runtime with the agent's own
tools: `grep` for keys, `Read` with offsets for bodies.

The trade-off is explicit. We pay more tokens per lookup than a retrieval pipeline would. In return: no indexing
infrastructure, no staleness window, no embedding-model dependency; the file on disk is the only source of truth;
editing it is the only thing needed to ship a change.

A reference that cannot be grepped against a known key is prose, not a reference, and belongs somewhere else.

### Three reference shapes

Pick by what the entries are keyed on, not by personal preference — each shape constrains how the agent searches it.

#### Shape A — Lookup table (Markdown table)

Use when: entries have a small fixed number of fields, each field fits on one line, the row key is short (a signal
phrase, a slug, an error code).

Rules:

- Column headings are stable across edits. Renaming a column is a breaking change for every skill that points at the
  file.
- The first column is the lookup key. It is unique — two rows with the same key is a defect.
- No multi-line cells. If a cell needs more than one line, the entry belongs in shape B, not here.
- One row per fact. Combining two signals in one row defeats grep.
- Sort order is documented at the top of the file so an editor inserting a new row knows where it goes.

Used for: signal tables (symptom → diagnostic command → target skill → prior), knowledge-area taxonomies (slug →
description → target L2 skill).

#### Shape B — Block-structured catalogue (Markdown headings + labelled fields)

Use when: entries are symptoms with a description, a root cause, and one or more procedures; each field is a paragraph,
a code block, or a list — not a one-liner; the heading itself is a searchable phrase (verbatim error text, or a short
failure-mode description).

This is the canonical shape for symptom catalogues consumed by experts' `references/symptoms.md`.

**Required structure.** One H2 per entry. Every entry has the same field labels in the same order. Field labels are
**bold** with a trailing colon — `**Symptoms:**`, not `### Symptoms` or `Symptoms:` plain. The skill greps for the
bold-colon form.

Required, in this order:

1. **Symptoms** — verbatim error strings, observable behaviour, where to see it. Bullet list preferred. Include the
   exact error text the user grep'd for, so the agent's match on the H2 is confirmed by the body.
2. **Root cause** — one or two short paragraphs. What is happening and why.
3. **How to fix** — ordered steps or commands. Mark destructive steps explicitly.

Optional, in this order if present:

- **How to check** — diagnostic commands to confirm the hypothesis before applying the fix. Goes between _Root cause_
  and _How to fix_ when present.
- **How to avoid this issue** — preventive guidance.
- **Note** — short caveats (one-line).
- **Warning** — destructive or expensive steps that need operator attention.

**Layout.**

```markdown
## <Short symptom name — searchable phrase>

**Symptoms:**

- <verbatim error text or observable signal>
- <one fact per bullet>

**Root cause:**

<one or two short paragraphs>

**How to check:**

\`\`\`bash <diagnostic commands> \`\`\`

**How to fix:**

1. <step>
2. <step>
```

**Heading rules.** The H2 text is the highest-signal phrase from the symptom — the verbatim error message when one
exists, otherwise component plus failure mode. One symptom per H2; do not nest sub-symptoms with H3. The H2 text is
stable; renaming = breaking change for every in-file anchor pointing at it.

**Field rules.** Labels are exact, including the colon. Empty fields don't get a label — omit
`**How to avoid this issue:**` rather than leave it empty. The same label never appears twice inside one symptom.

**Cross-references.** Inside the same file: link by H2 anchor. **Across files: not allowed.** A reference does not
assume the reader has another reference open. If two areas share a symptom, copy the entry or extract it into a shared
catalogue and point both areas at it.

#### Shape C — YAML structured records

Use when: entries have a strict schema with mandatory fields; entries are consumed both by humans and by a skill that
loads specific fields by name; machine-readable cross-references between entries matter.

Shape: a top-level list (`cases:` / `entries:` / …) of records. The schema is documented as a header comment block at
the top of the file. The skill greps for field names defined there.

Rules:

- The first comment block in the file is the schema.
- `id` (or the equivalent stable key) is the lookup key. Renaming = breaking change.
- All entries have all required fields. Optional fields are listed in the schema header.
- Don't mix schemas in one file. Two record shapes = two files.

Used for: trivial-cases catalogues consumed by L1 triage.

### Invariants across all shapes

- **Grep-friendly keys.** The body contains the searchable token verbatim. No paraphrasing the error text "for
  readability".
- **Self-contained.** A reference is usable without first reading another reference. Codes live where they are used.
- **Stable structure.** Once a shape is chosen for a file, every entry uses it. Adding a field means either adding it to
  every existing entry, or removing it entirely — never sometimes-present, sometimes-not.
- **One source of truth.** A fact lives in exactly one reference. If two references describe the same symptom, one is
  wrong.
- **No skill knowledge.** A reference describes domain facts (symptoms, signals, configuration) — not the skill that
  consumes it. "This row routes the agent to skill X" is a _column_ in a lookup table or a _field_ in a structured
  record, not free text in the entry body.

### How a skill points at a reference

The skill body must say, for each reference it depends on:

- file path (relative to the skill's `references/` directory),
- shape (A / B / C),
- what the agent greps for — the key column, the field name, or the heading shape,
- whether to `Read` the whole file or `grep` first.

This tells the agent how to query a reference it has not opened before, without resorting to a full scan.
