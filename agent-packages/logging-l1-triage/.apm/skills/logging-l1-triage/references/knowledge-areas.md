# Knowledge areas and classification signals

Load this file in Step 1 (ticket-type routing) and Step 4
(area classification) of the decision flow in `SKILL.md`.

Each knowledge area has a **slug** — a kebab-case identifier that is
used directly as the value of `knowledge_area:` in the output, and
matches the suffix of the corresponding L2 troubleshooting skill
(`troubleshoot-<slug>`). Slugs are the source of truth across all
three files (`SKILL.md`, this file, `trivial-cases.yaml`,
`output-schemas.md`); never rename one without updating the others.

The taxonomy has two orthogonal axes:

- **Knowledge area** — *what* the ticket is about.
- **Ticket type** — *what kind of work* is being asked for: Defect,
  Question, Request, or Admin. Only Defects flow into Steps 2–5;
  everything else is routed via the non-troubleshooting
  destinations table.

## Operational troubleshooting

L2 skills with runtime / server access.

| Slug | Area | Target L2 skill |
|---|---|---|
| `graylog-server` | Graylog Server (config, performance, journal, search/API, indices & rotation, plugins, streams, pipelines, backup retention) | `troubleshoot-graylog-server` |
| `opensearch` | OpenSearch / Elasticsearch (cluster health, indexer, mapping, security plugin, ES→OS migration, sizing) | `troubleshoot-opensearch` |
| `mongodb` | MongoDB (Graylog metadata store) | `troubleshoot-mongodb` |
| `fluent-collectors` | FluentD and FluentBit (pod lifecycle, config & parsing, delivery to Graylog, resources, routing) | `troubleshoot-fluent-collectors` |
| `monitoring` | Telegraf, Prometheus, Grafana, Zabbix (for logging-related concerns) | `troubleshoot-monitoring` |
| `backup` | Backup tooling — backup job, export/import/restore | `troubleshoot-backup` |

## Deployment troubleshooting

L2 skills with access to deployment artefacts (CI logs, Helm values,
Ansible output).

| Slug | Area | Target L2 skill |
|---|---|---|
| `deploy-pipeline` | CI/CD Pipelines — Jenkins, ArgoCD, GitLab CI, AppDeployer | `troubleshoot-deploy-pipeline` |
| `deploy-ansible` | Ansible installer — `external-logging-installer` playbook | `troubleshoot-deploy-ansible` |
| `deploy-helm` | Helm / K8s Operators / CRDs | `troubleshoot-deploy-helm` |
| `deploy-prereqs` | OS / K8s prerequisites — package versions, K8s compatibility, ARM/x86, disk sizing | `troubleshoot-deploy-prereqs` |
| `deploy-airgap` | Artifact registries / Air-gap installations | `troubleshoot-deploy-airgap` |

## Cross-cutting modules

Not standalone L2 skills. These are utility / knowledge modules that
the operational and deployment skills load on demand. L1 does not
route to them directly; mention a relevant module in `evidence` if it
strengthens the hypothesis.

| Slug | Module |
|---|---|
| `k8s-pod-debug` | K8s pod debugging primitives — describe, events, OOMKilled detection |
| `k8s-resources` | K8s resource limits & QoS |
| `openshift-scc` | OpenShift SCC / SELinux / Linux file permissions |
| `tls-pki` | Network / TLS / Certificates / PKI |
| `l7-routing` | L7 routing / Ingress / Load balancers |
| `auth-integration` | Auth integration — LDAP, SAML, auth-proxy |
| `gelf-protocol` | GELF protocol mechanics — UDP limits, TCP, chunking |
| `external-destinations` | External log destinations — S3, Splunk, Loki, Syslog, rsyslog |
| `parser-multiline` | Custom parser / regex / multiline |

## Non-troubleshooting destinations

These never escalate to an L2 troubleshooting skill. L1 routes them
to the destinations below and ends the flow.

