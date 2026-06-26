---
name: fluentd-troubleshoot
description: Diagnose FluentD problems in the Qubership logging stack — worker OOM kills, sustained DiskIO read load, GELF UDP "data too big / 128 chunks" buffer flush failures, ConfigMap-reloader-driven restarts. Use when symptoms point at the FluentD DaemonSet. Read-only against the live cluster; state-changing fixes are surfaced as proposed actions for the operator, never executed.
---

# Troubleshoot FluentD

## Protocol

Read [references/shared-contract.md](references/shared-contract.md) first — it governs invocation, action tiers,
read-before-recommend, the expert output contract, and the anti-fabrication rule.

## First read-safe diagnostic pass

```bash
# Workload. FluentD is a DaemonSet in standard mode; in HA mode it may not be present at all.
kubectl -n <ns> get ds -l app.kubernetes.io/name=fluentd -o wide

# Pod-level health. `LastState.terminated.reason: OOMKilled` is the headline you're hunting in the SIGKILL case.
kubectl -n <ns> get pods -l app.kubernetes.io/name=fluentd -o wide
kubectl -n <ns> describe pod <pod>     # restart count, last-state reason, OOM, evictions

# Recent error/warn tail. Worker SIGKILL and flush errors both surface here.
kubectl -n <ns> logs <pod> --tail=500 | grep -iE 'error|warn|sigkill|flush|chunks|oom'

# Memory limit (1Gi is the trap value: the hardcoded ~1GB buffer cannot fit).
kubectl -n <ns> get pod <pod> -o jsonpath='{.spec.containers[*].resources}'

# Effective configuration. Output/buffer stanzas in `output-graylog.conf` matter most.
kubectl -n <ns> get cm logging-fluentd -o yaml

# DiskIO from the node side — only if symptom mentions high read load and you have node-exec rights.
# This is read-safe but node-local; skip if unsure.
```

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
