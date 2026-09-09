#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
chart="$repo_root/charts/qubership-logging-operator"

assert_contains() {
    local expected=$1
    local rendered_output=$2
    if ! grep -Fq -- "$expected" <<<"$rendered_output"; then
        echo "Expected rendered monitoring selector to contain: $expected"
        echo "$rendered_output"
        exit 1
    fi
}

fluentbit=$(helm template logging "$chart" --show-only templates/fluentbit-daemonset/podmonitor.yaml \
    --set fluentbit.install=true)
assert_contains 'key: app.kubernetes.io/name' "$fluentbit"
assert_contains 'operator: In' "$fluentbit"
assert_contains '- logging-fluentbit' "$fluentbit"
assert_contains '- logging-fluentbit-forwarder' "$fluentbit"
assert_contains '- logging-fluentbit-aggregator' "$fluentbit"

fluentd=$(helm template logging "$chart" --show-only templates/fluentd/podmonitor.yaml \
    --set fluentd.install=true)
assert_contains 'app.kubernetes.io/name: logging-fluentd' "$fluentd"

graylog=$(helm template logging "$chart" --show-only templates/graylog/servicemonitor.yaml \
    --set graylog.install=true)
assert_contains 'app.kubernetes.io/name: graylog-service' "$graylog"