| Slug | Destination | When |
|---|---|---|
| `docs-faq` | Reply with documentation / FAQ pointer, recommend `close_as_resolved` | Pure how-to / clarification / doc-gap question |
| `security-review` | Route to the security team | CVE / SCA / security compliance review |
| `product-backlog` | Route to product backlog | Feature requests / RFEs |
| `architect-consultation` | Route to an architect | HA/DR design, sizing, best-practice consultation. These have very long resolution times because they are organisational, not technical — never escalate to an operational or deployment skill. |
| `ticket-housekeeping` | Apply L1 ticket housekeeping | Deduplication, priority disputes, SLA queries, ticket-system metadata edits |

When routing here, set `knowledge_area:` to the slug above and use
`target_skill: none` in the output — there is no L2 skill at the
other end.

## Ticket type — Step 1

Decide the type before classifying the area.

| Type | What it looks like | L1 action |
|---|---|---|
| **Defect** | Something is broken; observed behaviour differs from expected. | Continue to Step 2 (trivial-case match → intake → area classification). |
| **Question** | Request for information. Author wants to understand a feature or check a configuration assumption — nothing is broken. | Route to `docs-faq` (or `architect-consultation` if the question is an architectural one). |
| **Request** | Ask for a change — new feature, new integration, new deploy config. | Route to `product-backlog` (or `architect-consultation` for architecture). |
| **Admin** | Meta-work on the ticket itself — dedup, cancel, reclassify. | Route to `ticket-housekeeping`. |

A single ticket can mix Question and Defect; in that case treat it
as Defect and answer the question inside the `escalate` or
`recommend_resolve` reply.

## Classification signals — Step 4

Heuristics for picking the area from the symptom. High-confidence
mappings can drive `escalate` directly; ambiguous rows demand a
single disambiguating question (`bounce_back`,
`reason: classification_ambiguous`).

| Pattern in the ticket or attached logs | Area | Cross-cutting hint | Confidence |
|---|---|---|---|
| Graylog UI unavailable / HTTP 502 / login error | `graylog-server` | possibly `l7-routing` | high |
| Journal high utilisation / unprocessed messages growing | `graylog-server` | — | high |
| OpenSearch cluster status RED or YELLOW | `opensearch` | — | high |
| `IndexNotFoundException`, mapping field-type errors | `opensearch` | — | high |
| MongoDB connection errors from Graylog | `mongodb` | — | high |
| FluentD/FluentBit log: `Worker exited unexpectedly with signal SIGKILL` | `fluent-collectors` | `k8s-pod-debug`, `k8s-resources` | high |
| FluentBit log: `connection timeout` or `getaddrinfo Timeout` | `fluent-collectors` | `k8s-resources` (CPU throttling hypothesis) | high |
| FluentD log: `Data too big` or `would create more than 128 chunks` | `fluent-collectors` | `gelf-protocol` | high |
| FluentD log: `unmatched end tag` or `ConfigParseError` | `fluent-collectors` | `parser-multiline` | high |
| Application logs not appearing in Graylog at all | `fluent-collectors` OR `graylog-server` OR `deploy-pipeline` | — | ambiguous — disambiguate |
| Jenkins / ArgoCD job failed during install | `deploy-pipeline` | — | high |
| Ansible playbook failed at task X | `deploy-ansible` | — | high |
| Helm chart install / upgrade failed; CRD conflicts; reconcile errors | `deploy-helm` | — | high |
| K8s version / OS package / ARM compatibility errors | `deploy-prereqs` | — | high |
| Image pull failure in an offline environment | `deploy-airgap` | — | high |
| Telegraf / Prometheus exporter returns no metrics | `monitoring` | — | high |
| Grafana dashboard empty / broken queries | `monitoring` | — | high |
| Backup job failed | `backup` | — | high |

Suggested disambiguating questions for the ambiguous row above:

- "Is the Graylog UI reachable and showing recent messages from
  *other* sources?" — narrows `graylog-server` vs `fluent-collectors`.
- "Did the symptom appear immediately after a deployment / Helm
  upgrade / playbook run?" — surfaces `deploy-pipeline`,
  `deploy-ansible`, or `deploy-helm`.
- "Is the affected scope a single namespace, a single tenant, or
  the whole cluster?" — narrows `fluent-collectors` (collector-side)
  vs `graylog-server` (server-side).
