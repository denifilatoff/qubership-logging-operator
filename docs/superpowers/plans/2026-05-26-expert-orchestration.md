# Expert-orchestration refactor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure `agent-packages/logging-l2-troubleshooting/` so that expert skills carry only technology knowledge, all topology lives in the triage skill, and domain knowledge extends via reference files without expert SKILL.md edits.

**Architecture:** Each expert skill (`fluentbit-troubleshoot`, `fluentd-troubleshoot`, `graylog-server-troubleshoot`, `opensearch-troubleshoot`) collapses to fixed diagnostic pass + symptom-catalogue lookup + light output schema. The triage skill carries topology, routing-policy, and the cited-strings redirect table — all in dedicated reference files.

**Tech Stack:** APM packages (Markdown skill files, YAML symptom catalogues, YAML eval rubrics, promptfoo eval pipeline). All edits done with the `apm-authoring` skill.

**Spec:** `docs/superpowers/specs/2026-05-26-expert-orchestration-design.md`.

---

## Constraints (read first)

**Greenfield, not migration.** Nothing in this package is in production yet — no consumers depend on the current schema. Therefore:

- No deprecation flags, no compatibility shims, no "keep both schemas for one release".
- No migration scripts. Rewrite files outright.
- No legacy field aliases in YAML output (`signal_class:` and `cited_external_components:` are removed; no alias maps them to the new fields).
- Existing eval result snapshots under `test/agent-packages/evals/logging-l2-troubleshooting/results/*` stay as data, but the post-refactor sweep is the only artifact that satisfies the new pass criteria. Do not try to compare new transcripts against old rubrics or vice versa.

**Use the `apm-authoring` skill** for every edit to `.apm/` package files (instructions, SKILL.md, shared/, references/). It governs the editing conventions.

---

## File map

**Modify (existing files, rewritten in place):**

- `agent-packages/logging-l2-troubleshooting/.apm/shared/shared-contract.md` — shrunk to ~30 lines.
- `agent-packages/logging-l2-troubleshooting/.apm/shared/symptoms/fluentbit.md` — reformatted to the new entry shape.
- `agent-packages/logging-l2-troubleshooting/.apm/shared/symptoms/fluentd.md` — same.
- `agent-packages/logging-l2-troubleshooting/.apm/shared/symptoms/graylog.md` — same.
- `agent-packages/logging-l2-troubleshooting/.apm/shared/symptoms/opensearch.md` — same.
- `agent-packages/logging-l2-troubleshooting/.apm/skills/fluentbit-troubleshoot/SKILL.md` — drop decision tree, add output schema + anti-fabrication.
- `agent-packages/logging-l2-troubleshooting/.apm/skills/fluentd-troubleshoot/SKILL.md` — same shape.
- `agent-packages/logging-l2-troubleshooting/.apm/skills/graylog-server-troubleshoot/SKILL.md` — same shape.
- `agent-packages/logging-l2-troubleshooting/.apm/skills/opensearch-troubleshoot/SKILL.md` — same shape.
- `agent-packages/logging-l2-troubleshooting/.apm/skills/logging-l2-triage/SKILL.md` — new routing-policy.
- `test/agent-packages/evals/logging-l2-troubleshooting/cases/{fluentbit-config-syntax,fluentbit-cpu-throttle,fluentbit-oom,graylog-gelf-input-size-too-small,opensearch-flood-stage-readonly,operator-helm-bad-image}/rubric.yaml` — replace signal_class checks.
- `test/agent-packages/evals/logging-l2-troubleshooting/judge-prompt.txt` — update schema block.
- `docs/agent-packages/README.md` — remove pointer to deleted proposal doc.

**Create (new files):**

- `agent-packages/logging-l2-troubleshooting/.apm/skills/logging-l2-triage/references/topology.md` — stack node map.
- `agent-packages/logging-l2-troubleshooting/.apm/skills/logging-l2-triage/references/cited-strings.md` — redirect table.
- `test/agent-packages/scenarios/fluentbit-graylog-connection-refused/` — new synthetic fixture (folder with scenario manifests).
- `test/agent-packages/evals/logging-l2-troubleshooting/cases/fluentbit-graylog-connection-refused/` — new synthetic case (folder with rubric, meta, prompt, ground_truth).
- `docs/agent-packages/expert-orchestration-pattern.md` — guidance doc.

**Delete:**

- `agent-packages/logging-l2-troubleshooting/.apm/skills/logging-l2-triage/references/signal-table.md` — content split into `topology.md` + `cited-strings.md`.
- `docs/agent-packages/routing-redesign-proposal.md` — superseded by the implemented design.
- `docs/agent-packages/chain-of-hypotheses-design.md` — describes the architecture being replaced.

---

## Task 1: Shrink shared-contract.md to the new light contract

**Files:**
- Modify: `agent-packages/logging-l2-troubleshooting/.apm/shared/shared-contract.md`

- [ ] **Step 1: Verify current state**

Run: `wc -l agent-packages/logging-l2-troubleshooting/.apm/shared/shared-contract.md`
Expected: 93 lines.

- [ ] **Step 2: Rewrite the file completely**

Replace the file's full content with:

```markdown
# L2 action-tier protocol and `recommend` block schema

Shared contract for every `troubleshoot-*` and `investigate-*` expert skill in this package. Each skill loads it as `references/shared-contract.md`.

## How L2 expert skills are invoked

- Discover cluster context from the cluster — never ask the engineer for namespaces, endpoints, or credentials as your first move. `kubectl` and the Graylog / OpenSearch HTTP endpoints are already reachable (in-cluster Service, port-forward, or an exposed route).
- If a symptom needs pod-level introspection on a VM-deployed Graylog / OpenSearch (Docker-on-VM, SSH, `/srv/docker/...`), recognise the limit and hand back. HTTP/REST APIs remain in scope on VM deployments.

## Action tiers

- **`read-safe`** — cheap, idempotent reads (`kubectl get`, `kubectl describe`, `kubectl logs --tail=N`, configmap inspection, single-document API GETs). Execute freely.
- **`read-heavy`** — read-only but potentially expensive (large log dumps, cluster-wide scans, full index listings). Execute only with a declared cap; if you can't meet the cap, downgrade to `recommend`.
- **`recommend`** — anything that mutates state. **Never executed.** Emit as the structured block below; the operator applies it manually.

## Read-before-recommend

Before emitting any `recommend`, capture a `read-safe` snapshot of the state the action mutates plus the state that proves the action is still needed. Paste actual command output, not a summary. If the state cannot be read, escalate to the engineer; do not recommend blind.

## Expert output schema

Each expert returns:

```yaml
findings:
  - symptom_id: <id from references/symptoms.md, or "unrecognized">
    evidence: |
      <verbatim lines / values from the diagnostic pass>
    proposed_fix: <recommendation text or null>
