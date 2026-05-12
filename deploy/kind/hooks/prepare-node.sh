#!/usr/bin/env bash
set -euo pipefail

# Per-node prep before installing OpenSearch + logging stack:
#   1) /var/log/audit  — FluentBit reads /var/log/audit/audit.log from the host
#      filesystem on each node it runs on. On a fresh kind node it doesn't
#      exist, so the input fails and the pod crash-loops.
#   2) vm.max_map_count >= 262144 — OpenSearch refuses to start otherwise.
#      In recent kernels (Docker Desktop 4.x uses Linux 6.x) vm.max_map_count
#      is namespaced and can be raised inside a privileged kind node container.
# Both steps are idempotent.

REQUIRED_MAX_MAP_COUNT="${REQUIRED_MAX_MAP_COUNT:-262144}"

: "${CLUSTER_NAME:?CLUSTER_NAME is required (source deploy/kind/.env first)}"

if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  echo "kind cluster '$CLUSTER_NAME' not found." >&2
  exit 1
fi

NODES=()
while IFS= read -r line; do NODES+=("$line"); done < <(kind get nodes --name "$CLUSTER_NAME")

failed_nodes=()

for node in "${NODES[@]}"; do
  echo "▶ $node"

  docker exec "$node" bash -c \
    "mkdir -p /var/log/audit && chown 1000:1000 /var/log/audit && ls -ld /var/log/audit"

  current=$(docker exec "$node" sysctl -n vm.max_map_count)
  if (( current >= REQUIRED_MAX_MAP_COUNT )); then
    echo "  vm.max_map_count=$current (>= $REQUIRED_MAX_MAP_COUNT) ✓"
    continue
  fi

  echo "  vm.max_map_count=$current — raising to $REQUIRED_MAX_MAP_COUNT…"
  if docker exec "$node" sysctl -w "vm.max_map_count=$REQUIRED_MAX_MAP_COUNT" >/dev/null 2>&1; then
    new=$(docker exec "$node" sysctl -n vm.max_map_count)
    if (( new >= REQUIRED_MAX_MAP_COUNT )); then
      echo "  vm.max_map_count=$new ✓"
      continue
    fi
  fi

  failed_nodes+=("$node")
done

if (( ${#failed_nodes[@]} > 0 )); then
  cat >&2 <<MSG

✗ Could not raise vm.max_map_count on: ${failed_nodes[*]}

  vm.max_map_count is namespaced only on Linux 6.x+. If the kind nodes refuse
  the sysctl write, the host's Docker Desktop VM kernel is too old or the
  setting is not yet namespaced. Raise it on the Docker Desktop VM itself:

    docker run --rm --privileged --pid=host alpine \
      sysctl -w vm.max_map_count=$REQUIRED_MAX_MAP_COUNT

  Then re-run 'helmfile apply'. The setting persists for the lifetime of the
  Docker Desktop VM (until you 'Restart' it from the UI).
MSG
  exit 1
fi
