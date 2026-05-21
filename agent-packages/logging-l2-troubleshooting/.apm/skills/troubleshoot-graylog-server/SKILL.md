---
name: troubleshoot-graylog-server
description: Diagnose Graylog server problems in the Qubership logging stack — UI inaccessible / 504, browser-to-Graylog connection issues, ingress/route cyclic redirect, container OOM, low performance and journal growth, "Graylog not processing messages", oversized indices, negative unprocessed messages, incorrect timestamps, OpenSearch nodes info unavailable, widget errors on text fields, "Deflector exists as an index" errors. Use when symptoms point at Graylog itself (server, web UI, journal, indexer alias), not at OpenSearch storage or the FluentBit/FluentD collectors. Read-only against the live system; mutations go out as `recommend` blocks, never executed.
---

# Troubleshoot Graylog server

You are the L2 troubleshooting skill for the **Graylog server** knowledge area — the Graylog process and web UI, the disk journal, the indexer alias (`_deflector`), input management, and the immediate environment around the Graylog container (browser path, ingress, TLS to OpenSearch nodes). Entry points: handoff from `logging-l2-triage`, or engineer-driven invocation.

Many Graylog symptoms have a root cause downstream in OpenSearch (HDD full, mapping limit, read-only indices) or upstream in the collector (FluentD/FluentBit). Your job is to **localize the cause to one area** before recommending anything. If the cause is OpenSearch or the collectors, surface the finding and hand back to the engineer.

Diagnose, propose a fix as a `recommend` block, stop. You never mutate the system.

## Protocol

Read [references/shared-contract.md](references/shared-contract.md) first. `read-safe` / `read-heavy` / `recommend`, read-before-recommend, exact block schema. Everything you do is governed by it.

Graylog-specific notes:

- Deployment shape varies: VM-with-Docker (`docker ps`, `/srv/docker/graylog/*`, `service docker stop`) **or** Kubernetes (`kubectl -n logging get sts,deploy`). The same symptom needs different commands. Confirm which one you're on before reading state.
- Restarting Graylog containers, deleting journal directories, stopping inputs from the UI, and patching `graylog.conf` are all mutating. Emit as `recommend` with rollback.
- API calls against `/api/system/indexer/indices` with `DELETE`, or any write to `/_settings`, are mutating.

## First read-safe sweep

```bash
# --- VM deployment (Docker) ---
ssh <graylog-vm>
docker ps -f name=graylog                 # four containers expected: web, graylog, storage, mongo
df -h                                     # HDD utilisation — relevant to many symptoms
docker logs graylog_graylog_1 --tail=500 2>&1 | grep -iE 'error|warn|journal|deflector'
docker stats --no-stream                  # CPU / RAM pressure

# --- Kubernetes deployment ---
kubectl -n <ns> get sts,deploy,svc -l app.kubernetes.io/name=graylog -o wide
kubectl -n <ns> get pods -l app.kubernetes.io/name=graylog -o wide
kubectl -n <ns> describe pod <graylog-pod>
kubectl -n <ns> logs <graylog-pod> --tail=500 | grep -iE 'error|warn|journal|deflector'

# --- Common (works either way against the Graylog API) ---
# Node and journal state. Journal size and "unprocessed messages" tell most of the story.
curl -sk -u <u>:<p> https://<graylog>/api/system/journal
curl -sk -u <u>:<p> https://<graylog>/api/system/cluster/nodes
curl -sk -u <u>:<p> https://<graylog>/api/system/indexer/cluster/health
curl -sk -u <u>:<p> https://<graylog>/api/system/indexer/indices | head -200

# Inputs (stopping inputs is the recommendation in several scenarios; know which are running first).
curl -sk -u <u>:<p> https://<graylog>/api/system/inputstates
```

Whatever you actually observe becomes the `evidence` field on any `recommend` you emit. If the journal is large or growing, capture two readings spaced ~30 s apart — the trend matters more than the absolute number.

## Symptom catalogue

Match the report against [references/symptoms.md](references/symptoms.md). Canonical catalogue, do not paraphrase.

If the symptom is not in the catalogue, do **not** invent a solution. Report what you observed and stop. Adding new patterns means editing `docs/troubleshooting/graylog.md` first.

## Investigating disk pressure specifically

If the symptom is "HDD full" / "Graylog VM running out of space" and the engineer wants to know **which producers are filling the disk** (not just "free space, restart"), that is a focused diagnostic procedure — call the `investigate-graylog-disk-usage` skill from this package. It exists exactly for that breakdown.