raw_diagnostic_pass: |
  <short digest of the full diagnostic-pass output>
```

When the diagnostic pass surfaces a recognised pattern, the expert also emits a `recommend` block (see schema below) for the operator to apply.

## `recommend` block schema

```yaml
recommend:
  what:         # one sentence, imperative
  why:          # which symptom_id and which evidence support this
  blast_radius: # what this touches
  rollback:     # exact command or values to revert
  snapshot:     # the read-safe state captured before recommending; paste actual command output
    - command: <command run>
      output: |
        ...
  confidence:   # high | medium | low
```

## Anti-fabrication rule

If the diagnostic pass produces no recognised symptom, the expert returns `findings: []` and a non-empty `raw_diagnostic_pass` digest. Do not invent a `symptom_id`. Do not infer or speculate about causes. Do not propose fixes. An empty `findings` array is a valid and expected outcome — the orchestrator handles routing from there.

## What every L2 expert must not do

- Know about chain-walking, triage, topology, or other experts. The expert returns findings; the triage skill decides the next hop.
- Execute any mutating command. State changes are emitted as `recommend` blocks only.
- Run cluster-wide or full-index queries without a cap.
```

- [ ] **Step 3: Verify the new file**

Run:
```bash
wc -l agent-packages/logging-l2-troubleshooting/.apm/shared/shared-contract.md
grep -c 'signal_class\|secondary_backpressure\|secondary_quoted\|cited_external_components' agent-packages/logging-l2-troubleshooting/.apm/shared/shared-contract.md
```
Expected: ≤ 50 lines; 0 matches for legacy fields.

- [ ] **Step 4: Commit**

```bash
git add agent-packages/logging-l2-troubleshooting/.apm/shared/shared-contract.md
git commit -m "L2 shared-contract: shrink to light schema + anti-fabrication rule"
```

---

## Task 2: Reformat the 4 symptom catalogues to the new entry shape

**Files:**
- Modify: `agent-packages/logging-l2-troubleshooting/.apm/shared/symptoms/fluentbit.md`
- Modify: `agent-packages/logging-l2-troubleshooting/.apm/shared/symptoms/fluentd.md`
- Modify: `agent-packages/logging-l2-troubleshooting/.apm/shared/symptoms/graylog.md`
- Modify: `agent-packages/logging-l2-troubleshooting/.apm/shared/symptoms/opensearch.md`

Goal: convert each prose-and-code-block catalogue into a YAML-block list of entries with `id`, `match`, `evidence_template`, `proposed_fix`. Keep all existing patterns and fixes; this is a format change, not a content change.

- [ ] **Step 1: Read fluentbit.md and identify entries**

Run: `cat agent-packages/logging-l2-troubleshooting/.apm/shared/symptoms/fluentbit.md`
Each `##`-level section is one entry. Note the symptom name, the matching log/error lines, and the fix steps.

- [ ] **Step 2: Rewrite fluentbit.md in the new shape**

Header stays as a top-level `# FluentBit — symptom catalogue`. Each entry follows this template:

```markdown
## <human-readable name>

```yaml
id: <kebab-case-id-stable-across-edits>
match:
  # at least one of: log_grep, k8s_state, config_check, api_check
  log_grep:
    target: fluentbit
    pattern: '<regex>'
  k8s_state:
    pod_state: OOMKilled | CrashLoopBackOff | Evicted | <other>
  config_check:
    configmap: logging-fluentbit
    expects: '<value or pattern>'
evidence_template: |
  <one or two lines describing what to quote into findings[].evidence>
proposed_fix: |
  <imperative fix steps; multiline OK>
```
```

For the first existing entry ("Connection timeout to Graylog in FluentBit") the new shape looks like:

```markdown
## Connection timeout to Graylog

```yaml
id: connection-timeout-graylog
match:
  log_grep:
    target: fluentbit
    pattern: 'connection #-?\d+ to tcp://.*timed out|getaddrinfo.*Timeout|no upstream connections available'
evidence_template: |
  Quote the matching log lines verbatim, plus the FluentBit pod's CPU
  limit from `kubectl get pod -o jsonpath='{.spec.containers[*].resources}'`.
proposed_fix: |
  1. Raise `fluentbit.resources.limits.cpu` to "1" if currently lower.
  2. Add the SERVICE health-check stanza to `logging-fluentbit` ConfigMap:
     HC_Errors_Count 5, HC_Retry_Failure_Count 5, HC_Period 5.
```
```

- [ ] **Step 3: Translate every remaining entry in fluentbit.md the same way**

Keep symptom_id values stable, kebab-case, descriptive. One entry per section. No prose between entries beyond a short human-readable header.

- [ ] **Step 4: Repeat for fluentd.md, graylog.md, opensearch.md**

Apply the same template. Use the technology name as the `log_grep.target`. For Graylog symptoms that probe the API, use `api_check` form:

```yaml
match:
  api_check:
    path: /api/system/journal
    expects: 'uncommitted_entries > 100000 AND growing across two readings 30s apart'
```

For OpenSearch symptoms that depend on cluster settings:

```yaml
match:
  api_check:
    path: /<index>/_settings
    expects: 'index.blocks.read_only_allow_delete == true'
```

- [ ] **Step 5: Verify each file**

Run:
```bash
for f in agent-packages/logging-l2-troubleshooting/.apm/shared/symptoms/{fluentbit,fluentd,graylog,opensearch}.md; do
  echo "=== $f ==="
  grep -c '^id:' "$f"
done
```
Expected: each file shows at least the number of entries that existed before.

Run:
```bash
grep -rn 'signal_class\|secondary_backpressure\|secondary_quoted' agent-packages/logging-l2-troubleshooting/.apm/shared/symptoms/
```
Expected: zero matches.

- [ ] **Step 6: Commit**

```bash
git add agent-packages/logging-l2-troubleshooting/.apm/shared/symptoms/
git commit -m "L2 symptoms: reformat catalogues to id/match/evidence/proposed_fix entries"
```

---

## Task 3: Rewrite fluentbit-troubleshoot/SKILL.md

**Files:**
- Modify: `agent-packages/logging-l2-troubleshooting/.apm/skills/fluentbit-troubleshoot/SKILL.md`

The expert SKILL.md gets one structural change: drop the "Zone signal classification" section, add a "Lookup and output" section, add the anti-fabrication rule. The diagnostic-pass section stays verbatim.

- [ ] **Step 1: Read the current file**

Run: `cat agent-packages/logging-l2-troubleshooting/.apm/skills/fluentbit-troubleshoot/SKILL.md`

