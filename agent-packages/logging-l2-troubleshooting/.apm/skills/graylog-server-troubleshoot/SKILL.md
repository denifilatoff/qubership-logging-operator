---
name: graylog-server-troubleshoot
description: Diagnose Graylog server problems in the Qubership logging stack — UI inaccessible / 504, browser-to-Graylog connection issues, ingress/route cyclic redirect, container OOM, low performance and journal growth, "Graylog not processing messages", oversized indices, negative unprocessed messages, incorrect timestamps, OpenSearch nodes info unavailable, widget errors on text fields, "Deflector exists as an index" errors. Use when symptoms point at Graylog itself (server, web UI, journal, indexer alias), not at OpenSearch storage or the FluentBit/FluentD collectors. Read-only against the live system; mutations go out as `recommend` blocks, never executed.
---

# Troubleshoot Graylog server

## Protocol

Read [references/shared-contract.md](references/shared-contract.md) first — it governs invocation, action tiers, read-before-recommend, the `recommend` block schema, the symptom-catalogue convention, and the refute contract.

Graylog-specific notes:

- Restarting the Graylog pod, deleting journal data, stopping inputs from the UI, and patching `graylog.conf` are all mutating. Emit as `recommend` with rollback.
- API calls against `/api/system/indexer/indices` with `DELETE`, or any write to `/_settings`, are mutating.

## First read-safe diagnostic pass

```bash
# --- Kubernetes-side state ---
kubectl -n <ns> get sts,deploy,svc -l app.kubernetes.io/name=graylog -o wide
kubectl -n <ns> get pods -l app.kubernetes.io/name=graylog -o wide
kubectl -n <ns> describe pod <graylog-pod>
kubectl -n <ns> logs <graylog-pod> --tail=500 | grep -iE 'error|warn|journal|deflector'
kubectl -n <ns> get pvc                   # backing volume for journal + node data
kubectl -n <ns> describe pvc <graylog-pvc>

# --- Graylog HTTP API (works regardless of where Graylog runs) ---
# Node and journal state. Journal size and "unprocessed messages" tell most of the story.
curl -sk -u <u>:<p> https://<graylog>/api/system/journal
curl -sk -u <u>:<p> https://<graylog>/api/system/cluster/nodes
curl -sk -u <u>:<p> https://<graylog>/api/system/indexer/cluster/health
curl -sk -u <u>:<p> https://<graylog>/api/system/indexer/indices | head -200

# Inputs (stopping inputs is the recommendation in several scenarios; know which are running first).
curl -sk -u <u>:<p> https://<graylog>/api/system/inputstates
```

If the journal is large or growing, capture two readings spaced ~30 s apart — the trend matters more than the absolute number.

## Symptom catalogue

[references/symptoms.md](references/symptoms.md) — match against it; add patterns via `docs/troubleshooting/graylog.md` in the operator repo first.

## Zone signal classification (refute contract)

Walk the four classes in order. Emit on the first match.

**1. CLEAN**
- Pods `Running`, web UI reachable, no recent restarts / OOM.
- Journal size stable across two readings ~30s apart, "unprocessed messages" not climbing.
- Inputs `RUNNING` per `/api/system/inputstates`.
- OpenSearch nodes reachable per `/api/system/cluster/nodes`; no TLS errors to OpenSearch.
- No deflector / widget / fielddata / input-drop / parsing-failure warnings in `kubectl logs --tail=500`.

→ `hypothesis_refuted`, `signal_class: clean`.

**2. QUOTED**
- Graylog indexer or input logs cite an external system explicitly: `cluster_block_exception`, `FORBIDDEN/12/index read-only`, MongoDB connection errors, OpenSearch HTTP / TLS errors naming a host.

→ `hypothesis_refuted`, `signal_class: secondary_quoted`. Capture verbatim in `cited_external_components`.

**3. BACKPRESSURE** — all of:
- Journal size growing across two readings ~30s apart AND "unprocessed messages" climbing.
- Graylog itself is healthy (pods `Running`, no recent restarts / OOM, inputs `RUNNING`).
- No internal Graylog error explains the slowdown (no deflector / widget / TLS / parse error in logs).

→ `hypothesis_refuted`, `signal_class: secondary_backpressure`. The journal is Graylog's downstream buffer; sustained growth on a healthy Graylog means the store isn't draining.

**4. PRIMARY** (emit `recommend`):
- Input-side warnings about dropped messages or oversized frames (e.g. GELF input `max_message_size` too small).
- Deflector / alias / widget / fielddata errors ("Deflector exists as an index", "Active write index doesn't exist yet").
- Container OOM not related to journal.
- Ingress / TLS misconfig, web UI 502 / 504.
- ConfigMap typo causing restart.

## Investigating disk pressure specifically

If the engineer wants to know **which producers are filling the disk** (not just "free space, restart"), call the `graylog-disk-usage-investigate` skill from this package.
