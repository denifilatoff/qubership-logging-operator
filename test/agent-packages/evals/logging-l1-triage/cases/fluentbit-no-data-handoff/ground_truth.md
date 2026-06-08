**Taxonomy**

- intent: `problem`
- component: `fluentbit` (the forwarder failing to reach Graylog); `graylog` is
  a weaker but defensible read of the surface. fluentbit is preferred.
- platform: `kubernetes`
- phase: `runtime`
- symptom: `no_data`

**Disposition: `handoff_to_l2`**

No `rca-cases` matcher fires — a `connection refused` to the GELF input is not a
catalogued known case, so L1 cannot resolve it. Every required fact is present
inline, so the disposition is a handoff packet, not an
`additional_info_required` request.

The `no_data` row of `facts-required.md` plus the `problem` baseline are all
satisfied:

- `logging_version`: 14.8.1
- `deployment_params`: the LoggingService CR snippet
- `affected_scope`: namespace billing, service billing-api
- `lost_logs_example`: the node log line at 10:15:02Z
- `where_not_seen`: the Graylog UI (All messages stream)
- `query_used`: `source:billing-api AND namespace:billing`
- `graylog_fluent_logs`: the fluent-bit `connection refused` lines and the
  Graylog input status
- `configmap_fluent`: the fluent-bit GELF `[OUTPUT]` section

The handoff packet must carry `localization` and a `facts` map, each fact quoted
verbatim with its source. It must NOT ask for more data and must NOT invent a
known cause.

**Hard rules**

No live-system access, no mutation, no ticket closure.