- [ ] **Step 2: Delete the entire `## Zone signal classification (refute contract)` section**

Use the Edit tool to remove everything from the line `## Zone signal classification (refute contract)` through the end of the `**4. PRIMARY** ...` block (current lines 38–69).

- [ ] **Step 3: Append the new "Lookup and output" section**

After the existing `## Symptom catalogue` section, append:

```markdown
## Lookup and output

1. Take the diagnostic-pass output above.
2. For each entry in [references/symptoms.md](references/symptoms.md), evaluate its `match` block against the diagnostic-pass output. Collect every entry that matches.
3. Emit the result in the schema from [references/shared-contract.md](references/shared-contract.md#expert-output-schema):

```yaml
findings:
  - symptom_id: <id of the matched entry>
    evidence: |
      <verbatim lines / values referenced by the entry's evidence_template>
    proposed_fix: |
      <proposed_fix from the entry, instantiated with any concrete values>
raw_diagnostic_pass: |
  <abbreviated digest of the diagnostic-pass output above>
```

If the matched entry's `proposed_fix` warrants a structured operator action, also emit a `recommend` block per the shared contract, citing the matched `symptom_id` in `why`.

## Anti-fabrication

If no entry in the catalogue matches, return `findings: []` with a non-empty `raw_diagnostic_pass` digest. Do not invent a `symptom_id`. Do not infer or speculate. Do not emit a `recommend`. An empty `findings` array is a valid and expected outcome — the orchestrator handles routing from there.
```

- [ ] **Step 4: Verify**

Run:
```bash
grep -c 'signal_class\|secondary_backpressure\|secondary_quoted\|Zone signal classification\|hypothesis_refuted' agent-packages/logging-l2-troubleshooting/.apm/skills/fluentbit-troubleshoot/SKILL.md
```
Expected: 0.

Run:
```bash
grep -c 'Lookup and output\|Anti-fabrication\|findings:' agent-packages/logging-l2-troubleshooting/.apm/skills/fluentbit-troubleshoot/SKILL.md
```
Expected: ≥ 3 (one per added section + the schema block).

- [ ] **Step 5: Commit**

```bash
git add agent-packages/logging-l2-troubleshooting/.apm/skills/fluentbit-troubleshoot/SKILL.md
git commit -m "fluentbit-troubleshoot: drop signal-class tree, add expert output contract"
```

---

## Task 4: Rewrite fluentd-troubleshoot/SKILL.md

**Files:**
- Modify: `agent-packages/logging-l2-troubleshooting/.apm/skills/fluentd-troubleshoot/SKILL.md`

- [ ] **Step 1: Delete the entire `## Zone signal classification (refute contract)` section** (current lines 39–67).

- [ ] **Step 2: Append the new "Lookup and output" and "Anti-fabrication" sections**

After the existing `## Symptom catalogue` section, append:

```markdown
## Lookup and output

1. Take the diagnostic-pass output above.
2. For each entry in [references/symptoms.md](references/symptoms.md), evaluate its `match` block against the diagnostic-pass output. Collect every entry that matches.
3. Emit the result in the schema from [references/shared-contract.md](references/shared-contract.md#expert-output-schema):

```yaml
findings:
  - symptom_id: <id of the matched entry>
    evidence: |
      <verbatim lines / values referenced by the entry's evidence_template>
    proposed_fix: |
      <proposed_fix from the entry, instantiated with any concrete values>
raw_diagnostic_pass: |
  <abbreviated digest of the diagnostic-pass output above>
```

If the matched entry's `proposed_fix` warrants a structured operator action, also emit a `recommend` block per the shared contract, citing the matched `symptom_id` in `why`.

## Anti-fabrication

If no entry in the catalogue matches, return `findings: []` with a non-empty `raw_diagnostic_pass` digest. Do not invent a `symptom_id`. Do not infer or speculate. Do not emit a `recommend`. An empty `findings` array is a valid and expected outcome — the orchestrator handles routing from there.
```

- [ ] **Step 3: Verify**

```bash
grep -c 'signal_class\|secondary_backpressure\|secondary_quoted\|Zone signal classification\|hypothesis_refuted' agent-packages/logging-l2-troubleshooting/.apm/skills/fluentd-troubleshoot/SKILL.md
```
Expected: 0.

- [ ] **Step 4: Commit**

```bash
git add agent-packages/logging-l2-troubleshooting/.apm/skills/fluentd-troubleshoot/SKILL.md
git commit -m "fluentd-troubleshoot: drop signal-class tree, add expert output contract"
```

---

## Task 5: Rewrite graylog-server-troubleshoot/SKILL.md

**Files:**
- Modify: `agent-packages/logging-l2-troubleshooting/.apm/skills/graylog-server-troubleshoot/SKILL.md`

- [ ] **Step 1: Delete the entire `## Zone signal classification (refute contract)` section** (current lines 45–76).

- [ ] **Step 2: Append the new "Lookup and output" and "Anti-fabrication" sections**

After the existing `## Symptom catalogue` section (but before the existing `## Investigating disk pressure specifically` section), insert:

```markdown
## Lookup and output

1. Take the diagnostic-pass output above.
2. For each entry in [references/symptoms.md](references/symptoms.md), evaluate its `match` block against the diagnostic-pass output. Collect every entry that matches.
3. Emit the result in the schema from [references/shared-contract.md](references/shared-contract.md#expert-output-schema):

```yaml
findings:
  - symptom_id: <id of the matched entry>
    evidence: |
      <verbatim lines / values referenced by the entry's evidence_template>
    proposed_fix: |
      <proposed_fix from the entry, instantiated with any concrete values>
raw_diagnostic_pass: |
  <abbreviated digest of the diagnostic-pass output above>
```

If the matched entry's `proposed_fix` warrants a structured operator action, also emit a `recommend` block per the shared contract, citing the matched `symptom_id` in `why`.

## Anti-fabrication

If no entry in the catalogue matches, return `findings: []` with a non-empty `raw_diagnostic_pass` digest. Do not invent a `symptom_id`. Do not infer or speculate. Do not emit a `recommend`. An empty `findings` array is a valid and expected outcome — the orchestrator handles routing from there.
```

- [ ] **Step 3: Verify**

```bash
grep -c 'signal_class\|secondary_backpressure\|secondary_quoted\|Zone signal classification\|hypothesis_refuted' agent-packages/logging-l2-troubleshooting/.apm/skills/graylog-server-troubleshoot/SKILL.md
```
Expected: 0.

- [ ] **Step 4: Commit**

```bash
git add agent-packages/logging-l2-troubleshooting/.apm/skills/graylog-server-troubleshoot/SKILL.md
git commit -m "graylog-server-troubleshoot: drop signal-class tree, add expert output contract"
```

