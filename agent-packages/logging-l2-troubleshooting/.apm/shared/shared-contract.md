# L2 action-tier protocol and `recommend` block schema

Shared contract for every `troubleshoot-*` and `investigate-*` skill in this package. Each skill loads it as `references/shared-contract.md`.

## How L2 skills are invoked

- Discover cluster context from the cluster — never ask the engineer for namespaces, endpoints, or credentials as your first move. `kubectl` and the Graylog / OpenSearch HTTP endpoints are already reachable (in-cluster Service, port-forward, or an exposed route).
- If a symptom needs pod-level introspection (`kubectl logs`, `kubectl exec`, container fs) on a VM-deployed Graylog / OpenSearch (Docker-on-VM, SSH, `/srv/docker/...`), recognise the limit and hand back. The HTTP/REST APIs remain in scope on VM deployments.

## Action tiers

- **`read-safe`** — cheap, idempotent reads (`kubectl get`, `kubectl describe`, `kubectl logs --tail=N`, configmap inspection, single-document API GETs). Execute freely.
- **`read-heavy`** — read-only but potentially expensive or load-inducing (large log dumps, cluster-wide scans, full index listings). Execute only with a declared cap up front — line limit, time window, response cap. If you can't meet the cap, downgrade the operation to `recommend` so the operator decides whether to run it.
- **`recommend`** — anything that mutates state (`kubectl edit`, `kubectl scale`, `kubectl delete`, configmap patches, pod restarts, Graylog/OpenSearch API writes, PVC deletions). **Never executed.** Emit as the structured block below; the operator applies it manually.

## Read-before-recommend

A `recommend` is a proposed state change. Before emitting it, capture a `read-safe` snapshot of the state the action mutates **plus** the state that proves the action is still needed. The snapshot does two things: lets the operator verify the recommendation is still valid when they read it, and gives a rollback baseline.

The output of each skill's first read-safe diagnostic pass is what you turn into `snapshot:` and `evidence:` — capture the actual command output as you go, don't summarise.

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

## Symptom catalogue convention

Each area skill references `references/symptoms.md` (symlink to `shared/symptoms/<area>.md`). That file is the canonical catalogue — patterns, root causes, fixes. Cite the section you used; do not paraphrase it back into the SKILL.

To add a new pattern: edit the corresponding `docs/troubleshooting/<area>.md` in the operator repo first; do not invent a solution to retrofit into the skill or its symptoms file.

## Signal classification & refute contract

After the diagnostic pass, classify the in-zone signal as one of:

- **`clean`** — no failure signal in this zone.
- **`primary`** — signal in this zone, explainable by causes internal to it (misconfig, bug, hard panic, leak). Emit `recommend`, not refute.
- **`secondary_backpressure`** — signal in this zone, but the zone has buffering / queueing semantics and the failure mode (OOM under load, queue full, repeated reject, journal growth on a healthy server) is the shape of being pushed back on from outside. No external quote required.
- **`secondary_quoted`** — signal in this zone, and the zone's own logs / metrics quote an external component or external condition (a hostname, a write-block, a watermark, a refused connection) as the proximate trigger.

`clean` and `secondary_*` → emit `hypothesis_refuted`. `primary` → emit `recommend`. Mutually exclusive in a turn.

Each area skill defines the **decision tree** for its zone in its own SKILL ("Zone signal classification" section). The tree walks the four classes in order CLEAN → QUOTED → BACKPRESSURE → PRIMARY on observable predicates — `primary` is the default fallback when no other class matches.

An area skill never names which skill to call next and never reasons about stack topology. Routing on a refute is triage's job: it owns the topology map and the chain. The expert reports class + raw observations; triage decides the next hop.

Emit the refute in this shape:

```yaml
hypothesis_refuted: true
skill: <name of the area skill emitting this>
signal_class: clean | secondary_backpressure | secondary_quoted
diagnostic_pass_evidence: |
  <verbatim summary of what the diagnostic pass saw>
cited_external_components: # raw strings from logs / metrics; omit when signal_class=clean
  - <verbatim quote or component name, e.g. "graylog:12201 connection refused">
  - <"disk usage exceeded flood-stage watermark">
reason: <one sentence on why this class fits the diagnostic pass>
```

Rules:

- Refute is not "I'm not sure". `clean` means the diagnostic pass checked the things this zone owns and they're healthy. `secondary_*` means the diagnostic pass saw signal, but the signal is the shape of a consequence, not a root cause.
- A partial diagnostic pass that couldn't read what it needed escalates to the engineer (read-before-recommend rule), not refutes.
- Do not invent `cited_external_components`. Only strings the diagnostic pass actually observed.
- An area skill never invokes another area skill itself. The only outputs are `recommend` (case closed) or `hypothesis_refuted` (over to triage).

## What every L2 skill must not do

- Execute any mutating command, even one the engineer asks for inline. The engineer applies fixes from `recommend` blocks themselves.
- Run cluster-wide or full-index queries without a cap.
- Close tickets or post to the ticket-tracker.
- Invoke another area skill directly. If the cause sits in a different area, emit `hypothesis_refuted` (above) and stop — the triage caller routes the next hop.
