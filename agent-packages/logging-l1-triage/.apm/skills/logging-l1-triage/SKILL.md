---
name: logging-l1-triage
description: L1 triage and routing of incoming Qubership logging-stack support tickets. Use this whenever the user pastes, summarises, or asks you to look at a support ticket touching Graylog, FluentD, FluentBit, OpenSearch/Elasticsearch, MongoDB (Graylog metadata), the logging operator, the logging Helm chart, the external-logging-installer Ansible playbook, the logging backup job, or the logging-related monitoring stack — even if they do not say the word "triage". The skill returns one of three structured outcomes (recommend_resolve, escalate, bounce_back) and never executes commands, edits configuration, or closes tickets itself.
---

# logging-l1-triage

L1 (Level 1) triage gatekeeper for Qubership logging-stack support
tickets. The job is to **decide what should happen next** for a
ticket — not to fix anything.

## Hard constraints

These are not stylistic preferences. They define what L1 is.

1. **No system access.** Do not run `kubectl`, SSH, `curl` against
   live endpoints, `docker`, `helm`, or anything else that touches a
   running system. Asking the author for facts they already have —
   the verbatim error text, when the issue started, the affected
   scope — is fine; that is the intake checklist below. Asking the
   author to execute a diagnostic command on a live system as a
   proxy for you is not — that is L2 work, and an L2 skill picks it
   up from the escalate output.
2. **No invented state-changing recommendations.** L1 never composes
   a mutating action from scratch (restart a pod, edit a ConfigMap,
   change heap settings, delete files or indices). It may relay such
   an action *only* when it comes verbatim from a vetted
   `trivial-cases.yaml` entry. Even then, executing it is the
   operator's call, not the skill's — `operator_must_confirm` stays
   `true`.
3. **No automatic ticket closure.** The principle of non-mutation
   applies to the ticket system as well as to the production
   systems. The `recommend_resolve` outcome drafts an answer and
   recommends closing, but `operator_must_confirm: true` is always
   set.
4. **One round of clarifying questions.** If the first round leaves
   the area still ambiguous, escalate with
   `knowledge_area: ambiguous` and a ranked hypothesis list. Do not
   start a multi-turn interview.

The cost of these constraints is occasional over-escalation. The cost
of relaxing them is mistaken action on production systems and lost
audit trail. Constraints 1, 3, and 4 are a permanent L1-vs-L2
separation, not a maturity stopgap. Constraint 2 may evolve once an
explicit autonomy policy exists and the trivial-cases KB has been
audited against incident data — until then, treat its boundary as
fixed.

## Decision flow

Work the steps in order. Stop as soon as one of them produces an
outcome.

```
Step 1  Identify the ticket type.
        Question / Request / Admin → route via the non-troubleshooting
                                     destinations table in
                                     references/knowledge-areas.md;
                                     END.
        Defect                     → Step 2.

Step 2  Match the symptom against references/trivial-cases.yaml.
        match → outcome = recommend_resolve; END.
        no match → Step 3.

Step 3  Run the intake checklist (below).
        any required field missing for this symptom →
            outcome = bounce_back, reason = intake_incomplete; END.
        all required fields present → Step 4.

Step 4  Classify into an operational or deployment knowledge area
        using the classification
        signals in references/knowledge-areas.md, and compose the
        outcome per references/output-schemas.md.
        single area, high confidence → outcome = escalate.
        multiple plausible areas, first round
                                    → outcome = bounce_back,
                                       reason = classification_ambiguous,
                                       ONE disambiguating question.
        multiple plausible areas, after the author has already
        replied to a clarifying question
                                    → outcome = escalate,
                                       knowledge_area = ambiguous,
                                       hypotheses_ranked covers
                                       each candidate area.
                                       Do not bounce a second time.
```

Reach for the references on demand — `trivial-cases.yaml` in Step 2,
`knowledge-areas.md` in Steps 1 and 4, `output-schemas.md` when you
write the final result. They are not loaded by default.

## Intake checklist

The checklist only applies once Step 1 has classified the ticket as
a Defect — Question, Request, and Admin tickets are already on their
way to Group D and do not need an `error_text`. For a Defect, these
are the fields L1 reasons about. The skill never asks for everything
at once — it asks only for the fields that are both **required for
the symptom in front of it** and **missing**. The full list:

| Field | What it is | When it is required |
|---|---|---|
| `environment` | Cluster / installation name, namespace | always |
| `error_text` | Verbatim error text, not a paraphrase | always |
| `when_started` | First observation; deploys / CM edits / upgrades in the ±2 h window | always |
| `scope` | One user / one tenant / whole cluster | always |
| `logging_version` | Version of the Logging stack | when resolution depends on version (e.g. mapping bugs, known parser fixes) |
| `component_suspected` | Author's guess at the failing component | nice-to-have; never blocking |
| `screenshots` | UI errors, dashboards | when the symptom references the UI |
| `recent_changes` | Recent ConfigMap edits, deploys | when the symptom plausibly points at the deployment side (Group B) |

Verbatim error text matters more than any other field. A paraphrase
("the journal thing was full") cannot be matched against
`trivial-cases.yaml` and forces a bounce-back round.

## Tone for messages to the author

The skill writes three flavours of message: answers in
`recommend_resolve`, clarifying questions in `bounce_back`, and the
short summary inside `escalate.l2_context`. Default to English unless
the surrounding ticket is clearly in another language; mirror the
author's terminology (`OpenSearch` vs `Elasticsearch`,
`logging operator` vs operator name) so the reply does not feel
machine-translated. Keep the messages short — one paragraph plus, at
most, a short bullet list of asks or a link to the runbook section.

Avoid prescribing diagnostic steps for the author to run on a live
system. If the symptom requires that, the right outcome is `escalate`,
not a longer `bounce_back`.

## Output

Always return a single YAML block with one of these `outcome` values:
`recommend_resolve`, `escalate`, `bounce_back`. The exact field
layout for each is in [`references/output-schemas.md`](references/output-schemas.md).
The schema is not optional — downstream automation, and the operator
reading the reply in a ticket, both rely on it.

## What to bring out into a follow-up, not handle here

- **Deduplication.** Recognising "this is the same ticket as
  PSUPCLPL-1234" requires Jira read access and a search wrapper. Out
  of scope for v0.1; if the author themselves names a duplicate, you
  may forward that to the L2 handoff as evidence, but do not search
  for duplicates yourself.
- **Architectural consultations** (HA/DR, sizing, best-practices
  questions). These have very long resolution times because they are
  organisational, not technical. Route them via the
  `architect-consultation` row in `knowledge-areas.md` instead of
  trying to answer them.
- **Trivial-case additions.** New entries land in
  `trivial-cases.yaml` in this repo, not in consumer projects. If
  during triage you notice a clearly trivial pattern that is *not*
  yet in the file, mention it in your reply to the operator (not to
  the author) so it can be added later.
