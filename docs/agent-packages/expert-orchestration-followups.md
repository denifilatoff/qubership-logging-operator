# Expert-orchestration follow-ups

Items surfaced by the post-refactor eval run `20260526T063013Z` that are real but not blockers. None of them prevent the package from being useful; each weakens a specific architectural property documented in [expert-orchestration-pattern.md](expert-orchestration-pattern.md).

## 1. Symptom-id catalogue discipline

**Observation.** Experts emit `findings: - symptom_id: <id>` correctly as a structured field, but the `<id>` is sometimes invented from the failure description (`fluentbit_config_parse_failure_undefined_parsers`) rather than picked verbatim from the canonical entry in `references/symptoms.md` (`fluentbit-configmap-parse-error`).

**Impact.**
- Routing-policy is unaffected — it operates on `findings == []`, `evidence` regex, and `raw_diagnostic_pass` regex, not on `symptom_id` content.
- The symptom catalogue weakens as a shared knowledge base: the same failure mode gets reported under different ad-hoc ids across runs, no learning loop.
- Eval rubrics that grep for canonical ids fail even when the diagnosis is correct.

**Fix direction.**
- In each expert SKILL.md "Lookup and output" section, add an explicit instruction: "The `symptom_id` MUST be the literal `id:` field from the matched entry in `references/symptoms.md`. Do not paraphrase, abbreviate, or coin new ids."
- Consider an "id enumeration" block in the SKILL.md that lists the catalogue's current ids inline as a hint, so the model sees them in context (small per-expert: 3-5 entries each).
- Validate via a tightened rubric check that fails when a `symptom_id` doesn't appear in `shared/symptoms/<area>.md`.

**Not done because.** Prompt engineering scope; needs a deliberate iteration cycle with measurement, not a one-shot fix.

## 2. Cited-strings cascade test fixture

**Observation.** The new synthetic case `fluentbit-graylog-connection-refused` was meant to exercise the cited-strings cascade routing path. Two scenario designs were tried:

1. **Bad hostname in FluentBit ConfigMap** — fluentbit's expert correctly diagnosed the misconfigured ConfigMap and fixed it locally, never cascading.
2. **Graylog StatefulSet scaled to zero** — triage's initial diagnostic pass immediately saw the empty StatefulSet and routed straight to graylog-server-troubleshoot, skipping fluentbit.

Both designs produce correct real-world behaviour but neither exercises cited-strings cascade. Cascade routing fires only when the downstream failure is **not** visible from triage's cluster-wide initial pass.

**Fix direction.**
- Design a scenario where graylog pods are running healthy and the Service has endpoints, but the GELF traffic from FluentBit is rejected. Candidates:
  - NetworkPolicy blocking FluentBit → graylog:12201.
  - Graylog GELF input listening on a port that doesn't match the Service spec (input renamed via API).
  - Graylog GELF input stopped via Graylog API while the rest of Graylog stays up.
- Each of these keeps `kubectl get pods -l app.kubernetes.io/name=graylog` healthy and `kubectl get endpoints graylog-service` non-empty, hiding the downstream issue from triage's initial pass.
- FluentBit logs will then surface `connection refused` or `output timeout` lines naming graylog. cited-strings rule fires → cascade to graylog-server-troubleshoot.

**Not done because.** The above scenarios are heavier to set up than a simple helm `--set` mutation — they need NetworkPolicies or Graylog API state edits that the existing fixture mechanism doesn't yet support. Needs a separate iteration on the scenario harness.

## 3. (Watchlist) Direct-routing dominance over cascade

**Observation.** The orchestrator prefers the shortest correct path. When the cluster state directly shows a downstream issue, it routes there. Cascade routing only kicks in when the downstream issue is observable only inside an upstream expert's evidence.

**Impact.** This is correct real-world behaviour, but it means cited-strings cascade is rarely exercised in practice. The cited-strings.md table earns its keep on a smaller class of cases than originally imagined.

**Whether to act.** No fix needed — the architecture is doing the right thing. Worth noting if anyone wonders why the cited-strings pattern set stays small.
