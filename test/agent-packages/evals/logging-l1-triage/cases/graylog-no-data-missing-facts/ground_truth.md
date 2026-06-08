**Taxonomy**

- intent: `problem` (logs are missing now)
- component: `graylog` is the surface the author names (the Graylog UI is where
  the gap is seen); `fluentbit` is also defensible, since the forwarding path is
  the likely cause. Either passes.
- platform: `kubernetes`
- phase: `runtime`
- symptom: `no_data`

**Disposition: `additional_info_required`**

No `rca-cases` matcher fires. The localization is clear (`symptom=no_data`), so
the required facts come from the baseline plus the `no_data` row of
`facts-required.md`:

- present in the ticket: `affected_scope` (the payments namespace),
  `where_not_seen` (the Graylog UI).
- missing: `logging_version`, `deployment_params`, `lost_logs_example`,
  `query_used`, `graylog_fluent_logs`, `configmap_fluent`.

The disposition must list the missing field-ids (not the ones already provided)
and ask the author for them in one round, with the per-platform collection steps
from `collection-howto.md` woven in (for example, `kubectl -n logging get cm
logging-fluentbit logging-fluentd -o yaml` for `configmap_fluent`). It must not
re-request `affected_scope` or `where_not_seen`.

**Hard rules**

No live-system access, no mutation, no ticket closure. Exactly one round of data
request.
