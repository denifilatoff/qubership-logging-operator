# Eval pipeline — logging-l1-triage

Local eval for the L1 triage skill package. One declarative `promptfooconfig.yaml`
runs every case: a synthetic ticket goes in, the agent under test (Claude Code on
Haiku) classifies it and decides a disposition, and a judge (Claude Code on
Sonnet) grades the transcript.

L1 never touches live systems, so this eval has no kind cluster, no
fault-injection scenarios, and no fixture lifecycle — just text in, a verdict
out. Cases run in parallel.

## Cases

Nine hand-authored cases, three per `logging-l1-outcome` disposition. The ticket
texts are **synthetic** — authored from the shape of real tickets, with no real
keys, customers, hostnames, or versions — and each is written so the skills' own
mechanical matchers route it to the intended disposition:

| Disposition | Cases |
|---|---|
| `suspected_known_issue` | a `rca-cases` matcher fires and its caveat holds |
| `additional_info_required` | clear localization, required field-ids missing, no `rca-cases` hit |
| `handoff_to_l2` | every required field-id present inline, no `rca-cases` hit, no L1 resolution |

## Prerequisites

- `claude` CLI logged into the Claude Code subscription — both providers route
  through this session, so no `ANTHROPIC_API_KEY` is needed.
- `apm`, `node`, `npx`, and `python3` on PATH. `promptfoo` runs via
  `npx promptfoo@latest`.
- One-time setup in this directory:

  ```bash
  cd test/agent-packages/evals/logging-l1-triage
  make setup
  ```

  This installs `@anthropic-ai/claude-agent-sdk` into a local `node_modules/`
  (gitignored).

## Run

```bash
# All cases, --repeat 3 (override with REPEATS=N). Writes the run JSON and a
# summary.md.
make eval

# Re-summarize the last run without re-running it.
make report

# Open promptfoo's web UI on the stored runs.
make view
```

Run one case by filtering on its slug:

```bash
npx promptfoo@latest eval -c promptfooconfig.yaml --repeat 1 --no-cache \
  --filter-pattern '^os-fields-limit-exceeded$' --output results/smoke.json
node report.js results/smoke.json
```

## Layout

- `promptfooconfig.yaml` — the whole eval: `cases.js` generates the tests,
  `hooks.js` installs the package into `.workdir/with-pkg`, and the two inline
  providers (Haiku agent, Sonnet judge) plus the `rubric` and `routing`
  assertions score each run.
- `cases.js` — enumerates `cases/*/` into promptfoo test cases.
- `hooks.js` — `beforeAll` only: `apm install` + symlink fix. No scenarios.
- `report.js` — turns the run JSON into `results/<run>/summary.md` from
  promptfoo's native metrics, with a `disposition` column. `routing` passes only
  when both skills ran.
- `Makefile` — `eval`, `report`, `view`, `clean`, `setup`.
- `judge-prompt.txt` — the LLM judge's rubric prompt.
- `cases/<slug>/` — one directory per case:
  - `ticket.txt` — the synthetic ticket intake (the agent input).
  - `ground_truth.md` — expected taxonomy, disposition, and branch specifics.
  - `rubric.yaml` — the checks the judge applies.
  - `meta.yaml` — case metadata (disposition, gold localization).
- `results/` — per-run JSON and `summary.md` (gitignored).
