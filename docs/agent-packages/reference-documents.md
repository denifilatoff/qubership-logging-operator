# Reference Documents for Skills

**Status:** draft v0.1.

This document defines how reference documents — the runbooks, lookup tables, and structured catalogues that knowledge-area skills load on demand — are written so a coding agent can use them by `grep` and `Read` rather than by retrieval. It is the *how* behind the methodology's `Lookups by grep, not by retrieval` invariant (§1).

The audience is anyone authoring or editing a file under a skill's `references/` directory or a shared catalogue under `.apm/shared/`.

---

## 1. Why grep, not retrieval

We do not maintain a vector store, an embedding index, or any offline preprocessing step. References are searched at runtime with the agent's own tools: `grep` for keys, `Read` with offsets for bodies.

The trade-off is explicit. We pay more tokens per lookup than a retrieval pipeline would. In return:

- No indexing infrastructure, no staleness window, no embedding-model dependency.
- The file on disk is the only source of truth. Editing it is the only thing needed to ship a change.
- The skill body describes the file's shape (which columns / fields / headings exist, what to grep for, where the key sits), so the agent knows how to query a reference it has never opened before.

A reference document that cannot be grepped against a known key is prose, not a reference, and belongs in `docs/` rather than under a skill's `references/`.

---

## 2. Reference types

The skill-pack uses three reference shapes. Pick by what the entries are keyed on, not by personal preference — each shape constrains how the agent searches it.

### 2.1. Lookup table (Markdown table)

Use when:

- Entries have a small fixed number of fields.
- Each field fits on one line.
- The row key is short — a signal phrase, a slug, an error code.

Shape: one Markdown table, with stable column headings. The first column is the lookup key.

Rules:

- Column headings are stable across edits. Renaming a column is a breaking change to every skill that points at the file.
- The first column is unique. Two rows with the same key is a defect.
- No multi-line cells. If a cell needs more than one line, the entry belongs in a block-structured catalogue (§2.2), not a table.
- One row per fact. Combining two signals in one row defeats grep.
- Sort order is documented at the top of the file (alphabetical by key, by prior, by area, etc.) so an editor inserting a new row knows where it goes.

Examples in this repo:

- `signal-table.md` — runtime-signal → diagnostic command → target skill → prior.
- `knowledge-areas.md` — slug → area description → target L2 skill.

### 2.2. Block-structured catalogue (Markdown headings + labelled fields)

Use when:

- Entries are symptoms with a description, root cause, and one or more procedures.
- Each field is a paragraph, a code block, or a list — not a one-liner.
- The heading itself is a searchable phrase (verbatim error text, or a short failure-mode description).

This is the canonical shape for the symptom catalogues under `.apm/shared/symptoms/<area>.md`.

#### 2.2.1. Required structure per entry

One H2 per entry. Every entry has the same field labels in the same order. Field labels are **bold** with a trailing colon — `**Symptoms:**`, not `### Symptoms` or `Symptoms:` plain. The skill greps for the bold-colon form.

Required, in this order:

1. **Symptoms** — verbatim error strings, observable behaviour, where to see it. Bullet list preferred. Include the exact error text the user grep'd for, so the agent's match on the H2 is confirmed by the body.
2. **Root cause** — one or two short paragraphs. What is happening and why.
3. **How to fix** — ordered steps or commands. Kubernetes-only per the methodology's K8s-only invariant. Mark destructive steps explicitly.

Optional, in this order if present:

- **How to check** — diagnostic commands to confirm the hypothesis before applying the fix. Goes between *Root cause* and *How to fix* when present.
- **How to avoid this issue** — preventive guidance.
- **Note** — short caveats (one-line).
- **Warning** — destructive or expensive steps that need operator attention.

#### 2.2.2. Layout

```markdown
## <Short symptom name — searchable phrase>

**Symptoms:**

* <verbatim error text or observable signal>
* <one fact per bullet>

**Root cause:**

<one or two short paragraphs>

**How to check:**

\`\`\`bash
<diagnostic commands>
\`\`\`

**How to fix:**

1. <step>
2. <step>

**How to avoid this issue:**

<text>
```

#### 2.2.3. Heading rules

- The H2 text is the highest-signal phrase from the symptom. Verbatim error message when one exists ("Limit of total fields [1000] in index has been exceeded"); otherwise component plus failure mode ("Storage Full", "Graylog Pod OOM Killed").
- One symptom per H2. Do not nest sub-symptoms with H3. If two related symptoms share a fix, write the fix once in one H2 and have the other H2 cross-reference it via an in-file anchor.
- The H2 text is stable. Rename = breaking change for every in-file anchor that points at it.

#### 2.2.4. Field rules

- Field labels are exact: `**Symptoms:**` (with the colon, bold). No variants like `**Symptom:**`, `*Symptoms:*`, or `### Symptoms`. The skill body documents the exact string the agent greps for.
- Empty fields don't get a label. If a symptom has no preventive guidance, omit `**How to avoid this issue:**` rather than leaving an empty section.
- The same field label never appears twice inside one symptom. Two `**How to fix:**` blocks under one H2 = defect.

#### 2.2.5. Cross-references

- Inside the same file: link by H2 anchor — `[Storage Full](#storage-full)`.
- Across files: not allowed. Per the self-contained-docs principle, a reference does not assume the reader has another reference open. If two areas share a symptom, copy the entry or extract it into a shared `symptoms/<topic>.md` and point both areas at it.