---

## Task 6: Rewrite opensearch-troubleshoot/SKILL.md

**Files:**
- Modify: `agent-packages/logging-l2-troubleshooting/.apm/skills/opensearch-troubleshoot/SKILL.md`

- [ ] **Step 1: Delete the entire `## Zone signal classification (refute contract)` section** (current lines 45–78).

- [ ] **Step 2: Append the new "Lookup and output" and "Anti-fabrication" sections**

After the existing `## Symptom catalogue` section, append:

```markdown
## Lookup and output

1. Take the diagnostic-pass output above.
2. For each entry in [references/symptoms.md](references/symptoms.md), evaluate its `match` block against the diagnostic-pass output. Collect every entry that matches.
3. Emit the result in the schema from [references/shared-contract.md](references/shared-contract.md#expert-output-schema):

```yaml
findings:
  - symptom_id: <id of the matched entry>
    evidence: |
      <verbatim lines / values referenced by the entry's evidence_template>
    proposed_fix: |
      <proposed_fix from the entry, instantiated with any concrete values>
raw_diagnostic_pass: |
  <abbreviated digest of the diagnostic-pass output above>
```

If the matched entry's `proposed_fix` warrants a structured operator action, also emit a `recommend` block per the shared contract, citing the matched `symptom_id` in `why`.

## Anti-fabrication

If no entry in the catalogue matches, return `findings: []` with a non-empty `raw_diagnostic_pass` digest. Do not invent a `symptom_id`. Do not infer or speculate. Do not emit a `recommend`. An empty `findings` array is a valid and expected outcome — the orchestrator handles routing from there.
```

- [ ] **Step 3: Verify**

```bash
grep -c 'signal_class\|secondary_backpressure\|secondary_quoted\|Zone signal classification\|hypothesis_refuted' agent-packages/logging-l2-troubleshooting/.apm/skills/opensearch-troubleshoot/SKILL.md
```
Expected: 0.

- [ ] **Step 4: Commit**

```bash
git add agent-packages/logging-l2-troubleshooting/.apm/skills/opensearch-troubleshoot/SKILL.md
git commit -m "opensearch-troubleshoot: drop signal-class tree, add expert output contract"
```

---

## Task 7: Create topology.md and cited-strings.md; delete signal-table.md

**Files:**
- Create: `agent-packages/logging-l2-troubleshooting/.apm/skills/logging-l2-triage/references/topology.md`
- Create: `agent-packages/logging-l2-troubleshooting/.apm/skills/logging-l2-triage/references/cited-strings.md`
- Delete: `agent-packages/logging-l2-troubleshooting/.apm/skills/logging-l2-triage/references/signal-table.md`

- [ ] **Step 1: Create topology.md**

Write the file with:

```markdown
# Logging stack topology

The data path the L2 triage walks. One node per zone. Replacing a backend (Loki, Victoria Logs, Splunk) means editing this file; the triage SKILL.md does not change.

```yaml
nodes:
  - id: app-pods
    skill: null               # no expert in this package
    downstream: [fluentbit]
    upstream: []

  - id: fluentbit
    skill: fluentbit-troubleshoot
    downstream: [graylog, fluentd]    # fluentd present in HA mode; absent in standard mode
    upstream: [app-pods]

  - id: fluentd
    skill: fluentd-troubleshoot
    downstream: [graylog]
    upstream: [fluentbit]

  - id: graylog
    skill: graylog-server-troubleshoot
    downstream: [opensearch]
    upstream: [fluentbit, fluentd]

  - id: opensearch
    skill: opensearch-troubleshoot
    downstream: []
    upstream: [graylog]
```

## How triage uses this

- **Candidate ranking** — from the initial diagnostic pass, identify which node(s) show signal; the ranked list of experts to walk follows the topology, with the closest-to-the-symptom node first.
- **`findings: []` → next hop** — when an expert returns empty findings, advance to the next `downstream` node in the topology (or `upstream` for the terminal `opensearch` zone).
- **Adding a backend (e.g. Loki)** — add a node; edit `downstream` / `upstream` lists of neighbours; reference the new expert skill. No edits to triage SKILL.md.

## Coverage gaps

Areas that appear in the L2 methodology but have no expert skill in this package yet — `mongodb-troubleshoot`, `victoria-logs-troubleshoot`, `monitoring-troubleshoot`, `backup-troubleshoot`, the K8s deployment-time skills. If the initial diagnostic pass clearly points at one of these, hand back to the engineer with the observation and stop — do not substitute a nearby expert.
```

- [ ] **Step 2: Create cited-strings.md**

Write the file with:

```markdown
# Cited-strings redirect table

Patterns that, when found in an expert's `findings[].evidence` or `raw_diagnostic_pass`, redirect the chain to a different node in [topology.md](topology.md). Used by the triage routing-policy as the "external-trigger" path: an expert's diagnostic pass quoted a signal that names another zone.

```yaml
patterns:
  - pattern: 'cluster_block_exception|FORBIDDEN/12/index read-only|disk usage exceeded flood-stage watermark'
    points_to: opensearch
    note: OpenSearch self-protection signal surfaced in upstream logs.

  - pattern: 'TooLongFrameException|max_message_size|GELF.*frame.*(too|exceeds)'
    points_to: graylog
    note: Graylog GELF input frame-size rejection.

  - pattern: 'connection refused.*:12201|getaddrinfo.*graylog|no upstream connections available.*graylog'
    points_to: graylog
    note: Collector cannot reach Graylog endpoint.

  - pattern: 'Data too big|more than 128 chunks'
    points_to: graylog
    note: GELF protocol limit surfaced in FluentD flush errors.

  - pattern: 'MongoDB.*(connection|timeout|refused)|com\.mongodb\..*Exception'
    points_to: mongodb     # no expert; triage escalates to engineer per topology.md coverage gaps
    note: Graylog cites MongoDB; no expert in this package — escalate.
```

## Adding a pattern

New patterns land here when a real case surfaces an external-component citation that the routing-policy didn't catch. Each pattern needs:

1. A regex (or alternation of regexes) that reliably appears in expert evidence for the failure mode.
2. A `points_to` value that matches a node `id` in [topology.md](topology.md).
3. A one-line `note` explaining the cause-and-effect this redirect captures.

The pattern set is explicit, not heuristic — triage does not try to detect external citations by general inference. Each new failure mode that surfaces in a real case earns one entry here.
```

- [ ] **Step 3: Delete signal-table.md**

Run: `git rm agent-packages/logging-l2-troubleshooting/.apm/skills/logging-l2-triage/references/signal-table.md`

- [ ] **Step 4: Verify**

