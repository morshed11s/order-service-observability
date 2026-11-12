# Observability Stack for a Containerized Order Service

This project provides a local observability environment for a sample order-processing application. It combines Prometheus, Grafana, Loki, and Kubernetes log collection to demonstrate how metrics, application health, and operational events can be monitored in a single platform.

## Overview

The stack covers three core observability workflows:

| Workflow        | Description                                                                                                                     |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Metrics         | Host and application telemetry are collected by Node Exporter and the Order API, then visualized in Grafana through Prometheus. |
| Kubernetes logs | Application logs from `order-worker` pods running in MicroK8s are streamed to Loki via Grafana Alloy and queried with LogQL.  |
| Alerting        | Grafana alert rules evaluate service health and send notifications through SMTP to an operational inbox.                        |

This is designed as a practical reference and demonstration environment for monitoring and alerting patterns, rather than a generic learning assignment.

```text
 Ubuntu host - all published ports bound to 127.0.0.1

 +- Docker Compose - network "obs" (172.30.0.0/24) ---------------------------------------+
 |                         scrape 15s                                                     |
 |  +-------------------+               +--------------------+  PromQL                    |
 |  | Order API  :8000  +-------------->| Prometheus  :9090  +--------------+             |
 |  +-------------------+       +------>| metrics, 15 d      |              |             |
 |                              |       +--------------------+              v             |
 |  +-------------------+       |                                 +---------------------+ |
 |  | Node Exporter     +-------+                                 | Grafana  :3000      | |
 |  | 172.30.0.1:9100   |                                         | dashboards, alerts  | |
 |  +-------------------+                                         +---------------+-----+ |
 |                                      +--------------------+          ^         |       |
 |                                      | Loki  :3100        +----------+         |       |
 |                                      | logs, 7 d          |  LogQL             | SMTP  |
 |                                      +--------------------+                    |       |
 |                                                      ^                         |       |
 +------------------------------------------------------+-------------------------+-------+
                                                        | push to 127.0.0.1:3100  |
 +- MicroK8s -------------------------------------------+--------+                v
 |  ns orders-demo                      ns monitoring   |        |      +----------------+
 |  +-------------------+               +---------------+----+   |      | SMTP server    |
 |  | order-worker x2   +-------------->| Grafana Alloy      |   |      | alert inbox    |
 |  | stdout + stderr   | /var/log/pods | DaemonSet          |   |      +----------------+
 |  +-------------------+               +--------------------+   |
 +---------------------------------------------------------------+
```

| Flow | Path |
| ---- | ---- |
| Metrics | Prometheus scrapes the Order API and Node Exporter every 15 s; Grafana queries it with PromQL. |
| Logs | `order-worker` pods write to stdout/stderr; Alloy tails `/var/log/pods` and pushes to Loki on `127.0.0.1:3100`; Grafana queries it with LogQL. |
| Alerts | Grafana evaluates the alert rules and sends notifications through SMTP to the test inbox. |

## Repository structure

```
order-service-observability/
├── README.md                     this file: setup, verification, demo, cleanup
├── compose.yaml                  Prometheus, Grafana, Loki, Node Exporter, Order API
├── .env.example                  template for secrets (copy to .env, which is git-ignored)
├── .gitignore / .gitattributes
├── app/
│   ├── app.py                    Order API (Flask + prometheus_client)
│   ├── Dockerfile, .dockerignore
│   ├── requirements.txt, requirements-dev.txt
│   └── tests/test_app.py         pytest tests
├── prometheus/prometheus.yml     scrape jobs: node-exporter, order-api, prometheus
├── loki/config.yml               single-binary Loki, filesystem storage, 7-day retention
├── kubernetes/
│   ├── namespace.yaml            orders-demo + monitoring
│   ├── workload.yaml             order-worker Deployment (+ ConfigMap with the worker script)
│   └── alloy-values.yaml         Helm values: Alloy DaemonSet, pod log discovery, push to Loki
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/datasources.yaml
│   │   ├── dashboards/dashboards.yaml
│   │   └── alerting/             contact-points.yaml, policies.yaml, rules.yaml
│   └── dashboards/               observability-metrics.json, kubernetes-logs.json
├── alerting/configuration-notes.md   SMTP, threshold, evaluation, recipient, operator action
├── scripts/
│   ├── setup-ubuntu.sh           install Docker, MicroK8s, helm3, jq
│   ├── deploy-k8s.sh             deploy order-worker and Alloy to MicroK8s
│   ├── wait-ready.sh             wait until the stack (and optionally k8s) is ready
│   ├── traffic-test.sh           normal / high / failure / slow / demo traffic
│   ├── k8s-error-test.sh         raise / reset the worker's error rate
│   ├── promql-checks.sh          the five PromQL expressions + free/df/uptime cross-checks
│   ├── collect-artifact.sh       write text artifacts into artifact/
│   └── cleanup.sh                tear everything down
└── artifact/                     text artifacts (generated) + screenshots (taken during the demo),
                                  see artifact/README.md
```

