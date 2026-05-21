# logging-l2-troubleshooting

L2 troubleshooting skills for the Qubership logging stack. The engineer's local agent (Claude Code, Cursor, Codex, etc.) picks one of these skills after `logging-l1-triage` produces an `escalate` envelope, or directly during a co-debug session.

Every skill in this package is **read-only against live systems**. State-changing fixes are emitted as a structured `recommend` block per the shared protocol; the operator decides whether and when to apply them.

## Skills

| Skill | Role | When |
|---|---|---|
| [`logging-l2-triage`](.apm/skills/logging-l2-triage/SKILL.md) | Entry point / router | Any live troubleshooting session — runs a read-safe sweep, picks the right knowledge-area skill, hands off. Use this first; do not jump straight into a `troubleshoot-*` skill from a free-form complaint. |
| [`troubleshoot-graylog-server`](.apm/skills/troubleshoot-graylog-server/SKILL.md) | Graylog server | UI inaccessible, OOM, journal pressure, "not processing messages", deflector errors, widget errors, timestamps, OpenSearch nodes info unavailable. |
| [`troubleshoot-opensearch`](.apm/skills/troubleshoot-opensearch/SKILL.md) | OpenSearch / Elasticsearch | Mapping field-limit explosions, `.opendistro-ism-config` noise, heap past 32 GB, disk-allocator read-only locks. |
| [`troubleshoot-fluentd`](.apm/skills/troubleshoot-fluentd/SKILL.md) | FluentD | Worker SIGKILL / OOM, high DiskIO, GELF UDP "data too big / 128 chunks", configmap-reload restarts. |
| [`troubleshoot-fluentbit`](.apm/skills/troubleshoot-fluentbit/SKILL.md) | FluentBit | Connection timeout to Graylog, stuck pipeline, configmap-reload restarts. |
| [`investigate-graylog-disk-usage`](.apm/skills/investigate-graylog-disk-usage/SKILL.md) | Disk-usage breakdown | "Which producers are filling our log storage?" — ranked report by configurable dimension. Callable standalone or as a sub-step of `troubleshoot-graylog-server`. |

## Layout

```
agent-packages/logging-l2-troubleshooting/
├── apm.yml
├── README.md
└── .apm/
    ├── instructions/
    │   └── logging-l2-troubleshooting.instructions.md   # trigger merged into AGENTS.md / CLAUDE.md
    ├── shared/
    │   ├── shared-contract.md                        # action tiers + recommend block schema
    │   └── symptoms/                                 # canonical symptom catalogues
    │       ├── graylog.md
    │       ├── opensearch.md
    │       ├── fluentd.md
    │       └── fluentbit.md
    └── skills/
        ├── logging-l2-triage/                            # entry point — routes to the rest
        │   ├── SKILL.md
        │   └── references/
        │       ├── shared-contract.md  → ../../../shared/shared-contract.md
        │       └── signal-table.md                       # symptom → target-skill mapping with priors
        ├── troubleshoot-graylog-server/
        │   ├── SKILL.md
        │   └── references/
        │       ├── shared-contract.md  → ../../../shared/shared-contract.md
        │       └── symptoms.md          → ../../../shared/symptoms/graylog.md
        ├── troubleshoot-opensearch/  …
        ├── troubleshoot-fluentd/     …
        ├── troubleshoot-fluentbit/   …
        └── investigate-graylog-disk-usage/  …
```

## Reference content

Symptom catalogues live inside the package at `.apm/shared/symptoms/<area>.md` and are the **single source of truth**. Each skill's `references/symptoms.md` is a symlink into that shared directory (in-package, so it survives `apm install` resolution). The repo also ships `docs/troubleshooting/<area>.md` as symlinks pointing into this same shared directory, so human readers of the repo and the L2 skills see identical content.

Adding a new pattern or fixing a wrong one is a single edit — either in `.apm/shared/symptoms/<area>.md` directly, or via the `docs/troubleshooting/<area>.md` symlink; both routes hit the same file.

The shared `shared-contract.md` (action tiers, read-before-recommend rule, exact YAML block schema) is similarly symlinked into each skill's `references/`.

## Out of scope

Areas listed in the L2 methodology but **not** shipped yet because the catalogue has no entries for them: `troubleshoot-victoria-logs`, `troubleshoot-mongodb`, `troubleshoot-monitoring`, `troubleshoot-backup`, plus all deployment-time skills (`argocd`, `jenkins`, `ansible-vm-installer`, `logging-operator`). These will be added once `.apm/shared/symptoms/` grows the corresponding files.

## Install

```sh
apm install Netcracker/qubership-logging-operator/agent-packages/logging-l2-troubleshooting
apm compile
```

Pair with [`logging-l1-triage`](../logging-l1-triage/) for the full L1→L2 flow.
