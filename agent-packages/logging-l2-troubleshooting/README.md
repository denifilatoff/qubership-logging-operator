# logging-l2-troubleshooting

L2 troubleshooting skills for the Qubership logging stack. The engineer's local agent (Claude Code, Cursor, Codex, etc.) picks one of these skills after `logging-l1-triage` produces an `escalate` envelope, or directly during a co-debug session.

Every skill in this package is **read-only against live systems**. State-changing fixes are emitted as a structured `recommend` block per the shared protocol; the operator decides whether and when to apply them.

See `evals/` for the L2 eval pipeline and `docs/eval-pipeline-design.md` for its design.

## Skills

| Skill | Role | When |
|---|---|---|
| [`logging-l2-triage`](.apm/skills/logging-l2-triage/SKILL.md) | Entry point / router | Any live troubleshooting session — runs a read-safe diagnostic pass, picks the right knowledge-area skill, hands off. Use this first; do not jump straight into a `*-troubleshoot` skill from a free-form complaint. |
| [`graylog-server-troubleshoot`](.apm/skills/graylog-server-troubleshoot/SKILL.md) | Graylog server | UI inaccessible, OOM, journal pressure, "not processing messages", deflector errors, widget errors, timestamps, OpenSearch nodes info unavailable. |
| [`opensearch-troubleshoot`](.apm/skills/opensearch-troubleshoot/SKILL.md) | OpenSearch / Elasticsearch | Mapping field-limit explosions, `.opendistro-ism-config` noise, heap past 32 GB, disk-allocator read-only locks. |
| [`fluentd-troubleshoot`](.apm/skills/fluentd-troubleshoot/SKILL.md) | FluentD | Worker SIGKILL / OOM, high DiskIO, GELF UDP "data too big / 128 chunks", configmap-reload restarts. |
| [`fluentbit-troubleshoot`](.apm/skills/fluentbit-troubleshoot/SKILL.md) | FluentBit | Connection timeout to Graylog, stuck pipeline, configmap-reload restarts. |
| [`graylog-disk-usage-investigate`](.apm/skills/graylog-disk-usage-investigate/SKILL.md) | Disk-usage breakdown | "Which producers are filling our log storage?" — ranked report by configurable dimension. Callable standalone or as a sub-step of `graylog-server-troubleshoot`. |

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
        ├── graylog-server-troubleshoot/
        │   ├── SKILL.md
        │   └── references/
        │       ├── shared-contract.md  → ../../../shared/shared-contract.md
        │       └── symptoms.md          → ../../../shared/symptoms/graylog.md
        ├── opensearch-troubleshoot/  …
        ├── fluentd-troubleshoot/     …
        ├── fluentbit-troubleshoot/   …
        └── graylog-disk-usage-investigate/  …
```

## Reference content

Canonical symptom catalogues live inside the package at `.apm/shared/symptoms/<area>.md` and are the **single source of truth**. Each skill loads its area's catalogue as `references/symptoms.md`. The action-tier contract at `.apm/shared/shared-contract.md` is loaded by every skill as `references/shared-contract.md`.

How the wiring looks at each audience:

- **In this repo (developers):** `references/*.md` and `docs/troubleshooting/<area>.md` are symlinks back to the canonical files in `.apm/shared/`. Edit `.apm/shared/symptoms/<area>.md` (or `docs/troubleshooting/<area>.md`, which symlinks to it); every consumer of the symlink sees the change.
- **After `apm install` (consumers):** the package is sparse-checked-out and copied; `references/*.md` arrive as plain files containing the resolved content. There are no symlinks to maintain on the consumer side.

Adding a new pattern or fixing a wrong one is therefore a single edit in this repo.

## Out of scope

Areas listed in the L2 methodology but **not** shipped yet because the catalogue has no entries for them: `victoria-logs-troubleshoot`, `mongodb-troubleshoot`, `monitoring-troubleshoot`, `backup-troubleshoot`, plus the K8s deployment-time skills (`argocd`, `jenkins`, `logging-operator`). These will be added once `.apm/shared/symptoms/` grows the corresponding files. The Ansible VM installer (`external-logging-installer`) is **not** on this list — it deploys onto a Linux VM and is out of scope under the methodology's K8s-only invariant.

## Install

```sh
apm install Netcracker/qubership-logging-operator/agent-packages/logging-l2-troubleshooting
apm compile
```

Pair with [`logging-l1-triage`](../logging-l1-triage/) for the full L1→L2 flow.
