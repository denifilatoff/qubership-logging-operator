#!/usr/bin/env bash
set -euo pipefail

# Runs before the vmo release is uninstalled. Deletes the VLSingle CR while
# the VM operator is still around to garbage-collect its Deployment / Service
# / PVC. Without this the workload pods become orphaned after helmfile destroy.

: "${CLUSTER_NAME:?CLUSTER_NAME is required}"
CTX="kind-${CLUSTER_NAME}"

if ! kubectl --context "$CTX" get vlsingle k8s -n logging >/dev/null 2>&1; then
  echo "✓ vlsingle/k8s already absent"
  exit 0
fi

kubectl --context "$CTX" delete vlsingle k8s -n logging --wait=true --timeout=120s