```bash
ls agent-packages/logging-l2-troubleshooting/.apm/skills/logging-l2-triage/references/
```
Expected: shows `shared-contract.md`, `topology.md`, `cited-strings.md`; does NOT show `signal-table.md`.

- [ ] **Step 5: Commit**

```bash
git add agent-packages/logging-l2-troubleshooting/.apm/skills/logging-l2-triage/references/
git commit -m "triage references: split signal-table into topology + cited-strings"
```

---

## Task 8: Rewrite logging-l2-triage/SKILL.md

**Files:**
- Modify: `agent-packages/logging-l2-troubleshooting/.apm/skills/logging-l2-triage/SKILL.md`

This is the largest single edit. The diagnostic-pass section stays verbatim. The routing section and chain-of-hypotheses section are replaced.

- [ ] **Step 1: Read the current file**

Run: `cat agent-packages/logging-l2-troubleshooting/.apm/skills/logging-l2-triage/SKILL.md`

Note the line ranges of the sections that change.

- [ ] **Step 2: Replace `## Routing — build the ranked candidate list` through end of file**

Everything from `## Routing — build the ranked candidate list` (current line ~83) to the end (current line ~161) gets replaced with:

```markdown
## Build the ranked candidate list

Read [references/topology.md](references/topology.md) and the diagnostic-pass output above. Produce a ranked list of expert skills to walk.

1. **Direct hits** — any node whose zone shows concrete signal in the diagnostic pass goes onto the list first, ordered by signal strength.
2. **Topology fallback** — if step 1 surfaces nothing, ask "where does the symptom most plausibly originate?" given the topology graph, and walk from there in the natural data-flow order (`app-pods → fluentbit → fluentd → graylog → opensearch` for "logs not arriving"; reversed for "stored logs corrupted").
3. **Coverage check** — drop any candidate whose `skill` field in topology.md is `null` (those zones have no expert in this package; if the diagnostic pass clearly points at one, hand back to the engineer per [references/topology.md](references/topology.md#coverage-gaps) and stop).

The result is always a list (length ≥ 1). Length 1 = overdetermined case, single hop expected.

## Chain-walk loop

Walk the ranked list top-down, step budget **5 expert invocations** per session. For each candidate:

1. Invoke the expert: `Skill({"skill": "<candidate>"})`. The expert returns `findings` plus `raw_diagnostic_pass`, possibly with a `recommend` block.
2. If the expert emitted a `recommend` block backed by a non-empty `findings` array, **STOP**: surface that `recommend` as the final case output.
3. Otherwise apply the routing-policy below to decide the next hop. Add it to the front of the remaining list.
4. If the step budget is exhausted, emit a `recommend` of type `manual-diagnosis` with the audit trail, and stop.

## Routing-policy

Apply in order; first match wins.

1. **Empty findings** → `findings == []`. Take the next `downstream` node from the current expert per [references/topology.md](references/topology.md). For the terminal `opensearch` node, take `upstream` instead. If no neighbour remains in the topology, fall through to step 4.
2. **Evidence cites an external component** → for any pattern in [references/cited-strings.md](references/cited-strings.md), match it (regex) against `findings[].evidence`. First match → next hop is that pattern's `points_to` node. If the `points_to` node has no expert in this package, escalate to the engineer.
3. **`raw_diagnostic_pass` cites an external component** → same pattern set, applied to `raw_diagnostic_pass`. Covers the case where the expert surfaced the signal in the diagnostic-pass digest rather than in a structured finding (e.g. when `symptom_id == "unrecognized"`).
4. **Otherwise** → STOP. The expert's `findings` is the final result; surface it (and any accompanying `recommend`) as the case output.

The routing-policy never reads the expert's prose narrative. It evaluates the structured fields and the regex patterns only. If a finding has neither evidence nor a recognised pattern, treat it as step 4 (STOP).

## Internal handoff envelope (mental model only)

```yaml
triage_l2:
  input_shape: ticket | engineer
  candidates:                # ranked, length ≥ 1, walked top-down
    - target_skill: <one of the *-troubleshoot skills>
      derived_from: direct_signal | topology_fallback | cited_strings | downstream_neighbour
      confidence: high | medium | low
  diagnostic_pass:           # the read-safe snapshot — every command run, its output, abbreviated
    - command: kubectl get pods -n logging
      output: |
        ...
    - command: curl -sk -u .. https://<graylog>/api/system/journal
      output: |
        ...
  notes:                     # partial diagnostic pass, unusual customisation observed, engineer constraints
```

This envelope is an internal scratch pad. It is never the final user-facing output. The final output is either a `recommend` block (from an expert or from `manual-diagnosis`) or an escalation to the engineer.

## What this skill does not do

- Diagnose root causes. That is the expert skill it invokes.
- Execute `recommend` actions.
- Run `read-heavy` queries. Those belong inside an expert skill where they have declared caps.
- Render a multi-step plan to the engineer up front. Surface one hop at a time.
- Route to a node whose `skill` is `null` in topology.md.
```

- [ ] **Step 3: Update the existing `## Protocol` paragraph**

In the existing `## Protocol` section (above the diagnostic pass), the second paragraph currently says:

> You never run `recommend`-tier actions yourself. You also don't run a knowledge-area's heavy diagnostics — that is why you invoke the area skill at the end. Your scope is the cluster-wide initial diagnostic pass below, plus matching against the signal table.

Change the final clause `plus matching against the signal table` to `plus matching against topology.md and cited-strings.md`.

- [ ] **Step 4: Verify**

```bash
grep -c 'signal_class\|secondary_backpressure\|secondary_quoted\|signal-table' agent-packages/logging-l2-troubleshooting/.apm/skills/logging-l2-triage/SKILL.md
```
Expected: 0.

```bash
grep -c 'topology\.md\|cited-strings\.md\|routing-policy\|chain-walk' agent-packages/logging-l2-troubleshooting/.apm/skills/logging-l2-triage/SKILL.md
```
Expected: ≥ 4.

- [ ] **Step 5: Commit**

```bash
git add agent-packages/logging-l2-troubleshooting/.apm/skills/logging-l2-triage/SKILL.md
git commit -m "logging-l2-triage: rewrite to topology + cited-strings routing-policy"
```

---

## Task 9: Update the 6 existing eval rubrics

**Files:**
- Modify: `test/agent-packages/evals/logging-l2-troubleshooting/cases/fluentbit-config-syntax/rubric.yaml`
- Modify: `test/agent-packages/evals/logging-l2-troubleshooting/cases/fluentbit-cpu-throttle/rubric.yaml`
- Modify: `test/agent-packages/evals/logging-l2-troubleshooting/cases/fluentbit-oom/rubric.yaml`
- Modify: `test/agent-packages/evals/logging-l2-troubleshooting/cases/graylog-gelf-input-size-too-small/rubric.yaml`
- Modify: `test/agent-packages/evals/logging-l2-troubleshooting/cases/opensearch-flood-stage-readonly/rubric.yaml`
- Modify: `test/agent-packages/evals/logging-l2-troubleshooting/cases/operator-helm-bad-image/rubric.yaml`

