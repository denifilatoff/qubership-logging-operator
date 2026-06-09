# Scenarios

Each subdirectory reproduces one failure on a running logging stack.

| Scenario                                | Component   | Backend       | What breaks                                                       |
|-----------------------------------------|-------------|---------------|-------------------------------------------------------------------|
| `fluentbit-config-syntax`               | fluentbit   | any           | Broken ConfigMap → FluentBit CrashLoopBackOff                     |
| `fluentbit-oom`                         | fluentbit   | any           | Memory limit too low → FluentBit OOMKilled                        |
| `fluentbit-cpu-throttle`                | fluentbit   | graylog       | CPU limit too low → throughput collapse, messages lost            |
| `opensearch-flood-stage-readonly`       | opensearch  | graylog       | Flood-stage trip → indices read-only                              |
| `graylog-gelf-input-size-too-small`     | graylog     | graylog       | GELF input `max_message_size` too small → big logs dropped        |
| `operator-helm-bad-image`               | operator    | any           | Bad image tag → operator ImagePullBackOff                         |

## Runtime contract

Scenarios assume a running logging stack with:

- Cluster reachable via context `$KCTX` (`lib.sh` derives it from
  `deploy/kind/.env`).
- Namespaces: `logging`, plus `opensearch` / `graylog` /
  `log-generator` as needed.
- Services with `helmfile.yaml.gotmpl`-equivalent names:
  `opensearch-cluster.opensearch`, `graylog-service.logging`,
  `log-generator-svc.log-generator`.
- Operator running in `logging` as helm release
  `qubership-logging-operator` (only required for scenarios that do
  `helm upgrade --reuse-values`: `fluentbit-oom`,
  `fluentbit-cpu-throttle`, `operator-helm-bad-image`).

`deploy/kind/` is one way to satisfy this contract.

## Workflow

```bash
# bring up baseline (one-time, from repo root)
cd deploy/kind
set -a && source .env && set +a
helmfile -f helmfile.yaml.gotmpl apply

# operate scenarios
cd ../../test/agent-packages/scenarios
./fixture.sh list
./fixture.sh apply  fluentbit-oom
# ... run the skill / eval against the cluster ...
./fixture.sh revert fluentbit-oom
```

**Policy**: one scenario active at a time. `apply` refuses if another is
already active — `revert` it first. State is tracked in `.state/`.

## Per-scenario layout

```text
<scenario-slug>/
  README.md        case description and injection mechanics
  apply.sh         introduces the failure
  revert.sh        restores baseline
```
