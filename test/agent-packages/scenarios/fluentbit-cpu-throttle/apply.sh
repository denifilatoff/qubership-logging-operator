#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib.sh"

RELEASE="qubership-logging-operator"
NS="logging"
CHART="$KIND_DIR/../../charts/qubership-logging-operator"
# Default fluentbit limit is 200m. Push to 5m to make starvation
# unmistakable; bump load below to overcome any kernel/buffering slack.
NEW_CPU_LIMIT="5m"
NEW_CPU_REQUEST="1m"
LOAD_MSG_PER_SEC=10000
LOAD_GEN_TIME=300

log "current helm revision (revert.sh will rollback to it):"
helm --kube-context "$KCTX" -n "$NS" history "$RELEASE" | tail -3

# Both must be lowered together: Kubernetes rejects DaemonSet updates
# where requests.cpu > limits.cpu, and the chart's default request is
# 50m. Without --set on requests, the operator reconcile fails with a
# validation error and the DaemonSet keeps its old (healthy) CPU limit
# — fixture would not throttle anything. See F2 for the analogous case
# on memory.
log "upgrading $RELEASE with fluentbit.resources.limits.cpu=$NEW_CPU_LIMIT, requests.cpu=$NEW_CPU_REQUEST"
helm --kube-context "$KCTX" -n "$NS" upgrade "$RELEASE" "$CHART" \
  --reuse-values \
  --set "fluentbit.resources.limits.cpu=$NEW_CPU_LIMIT" \
  --set "fluentbit.resources.requests.cpu=$NEW_CPU_REQUEST" \
  --wait=false

log "waiting for daemonset rollout"
"${KUBECTL[@]}" -n "$NS" rollout status ds -l name=logging-fluentbit --timeout=300s || true

log "driving load: $LOAD_MSG_PER_SEC msg/s for ${LOAD_GEN_TIME}s via qubership-log-generator"
LG_BODY=$(printf '{"message":"fluentbit-cpu-throttle-stress","genTime":%d,"msgPerSec":%d}' "$LOAD_GEN_TIME" "$LOAD_MSG_PER_SEC")
"${KUBECTL[@]}" -n log-generator run "lg-curl-$RANDOM" \
  --rm -i --restart=Never --quiet \
  --image=curlimages/curl:8.10.1 \
  --command -- curl -sS -H 'Content-Type: application/json' -X POST -d "$LG_BODY" \
  'http://qubership-log-generator-service.log-generator:8080/editor/editLogs' >/dev/null || true

cat <<'NOTE'

────────────────────────────────────────────────────────────
Fault active. Skill probe commands:

  # 1) Effective CPU limit on the DaemonSet
  kubectl -n logging get ds logging-fluentbit \
    -o jsonpath='{.spec.template.spec.containers[?(@.name=="logging-fluentbit")].resources}{"\n"}'

  # 2) cgroup throttling stats — the smoking gun (nr_throttled ≈ nr_periods)
  POD=$(kubectl -n logging get pods -l name=logging-fluentbit \
    -o jsonpath='{.items[?(@.spec.nodeName=="local-dev-worker")].metadata.name}')
  kubectl -n logging debug $POD --image=alpine:3 --target=logging-fluentbit \
    -it -- cat /sys/fs/cgroup/cpu.stat

  # 3) FluentBit metrics — input/output records advance very slowly,
  #    the endpoint itself returns the same snapshot for many seconds
  kubectl -n logging port-forward $POD 12020:2020 &
  curl -sS http://127.0.0.1:12020/api/v1/metrics | jq .input.tail.0,.output

NB: there are NO 'connection timeout' or 'getaddrinfo' errors in
fluent-bit logs. Symptom is a throughput collapse, not a timeout flood.
────────────────────────────────────────────────────────────
NOTE
