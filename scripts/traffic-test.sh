#!/usr/bin/env bash
# usage: traffic-test.sh normal|high|failure|slow|demo [seconds]
set -euo pipefail

API="${API_URL:-http://127.0.0.1:8000}"
MODE="${1:-normal}"
DURATION="${2:-60}"
PRODUCTS=(widget gadget gizmo)

snapshot() {
  local m; m=$(curl -fsS "$API/metrics")
  echo "$m" | grep -E '^(http_requests_total|orders_created_total|orders_failed_total|orders_value_usd_total|http_request_duration_seconds_count)' \
    | grep -v ' 0.0$' | sort || true
  echo "-- latency histogram buckets, POST /api/orders (cumulative, le = upper bound in seconds) --"
  echo "$m" | grep -E '^http_request_duration_seconds_(bucket|sum)\{endpoint="/api/orders"' || echo "(no /api/orders requests yet)"
}

order() {
  local p=${PRODUCTS[$((RANDOM % 3))]} q=$((RANDOM % 5 + 1))
  curl -s -o /dev/null -w '%{http_code}\n' -X POST "$API/api/orders$1" \
    -H 'Content-Type: application/json' -d "{\"product\":\"$p\",\"quantity\":$q}"
}

run() {
  local mode=$1 secs=$2 rate delay end
  case $mode in
    normal)  rate=2 ;;
    high)    rate=25 ;;
    failure) rate=10 ;;
    slow)    rate=3 ;;
    *) echo "unknown mode: $mode"; exit 1 ;;
  esac
  delay=$(awk "BEGIN{print 1/$rate}")
  end=$((SECONDS + secs))
  echo "==> $mode traffic: ~$rate req/s for ${secs}s against $API"
  while (( SECONDS < end )); do
    case $mode in
      failure)
        r=$((RANDOM % 10))
        if   (( r < 3 )); then order "?simulate=error" &
        elif (( r < 4 )); then curl -s -o /dev/null -w '%{http_code}\n' -X POST "$API/api/orders" \
                                 -H 'Content-Type: application/json' -d '{"product":"widget","quantity":0}' &
        else order "" &
        fi ;;
      slow) order "?simulate=slow" & ;;
      *)    order "" & ;;
    esac
    (( RANDOM % 10 == 0 )) && curl -s -o /dev/null -w '%{http_code}\n' "$API/health" &
    sleep "$delay"
  done | sort | uniq -c | awk '{printf "    HTTP %s x %s\n", $2, $1}'
  wait
}

curl -fsS "$API/health" >/dev/null || { echo "Order API not reachable at $API"; exit 1; }

echo "---- metrics BEFORE ----"; snapshot
if [[ $MODE == demo ]]; then
  run normal 60; run high 60; run slow 30; run failure 60
else
  run "$MODE" "$DURATION"
fi
echo "---- metrics AFTER ----"; snapshot
