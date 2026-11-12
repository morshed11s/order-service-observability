#!/usr/bin/env bash
set -euo pipefail
PROM="${PROM_URL:-http://127.0.0.1:9090}"

q() {
  curl -fsS --get "$PROM/api/v1/query" --data-urlencode "query=$1" \
    | jq -r '.data.result[0].value[1] // "no data"'
}
show() { printf '%-26s %-14s %s\n' "$1" "$(q "$2")" "$2"; }

echo "== Prometheus targets =="
curl -fsS "$PROM/api/v1/targets" | jq -r '.data.activeTargets[] | "\(.labels.job)\t\(.health)\t\(.scrapeUrl)"' | column -t
echo
echo "== Required PromQL expressions =="
show "CPU %"            '100 * (1 - avg(rate(node_cpu_seconds_total{job="node-exporter",mode="idle"}[5m])))'
show "RAM %"            '100 * (1 - node_memory_MemAvailable_bytes{job="node-exporter"} / node_memory_MemTotal_bytes{job="node-exporter"})'
show "Requests/second"  'sum(rate(http_requests_total{job="order-api"}[1m]))'
show "5xx error ratio"  '(sum(rate(http_requests_total{job="order-api",status=~"5.."}[5m])) or vector(0)) / clamp_min(sum(rate(http_requests_total{job="order-api"}[5m])), 0.001)'
show "p95 latency (s)"  'histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{job="order-api"}[5m])))'
echo
echo "== Extra host readings =="
show "Disk / used %"    '100 * (1 - node_filesystem_avail_bytes{job="node-exporter",mountpoint="/"} / node_filesystem_size_bytes{job="node-exporter",mountpoint="/"})'
show "Uptime (s)"       'time() - node_boot_time_seconds{job="node-exporter"}'
show "Load 1m"          'node_load1{job="node-exporter"}'
NET_DEV='device!~"lo|veth.*|docker.*|br-.*|cali.*|vxlan.*|flannel.*|cni.*"'
show "Network rx (bit/s)" "8 * sum(rate(node_network_receive_bytes_total{job=\"node-exporter\",$NET_DEV}[5m]))"
show "Network tx (bit/s)" "8 * sum(rate(node_network_transmit_bytes_total{job=\"node-exporter\",$NET_DEV}[5m]))"
show "Orders created"   'sum(orders_created_total{job="order-api"})'

echo
echo "== Cross-check 1: RAM (free) =="
free -b | awk '/^Mem:/ {printf "free:        total=%d available=%d  -> used%%=%.2f\n", $2, $7, 100*(1-$7/$2)}'
printf 'prometheus:  total=%s available=%s\n' \
  "$(q 'node_memory_MemTotal_bytes{job="node-exporter"}')" "$(q 'node_memory_MemAvailable_bytes{job="node-exporter"}')"

echo
echo "== Cross-check 2: root filesystem (df) =="
df -B1 --output=size,used,avail,pcent / | awk 'NR==2 {printf "df:          size=%d avail=%d  use%%=%s (df rounds up; used/(used+avail))\n", $1, $3, $4}'
printf 'prometheus:  size=%s avail=%s\n' \
  "$(q 'node_filesystem_size_bytes{job="node-exporter",mountpoint="/"}')" "$(q 'node_filesystem_avail_bytes{job="node-exporter",mountpoint="/"}')"

echo
echo "== Cross-check 3: uptime / load =="
echo "uptime:      $(uptime)"
echo "/proc:       uptime_s=$(cut -d' ' -f1 /proc/uptime)  loadavg=$(cut -d' ' -f1-3 /proc/loadavg)"
printf 'prometheus:  uptime_s=%s load1=%s\n' "$(q 'time() - node_boot_time_seconds{job="node-exporter"}')" "$(q 'node_load1{job="node-exporter"}')"
