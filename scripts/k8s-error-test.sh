#!/usr/bin/env bash
# usage: k8s-error-test.sh start|stop
set -euo pipefail
KUBECTL="microk8s kubectl -n orders-demo"

if ! $KUBECTL get deploy/order-worker >/dev/null 2>&1; then
  echo "order-worker is not deployed (namespace orders-demo is missing or empty)."
  echo "Run ./scripts/deploy-k8s.sh first, then retry: $0 ${1:-start}"
  exit 1
fi

case "${1:-start}" in
  start) $KUBECTL set env deploy/order-worker ERROR_RATE=0.6 ;;
  stop)  $KUBECTL set env deploy/order-worker ERROR_RATE=0.1 ;;
  *) echo "usage: $0 start|stop"; exit 1 ;;
esac
$KUBECTL rollout status deploy/order-worker --timeout=120s
echo "Recent stderr/ERROR lines from the live pods:"
sleep 10
$KUBECTL logs deploy/order-worker --since=30s --timestamps | grep -E 'ERROR|WARN' | tail -n 10 || true
cat <<'MSG'

Grafana Explore (Loki) queries:
  {namespace="orders-demo", stream="stderr"} | json | level="ERROR"
  sum by (pod) (count_over_time({namespace="orders-demo"} | json | level="ERROR" [1m]))
MSG