Example file: `.apm/shared/symptoms/opensearch.md`.

### 2.3. YAML structured records

Use when:

- Entries have a strict schema with mandatory fields.
- Entries are consumed both by humans (reading the file) and by a skill that loads specific fields (e.g. `id`, `trigger`, `recommended_ticket_action`).
- Machine-readable cross-references between entries matter.

Shape: a top-level list (`cases:` / `entries:` / etc.) of records. Each record has the same schema. The schema is documented as a header comment block at the top of the file.

Rules:

- The first comment block in the file is the schema. The skill greps for field names defined there.
- `id` (or the equivalent stable key) is the lookup key. Renaming an `id` is a breaking change.
- All entries have all required fields. Optional fields are listed in the schema header.
- Don't mix schemas in one file. If two record shapes are needed, use two files.

Example: `trivial-cases.yaml`.

---

## 3. Invariants across all types

These apply to every reference document, regardless of shape.

- **Grep-friendly keys.** The body contains the searchable token verbatim. No paraphrasing the error text "for readability".
- **Self-contained.** A reference is usable without first reading another reference. No "see the codes table" — the codes live where they are used, or a copy lives in this file.
- **Stable structure.** Once a type is chosen for a file, every entry uses the same shape. Adding a new field means either adding it to every existing entry, or removing the field entirely — never sometimes-present, sometimes-not.
- **One source of truth.** A fact lives in exactly one reference. If two references describe the same symptom, one is wrong. Pick the canonical home and have the other point at it (within the rules of §2.2.5).
- **Versioning.** Schema-level changes (new required field, renamed column, renamed key) bump the skill manifest's `version`. Prose edits do not.
- **No skill knowledge.** The reference describes domain facts (symptoms, signals, configuration) — not the skill that consumes it. A reference does not mention "this row routes the agent to skill X" inside the row body; that mapping is the *column* in a lookup table or the *field* in a structured record, not free text.

---

## 4. How a skill points at its references

The skill body must say, for each reference it depends on:

- file path (relative to the skill's `references/` directory),
- type (§2.1 / §2.2 / §2.3),
- what the agent greps for — the key column, the field name, or the heading shape,
- whether to `Read` the whole file or `grep` first.

Example, from `logging-l2-triage/SKILL.md`:

> Match the observations against [references/signal-table.md](references/signal-table.md). That file has the symptom → target-skill mapping with priors. Do not paraphrase it back into this SKILL; load it on demand and cite the rows you matched.

This tells the agent: type is lookup table, key is the "Runtime signal observed" column, action is grep — not Read-the-whole-file.

---

## 5. Prior art and trade-offs

The conventions above are not novel. They borrow from:

- **KCS** (Knowledge-Centered Service) — the support-knowledge-base methodology behind `Issue / Environment / Resolution / Cause`. Our `Symptoms / Root cause / How to fix` is a thin variation: we drop *Environment* (the methodology's K8s-only invariant supplies it once for the whole pack) and keep the rest.
- **Diátaxis** — the documentation framework that separates *reference* (consult while working) from *how-to* (a procedure that gets work done). The block-structured catalogue (§2.2) is technically a hybrid: the H2 plus the symptoms block is reference (the agent looks the symptom up), and the how-to-fix block is how-to (a procedure that follows once the match lands). We accept the hybrid because the lookup key and the procedure live one Read away in the agent's flow; splitting them across files would force every match to chase a second reference.
- **Sigma rules** (security detection-as-code) — YAML rules with a stable schema and a stable `id`. Our §2.3 type follows the same principle.

What we deliberately do **not** follow:

- **Retrieval-augmented runbook indexes.** Recent practice ([context-optimised parsers, llms.txt for API docs](https://buildwithfern.com/post/optimizing-api-docs-ai-agents-llms-txt-guide)) replaces grep with structured retrieval to save tokens. We don't, because the trade-off described in §1 favours single-source-of-truth-on-disk over a separate index for our use case.
- **Executable runbook DSLs** ([PagerDuty / Rundeck](https://medium.com/@Quaxel/runbooks-to-agents-automating-the-boring-80-of-on-call-5b4d763cfe8b), and the recent ["Runbook as agent" work](https://rocm.blogs.amd.com/software-tools-optimization/maxtext-slurm-agentic-diagnosis/README.html)). Those are *executable* — they run on a runbook engine. Ours are *consulted* — the operator decides whether to run any recommended step. Different artefact, different shape.

No external spec is followed verbatim. The conventions here are the ones this skill-pack uses today; adapt them when adding a new type, do not blindly inherit from one of the references above.

---

## 6. Out of scope

- Internal authoring style of the *skill body* (`SKILL.md`) — covered by the `apm-authoring` skill in the host repo's `.claude/skills/`.
- Choice of file format for a new reference type beyond the three listed here. If a new shape is needed (e.g. JSON Schema, OpenAPI fragment), extend §2 first, then write the file.
- Catalogue versioning across major skill-pack releases. The `version:` field in `apm.yml` handles it; the migration story is not specified here.
- LLM-side context-window optimisation. The grep-not-retrieval invariant (§1) is the contract; further token-saving tricks belong in the skill body, not in the reference.
