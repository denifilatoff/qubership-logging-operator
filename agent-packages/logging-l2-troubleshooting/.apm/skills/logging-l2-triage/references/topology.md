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
