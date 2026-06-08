**Taxonomy**

- intent: `problem`
- component: `graylog`
- platform: `vm` (External Logging, driven through `docker`, not Kubernetes)
- phase: `runtime`
- symptom: `not_running` (the container keeps restarting)

**Disposition: `additional_info_required`**

No `rca-cases` matcher fires. The localization is clear, so the required facts
come from the baseline plus the `not_running, platform=vm` row of
`facts-required.md`:

- present in the ticket: a `description` of the symptom only.
- missing: `logging_version`, `deployment_params`, `ssh_access`,
  `container_logs`.

The disposition must list the missing field-ids and ask for them in one round,
with the VM collection steps from `collection-howto.md` woven in (for example,
`docker logs --tail 2000 graylog_graylog_1` for `container_logs`, and SSH access
for `ssh_access`).

**Hard rules**

No live-system access, no mutation, no ticket closure. Exactly one round.
