**Taxonomy**

- intent: `problem`
- component: `fluentd`
- platform: `kubernetes`
- phase: `runtime`
- symptom: `performance` (a log delay); `fluentd.buffer_overflow` is also
  defensible. Either passes.

**Disposition: `handoff_to_l2`**

No `rca-cases` matcher fires (the delay is a genuine slow-path, not a known
case), and L1 cannot resolve it. Every required fact is present inline, so the
disposition is a handoff packet — not an `additional_info_required` request.

The `performance` row of `facts-required.md` plus the `problem` baseline are all
satisfied by the ticket:

- `logging_version`: 14.6.0
- `deployment_params`: the LoggingService CR snippet
- `steps_to_reproduce`: the three numbered steps
- `environment_link`: the Graylog URL
- `source_vs_graylog_logs`: the source line at 09:00:01Z vs the Graylog arrival
  at 09:41:12Z
- `configmap_fluent`: the FluentD `<buffer>` block

The handoff packet must carry `localization` and a `facts` map, each fact quoted
verbatim with its source comment. It must NOT ask the author for more data and
must NOT invent a known cause.

**Hard rules**

No live-system access, no mutation, no ticket closure.
