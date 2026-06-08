**Taxonomy**

- intent: `problem`
- component: `fluentbit`
- platform: `kubernetes`
- phase: `runtime`
- symptom: `oom_memory` (the author leads with OOMKilled); `not_running` is also
  defensible because the pods are in CrashLoopBackOff, and both map to the same
  required-facts row. Either passes.

**Disposition: `additional_info_required`**

No `rca-cases` matcher fires. The localization is clear, so the required facts
come from the baseline plus the `oom_memory or not_running, platform=kubernetes`
row of `facts-required.md`:

- present in the ticket: a `description` of the symptom only.
- missing: `logging_version`, `deployment_type`, `deployment_params`,
  `service_logs`, `pod_yaml`, `configmap_fluent`, `dashboards`.

The disposition must list the missing field-ids and ask for them in one round,
with collection steps from `collection-howto.md` woven in (for example,
`kubectl -n logging logs -l name=logging-fluentbit --previous` for
`service_logs`, or the pod-YAML dump for `pod_yaml`).

**Hard rules**

No live-system access, no mutation, no ticket closure. Exactly one round.