## Prerequisites

Requirements: Ubuntu 26.04, at least 4 vCPU and 8 GB RAM, internet access to pull images.

```bash
git clone <repo-url> order-service-observability && cd order-service-observability   # or unzip the archive
chmod +x scripts/*.sh
./scripts/setup-ubuntu.sh          # Docker Engine + Compose plugin, MicroK8s, dns + helm3 add-ons, jq
newgrp docker; newgrp microk8s     # or log out and back in

# verify the toolchain
lsb_release -d && docker compose version
microk8s status --wait-ready && microk8s kubectl get nodes
./scripts/collect-artifact.sh versions && cat artifact/01-versions-and-structure.txt
```

> **Deviation: Ubuntu 22.04 instead of 26.04.** The artifacts in `artifact/` were captured in a VirtualBox VM
> (Vagrant box `ubuntu/jammy64`, 4 vCPU, 6 GB RAM, 2 GB swap) running **Ubuntu 22.04.5 LTS**. Nothing in the project depends on the release:
> `setup-ubuntu.sh` reads the codename from `/etc/os-release` for the Docker apt repository, and every
> other component (Docker Engine, Compose, MicroK8s, Helm, the container images) is the same on both
> releases. On 26.04 the same commands apply unchanged.

> **Running in a VM**
> To open the UIs from the host, tunnel the loopback ports:
> `ssh -L 3000:127.0.0.1:3000 -L 9090:127.0.0.1:9090 <vm>` (with Vagrant: `vagrant ssh -- -L 3000:127.0.0.1:3000 -L 9090:127.0.0.1:9090`).

## Configuration and startup

```bash
cp .env.example .env && chmod 600 .env
nano .env                         # Grafana admin password, SMTP host/user/app password, ALERT_EMAIL_TO

docker compose config --quiet && echo "config OK"
docker compose up -d --build
docker compose ps                 # all services "running" / order-api "healthy"
```

| UI / API      | URL (loopback only)            | Notes                                                 |
| ------------- | ------------------------------ | ----------------------------------------------------- |
| Grafana       | http://127.0.0.1:3000          | log in with `GF_ADMIN_USER` / `GF_ADMIN_PASSWORD` |
| Prometheus    | http://127.0.0.1:9090/targets  |                                                       |
| Order API     | http://127.0.0.1:8000/health   |                                                       |
| Loki          | http://127.0.0.1:3100/ready    |                                                       |
| Node Exporter | http://172.30.0.1:9100/metrics | private bridge address, not loopback                  |

Design decisions:

* **Durable data:** named volumes `prometheus_data`, `loki_data` and `grafana_data`. To check persistence, run
  `docker compose restart` (or `down` then `up -d`). The dashboards still show the earlier data.
* **Restart behaviour:** every service has `restart: unless-stopped`, and logs rotate (json-file, 3 × 10 MB).
* **Service discovery:** Prometheus reaches `order-api:8000`, and Grafana reaches `prometheus:9090` and
  `loki:3100`, through Docker's embedded DNS on the `obs` network.
* **Configuration:** all of it comes from mounted files (read-only) and environment variables from `.env`.
* **Real host metrics:** Node Exporter uses `network_mode: host` and `pid: host` (real interfaces and processes),
  with `/` mounted read-only (`/:/host:ro,rslave`, `--path.rootfs=/host`).
* **Private endpoints:** Grafana, Prometheus, Loki and the API publish on **127.0.0.1** only. Node Exporter
  shares the host network, so it binds to **172.30.0.1**, the gateway of the `obs` bridge. Only the host and
  its containers can reach that address. Check with `ss -tlnp`: nothing listens on `0.0.0.0` for these
  services.

## Application instrumentation and API behavior

| Endpoint             | Behaviour                                                                                                                                                                    |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `GET /health`      | `200 {"status":"ok"}`                                                                                                                                                      |
| `POST /api/orders` | `201` with `{"product":"widget","quantity":2}`; `400` for invalid input or an unknown product; `?simulate=error` returns `500`; `?simulate=slow` adds 0.8–1.5 s |
| `GET /metrics`     | Prometheus text format                                                                                                                                                       |

