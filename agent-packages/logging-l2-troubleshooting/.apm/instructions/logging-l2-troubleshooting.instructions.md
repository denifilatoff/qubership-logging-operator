---
description: L2 routing and troubleshooting for the Qubership logging stack — entry point is `logging-l2-triage`, which inspects the live cluster and hands off to the matching knowledge-area skill.
applyTo: "**/*"
---

## Skill trigger: logging-l2-triage

When the engineer is troubleshooting a problem in the Qubership logging stack against a **live cluster** — anything about Graylog, OpenSearch (or Elasticsearch), FluentD, FluentBit, log volume on disk, "logs not arriving", "Graylog journal full", "who's filling our log storage", an L1 handoff with `area: ambiguous`, or a free-form co-debug session — invoke `logging-l2-triage`.

Do this even when the area looks obvious from the engineer's description. `logging-l2-triage` runs a short read-safe sweep across the cluster and grounds the routing decision in what is actually true right now, not in the words of the complaint. It then hands off to one of:

- `graylog-server-troubleshoot`
- `opensearch-troubleshoot`
- `fluentd-troubleshoot`
- `fluentbit-troubleshoot`
- `graylog-disk-usage-investigate`

All skills in this package are read-only against live systems. Any state-changing fix is emitted as a structured `recommend` block per the shared protocol in `.apm/shared/shared-contract.md` — the operator decides whether and when to apply it.

If the engineer is **not** in front of a live cluster (working from a ticket only, no `kubectl` / API access), use `logging-l1-triage` (separate package) instead.
