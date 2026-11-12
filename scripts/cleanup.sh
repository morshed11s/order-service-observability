#!/usr/bin/env bash
# --purge also removes the volumes and app image
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Kubernetes resources"
microk8s helm3 uninstall alloy -n monitoring 2>/dev/null || true
microk8s kubectl delete -f kubernetes/workload.yaml --ignore-not-found
microk8s kubectl delete -f kubernetes/namespace.yaml --ignore-not-found

echo "==> Docker Compose stack"
if [[ "${1:-}" == "--purge" ]]; then
  docker compose down --volumes --rmi local
else
  docker compose down
fi
echo "Done."