| Metric                            | Type                          | Labels (bounded)                                                          |
| --------------------------------- | ----------------------------- | ------------------------------------------------------------------------- |
| `http_requests_total`           | counter                       | `method`, `endpoint` (route template or `unmatched`), `status`    |
| `http_request_duration_seconds` | histogram (5 ms … 5 s)       | `method`, `endpoint`                                                  |
| `http_requests_in_progress`     | gauge                         | –                                                                        |
| `orders_created_total`          | counter (business event)      | `product` (fixed catalogue of 3)                                        |
| `orders_value_usd_total`        | counter (business event, USD) | –                                                                        |
| `orders_failed_total`           | counter                       | `reason` (validation, unknown_product, simulated_error, internal_error) |

Raw paths and user input never become label values, so the number of series stays bounded. `/metrics`
scrapes are not counted as traffic. Every request writes a structured JSON log line.

```bash
curl -i http://127.0.0.1:8000/health
curl -i -X POST http://127.0.0.1:8000/api/orders -H 'Content-Type: application/json' -d '{"product":"gadget","quantity":2}'
curl -i -X POST 'http://127.0.0.1:8000/api/orders?simulate=error' -H 'Content-Type: application/json' -d '{"product":"gadget"}'
curl -i -X POST http://127.0.0.1:8000/api/orders -H 'Content-Type: application/json' -d '{"product":"widget","quantity":0}'
curl -s http://127.0.0.1:8000/metrics | grep -E '^(http_|orders_)'

./scripts/traffic-test.sh normal 60      # ~2 req/s; the script prints metrics BEFORE and AFTER
./scripts/traffic-test.sh high 60        # ~25 req/s
./scripts/traffic-test.sh failure 60     # ~30% 500s, 10% 400s
./scripts/traffic-test.sh slow 60        # p95 latency rises above 1 s

# unit tests
cd app && python3 -m venv .venv && . .venv/bin/activate && pip install -r requirements-dev.txt && pytest -q
```

## Metrics collection and PromQL

* Scrape jobs: `node-exporter` (172.30.0.1:9100), `order-api` (order-api:8000) and `prometheus`, every **15 s**.
* Run `./scripts/promql-checks.sh`. It prints the target health, the five required expressions, and the
  `free`, `df` and `uptime` cross-checks.
* The expressions are in [scripts/promql-checks.sh](scripts/promql-checks.sh).

## Kubernetes workloads and log collection

```bash
./scripts/deploy-k8s.sh     # namespaces, order-worker Deployment (2 replicas), Alloy via Helm
microk8s kubectl get nodes
microk8s kubectl get pods -A
microk8s kubectl -n orders-demo logs deploy/order-worker --timestamps --tail=20
microk8s kubectl -n monitoring get pods -l app.kubernetes.io/name=alloy     # 1/1 Running
./scripts/k8s-error-test.sh start    # intentional error scenario: 60% of orders fail (stderr ERROR)
./scripts/k8s-error-test.sh stop
```

**Workload:** `order-worker` simulates a fulfilment worker. It writes JSON `INFO` events to **stdout**
(`order_picked`, `order_shipped`) and `WARN`/`ERROR` events to **stderr** (`warehouse_slow`,
`payment_failed`). It runs as non-root with a read-only root filesystem.

**How the logs reach Loki (networking):**

1. The kubelet and containerd write each container's stdout and stderr to `/var/log/pods/<ns>_<pod>_<uid>/<container>/*.log`
   in CRI format.
2. Alloy runs as a DaemonSet that mounts the node's `/var/log` read-only. `discovery.kubernetes` lists the pods,
   `discovery.relabel` adds the `namespace`, `pod`, `container`, `app`, `node` and `job` labels, and
   `loki.source.file` tails the files. `stage.cri` parses the format and adds `stream=stdout|stderr`.
   `stage.json` pulls out the `level`, and `cluster="microk8s"` is added.
3. Alloy runs with **`hostNetwork: true`**, so `127.0.0.1` inside the Alloy pod is the host's loopback.
   It pushes to `http://127.0.0.1:3100/loki/api/v1/push`, which is Loki's Compose port published on
   loopback only. This way Loki is never exposed on a LAN interface, and you don't need a NodePort,
   bridge IP or firewall rule.
   *Alternative:* without hostNetwork, publish Loki on `172.30.0.1:3100` and push to that address.
   This only works if the pod network can route to the docker bridge.

Grafana Explore → **Loki** example queries:

