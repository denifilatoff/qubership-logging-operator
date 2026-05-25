---
description: Trigger for the logging-l1-triage skill on incoming logging-stack support tickets.
applyTo: "**/*"
---

## Skill trigger: `logging-l1-triage`

When the user pastes, summarises, or asks you to look at an incoming
support ticket about the Qubership logging stack — Graylog, FluentD,
FluentBit, OpenSearch / Elasticsearch, MongoDB (Graylog metadata), the
logging operator, the logging Helm chart, the `external-logging-installer`
Ansible playbook, the logging backup job, or the logging-related parts
of the monitoring stack (Telegraf, Prometheus, Grafana, Zabbix) — apply
the `logging-l1-triage` skill before drafting any reply.

L1 triage never executes diagnostic commands, never modifies
configuration, and never closes tickets. If the user is asking you to
run `kubectl` or change a ConfigMap, that is L2 work — escalate via the
skill's output schema instead of acting.
