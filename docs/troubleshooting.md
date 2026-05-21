# Troubleshooting

Troubleshooting reference for the Qubership logging stack, split by component. Each file below is the canonical source for its area and is loaded on demand by the matching L2 troubleshooting skill (`agent-packages/logging-l2-troubleshooting/`).

- [Graylog](troubleshooting/graylog.md) — connection, HDD/OOM/perf, indices and deflector, performance tuning.
- [OpenSearch](troubleshooting/opensearch.md) — field-limit explosions, ISM noise, heap sizing, read-only locks.
- [FluentD](troubleshooting/fluentd.md) — worker OOM, DiskIO load, GELF UDP chunking, configmap reload.
- [FluentBit](troubleshooting/fluentbit.md) — Graylog connection timeouts, stuck pipeline, configmap reload.

Add new patterns to the relevant file. Skills under `agent-packages/logging-l2-troubleshooting/.apm/skills/<name>/references/symptoms.md` are symlinks back to these documents — one source of truth.
