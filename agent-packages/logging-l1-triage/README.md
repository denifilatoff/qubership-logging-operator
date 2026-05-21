# logging-l1-triage

L1 triage and routing skill for incoming Qubership logging-stack support
tickets. The agent reads a ticket (Graylog, FluentD/FluentBit,
OpenSearch, MongoDB, logging operator, Helm chart, Ansible installer,
backup, monitoring) and produces one of three structured outcomes:

- `recommend_resolve` — the symptom matches a known trivial case; the
  skill drafts an answer to the author and recommends closing the
  ticket. A human operator confirms the close; the skill never closes
  tickets itself.
- `escalate` — the ticket is a defect with enough information to
  classify into one Group A (operational) or Group B (deployment)
  knowledge area. The skill produces a structured handoff for the
  corresponding L2 troubleshooting skill.
- `bounce_back` — either the intake checklist is incomplete or the
  symptom is ambiguous across multiple knowledge areas. The skill
  drafts one round of targeted clarifying questions.

L1 has **no server access**. It does not run `kubectl`, SSH, or any
diagnostic command; it does not modify configuration; and it does not
close tickets. Any state-changing recommendation belongs in an L2
skill, not here.

## Install

```sh
apm install Netcracker/qubership-logging-operator/agent-packages/logging-l1-triage
```

Then run `apm compile` to merge the trigger into your local
`AGENTS.md` / `CLAUDE.md`.

## What you get

- A short instruction that nudges the agent toward the skill whenever
  the user pastes or summarises an incoming logging-stack ticket.
- The skill itself
  ([`SKILL.md`](.apm/skills/logging-l1-triage/SKILL.md)) — decision
  flow, intake checklist, classification signals, output schemas.
- Reference data the skill loads on demand:
  - [`trivial-cases.yaml`](.apm/skills/logging-l1-triage/references/trivial-cases.yaml)
    — the trivial-case knowledge base (`recommend_resolve` matcher).
  - [`knowledge-areas.md`](.apm/skills/logging-l1-triage/references/knowledge-areas.md)
    — Group A / Group B / Group D taxonomy used to pick the
    `target_skill`.
  - [`output-schemas.md`](.apm/skills/logging-l1-triage/references/output-schemas.md)
    — full YAML schema for each outcome.

## Scope and limits

- Single round of clarifying questions. If a second round would be
  needed, the skill escalates with `area: ambiguous` and a ranked
  hypothesis list instead.
- No deduplication against the ticket system in v0.1. That requires
  Jira read access and is tracked as a follow-up.
- `trivial-cases.yaml` is seeded from the current `troubleshooting.md`
  runbook. New entries are added in this repo, not patched into
  consumer projects.
