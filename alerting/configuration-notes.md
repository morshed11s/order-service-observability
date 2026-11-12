# Email alerting – configuration notes

Everything is provisioned from files in [`grafana/provisioning/alerting/`](../grafana/provisioning/alerting/).
Grafana loads them at startup, so no alerting setup is done by hand in the UI.

## 1. SMTP (secrets stay out of source control)

Grafana reads its SMTP settings from environment variables. `compose.yaml` maps them from `.env`,
which is git-ignored and never included in the ZIP:

| Grafana setting          | Comes from (`.env`)     | Example                          |
|--------------------------|-------------------------|----------------------------------|
| `GF_SMTP_ENABLED`        | fixed `true`            |                                  |
| `GF_SMTP_HOST`           | `SMTP_HOST`             | `smtp.gmail.com:587`             |
| `GF_SMTP_USER`           | `SMTP_USER`             | `alerts@example.com`             |
| `GF_SMTP_PASSWORD`       | `SMTP_PASSWORD`         | an app password, never the real account password |
| `GF_SMTP_FROM_ADDRESS`   | `SMTP_FROM_ADDRESS`     | `alerts@example.com`             |
| `GF_SMTP_STARTTLS_POLICY`| `SMTP_STARTTLS_POLICY`  | `MandatoryStartTLS`              |

Compose stops with an error if a required value (`SMTP_HOST`, `SMTP_FROM_ADDRESS`,
`ALERT_EMAIL_TO`, `GF_ADMIN_PASSWORD`) is missing. The Grafana API and UI never show the SMTP password.

**Test inbox options:** a Gmail account with an
[App Password](https://support.google.com/accounts/answer/185833) (`smtp.gmail.com:587`), or a free
[Mailtrap](https://mailtrap.io) sandbox inbox (`sandbox.smtp.mailtrap.io:2525`).

## 2. Contact point, `email-oncall`

`contact-points.yaml` creates one email contact point. Its recipient is `${ALERT_EMAIL_TO}`, which Grafana
fills in from the environment when it loads the file. `singleEmail: true` sends one mail to all recipients,
and resolved notifications are turned on.

To check SMTP on its own: open **Alerting → Contact points → email-oncall → Test** in Grafana. The test mail
should arrive within seconds.

## 3. Notification policy

`policies.yaml` sends every alert to `email-oncall`, grouped by folder and alert name:

| Setting           | Value | Meaning                                                |
|-------------------|-------|--------------------------------------------------------|
| `group_wait`      | 30s   | wait before the first notification for a new group     |
| `group_interval`  | 2m    | wait before notifying about new alerts in the group    |
| `repeat_interval` | 1h    | re-send while still firing                             |

## 4. Alert rules (folder `Observability`, group `order-api`, evaluated every 30s)

### a) Order API scrape target down (critical), the one to demonstrate

| Item | Value |
|------|-------|
| Query | `sum(up{job="order-api"}) or vector(0)` |
| Condition | last value **< 1** |
| Pending period (`for`) | **1m** |
| No data | treated as Alerting |
| Recipient | `email-oncall` → `ALERT_EMAIL_TO` |
| Operator action | `docker compose ps order-api`, then `docker compose logs --tail=100 order-api`, then `curl http://127.0.0.1:8000/health`, then restart with `docker compose up -d order-api` and look into the root cause (crash, OOM, bad deploy). |

Why it matters: when the target is down, customers cannot place orders and **all application metrics stop**.
That is also why `or vector(0)` is used: the alert still works if the series disappears.

### b) Order API high 5xx error rate (warning)

| Item | Value |
|------|-------|
| Query | `(sum(rate(http_requests_total{job="order-api",status=~"5.."}[2m])) or vector(0)) / clamp_min(sum(rate(http_requests_total{job="order-api"}[2m])), 0.001)` |
| Condition | last value **> 0.05** (5% of requests) |
| Pending period | **2m** |
| Operator action | Check the *Error rate* and *Business events* panels and look for `"level": "ERROR"` in the app logs. Roll back the last change, or reset `APP_FAILURE_RATE=0` if a test was left running. |

Only 5xx (server-side) errors count. 4xx validation errors are the client's fault and should not page anyone.

## 5. Controlled test (safe, fully reversible)

```bash
# A) target down: about 1.5 to 2.5 minutes until the email arrives
docker compose stop order-api
#   30s evaluation, then 1m pending, then Firing, then 30s group_wait, then email
#   Watch: Grafana > Alerting > Alert rules > "Order API scrape target down" (Normal > Pending > Firing)
docker compose start order-api        # a "Resolved" email follows

# B) error rate: about 3 to 4 minutes
./scripts/traffic-test.sh failure 240  # ~30% of requests return HTTP 500
```

Expected email subject: `[FIRING:1] Order API scrape target down Observability (...)`.
For the artifact screenshot, show the subject, the timestamp, the alert labels and the summary. Hide the
recipient address and any other personal details.

Alert history is under **Alerting → Alert rules → (rule) → History**. You can also list it from the command line:
`./scripts/collect-artifact.sh alerts`.
