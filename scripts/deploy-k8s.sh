#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

KUBECTL="microk8s kubectl"
HELM="microk8s helm3"

echo "==> Waiting for MicroK8s"
microk8s status --wait-ready >/dev/null

echo "==> Checking that Loki is reachable on the host loopback"
# loki returns 503 for a bit after startup
for i in $(seq 1 18); do
  curl -fsS http://127.0.0.1:3100/ready >/dev/null 2>&1 && { echo "Loki is ready"; break; }
  if (( i == 18 )); then
    echo "Loki is still not ready after 90 s."
    echo "Check 'docker compose ps loki' and 'docker compose logs --tail=30 loki', or run 'docker compose up -d'."
    exit 1
  fi
  echo "    Loki not ready yet (attempt $i/18), retrying in 5 s..."
  sleep 5
done

echo "==> Namespaces and workload"
$KUBECTL apply -f kubernetes/namespace.yaml
$KUBECTL apply -f kubernetes/workload.yaml
$KUBECTL -n orders-demo rollout status deploy/order-worker --timeout=180s

echo "==> Grafana Alloy (Helm)"
$HELM repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
$HELM repo update grafana
$HELM upgrade --install alloy grafana/alloy \
  --namespace monitoring --create-namespace \
  -f kubernetes/alloy-values.yaml
$KUBECTL -n monitoring rollout status ds/alloy --timeout=180s

echo "==> Status"
$KUBECTL get pods -n orders-demo -o wide
$KUBECTL get pods -n monitoring -o wide
echo
echo "Logs should appear in Loki within ~30 s. Check with: ./scripts/collect-artifact.sh loki"
