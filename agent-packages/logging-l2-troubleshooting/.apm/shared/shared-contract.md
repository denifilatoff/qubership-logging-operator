# L2 action-tier protocol and expert output contract

Shared contract for every `troubleshoot-*` and `investigate-*` expert skill in this package. Each skill loads it as
`references/shared-contract.md`.

## How L2 expert skills are invoked

- Discover cluster context from the cluster — never ask the engineer for namespaces, endpoints, or credentials as your
  first move. `kubectl` and the Graylog / OpenSearch HTTP endpoints are already reachable (in-cluster Service,
  port-forward, or an exposed route).
- If a symptom needs pod-level introspection on a VM-deployed Graylog / OpenSearch (Docker-on-VM, SSH,
  `/srv/docker/...`), recognise the limit and hand back. HTTP/REST APIs remain in scope on VM deployments.

## Action tiers

- **`read-safe`** — cheap, idempotent reads (`kubectl get`, `kubectl describe`, `kubectl logs --tail=N`, configmap
  inspection, single-document API GETs). Execute freely.
- **`read-heavy`** — read-only but potentially expensive (large log dumps, cluster-wide scans, full index listings).
  Execute only with a declared cap; if you can't meet the cap, downgrade to `recommend`.
- **`recommend`** — anything that mutates state. **Never executed.** Describe it in prose per Expert output below; the
  operator applies it manually.

## Read-before-recommend

Before emitting any `recommend`, capture a `read-safe` snapshot — actual command output, not a summary — and list every
item under `recommend.snapshot` with its `command` and pasted `output`. The snapshot must cover both:

- **the state the action changes** — the resource you propose to mutate; and
- **the state that proves the fix targets the right zone** — evidence that the component you are about to change is the
  faulty one, and that the surrounding components are healthy. A cross-zone recommend that does not show the
  neighbouring zones are fine is unproven: e.g. before recommending a Graylog-side change because collectors cannot
  deliver, snapshot the Graylog pods as Running/Ready (the server is up) alongside the misconfigured resource, so the
  recommend is not misdirected at a healthy part of the stack.

If a required piece of state cannot be read, escalate to the engineer; do not recommend blind.

## Right depth and complete fix

Confirm the root cause, not the surface symptom. If one read deeper exposes the setting that drives the symptom, take
that read before recommending — a fix aimed at the surface (clearing a block, bumping one field) that leaves the cause
in place will re-trigger. A recommend is incomplete when it changes only one of a coupled pair of settings, or when it
asserts a value (a version, a size, a tag) that was not derived from cluster state. Name the paired setting, the root
setting, and how the value was read.

## Expert output

Each expert writes a prose analysis for the engineer. It MUST:

- State the matched `symptom_id` for every symptom it confirms, copied character-for-character from the matcher's
  JSON output (equivalently, the `[id]` header in `references/symptoms.txt`). The `symptom_id` is a fixed catalog
  token, not a label you compose: keep its exact casing and hyphens, never rewrite it (for example swapping
  hyphens for underscores), and never invent a descriptive id of your own. It is the stable anchor the triage
  orchestrator routes on, so any paraphrase or reformat breaks routing. If nothing in the catalog matched, state
  that none did (see the anti-fabrication rule) rather than supplying one.
- Quote the verbatim diagnostic lines or values that prove the match (not a paraphrase).
- Give the proposed fix as prose, weaving in: what to change, why (which `symptom_id` and which evidence support it),
  the blast radius, the exact rollback, and a confidence level (high / medium / low).
- Capture the read-safe snapshot the fix relies on — paste the actual command output, covering both the state the action
  changes and the state proving the fix targets the right zone (see Read-before-recommend above).

Do not emit a fenced machine-readable block. Plain, well-structured prose is the deliverable; the orchestrator is itself
a model and reads it.

When the diagnostic pass surfaces no recognised symptom, say so plainly, paste a short digest of the diagnostic-pass
output, and stop. See the anti-fabrication rule below.

## Anti-fabrication rule

If the diagnostic pass produces no recognised symptom, the expert says so plainly and pastes a non-empty digest of the
diagnostic-pass output. Do not invent a `symptom_id`. Do not infer or speculate about causes. Do not propose fixes. A
"no known symptom matched" result is valid and expected — the orchestrator handles routing from there.

## What every L2 expert must not do

- Know about chain-walking, triage, topology, or other experts. The expert reports what it found; the triage skill
  decides the next hop.
- Diagnose or recommend a fix for a fault that lies in a different component than your own. When your reads show your
  component is healthy or correctly configured and the evidence points at another zone — for example the collector is
  fine but the Graylog endpoint refuses the connection, or its GELF input is bound to the wrong port — quote that
  cross-zone evidence and hand back. Do not freelance a remediation for a zone whose symptom catalog you have not read:
  a fix authored outside your zone is how a correct observation becomes a wrong recommend.
- Execute any mutating command. State changes are described as proposed fixes for the operator to apply, never executed.
- Run cluster-wide or full-index queries without a cap.
