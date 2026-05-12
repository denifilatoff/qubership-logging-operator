#!/usr/bin/env bash
set -euo pipefail

# qubership-logging-operator chart renders ServiceMonitor / PodMonitor /
# PrometheusRule / GrafanaDashboard. Without these CRDs helm install fails.
# Skip any CRD that's already installed — don't overwrite a foreign version.
BASE="https://raw.githubusercontent.com/Netcracker/qubership-monitoring-operator/refs/heads/main/charts/qubership-monitoring-operator/charts"

apply_if_missing() {
  local name="$1" url="$2"
  if kubectl get crd "$name" >/dev/null 2>&1; then
    echo "✓ $name already installed, skipping"
  else
    # Some CRDs are too large for client-side apply (annotation size limit).
    kubectl apply --server-side -f "$url"
  fi
}

apply_if_missing grafanadashboards.integreatly.org \
  "$BASE/grafana-operator/crds/integreatly.org_grafanadashboards.yaml"
apply_if_missing prometheusrules.monitoring.coreos.com \
  "$BASE/victoriametrics-operator/crds/monitoring.coreos.com_prometheusrules.yaml"
apply_if_missing servicemonitors.monitoring.coreos.com \
  "$BASE/victoriametrics-operator/crds/monitoring.coreos.com_servicemonitors.yaml"
apply_if_missing podmonitors.monitoring.coreos.com \
  "$BASE/victoriametrics-operator/crds/monitoring.coreos.com_podmonitors.yaml"

# Pre-install CRDs that charts reference from their own templates. On a fresh
# cluster helmfile's diff render fails because the API isn't registered yet.

# qubership-logging-operator's LoggingService CR is rendered by the chart.
apply_if_missing loggingservices.logging.netcracker.com \
  "$(dirname "$0")/../../../charts/qubership-logging-operator/crds/logging.netcracker.com_loggingservices.yaml"

if [[ "${BACKEND:-}" == "graylog" ]]; then
  OS_VER="${OPENSEARCH_VERSION:-2.3.0}"
  apply_if_missing opensearchservices.netcracker.com \
    "https://raw.githubusercontent.com/Netcracker/qubership-opensearch/${OS_VER}/operator/charts/helm/opensearch-service/crds/crd.yaml"
fi
