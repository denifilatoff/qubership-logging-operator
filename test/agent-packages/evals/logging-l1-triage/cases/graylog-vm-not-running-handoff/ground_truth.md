**Taxonomy**

- intent: `problem`
- component: `graylog` is the surface the author points at (the Graylog
  container will not stay up); `mongodb` is also defensible, since the container
  log shows the MongoDB socket is the cause. Either passes.
- platform: `vm` (External Logging, `docker`-based)
- phase: `runtime`
- symptom: `not_running`

**Disposition: `handoff_to_l2`**

No `rca-cases` matcher fires (a MongoDB `Connection refused` on a VM is not a
catalogued case), and L1 cannot resolve it. Every required fact is present
inline, so the disposition is a handoff packet — not an
`additional_info_required` request. This is the fact-complete twin of
`graylog-vm-not-running-missing-facts`.

The `not_running, platform=vm` row of `facts-required.md` plus the `problem`
baseline are all satisfied:

- `logging_version`: 14.5.2
- `deployment_params`: the External Logging inventory snippet
- `ssh_access`: provided (`ssh deploy@graylog-vm-01` with the attached key)
- `container_logs`: the `docker logs` excerpt with the MongoDB connection error

The handoff packet must carry `localization` and a `facts` map, each fact quoted
verbatim with its source. It must NOT ask for more data and must NOT invent a
known cause.

**Hard rules**

No live-system access, no mutation, no ticket closure.