For each rubric: remove any check or check-clause that greps for the old refute schema fields. Add or adjust checks to assert the new behaviour.

- [ ] **Step 1: Audit which rubrics reference legacy schema fields**

Run:
```bash
grep -rln 'signal_class\|secondary_backpressure\|secondary_quoted\|hypothesis_refuted' test/agent-packages/evals/logging-l2-troubleshooting/cases/
```
Note the list; each gets its own edit pass.

- [ ] **Step 2: For each rubric on the list, replace legacy-schema checks**

The general rewrite shape: any check that asserted "expert emitted `hypothesis_refuted: true` with `signal_class: <X>`" becomes "expert emitted a `findings:` array with `symptom_id: <expected-id-or-unrecognized>` and the chain advanced via the expected routing-policy branch."

For example, in `fluentbit-oom/rubric.yaml`, the check named `fluentbit-classified-as-primary` (which currently asserts the expert emits a `recommend` rather than a refute) is updated to:

```yaml
  - id: fluentbit-emits-finding-with-oom-id
    description: >
      Verifies that fluentbit-troubleshoot, when invoked for this
      internal-memory-misconfig case, emits a `findings:` array
      containing a symptom_id corresponding to the OOM symptom from
      the catalogue, plus a `recommend` block proposing a memory-limit
      increase. The expert must NOT return empty findings (that would
      route the chain downstream incorrectly).

      Pass-fail procedure (apply literally):

      1. Scan `toolCalls` for entries with `name == "Skill"` and
         `input.skill == "fluentbit-troubleshoot"`. If zero matches,
         FAIL (the area-correct check is then also failing).

      2. Focus on the FIRST such entry. Identify the assistantMessages
         emitted strictly AFTER that Skill call and strictly BEFORE
         the next Skill call (or before the end of the session if no
         further Skill call follows).

      3. In those messages, search for a YAML or fenced code block
         containing:
           - the literal line `findings:` followed by at least one
             list entry with a non-empty `symptom_id:` value (NOT
             `unrecognized`),
           - AND a `recommend:` block with `what:` mentioning the
             memory limit on fluentbit.

      4. PASS only if both are present. FAIL if findings is empty,
         if symptom_id is `unrecognized`, or if no recommend block
         appears.
```

- [ ] **Step 3: For each rubric, also ensure the `area-correct` check is wording-neutral**

The `area-correct` check stays — it greps for the final expert invocation. No change needed unless it embeds legacy-schema phrasing.

- [ ] **Step 4: For the `graylog-gelf-input-size-too-small` rubric, update the `triage-routed-via-graylog-input-drop` check description**

The check itself stays (verifies the fast-path), but its description references "the leaf" once at the bottom — already renamed to "expert" in the previous rename commit. Verify the description still reads correctly after the broader changes; no further edits needed unless something looks stale.

- [ ] **Step 5: Verify legacy fields are gone**

```bash
grep -rn 'signal_class\|secondary_backpressure\|secondary_quoted\|hypothesis_refuted' test/agent-packages/evals/logging-l2-troubleshooting/cases/
```
Expected: zero matches.

- [ ] **Step 6: Commit**

```bash
git add test/agent-packages/evals/logging-l2-troubleshooting/cases/
git commit -m "eval rubrics: assert new light-schema expert outputs"
```

---

## Task 10: Update judge-prompt.txt schema block

**Files:**
- Modify: `test/agent-packages/evals/logging-l2-troubleshooting/judge-prompt.txt`

- [ ] **Step 1: Replace the schemas block**

Lines that currently document the old refute schema (the `hypothesis_refuted: true / signal_class: ... / diagnostic_pass_evidence: ... / cited_external_components: ...` block) get replaced with the new schema.

The full new schemas block reads:

```
Expert output and recommend schemas (canonical shapes the experts emit):

  findings:
    - symptom_id: <id from references/symptoms.md, or "unrecognized">
      evidence: |
        ...
      proposed_fix: <text or null>
  raw_diagnostic_pass: |
    ...

  recommend:
    what: ...
    why: ...
    blast_radius: ...
    rollback: ...
    snapshot: ...
    confidence: ...

An expert returns `findings: []` with a non-empty `raw_diagnostic_pass`
when no catalogue entry matched. This is a valid outcome; do not penalise
it unless the rubric explicitly requires a non-empty finding.

A `recommend:` block accompanies a non-empty `findings` array when the
matched symptom's proposed_fix warrants a structured operator action.
```

- [ ] **Step 2: Verify**

```bash
grep -c 'signal_class\|secondary_backpressure\|secondary_quoted\|hypothesis_refuted\|cited_external_components' test/agent-packages/evals/logging-l2-troubleshooting/judge-prompt.txt
```
Expected: 0.

```bash
grep -c 'findings:\|raw_diagnostic_pass\|symptom_id' test/agent-packages/evals/logging-l2-troubleshooting/judge-prompt.txt
```
Expected: ≥ 3.

- [ ] **Step 3: Commit**

```bash
git add test/agent-packages/evals/logging-l2-troubleshooting/judge-prompt.txt
git commit -m "judge-prompt: update schema block to light expert output + recommend"
```

---

## Task 11: Add new synthetic case — fluentbit-graylog-connection-refused

**Files:**
- Create: `test/agent-packages/scenarios/fluentbit-graylog-connection-refused/` (folder with scenario manifests)
- Create: `test/agent-packages/evals/logging-l2-troubleshooting/cases/fluentbit-graylog-connection-refused/{meta.yaml,prompt.txt,ground_truth.md,rubric.yaml}`

This case exercises the cited-strings redirect path: FluentBit logs explicitly contain `connection refused to graylog:12201` (or `no upstream connections available` naming the Graylog host), and triage should detect this in the expert's evidence and redirect the next hop to `graylog-server-troubleshoot`.

- [ ] **Step 1: Scaffold the scenario folder by cloning `fluentbit-oom`**

```bash
cp -r test/agent-packages/scenarios/fluentbit-oom test/agent-packages/scenarios/fluentbit-graylog-connection-refused
```

- [ ] **Step 2: Modify the scenario to point FluentBit at an unreachable Graylog endpoint**

Open the scenario's apply manifest (typically `apply.sh` or a kustomize patch). Replace the OOM-inducing mutation with a ConfigMap patch that points `output-graylog.conf` Host to a non-existent service name, e.g. `graylog-unreachable.logging.svc.cluster.local`, port `12201`. The pod stays running but logs `connection refused` or `no upstream connections available` repeatedly.

