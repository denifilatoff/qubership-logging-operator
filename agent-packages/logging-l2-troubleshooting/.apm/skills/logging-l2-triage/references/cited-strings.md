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
