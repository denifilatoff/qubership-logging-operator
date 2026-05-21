# Output schemas

The skill always returns one YAML block. Pick the schema that
matches `outcome`. Field order in the output should follow the
order shown here so operators reading many tickets can scan
quickly.

The schemas are intentionally small. Anything that does not fit a
listed field belongs either in `response_to_author`,
`message_to_author`, `evidence`, or `l2_context` — do not invent new
top-level fields.

All `knowledge_area:` values are slugs from
[`knowledge-areas.md`](knowledge-areas.md). Same for `target_skill:`,
which is always either a `troubleshoot-<slug>` name or the literal
`none` (for non-troubleshooting destinations and for the
`ambiguous` fallback).

## `recommend_resolve`

Use when a `trivial-cases.yaml` entry matched and the recommended
action is safe to propose. The operator is the one who actually
closes the ticket; `operator_must_confirm` is always `true`.

```yaml
outcome: recommend_resolve
knowledge_area: opensearch           # slug from knowledge-areas.md
trivial_case_id: ism-config-cosmetic # id from trivial-cases.yaml
response_to_author: |
  <the answer the author should receive, drafted in their language>
runbook_section: troubleshooting.md#errors-no-such-index-opendistro-ism-config
recommended_ticket_action: close_as_resolved
operator_must_confirm: true
```

Notes:

- If the trivial-case entry has a `notes` block flagging a caveat
  (for example "only trivial when X"), and that caveat is *not*
  satisfied in this ticket, do not use `recommend_resolve`.
  Escalate instead.
- `response_to_author` substitutes `{{placeholders}}` from the
  trivial-case entry only when the value is known from the ticket
  (for example the OpenSearch endpoint named in a screenshot).
  Otherwise leave the placeholder in place — the operator will
  fill it in.

## `escalate`

Use when the ticket is a Defect, intake is complete, and one
operational or deployment area fits with high confidence (Step 4 of
the decision flow).

```yaml
outcome: escalate
target_skill: troubleshoot-fluent-collectors
knowledge_area: fluent-collectors
ticket_type: defect
priority: P2                                   # P0 catastrophe / P1 degradation /
                                               # P2 partial / P3 cosmetic
affected_scope: "single namespace: payments"
evidence:
  - "FluentBit pod logs: 'connection timeout to tcp://graylog:12201'"
  - "Most recent change: ConfigMap edit ~2 h before the report"
hypotheses_ranked:
  - "CPU throttling of FluentBit (most likely per runbook)"
  - "DNS resolution failure"
  - "NetworkPolicy blocking egress"
cross_cutting_hints:                           # optional; slugs from
  - k8s-resources                              # knowledge-areas.md
recommended_runbook_section: troubleshooting.md#connection-timeout-to-graylog-in-fluentbit
l2_context:
  check_first: "fluentbit.resources.limits.cpu and current usage"
  confirm:     "Graylog reachable from another pod in the same namespace"
```

Field rules:

- `target_skill` and `knowledge_area` must agree with the row in
  `knowledge-areas.md` — the slug after `troubleshoot-` is the
  area slug.
- `priority` is the L1 estimate based on author-reported scope and
  severity. L2 may revise it.
- `evidence` contains verbatim log snippets, error messages, and
  observed facts only. No interpretation — interpretations go in
  `hypotheses_ranked`.
- `hypotheses_ranked` is ordered: most likely first. Two or three
  entries are typical; more than four usually means classification
  is not as confident as the outcome claims.
- `cross_cutting_hints` is optional; use it to flag relevant
  cross-cutting modules (`tls-pki`, `k8s-resources`, `gelf-protocol`,
  …) so the L2 skill loads them earlier.
- `l2_context` is the short briefing the next skill reads first.
  Keep it to one or two lines per key.

### `escalate` with `knowledge_area: ambiguous`

Use only in the second-round case from the decision flow: the
author has already replied to one disambiguating question and the
area is still not single-valued.

```yaml
outcome: escalate
target_skill: none                             # no single L2 owner yet
knowledge_area: ambiguous
ticket_type: defect
priority: P2
affected_scope: "single tenant: payments"
evidence:
  - "Author confirms application logs are missing since 14:20 UTC"
  - "Graylog UI is reachable; recent messages from *other* tenants
     still arriving"
  - "No deploy in the ±2 h window per author"
hypotheses_ranked:
  - "fluent-collectors: tenant-scoped collector misconfiguration"
  - "graylog-server: stream / pipeline rule dropping this tenant"
candidate_areas:                               # required for ambiguous
  - fluent-collectors
  - graylog-server
recommended_runbook_section: troubleshooting.md#no-logs-from-one-tenant
l2_context:
  check_first: "which of the two areas owns the symptom — operator
                routes to the matching L2 skill"
```

Rules specific to the ambiguous form:

- `target_skill: none` — the operator picks the L2 skill after a
  quick triage glance. Do not guess.
- `candidate_areas` lists every slug under consideration, ordered
  the same way as `hypotheses_ranked`.
- `hypotheses_ranked` entries should be prefixed with the candidate
  area's slug so the operator sees which guess belongs to which
  area.

## `bounce_back`

Use when the intake checklist is incomplete *or* when classification
remains ambiguous after Step 4 (first round). Both cases use the
same outcome name but different `reason` values. A second
`bounce_back` round is not allowed — see the ambiguous-escalate
variant above.

```yaml
outcome: bounce_back
reason: intake_incomplete            # or: classification_ambiguous
message_to_author: |
  <one short paragraph asking only for the missing fields or
   answering one disambiguating question; drafted in the author's
   language>
fields_requested:
  - error_text
  - when_started
  - search_returning_recent_logs
```

Field rules:

- `reason: intake_incomplete` — list the missing intake fields in
  `fields_requested`. Ask only for what is needed *for this
  symptom*, not the whole checklist.
- `reason: classification_ambiguous` — `fields_requested` should
  contain a single disambiguating signal (e.g.
  `recent_deploy_in_window`, `ui_reachable`, `affected_scope`) and
  `message_to_author` should ask exactly one question.
