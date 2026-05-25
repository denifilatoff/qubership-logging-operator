---
name: graylog-server-troubleshoot
description: Diagnose Graylog server problems in the Qubership logging stack — UI inaccessible / 504, browser-to-Graylog connection issues, ingress/route cyclic redirect, container OOM, low performance and journal growth, "Graylog not processing messages", oversized indices, negative unprocessed messages, incorrect timestamps, OpenSearch nodes info unavailable, widget errors on text fields, "Deflector exists as an index" errors. Use when symptoms point at Graylog itself (server, web UI, journal, indexer alias), not at OpenSearch storage or the FluentBit/FluentD collectors. Read-only against the live system; mutations go out as `recommend` blocks, never executed.
---

# Troubleshoot Graylog server

## Protocol

Read [references/shared-contract.md](references/shared-contract.md) first — it governs invocation, action tiers, read-before-recommend, the `recommend` block schema, the expert output schema, and the anti-fabrication rule.

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

## Lookup and output

1. Take the diagnostic-pass output above.
2. For each entry in [references/symptoms.md](references/symptoms.md), evaluate its `match` block against the diagnostic-pass output. Collect every entry that matches.
3. Emit the result in the schema from [references/shared-contract.md](references/shared-contract.md#expert-output-schema):

```yaml
findings:
  - symptom_id: <id of the matched entry>
    evidence: |
      <verbatim lines / values referenced by the entry's evidence_template>
    proposed_fix: |
      <proposed_fix from the entry, instantiated with any concrete values>
raw_diagnostic_pass: |
  <abbreviated digest of the diagnostic-pass output above>
```

If the matched entry's `proposed_fix` warrants a structured operator action, also emit a `recommend` block per the shared contract, citing the matched `symptom_id` in `why`.

## Anti-fabrication

If no entry in the catalogue matches, return `findings: []` with a non-empty `raw_diagnostic_pass` digest. Do not invent a `symptom_id`. Do not infer or speculate. Do not emit a `recommend`. An empty `findings` array is a valid and expected outcome — the orchestrator handles routing from there.

## Investigating disk pressure specifically

If the engineer wants to know **which producers are filling the disk** (not just "free space, restart"), call the `graylog-disk-usage-investigate` skill from this package.
