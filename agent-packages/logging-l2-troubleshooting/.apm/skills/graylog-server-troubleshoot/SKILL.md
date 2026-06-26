---
name: graylog-server-troubleshoot
description: Diagnose Graylog server problems in the Qubership logging stack — UI inaccessible / 504, browser-to-Graylog connection issues, ingress/route cyclic redirect, container OOM, low performance and journal growth, "Graylog not processing messages", oversized indices, negative unprocessed messages, incorrect timestamps, OpenSearch nodes info unavailable, widget errors on text fields, "Deflector exists as an index" errors. Use when symptoms point at Graylog itself (server, web UI, journal, indexer alias), not at OpenSearch storage or the FluentBit/FluentD collectors. Read-only against the live system; state-changing fixes are surfaced as proposed actions for the operator, never executed.
---

# Troubleshoot Graylog server

## Protocol

Read [references/shared-contract.md](references/shared-contract.md) first — it governs invocation, action tiers,
read-before-recommend, the expert output contract, and the anti-fabrication rule.

Graylog-specific notes:

- Restarting the Graylog pod, deleting journal data, stopping inputs from the UI, and patching `graylog.conf` are all
  mutating. Emit as `recommend` with rollback.
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

If the journal is large or growing, capture two readings spaced ~30 s apart — the trend matters more than the absolute
number.

## Match symptoms

1. Concatenate the diagnostic-pass output above into a single text buffer (a temp file is fine).
2. Run the deterministic matcher over it:

   ```bash
   python3 scripts/match_symptoms.py <diagnostic-output-file>
   ```

   It prints a JSON list of `symptom_id`s whose patterns matched. Each is a **hint**, not a verdict.

3. For every returned id, read its section in [references/symptoms.md](references/symptoms.md) and confirm the
   **Confirm** condition actually holds against your evidence — including any non-textual threshold (for example a
   memory limit).
4. **Always** also review the `Detection: manual` entries in [references/symptoms.md](references/symptoms.md). The
   matcher never returns them by design; check whether your diagnostic evidence fits one. An empty matcher result does
   **not** mean "no symptom" — do this manual sweep first.

## Write your analysis

Write prose for the engineer, per the contract in
[references/shared-contract.md](references/shared-contract.md#expert-output). For each confirmed symptom:

- Copy the `symptom_id` from the matcher output verbatim: the exact token, no reformatting, never one you invent (see
  the contract).
- Quote the verbatim diagnostic lines or values that prove it.
- Give the **Fix** from the symptom's section as prose, with the rollback, blast radius, and a confidence level. Include
  the read-safe snapshot the fix relies on (actual command output).

Do not emit a fenced YAML block. The triage orchestrator reads your prose.

## Anti-fabrication

If neither the matcher nor the manual sweep confirms a symptom, say so plainly, paste a short digest of the
diagnostic-pass output, and stop. Do not invent a `symptom_id`. Do not infer or speculate about causes. Do not propose a
fix. A "no known symptom matched" result is valid and expected — the orchestrator routes from there.
