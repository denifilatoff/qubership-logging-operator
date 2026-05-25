# Fixtures

Each subdirectory is a reproducible failure scenario for the local kind
stack.

| Fixture | Case |
|---|---|
| F1-fluent-config-syntax    | Broken ConfigMap → FluentBit CrashLoopBackOff |
| F2-fluent-oom              | Memory limit too low → FluentBit OOMKilled    |
| F3-disk-readonly           | OpenSearch flood-stage → indices read-only     |
| F4-helm-bad-image          | Bad image tag → operator ImagePullBackOff      |
| F5b-fluentbit-cpu-throttle | CPU limit too low → throughput collapse, messages lost |
| F7-gelf-input-size         | Graylog GELF input `max_message_size` too small → big logs dropped |

## Workflow

```bash
cd deploy/kind
# baseline once per session
helmfile -f helmfile.yaml.gotmpl apply

cd fixtures
./fixture.sh list
./fixture.sh apply  F3-disk-readonly
# ... run the skill against the cluster ...
./fixture.sh revert F3-disk-readonly
./fixture.sh apply  F2-fluent-oom
# ...
```

**Policy**: one fixture active at a time. `apply` refuses if another is
already active — `revert` it first. State is tracked in `.state/`.

## Per-fixture layout

```
F<id>-<slug>/
  README.md        case description and injection mechanics
  apply.sh         introduces the failure
  revert.sh        restores baseline
  values-patch.yaml   (optional) helm values overlay for helm-based fixtures
```

## Notes on the kind stack

- `BACKEND=graylog` is needed for F3 / F5b / F7 (uses OpenSearch + Graylog).
- `BACKEND=victorialogs` is fine for F1 / F2 (collector-only).
- FluentD is `install: false` by default in both backends. Fixtures F1 /
  F2 / F5b target FluentBit only.
