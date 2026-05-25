# L2 action-tier protocol and `recommend` block schema

Shared contract for every `troubleshoot-*` and `investigate-*` expert skill in this package. Each skill loads it as `references/shared-contract.md`.

## How L2 expert skills are invoked

- Discover cluster context from the cluster — never ask the engineer for namespaces, endpoints, or credentials as your first move. `kubectl` and the Graylog / OpenSearch HTTP endpoints are already reachable (in-cluster Service, port-forward, or an exposed route).
- If a symptom needs pod-level introspection on a VM-deployed Graylog / OpenSearch (Docker-on-VM, SSH, `/srv/docker/...`), recognise the limit and hand back. HTTP/REST APIs remain in scope on VM deployments.

## Action tiers

- **`read-safe`** — cheap, idempotent reads (`kubectl get`, `kubectl describe`, `kubectl logs --tail=N`, configmap inspection, single-document API GETs). Execute freely.
- **`read-heavy`** — read-only but potentially expensive (large log dumps, cluster-wide scans, full index listings). Execute only with a declared cap; if you can't meet the cap, downgrade to `recommend`.
- **`recommend`** — anything that mutates state. **Never executed.** Emit as the structured block below; the operator applies it manually.

## Read-before-recommend

Before emitting any `recommend`, capture a `read-safe` snapshot of the state the action mutates plus the state that proves the action is still needed. Paste actual command output, not a summary. If the state cannot be read, escalate to the engineer; do not recommend blind.

## Expert output schema

Each expert returns:

```yaml
findings:
  - symptom_id: <id from references/symptoms.md, or "unrecognized">
    evidence: |
      <verbatim lines / values from the diagnostic pass>
    proposed_fix: <recommendation text or null>
raw_diagnostic_pass: |
  <short digest of the full diagnostic-pass output>
```

When the diagnostic pass surfaces a recognised pattern, the expert also emits a `recommend` block (see schema below) for the operator to apply.

## `recommend` block schema

```yaml
recommend:
  what:         # one sentence, imperative
  why:          # which symptom_id and which evidence support this
  blast_radius: # what this touches
  rollback:     # exact command or values to revert
  snapshot:     # the read-safe state captured before recommending; paste actual command output
    - command: <command run>
      output: |
        ...
  confidence:   # high | medium | low
```

## Anti-fabrication rule

If the diagnostic pass produces no recognised symptom, the expert returns `findings: []` and a non-empty `raw_diagnostic_pass` digest. Do not invent a `symptom_id`. Do not infer or speculate about causes. Do not propose fixes. An empty `findings` array is a valid and expected outcome — the orchestrator handles routing from there.

## What every L2 expert must not do

- Know about chain-walking, triage, topology, or other experts. The expert returns findings; the triage skill decides the next hop.
- Execute any mutating command. State changes are emitted as `recommend` blocks only.
- Run cluster-wide or full-index queries without a cap.
