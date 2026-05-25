# L2 action-tier protocol and `recommend` block schema

Shared contract for every `troubleshoot-*` and `investigate-*` skill in this package. Each skill loads it as `references/shared-contract.md`.

## Action tiers

- **`read-safe`** — cheap, idempotent reads (`kubectl get`, `kubectl describe`, `kubectl logs --tail=N`, configmap inspection, single-document API GETs). Execute freely.
- **`read-heavy`** — read-only but potentially expensive or load-inducing (large log dumps, cluster-wide scans, full index listings). Execute only with a declared cap up front — line limit, time window, response cap. If you can't meet the cap, downgrade the operation to `recommend` so the operator decides whether to run it.
- **`recommend`** — anything that mutates state (`kubectl edit`, `kubectl scale`, `kubectl delete`, configmap patches, pod restarts, Graylog/OpenSearch API writes, PVC deletions). **Never executed.** Emit as the structured block below; the operator applies it manually.

## Read-before-recommend

A `recommend` is a proposed state change. Before emitting it, capture a `read-safe` snapshot of the state the action mutates **plus** the state that proves the action is still needed. The snapshot does two things: lets the operator verify the recommendation is still valid when they read it, and gives a rollback baseline.

If the state cannot be read — RBAC denial, pod unreachable, command times out — do **not** recommend blind. Escalate to the engineer with what failed and stop.

## `recommend` block schema

Emit each state-changing proposal in this exact YAML shape:

```yaml
recommend:
  what:        # one sentence, imperative. "Raise fluentbit.resources.limits.cpu from 500m to 1."
  why:         # which catalogue entry / which evidence supports this. Cite the symptom verbatim.
  blast_radius: # what this touches. One pod? A namespace? The whole logging stack?
  rollback:    # exact command or values to revert.
  snapshot:    # the read-safe state captured before recommending. Paste actual command output, not a summary.
    - command: kubectl -n <ns> get pod <pod> -o jsonpath='{.spec.containers[*].resources}'
      output: |
        ...
    - command: kubectl -n <ns> logs <pod> --tail=100
      output: |
        ...
  confidence:  # high | medium | low — your read on whether this is the right fix.
```

Multiple recommendations in one session each get their own block. Do not bundle unrelated actions into one `recommend`.

## Hypothesis refute

Triage calls an area skill on a ranked hypothesis. If the area skill's sweep produces no evidence of a root cause **in its own zone**, the hypothesis is wrong and the area skill must say so explicitly — not invent a recommend, not stop silently. Triage's chain-of-hypotheses loop advances to the next candidate on this signal; without it the chain stops at the wrong area.

Each area skill defines what "clean for this zone" looks like in its own SKILL (the absence-of-signals checklist). The output shape and semantics are uniform and live here:

```yaml
hypothesis_refuted: true
skill: <name of the area skill emitting this>
sweep_evidence: |
  <verbatim summary of what the sweep saw, including the absence of in-zone signals>
likely_downstream_area: <name of an area whose signals do appear, or `unknown`>
reason: <one sentence on why the sweep clears this zone, and what cross-zone signal (if any) points elsewhere — e.g. a quoted downstream error in this component's logs>
```

Rules:

- A `recommend` block and a `hypothesis_refuted` are **mutually exclusive** for a given turn. Found the cause in zone → recommend and stop. Cleared the zone → refute and let triage advance. Never emit both.
- An area skill never invokes another area skill itself. Advancing the chain is triage's job; the area skill's only outputs are `recommend` (case closed) or `hypothesis_refuted` (over to triage).
- Refute is not "I'm not sure". Refute is "the sweep checked the things this zone owns and they're healthy". A partial sweep that couldn't read what it needed escalates to the engineer (read-before-recommend rule) instead.

## What every L2 skill must not do

- Execute any mutating command, even one the engineer asks for inline. The engineer applies fixes from `recommend` blocks themselves.
- Run cluster-wide or full-index queries without a cap.
- Close tickets or post to the ticket-tracker.
- Invoke another area skill directly. If the cause sits in a different area, emit `hypothesis_refuted` (above) and stop — the triage caller routes the next hop.
