#!/usr/bin/env bash
# usage: wait-ready.sh [k8s]
set -uo pipefail
cd "$(dirname "$0")/.."
TIMEOUT="${WAIT_TIMEOUT:-180}"

wait_for() {
  local label=$1; shift
  local start=$SECONDS
  printf '%-34s' "$label"
  until "$@" >/dev/null 2>&1; do
    if (( SECONDS - start >= TIMEOUT )); then echo "NOT READY after ${TIMEOUT}s"; return 1; fi
    sleep 3
  done
  echo "ready ($(( SECONDS - start ))s)"
}

loki_has_orders_demo() {
  curl -fsS http://127.0.0.1:3100/loki/api/v1/label/namespace/values | grep -q '"orders-demo"'
}

rc=0
wait_for "Prometheus  127.0.0.1:9090"  curl -fsS http://127.0.0.1:9090/-/ready        || rc=1
wait_for "Loki        127.0.0.1:3100"  curl -fsS http://127.0.0.1:3100/ready          || rc=1
wait_for "Grafana     127.0.0.1:3000"  curl -fsS http://127.0.0.1:3000/api/health     || rc=1
wait_for "Order API   127.0.0.1:8000"  curl -fsS http://127.0.0.1:8000/health         || rc=1

if [[ "${1:-}" == "k8s" ]]; then
  K="microk8s kubectl"
  wait_for "order-worker pods (orders-demo)" $K -n orders-demo rollout status deploy/order-worker --timeout=5s || rc=1
  wait_for "Alloy DaemonSet (monitoring)"    $K -n monitoring rollout status ds/alloy --timeout=5s           || rc=1
  wait_for "orders-demo logs in Loki"        loki_has_orders_demo                                            || rc=1
fi

if (( rc == 0 )); then echo "All ready."; else
  echo "Something is not ready. Check: docker compose ps; docker compose logs --tail=30 <service>"
fi
exit $rc