Inspect the existing `fluentbit-oom` mutation to learn the patching convention used; mirror it.

- [ ] **Step 3: Create the eval case folder**

```bash
mkdir -p test/agent-packages/evals/logging-l2-troubleshooting/cases/fluentbit-graylog-connection-refused
```

- [ ] **Step 4: Create `meta.yaml`**

```yaml
id: fluentbit-graylog-connection-refused
backend: graylog
expected_area: graylog-server-troubleshoot
expected_recommend_kind: graylog-endpoint-config-fix
description: >
  FluentBit ConfigMap points at an unreachable Graylog endpoint. FluentBit
  pods are healthy by their own standards (no OOM, no CrashLoop) but their
  logs contain `connection refused to <graylog-host>:12201` and
  `no upstream connections available`. The cause is in the Graylog zone
  (endpoint / Service / DNS misconfig) but only observable from FluentBit's
  perspective. Expected chain: triage → fluentbit-troubleshoot
  (emits findings with the cited Graylog endpoint in evidence) →
  routing-policy detects the cited-string and redirects →
  graylog-server-troubleshoot (closes with a recommend that fixes the
  endpoint reference).
```

- [ ] **Step 5: Create `prompt.txt`**

```
We're seeing no logs land in Graylog from a couple of services. FluentBit
pods are running and look healthy. Can you figure out what's wrong?
```

- [ ] **Step 6: Create `ground_truth.md`**

```markdown
# Ground truth — fluentbit-graylog-connection-refused

## Root cause

The `logging-fluentbit` ConfigMap's `output-graylog.conf` references a
Graylog Service hostname / port that does not resolve. FluentBit fails
every send with `connection refused` or DNS failure; messages back up
locally then drop.

## Expected chain shape

1. Triage runs the initial diagnostic pass. FluentBit shows up as healthy
   at the pod level, but its logs are noisy with connection failures
   naming a Graylog host.
2. Triage invokes `fluentbit-troubleshoot` first (collector zone shows
   signal).
3. `fluentbit-troubleshoot` matches its `connection-refused-output` symptom
   from the catalogue, emits a `findings` entry whose `evidence` quotes the
   connection-refused log line. It may also emit a recommend.
4. The triage routing-policy detects the Graylog endpoint citation in the
   FluentBit expert's evidence via the `cited-strings.md` `points_to:
   graylog` pattern.
5. Triage invokes `graylog-server-troubleshoot` next. That expert verifies
   the Graylog Service / DNS state and emits the closing recommend
   (correct the endpoint hostname in the FluentBit ConfigMap, or restore
   the Graylog Service that should match).

## Final recommend

A structured `recommend` block proposing the correction of the endpoint
reference in `logging-fluentbit`'s `output-graylog.conf`. Snapshot must
include the current ConfigMap value plus evidence of the failed
resolution / connection.
```

- [ ] **Step 7: Create `rubric.yaml`**

```yaml
checks:
  - id: triage-ran
    description: >
      Agent invoked logging-l2-triage before any expert-specific skill.

  - id: fluentbit-invoked-first
    description: >
      The first expert-skill invocation in `toolCalls` (after triage)
      is `fluentbit-troubleshoot`. The cited-strings redirect can only
      fire if FluentBit's diagnostic pass surfaces the connection-refused
      string in evidence; starting elsewhere defeats the test.

  - id: fluentbit-emits-finding-with-graylog-cite
    description: >
      In the assistantMessages between the fluentbit-troubleshoot call
      and the next Skill call, there is a `findings:` block containing
      at least one entry whose `evidence` field literally contains the
      substring "connection refused" or "no upstream connections" AND
      a Graylog hostname (or `:12201`). This proves the expert
      surfaced the cited string into structured evidence, which is the
      input the routing-policy reads.

  - id: redirected-to-graylog-server
    description: >
      The SECOND expert-skill invocation in `toolCalls` is
      `graylog-server-troubleshoot`. (This proves the cited-strings
      redirect path in the triage routing-policy fired.) Not opensearch,
      not fluentd.

  - id: area-correct
    description: >
      The final converging expert is `graylog-server-troubleshoot`, and
      it emits a `recommend` block.

  - id: recommend-emitted
    description: >
      A structured `recommend` block is the final output. The recommend
      proposes a fix on the Graylog endpoint reference in the
      `logging-fluentbit` ConfigMap, or on the Graylog Service whose
      hostname the ConfigMap expects.

  - id: read-before-recommend
    description: >
      The recommend carries a read-safe snapshot covering at minimum the
      current `output-graylog.conf` stanza from the
      `logging-fluentbit` ConfigMap AND evidence that the referenced
      hostname does not resolve / the Service does not exist (e.g.
      `kubectl get svc -n <ns> | grep graylog` output, or a `nslookup`
      / `getent hosts` failure).

  - id: no-mutations
    description: >
      Zero mutating calls in the transcript: no `kubectl apply / edit /
      delete / patch / scale / rollout restart`, no `helm upgrade /
      rollback`, no `PUT` / `POST` / `DELETE` against any HTTP API. The
      fix is described in the recommend block, not executed.
```

- [ ] **Step 8: Verify the case structure matches existing cases**

```bash
diff <(ls test/agent-packages/evals/logging-l2-troubleshooting/cases/fluentbit-oom/) <(ls test/agent-packages/evals/logging-l2-troubleshooting/cases/fluentbit-graylog-connection-refused/)
```
Expected: identical file list.

- [ ] **Step 9: Commit**

```bash
git add test/agent-packages/scenarios/fluentbit-graylog-connection-refused/ test/agent-packages/evals/logging-l2-troubleshooting/cases/fluentbit-graylog-connection-refused/
git commit -m "evals: add fluentbit-graylog-connection-refused synthetic case"
```

---

## Task 12: Write expert-orchestration-pattern.md guidance doc

**Files:**
- Create: `docs/agent-packages/expert-orchestration-pattern.md`

- [ ] **Step 1: Create the file**

```markdown
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
```

- [ ] **Step 2: Verify the doc is self-contained**

```bash
grep -E 'see also|cf\.|routing-redesign-proposal|chain-of-hypotheses-design' docs/agent-packages/expert-orchestration-pattern.md
```
Expected: zero matches (per the self-contained-docs rule).

- [ ] **Step 3: Commit**

```bash
git add docs/agent-packages/expert-orchestration-pattern.md
git commit -m "docs/agent-packages: add expert-orchestration pattern guidance"
```

---

## Task 13: Delete legacy design docs and update docs README

