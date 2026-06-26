# logging-l2-troubleshooting

L2 troubleshooting skills for the Qubership logging stack. The engineer's local agent (Claude Code, Cursor, Codex, etc.)
picks one of these skills after `logging-l1-triage` produces an `escalate` envelope, or directly during a co-debug
session.

Every skill in this package is **read-only against live systems**. State-changing fixes are surfaced as proposed actions
in prose per the shared protocol; the operator decides whether and when to apply them.

See `evals/` for the L2 eval pipeline and `docs/agent-packages/04-evaluation.md` for its design.

## How it works

One router, several area experts, one shared protocol. Triage routes but never diagnoses; experts diagnose but never
route.

```text
complaint  /  L1 "escalate" envelope
        │
        ▼
┌────────────────────┐   read-safe diagnostic pass (cluster-wide)
│ logging-l2-triage  │   rank candidate experts ──◄ topology.md (node graph)
└─────────┬──────────┘                           ──◄ cited-strings.md (redirects)
          │  Skill({ skill: "<area>-troubleshoot" })
          ▼
┌───────────────────────────────────────────────────┐
│ <area>-troubleshoot expert                         │
│   1. own read-safe diagnostic pass                 │
│   2. match_symptoms.py ──► symptom_id hints     ──◄ symptoms.txt
│   3. confirm each hint                          ──◄ symptoms.md (Confirm)
│   4. write prose: symptom_id + evidence + Fix   ──◄ shared-contract.md
└─────────┬─────────────────────────────────────────┘
          │  prose analysis back to triage
          ▼
   routing-policy (reads the expert's prose)
     • symptom confirmed         ──► STOP — surface the proposed fix
     • no symptom / cited string  ──► next hop, re-enter an expert  (≤ 5 hops)
     • budget exhausted           ──► manual-diagnosis hand-off
```

Read-only throughout. The final output is always **prose** — a proposed fix carrying a read-safe snapshot that proves it
targets the right zone — never an executed change. The operator decides whether to apply it.

## Skills

| Skill                                                                                   | Role                       | When                                                                                                                                                                                                                 |
| --------------------------------------------------------------------------------------- | -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`logging-l2-triage`](.apm/skills/logging-l2-triage/SKILL.md)                           | Entry point / router       | Any live troubleshooting session — runs a read-safe diagnostic pass, picks the right knowledge-area skill, hands off. Use this first; do not jump straight into a `*-troubleshoot` skill from a free-form complaint. |
| [`graylog-server-troubleshoot`](.apm/skills/graylog-server-troubleshoot/SKILL.md)       | Graylog server             | UI inaccessible, OOM, journal pressure, "not processing messages", deflector errors, widget errors, timestamps, OpenSearch nodes info unavailable.                                                                   |
| [`opensearch-troubleshoot`](.apm/skills/opensearch-troubleshoot/SKILL.md)               | OpenSearch / Elasticsearch | Mapping field-limit explosions, `.opendistro-ism-config` noise, heap past 32 GB, disk-allocator read-only locks.                                                                                                     |
| [`fluentd-troubleshoot`](.apm/skills/fluentd-troubleshoot/SKILL.md)                     | FluentD                    | Worker SIGKILL / OOM, high DiskIO, GELF UDP "data too big / 128 chunks", configmap-reload restarts.                                                                                                                  |
| [`fluentbit-troubleshoot`](.apm/skills/fluentbit-troubleshoot/SKILL.md)                 | FluentBit                  | Connection timeout to Graylog, stuck pipeline, configmap-reload restarts.                                                                                                                                            |
| [`graylog-disk-usage-investigate`](.apm/skills/graylog-disk-usage-investigate/SKILL.md) | Disk-usage breakdown       | "Which producers are filling our log storage?" — ranked report by configurable dimension. Callable standalone or as a sub-step of `graylog-server-troubleshoot`.                                                     |

## Layout

```text
agent-packages/logging-l2-troubleshooting/
├── apm.yml
├── README.md
└── .apm/
    ├── instructions/
    │   └── logging-l2-troubleshooting.instructions.md   # trigger merged into AGENTS.md / CLAUDE.md
    ├── shared/
    │   ├── shared-contract.md                        # action tiers + expert output contract
    │   └── match_symptoms.py                         # deterministic symptom matcher (shared by every expert)
    └── skills/
        ├── logging-l2-triage/                            # entry point — routes to the rest
        │   ├── SKILL.md
        │   └── references/
        │       ├── shared-contract.md  → ../../../shared/shared-contract.md
        │       ├── topology.md                           # node graph + downstream/upstream routing
        │       └── cited-strings.md                      # cross-component redirect patterns
        ├── graylog-server-troubleshoot/
        │   ├── SKILL.md
        │   ├── references/
        │   │   ├── shared-contract.md  → ../../../shared/shared-contract.md
        │   │   ├── symptoms.txt                          # regex/phrase catalog (deterministic match)
        │   │   └── symptoms.md                           # per-id prose: What / Confirm / Fix
        │   └── scripts/
        │       └── match_symptoms.py  → ../../../shared/match_symptoms.py
        ├── opensearch-troubleshoot/  …
        ├── fluentd-troubleshoot/     …
        ├── fluentbit-troubleshoot/   …
        └── graylog-disk-usage-investigate/  …
```

## Reference content

Each expert owns its symptom catalog as two real files in its own `references/` folder:

- `symptoms.txt` — a deterministic catalog of `[symptom-id]` sections, each holding phrase or `re:` regex lines.
  `scripts/match_symptoms.py` matches it against the diagnostic-pass output and returns the matching ids as hints.
- `symptoms.md` — per-id prose (What / Confirm / Fix / Caveat-next). Signal-less symptoms carry a
  `**Detection: manual**` marker and have no `symptoms.txt` entry; the expert reviews them whenever the matcher returns
  nothing.

The matcher itself is identical for every expert, so it lives once at `.apm/shared/match_symptoms.py` and is symlinked
into each `scripts/`. The action-tier and output contract at `.apm/shared/shared-contract.md` is likewise symlinked into
each `references/`.

Symptom prose is condensed from the operator troubleshooting guide at `docs/troubleshooting.md`, which stays the
canonical source. To add or fix a pattern, edit that guide first, then the affected expert's `symptoms.txt` /
`symptoms.md`.

How the wiring looks at each audience:

- **In this repo (developers):** `references/shared-contract.md` and `scripts/match_symptoms.py` are symlinks back to
  `.apm/shared/`; `symptoms.txt` and `symptoms.md` are real per-skill files.
- **After `apm install` (consumers):** the package is copied and symlink targets are resolved, so every file arrives as
  plain content. There are no symlinks to maintain on the consumer side.

## Out of scope

Areas listed in the L2 methodology but **not** shipped yet because the catalogue has no entries for them:
`victoria-logs-troubleshoot`, `mongodb-troubleshoot`, `monitoring-troubleshoot`, `backup-troubleshoot`, plus the K8s
deployment-time skills (`argocd`, `jenkins`, `logging-operator`). These will be added once a corresponding expert skill
with its own symptom catalog ships. The Ansible VM installer (`external-logging-installer`) is **not** on this list — it
deploys onto a Linux VM and is out of scope under the methodology's K8s-only invariant.

## Install

```sh
apm install Netcracker/qubership-logging-operator/agent-packages/logging-l2-troubleshooting
apm compile
```

Pair with `logging-l1-triage` for the full L1→L2 flow.
