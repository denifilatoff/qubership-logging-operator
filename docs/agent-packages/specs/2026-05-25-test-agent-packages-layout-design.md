# Test & agent-package layout

Status: draft for review
Date: 2026-05-25

## Mental model

- **Skill package** — distribution unit; own lifecycle; ships via APM.
- **Scenario** — failure injected on a running logging stack. Shared
  between skills. One scenario × N skills = N evals.
- **Eval** — per-skill expectation (prompt + ground truth + rubric) for
  one (skill, scenario) pair.

Skill packages contain only what ships to consumers. Test infrastructure
lives in its own tree.

## Layout

```
agent-packages/                          # distribution only
  logging-l1-triage/
    .apm/
    apm.yml
    README.md
  logging-l2-troubleshooting/
    .apm/
    apm.yml
    README.md

deploy/kind/                             # cluster baseline only
  helmfile.yaml.gotmpl
  values-*.yaml
  hooks/
  .env.example
  README.md

test/
  envtests/                              # unchanged
  robot-tests/                           # unchanged
  agent-packages/                        # tests for our skill packages
    scenarios/                           # shared cluster failures
      lib.sh                             # KCTX, KIND_DIR, KUBECTL helpers
      fixture.sh                         # apply / revert / list runner
      fluentbit-config-syntax/
        apply.sh
        revert.sh
        README.md
      fluentbit-oom/
      fluentbit-cpu-throttle/
      opensearch-flood-stage-readonly/
      graylog-gelf-input-size-too-small/
      operator-helm-bad-image/
      README.md                          # contract: what stack must be up
    evals/                               # per-skill expectations
      logging-l2-troubleshooting/
        promptfooconfig.yaml
        Makefile
        providers/
        cases/
          fluentbit-oom/
            prompt.txt
            ground_truth.md
            rubric.yaml
            meta.yaml
          ...
        results/                         # gitignored
        README.md
      logging-l1-triage/                 # appears when first eval lands

docs/
  agent-packages/                        # cross-cutting meta-docs
    README.md                            # index
    specs/
      YYYY-MM-DD-<slug>-design.md
    eval-pipeline-design.md
    eval-framework-survey.md
    skill-evaluation-methodology.md
    package-layering-model.md
    reference-documents.md
    troubleshooting-methodology.md
    archive/
  (operator product docs untouched)
```

## Naming convention for scenarios

`<component>-<problem>` slug. No prefix, no numbering.

- Component prefix gives `ls`-grouping: `fluentbit-*` clusters all
  fluentbit scenarios together.
- Slug self-documents what breaks and how.
- Add or remove a scenario without renumbering anything else.

Tags for filtering live in each scenario's `meta.yaml`:
`backend: graylog`, `component: fluentbit`, `severity: ...` etc. Use
these to filter / group at runtime instead of encoding meaning in the
directory name.

## Scenario runtime contract

Scenarios are not kind-specific. They depend on **runtime state of the
logging stack**, not on how it was provisioned. The contract a
scenario can assume:

- Cluster reachable via context `$KCTX` (set by `lib.sh` from `.env`).
- Namespaces present: `logging`, `opensearch`, `graylog`,
  `log-generator` (subset depending on `BACKEND`).
- Services with the names produced by `deploy/kind/helmfile.yaml.gotmpl`:
  `opensearch-cluster.opensearch`, `graylog-service.logging`,
  `log-generator-svc.log-generator`.
- Operator running in `logging` as helm release
  `qubership-logging-operator`. Required only for scenarios that do
  `helm upgrade --reuse-values`: `fluentbit-oom`,
  `fluentbit-cpu-throttle`, `operator-helm-bad-image`.
- `BACKEND=graylog` for scenarios that touch graylog or opensearch:
  `opensearch-flood-stage-readonly`, `fluentbit-cpu-throttle`,
  `graylog-gelf-input-size-too-small`.

`deploy/kind/` is one way to satisfy this contract — currently the
only one we ship. A stack provisioned by other means (Argo, Flux,
manual helm) that meets the contract supports the same scenarios.

`test/agent-packages/scenarios/README.md` states this contract
explicitly. `deploy/kind/README.md` references it as one supported
provisioning method.

### Path resolution

`lib.sh` computes `KIND_DIR` relative to its own location:

```bash
KIND_DIR="$(cd "$SCRIPT_DIR/../../../deploy/kind" && pwd)"
```

Scenarios that need the operator chart compute it from `KIND_DIR`:

```bash
CHART="$KIND_DIR/../../charts/qubership-logging-operator"
```

This keeps scenarios portable: relocating `test/agent-packages/` is a
single edit in `lib.sh`.

## Documentation home

`docs/agent-packages/` is the home for everything cross-cutting between
skill packages — design specs, methodology, framework research,
evaluation models. Rules:

- These docs are **not** part of any skill's distribution. They
  describe our process, decisions, and shared methodology.
- The existing `docs/` tree (api.md, architecture.md, cookbook, etc.)
  is the operator's user-facing product documentation.
  `agent-packages/` sits inside it as a separate sub-tree so the docs
  root stays unified while the audience is clear.
- Implementation specs go under `docs/agent-packages/specs/` with a
  `YYYY-MM-DD-<slug>-design.md` filename.
- `docs/agent-packages/README.md` is a one-screen index.

Skill-internal references — material the skill itself reads at runtime
— stay under `.apm/skills/<name>/references/` and ship with the
package. The line: if the skill cites the doc in its own body, it's a
reference; if a human reads it to understand the skill, it's a meta-doc
and lives under `docs/agent-packages/`.

## Verification

After the layout lands, two checks must pass:

1. **APM install pulls only distribution material.**
   `apm install <path-to-agent-packages/logging-l2-troubleshooting> --target claude`
   must complete without `apm audit` blockers, and
   `apm_modules/_local/logging-l2-troubleshooting/` must contain only
   `.apm/`, `apm.yml`, `README.md`.
2. **Eval pipeline runs end-to-end.**
   `cd test/agent-packages/evals/logging-l2-troubleshooting && make eval-<one-scenario>`
   must execute against a live kind cluster, apply the scenario,
   produce a graded result, and revert cleanly.

## Out of scope

- Promptfoo vs inspect-ai choice — separate decision.
- Converting helm-aware scenarios (`fluentbit-oom`,
  `fluentbit-cpu-throttle`, `operator-helm-bad-image`) to
  provisioning-agnostic `kubectl patch`. These scenarios use
  `helm upgrade --reuse-values` against the operator release, which
  leaks the provisioning method into the scenario; cleanup is tracked
  separately.
- Promoting any specific document from `docs/agent-packages/` into a
  skill's `.apm/skills/<name>/references/`. Default home is the
  meta-doc tree; promotion happens on demand when a skill cites it.
- Operator product docs under `docs/` (api.md, architecture.md, etc.).
- L1 eval pipeline — `test/agent-packages/evals/logging-l1-triage/`
  appears when the first L1 eval lands; no scaffolding ahead of time.
