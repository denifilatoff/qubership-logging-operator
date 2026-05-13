# Local kind deployment

## Prereqs

```bash
brew install kind helm helmfile
helm plugin install https://github.com/databus23/helm-diff --verify=false
```

## Install

```bash
cp deploy/kind/.env.example deploy/kind/.env
# edit deploy/kind/.env — set CLUSTER_NAME and BACKEND (graylog | victorialogs)

kind create cluster --name "$(grep ^CLUSTER_NAME deploy/kind/.env | cut -d= -f2)"

set -a && source deploy/kind/.env && set +a
helmfile -f deploy/kind/helmfile.yaml.gotmpl apply
```

> First `apply` with `BACKEND=graylog` pulls a ~1.5GB OpenSearch image — give it 30–40 min on a fresh node.

## Switch backend

```bash
# tear down current backend, edit BACKEND in deploy/kind/.env, then apply again
set -a && source deploy/kind/.env && set +a
helmfile -f deploy/kind/helmfile.yaml.gotmpl destroy

# edit BACKEND, source again, apply
helmfile -f deploy/kind/helmfile.yaml.gotmpl apply
```

## Access the UI

Port-forward the backend service to `localhost` while the cluster is running.

**Graylog** (web UI on `:9000`, default creds `admin` / `admin`):

```bash
kubectl --context "kind-$CLUSTER_NAME" -n logging port-forward svc/graylog-service 9000:9000
# open http://localhost:9000
```

**VictoriaLogs** (HTTP API + built-in UI on `:9428`):

```bash
kubectl --context "kind-$CLUSTER_NAME" -n logging port-forward svc/vlsingle-k8s 9428:9428
# open http://localhost:9428/select/vmui
```

## Log generator

The stack always installs `qubership-log-generator` in namespace `log-generator`. It writes all built-in patterns (java/go/json/nginx/glusterd/unicode/spring/zipkin) at 5 msg/sec each with multiline enabled; the fluentbit daemonset picks the lines up from `/var/log/containers` and ships them to the active backend. To stream the raw output:

```bash
kubectl --context "kind-$CLUSTER_NAME" -n log-generator logs -f -l name=qubership-log-generator
```

The chart ships an HTTP server with a UI for sending one-off custom messages into the same stream, plus Prometheus metrics. The kind preset has `ingress.enabled: false`, so reach it via port-forward:

```bash
kubectl --context "kind-$CLUSTER_NAME" -n log-generator port-forward svc/qubership-log-generator-service 8080:8080
# UI:      http://localhost:8080/customLogEditorPage
# Metrics: http://localhost:8080/metrics
```

Chart lives in the sibling repo at `../qubership-log-generator/charts/qubership-log-generator` relative to this repo root — clone it next to `qubership-logging-operator`.

## Hooks

- `prepare-node.sh` (prepare) — creates `/var/log/audit` on each kind node and raises `vm.max_map_count`, without which FluentBit crashloops and OpenSearch refuses to start.
- `apply-monitoring-crds.sh` (prepare) — pre-installs `ServiceMonitor` / `PodMonitor` / `PrometheusRule` / `GrafanaDashboard` / `LoggingService` / `OpenSearchService` CRDs, without which helm render fails on a fresh cluster. The `qubership-monitoring-operator` source URL is **pinned to commit `2c0cf2537b`**: upstream commit `c61cc8e` (2026-05-12) upgraded grafana-operator 4.x→5.x and renamed the GrafanaDashboard group from `integreatly.org` to `grafana.integreatly.org`, but the qubership-logging-operator and qubership-log-generator charts still emit `apiVersion: integreatly.org/v1alpha1`. Until both charts migrate, the pre-rename CRD is what makes helm render succeed. Once the charts migrate, drop the pin and switch the URL back to `refs/heads/main`.
- `install-vlsingle.sh` (vmo postsync) — applies the `VLSingle` CR after the VictoriaMetrics operator installs its CRD; this CR is what actually spawns the log-storage workload.
- `uninstall-vlsingle.sh` (vmo preuninstall) — deletes the `VLSingle` CR while the operator is still alive so it can garbage-collect the Deployment / Service / PVC instead of orphaning them.

## Uninstall

```bash
set -a && source deploy/kind/.env && set +a
helmfile -f deploy/kind/helmfile.yaml.gotmpl destroy
kind delete cluster --name "$CLUSTER_NAME"
```