```logql
{namespace="orders-demo"}                                             # all workload logs
{namespace="orders-demo", pod=~"order-worker-.*", container="worker"} # filter by pod/container
{namespace="orders-demo", stream="stderr"} | json | level="ERROR"     # recent errors
sum by (pod) (count_over_time({namespace="orders-demo"} | json | level="ERROR" [1m]))
```

`./scripts/collect-artifact.sh k8s loki` saves the `kubectl logs` output next to the same ERROR lines
queried from Loki. The order IDs and timestamps match.

## Grafana dashboards

Grafana loads the data sources (Prometheus `uid=prometheus`, Loki `uid=loki`) and two dashboards
(folder *Observability*) automatically. The exported JSON is in [grafana/dashboards/](grafana/dashboards/).

* **Ubuntu Host & Order API – Metrics** (`obs-metrics`), 20 panels:
  * Host: CPU %, RAM %, root disk %, uptime, load, targets UP, CPU by mode, RAM %, disk % per mount,
    network throughput (rx/tx bit/s).
  * App: requests/s, 5xx error rate, p95 latency, orders created, order value, API up, requests/s by
    endpoint and status, error rate (5xx and non-2xx), p50/p95/p99 latency, orders created and failed per minute.
* **MicroK8s Pod Logs (Loki)** (`obs-k8s-logs`): variables for namespace, pod, container and a line filter.
  Panels: log volume by stream, errors per minute by pod, recent errors, and all logs.

To re-export after editing in the UI: **Dashboard → Share → Export → Save to file**, and replace the file in
`grafana/dashboards/`.

## Alerting and notification flow

All the details are in [alerting/configuration-notes.md](alerting/configuration-notes.md). In summary:

* SMTP is set through `GF_SMTP_*` variables from `.env`. No credentials are in the repository.
* Contact point `email-oncall` sends to `${ALERT_EMAIL_TO}`. The policy uses group_wait 30s, group_interval 2m
  and repeat 1h.
* **Order API scrape target down:** `sum(up{job="order-api"}) or vector(0) < 1` for **1m**, evaluated every 30s,
  severity critical.
* **Order API high 5xx error rate:** a 5xx ratio **> 5 %** for **2m**, severity warning.

```bash
docker compose stop order-api     # wait ~2 min: Pending, then Firing, then the email arrives
docker compose start order-api    # a resolved email follows
./scripts/collect-artifact.sh alerts
```

## End-to-end validation

1. **Normal:** run `./scripts/traffic-test.sh normal 60`. Requests/s is about 2, the error rate is 0, and p95 is about 0.1 s.
2. **High traffic:** run `./scripts/traffic-test.sh high 60`. Requests/s goes up to about 25, host CPU rises slightly,
   and the orders-created counter climbs faster.
3. **Controlled failure:** run `./scripts/traffic-test.sh failure 180`. The 5xx ratio is about 30%,
   `orders_failed_total{reason="simulated_error"}` grows, and the *high 5xx error rate* alert fires after about 2 minutes.
4. **Kubernetes failure:** run `./scripts/k8s-error-test.sh start`. Errors per minute by pod spike on the logs
   dashboard, and the `payment_failed` lines can be seen both in `kubectl logs` and in Loki.
5. **Outage:** run `docker compose stop order-api`. *API up* drops to 0, the target-down alert fires, and an
   email arrives. Then run `docker compose start order-api`.
6. Collect all text artifacts with `./scripts/collect-artifact.sh` and add the screenshots
   listed in [artifact/README.md](artifact/README.md).

**Limitations and possible improvements**

* Single-node, single-replica Loki and Prometheus with local storage, so there is no high availability.
  Production would use object storage (S3/MinIO) and remote-write or Mimir.
* The `hostNetwork` setup for Alloy relies on MicroK8s and Compose running on the same machine. A
  multi-node cluster would need Loki behind an authenticated, TLS-protected ingress.
* Alert rules are not yet tested automatically (for example with `promtool test rules`). Logs are not
  connected to traces (OpenTelemetry tracing plus Tempo would add request correlation).

## Cleanup and teardown

```bash
./scripts/cleanup.sh            # remove K8s resources and stop the stack (keeps the data volumes)
./scripts/cleanup.sh --purge    # also delete the volumes and the locally built image
# optional: sudo snap remove microk8s
```

## Packaging for delivery

```bash
cd .. && zip -r 30245_observability.zip order-service-observability \
  -x 'order-service-observability/.env' 'order-service-observability/**/.venv/*' 'order-service-observability/**/__pycache__/*' 'order-service-observability/.git/*'
unzip -l 30245_observability.zip | grep -c '\.env$'   # must print 0 (only .env.example is allowed)
```
