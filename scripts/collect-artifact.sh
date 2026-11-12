#!/usr/bin/env bash
# usage: collect-artifact.sh [versions|compose|k8s|metrics|loki|alerts|persistence]
# persistence restarts the stack, so it's not in the default run
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p artifact
KUBECTL="microk8s kubectl"
GRAFANA="${GRAFANA_URL:-http://127.0.0.1:3000}"
[[ -f .env ]] && set -a && . ./.env && set +a

section() { echo; echo "\$ $*"; "$@" 2>&1; }

versions() {
  { section lsb_release -a; section uname -r; section docker version --format 'Docker Engine {{.Server.Version}}'
    section docker compose version; section microk8s version; section microk8s status --wait-ready
    section $KUBECTL version; section microk8s helm3 version
    section find . \( -path ./.git -o -path ./app/.venv -o -path ./app/.pytest_cache -o -name __pycache__ \) -prune -o -type f ! -name .env -print
  } > artifact/01-versions-and-structure.txt
}
compose() {
  { section docker compose config --quiet && echo "compose config: valid"
    section docker compose ps
    section docker volume ls --filter name=observability
    section ss -tlnp
  } > artifact/02-compose.txt
}
k8s() {
  { section $KUBECTL get nodes -o wide; section $KUBECTL get pods -A -o wide
    section $KUBECTL -n orders-demo logs deploy/order-worker --timestamps --tail=25
    section $KUBECTL -n monitoring get ds,pods -l app.kubernetes.io/name=alloy
    section curl -fsS http://127.0.0.1:12345/-/ready
    echo; echo '$ Alloy pipeline metrics (files tailed, log lines pushed to Loki)'
    curl -fsS http://127.0.0.1:12345/metrics \
      | grep -E '^(loki_source_file_files_active_total|loki_write_sent_entries_total|loki_write_dropped_entries_total)'
    echo; echo '$ Alloy logs about the orders-demo workload'
    $KUBECTL -n monitoring logs ds/alloy -c alloy --tail=500 2>&1 | grep 'orders-demo' | tail -10
  } > artifact/05-kubernetes.txt
}
persistence() {
  local auth="${GF_ADMIN_USER:-admin}:${GF_ADMIN_PASSWORD:-}"
  oldest() {
    local s; s=$(curl -fsS --get http://127.0.0.1:9090/api/v1/query \
      --data-urlencode 'query=min(min_over_time(timestamp(up{job="node-exporter"})[30d:5m]))' | jq -r '.data.result[0].value[1]')
    echo "oldest node-exporter sample in Prometheus: $(date -u -d "@${s%.*}" '+%F %T UTC')"
    echo "Loki orders-demo lines in the last 24 h:   $(curl -fsS --get http://127.0.0.1:3100/loki/api/v1/query \
      --data-urlencode 'query=sum(count_over_time({namespace="orders-demo"}[24h]))' | jq -r '.data.result[0].value[1]')"
    echo "Grafana dashboards:                         $(curl -fsS -u "$auth" "$GRAFANA/api/search?type=dash-db" | jq -r '[.[].title] | join(", ")')"
  }
  { echo '$ BEFORE restart'; oldest
    section docker compose restart
    ./scripts/wait-ready.sh
    echo; echo '$ AFTER restart (the same history is still there)'; oldest
  } > artifact/02-persistence.txt 2>&1
}
metrics() {
  { section curl -s -i http://127.0.0.1:8000/health
    section curl -s -i -X POST http://127.0.0.1:8000/api/orders -H 'Content-Type: application/json' -d '{"product":"gadget","quantity":2}'
    section curl -s -i -X POST "http://127.0.0.1:8000/api/orders?simulate=error" -H 'Content-Type: application/json' -d '{"product":"gadget"}'
    section curl -s -i -X POST http://127.0.0.1:8000/api/orders -H 'Content-Type: application/json' -d '{"product":"widget","quantity":0}'
    echo; echo '$ curl -s http://127.0.0.1:8000/metrics | grep -E "^(http_|orders_)"'
    curl -s http://127.0.0.1:8000/metrics | grep -E '^(http_|orders_)'
  } > artifact/03-app-metrics.txt
  ./scripts/promql-checks.sh > artifact/04-promql-and-crosschecks.txt 2>&1
}
loki() {
  { echo '$ Loki labels'; curl -fsS http://127.0.0.1:3100/loki/api/v1/labels | jq -c .data
    echo '$ namespaces seen by Loki'; curl -fsS http://127.0.0.1:3100/loki/api/v1/label/namespace/values | jq -c .data
    echo '$ last 10 ERROR lines: {namespace="orders-demo", stream="stderr"} |= "ERROR"'
    curl -fsS --get http://127.0.0.1:3100/loki/api/v1/query_range \
      --data-urlencode 'query={namespace="orders-demo", stream="stderr"} |= "ERROR"' \
      --data-urlencode 'limit=10' --data-urlencode "start=$(( $(date +%s) - 900 ))000000000" \
      | jq -r '.data.result[] | .stream.pod as $p | .values[] | "\(.[0] | tonumber / 1e9 | todate) \($p) \(.[1])"'
  } > artifact/05-loki-query.txt 2>&1
}
alerts() {
  local auth="${GF_ADMIN_USER:-admin}:${GF_ADMIN_PASSWORD:-}"
  { echo '$ Grafana alert rules (provisioned)'
    curl -fsS -u "$auth" "$GRAFANA/api/v1/provisioning/alert-rules" | jq -r '.[] | "\(.uid)\t\(.title)\tfor=\(.for)"'
    echo; echo '$ Contact points (credentials are never returned)'
    curl -fsS -u "$auth" "$GRAFANA/api/v1/provisioning/contact-points" | jq -c '.[] | {name, type, addresses: "<hidden>"}'
    echo; echo '$ Current alert instances'
    curl -fsS -u "$auth" "$GRAFANA/api/prometheus/grafana/api/v1/alerts" \
      | jq -r '.data.alerts[]? | "\(.activeAt)\t\(.state)\t\(.labels.alertname)"'
  } > artifact/07-alerting.txt 2>&1
}

targets=("$@")
(( ${#targets[@]} )) || targets=(all)
for target in "${targets[@]}"; do
  case $target in
    all) versions; compose; k8s; metrics; loki; alerts ;;
    versions|compose|k8s|metrics|loki|alerts|persistence) "$target" ;;
    *) echo "unknown section: $target (use versions|compose|k8s|metrics|loki|alerts|persistence)"; exit 1 ;;
  esac
done
ls -1 artifact/*.txt
