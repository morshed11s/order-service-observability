# Artifacts

Text artifacts are produced by `./scripts/collect-artifact.sh`. Screenshots are taken by hand during the live run.
Before you save any screenshot, **blur or crop out** passwords, SMTP credentials, email addresses and personal data.

| File | Task | How to produce |
|------|------|----------------|
| `01-versions-and-structure.txt` | 1 | `collect-artifact.sh versions`: Ubuntu, Docker, Compose, MicroK8s, kubectl, Helm, file tree |
| `02-compose.txt` | 2 | `collect-artifact.sh compose`: compose config, `docker compose ps`, volumes, listening sockets (all on 127.0.0.1 or 172.30.0.1) |
| `03-app-metrics.txt` | 3 | `collect-artifact.sh metrics`: 200, 201, 500 and 400 responses, plus the custom `/metrics` lines |
| `04-promql-and-crosschecks.txt` | 4 | targets UP, five PromQL results, `free` / `df` / `uptime` cross-checks |
| `05-kubernetes.txt`, `05-loki-query.txt` | 5 | nodes, all pods, workload logs, Alloy status, the same ERROR lines queried from Loki |
| `07-alerting.txt` | 7 | rules, contact point (credentials hidden), alert instances |
| `traffic-before-after.txt` | 3, 8 | `./scripts/traffic-test.sh demo \| tee artifact/traffic-before-after.txt` |
| `compose-and-cluster.png` | 1, 2, 5 | terminal showing `docker compose ps` and `microk8s kubectl get pods -A` |
| `prometheus-targets.png` | 4 | http://127.0.0.1:9090/targets with node-exporter and order-api UP |
| `grafana-metrics.png` | 6 | the *Ubuntu Host & Order API – Metrics* dashboard, host section (CPU, RAM, disk, uptime, load, targets) |
| `grafana-host-traffic-1.png`, `grafana-host-traffic-2.png` | 6, 8 | the host section during the traffic test (CPU and load rise with the request rate) |
| `grafana-app-metrics.png` | 6, 8 | the dashboard's *Order API* section during `traffic-test.sh demo`: requests/s, 5xx error rate, p95 latency, orders created |
| `kubernetes-logs.png` | 5, 6 | Grafana Explore → Loki: `{namespace="orders-demo", stream="stderr"} \| json \| level="ERROR"` (live `payment_failed` lines from both pods) |
| `alert-firing.png` | 7 | Alerting → Alert rules: 2 provisioned rules, 1 firing |
| `alert-rule-detail.png` | 7 | *Order API scrape target down* = Firing: query `sum(up{job="order-api"}) or vector(0)` = 0, evaluated every 30s |
| `email-alert.png` | 7 | the received email (subject and timestamp visible, recipient blurred) |
| `resolved-email.png` | 7 | the resolved email after `docker compose start order-api` |
| `persistence-after-restart.png` | 2 | the dashboard still shows earlier data after `docker compose restart` |