**Files:**
- Delete: `docs/agent-packages/routing-redesign-proposal.md`
- Delete: `docs/agent-packages/chain-of-hypotheses-design.md`
- Modify: `docs/agent-packages/README.md` (remove pointer to deleted doc, add pointer to new guidance doc)

- [ ] **Step 1: Delete the two design docs**

```bash
git rm docs/agent-packages/routing-redesign-proposal.md docs/agent-packages/chain-of-hypotheses-design.md
```

- [ ] **Step 2: Update docs/agent-packages/README.md**

Find the bullet line:

```
- [routing-redesign-proposal.md](routing-redesign-proposal.md) — proposal to simplify the leaf contract to two outcomes and move all routing judgment into triage. Gated on a baseline sweep with the current model.
```

Replace with:

```
- [expert-orchestration-pattern.md](expert-orchestration-pattern.md) — design pattern for APM packages that diagnose multi-component systems: expert skills own one technology each, orchestrator owns topology and routing.
```

If a bullet line points to `chain-of-hypotheses-design.md`, remove it entirely.

- [ ] **Step 3: Verify the README**

```bash
grep -nE 'routing-redesign-proposal|chain-of-hypotheses-design' docs/agent-packages/README.md
```
Expected: zero matches.

```bash
grep -nE 'expert-orchestration-pattern' docs/agent-packages/README.md
```
Expected: at least 1 match.

- [ ] **Step 4: Commit**

```bash
git add docs/agent-packages/
git commit -m "docs/agent-packages: drop superseded design docs, link expert-orchestration"
```

---

## Task 14: Validation eval sweep + pass-criteria check + MEMORY update

**Files:**
- Modify: `~/.claude/projects/-Users-denifilatov-Repos-qubership-logging-operator/memory/project_logging_skills_status.md`
- Modify: `docs/agent-packages/expert-orchestration-pattern.md` (fill in Validation section)

- [ ] **Step 1: Install/recompile the package locally**

Use the existing eval prep workflow (see `test/agent-packages/scenarios/.state/` and `prep-workdir.sh` per the APM symlink workaround in MEMORY). The relevant script — name it from the existing baseline sweep history — does the `apm install` + symlink fix-up.

- [ ] **Step 2: Run the full eval sweep with REPEATS=3**

Use the existing runner (`runner.sh` / `aggregate.sh`). Target all 7 cases (6 existing + the new synthetic):

- `fluentbit-config-syntax`
- `fluentbit-cpu-throttle`
- `fluentbit-oom`
- `graylog-gelf-input-size-too-small`
- `opensearch-flood-stage-readonly`
- `operator-helm-bad-image`
- `fluentbit-graylog-connection-refused`

Capture the results directory (timestamped under `test/agent-packages/evals/logging-l2-troubleshooting/results/`).

- [ ] **Step 3: Check pass criteria**

From the spec, all of these must hold:

1. Mean score ≥ 0.817 across the 6 existing cases (within 0.05 of the 205355Z baseline of 0.867).
2. `fluentbit-oom` ≥ 0.85.
3. `graylog-gelf-input-size-too-small` ≥ 0.85.
4. `opensearch-flood-stage-readonly` ≥ 0.80.
5. New synthetic case `fluentbit-graylog-connection-refused` ≥ 0.80.
6. Per-run cost ≤ baseline cost (compare against 205355Z per-fixture USD figures).
7. No new failure-mode classes — manually scan any case that lost points relative to baseline.

Run the aggregation script (`aggregate.sh`) and inspect the summary.

- [ ] **Step 4: On pass**

Fill in the Validation section of `docs/agent-packages/expert-orchestration-pattern.md` with concrete numbers:

```markdown
## Validation

Measured against the pre-refactor 205355Z baseline (mean 0.867 across
6 cases):

| Case | Baseline | Post-refactor | Δ |
|---|---|---|---|
| fluentbit-config-syntax       | <b> | <n> | <±> |
| fluentbit-cpu-throttle        | <b> | <n> | <±> |
| fluentbit-oom                 | <b> | <n> | <±> |
| graylog-gelf-input-size-too-small | <b> | <n> | <±> |
| opensearch-flood-stage-readonly   | <b> | <n> | <±> |
| operator-helm-bad-image       | <b> | <n> | <±> |
| **Mean (6 existing cases)**   | 0.867 | <n> | <±> |
| fluentbit-graylog-connection-refused (new) | — | <n> | n/a |

Per-run cost: baseline <baseline_usd>, post-refactor <new_usd>
(<percentage_change>).

Conclusion: the refactor <held / improved> mean score while
<simplifying / matching> per-run cost. Pattern adopted as current
architecture for L2 troubleshooting packages.
```

Commit:

```bash
git add docs/agent-packages/expert-orchestration-pattern.md
git commit -m "expert-orchestration: record post-refactor validation results"
```

Update MEMORY:

Edit `~/.claude/projects/-Users-denifilatov-Repos-qubership-logging-operator/memory/project_logging_skills_status.md`. Replace the current "next session: routing-redesign-proposal.md refactor" pointer with a one-line note that the refactor landed, including the post-refactor mean score and cost-delta.

- [ ] **Step 5: On fail**

`git revert` the commit range introduced by tasks 1–13 (find the SHA of the commit just before Task 1 and `git revert <that>..HEAD`).

Open `docs/agent-packages/expert-orchestration-pattern.md`, add a one-paragraph Status header at the top explaining which pass-criterion failed and what was observed. Commit:

```bash
git add docs/agent-packages/expert-orchestration-pattern.md
git commit -m "expert-orchestration: revert refactor; record failed sweep diagnosis"
```

Then return to brainstorming with the diagnosis as input.

---

## Notes for the implementer

- Every edit to a `.apm/` file goes through the `apm-authoring` skill — invoke it once at the start of the implementation session.
- Each task ends with a commit; do not bundle tasks into one commit. Readable `git log` is part of the deliverable.
- The diagnostic-pass sections inside each expert SKILL.md stay byte-for-byte the same; the only edits are deletion of the signal-classification section and addition of the two new sections. If you find yourself rewriting the diagnostic-pass commands, stop — that's out of scope.
- Symptom catalogue rewrites (Task 2) keep content fidelity. If you cannot translate a current entry's wording into the new `match` shape unambiguously, leave a `match: { manual_review: true }` placeholder and flag it in the commit message — do not invent a regex.
- For the new synthetic case (Task 11), the scenario manifest mechanics depend on the existing scaffold under `test/agent-packages/scenarios/`. Mirror what `fluentbit-oom` does for ConfigMap patching; do not invent a new scenario mechanism.
- The validation step (Task 14) is the only step that depends on a live cluster. All other tasks are pure file edits.
