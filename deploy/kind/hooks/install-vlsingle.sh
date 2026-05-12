#!/usr/bin/env bash
set -euo pipefail

# Installed after the VictoriaMetrics operator release. Waits for the operator
# rollout, applies a VLSingle CR named "k8s", waits for it to become operational.

: "${CLUSTER_NAME:?CLUSTER_NAME is required}"
STORAGE_CLASS="${STORAGE_CLASS:-standard}"
CTX="kind-${CLUSTER_NAME}"

kubectl --context "$CTX" -n logging rollout status \
  deployment -l app.kubernetes.io/instance=vmo --timeout=300s

cat <<EOF | kubectl --context "$CTX" apply -f -
apiVersion: operator.victoriametrics.com/v1
kind: VLSingle
metadata:
  name: k8s
  namespace: logging
spec:
  resources:
    limits:
      cpu: 500m
      memory: 256Mi
    requests:
      cpu: 250m
      memory: 64Mi
  retentionPeriod: '1'
  storage:
    resources:
      requests:
        storage: 5Gi
    storageClassName: ${STORAGE_CLASS}
EOF

kubectl --context "$CTX" -n logging wait \
  --for=jsonpath='{.status.updateStatus}'=operational \
  vlsingle/k8s --timeout=300s
