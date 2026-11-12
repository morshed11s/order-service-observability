# Order API. Use ?simulate=error or ?simulate=slow on POST /api/orders for testing.

from __future__ import annotations

import json
import logging
import os
import random
import sys
import time
import uuid

from flask import Flask, Response, g, jsonify, request
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    Counter,
    Gauge,
    Histogram,
    Info,
    generate_latest,
)
from werkzeug.exceptions import HTTPException

APP_VERSION = os.getenv("APP_VERSION", "1.0.0")
FAILURE_RATE = float(os.getenv("FAILURE_RATE", "0"))

# fixed list so the product label stays bounded
CATALOGUE = {"widget": 9.99, "gadget": 24.50, "gizmo": 4.25}
FAILURE_REASONS = ("validation", "unknown_product", "simulated_error", "internal_error")

REQUESTS = Counter(
    "http_requests_total",
    "Total HTTP requests handled by the Order API.",
    ["method", "endpoint", "status"],
)
LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency in seconds.",
    ["method", "endpoint"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0),
)
IN_PROGRESS = Gauge(
    "http_requests_in_progress",
    "HTTP requests currently being processed.",
)
ORDERS_CREATED = Counter(
    "orders_created_total",
    "Business event: orders successfully created.",
    ["product"],
)
ORDER_VALUE = Counter(
    "orders_value_usd_total",
    "Business event: cumulative value of created orders in US dollars.",
)
ORDERS_FAILED = Counter(
    "orders_failed_total",
    "Orders that could not be created, by failure reason.",
    ["reason"],
)
BUILD_INFO = Info("order_api_build", "Order API build information.")
BUILD_INFO.info({"version": APP_VERSION})

# create series up front so they show 0 instead of missing
for _product in CATALOGUE:
    ORDERS_CREATED.labels(product=_product)
for _reason in FAILURE_REASONS:
    ORDERS_FAILED.labels(reason=_reason)

logging.basicConfig(stream=sys.stdout, level=logging.INFO, format="%(message)s")
log = logging.getLogger("order-api")


def log_event(level: int, event: str, **fields) -> None:
    record = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "level": logging.getLevelName(level),
              "event": event, **fields}
    log.log(level, json.dumps(record))


app = Flask(__name__)


def _endpoint_label() -> str:
    # route template, not the raw path
    return request.url_rule.rule if request.url_rule is not None else "unmatched"


@app.before_request
def _start_timer() -> None:
    g.start = time.perf_counter()
    g.request_id = request.headers.get("X-Request-ID", uuid.uuid4().hex[:12])
    IN_PROGRESS.inc()


@app.after_request
def _record_metrics(response: Response) -> Response:
    IN_PROGRESS.dec()
    endpoint = _endpoint_label()
    if endpoint != "/metrics":  # don't count scrapes
        elapsed = time.perf_counter() - g.get("start", time.perf_counter())
        LATENCY.labels(request.method, endpoint).observe(elapsed)
        REQUESTS.labels(request.method, endpoint, str(response.status_code)).inc()
    response.headers["X-Request-ID"] = g.get("request_id", "")
    return response


@app.errorhandler(404)
def _not_found(_err):
    return jsonify(error="not found"), 404


@app.errorhandler(405)
def _not_allowed(_err):
    return jsonify(error="method not allowed"), 405


@app.errorhandler(Exception)
def _unhandled(err):
    if isinstance(err, HTTPException):
        return jsonify(error=err.description), err.code
    ORDERS_FAILED.labels(reason="internal_error").inc()
    log_event(logging.ERROR, "unhandled_exception", error=type(err).__name__,
              request_id=g.get("request_id"))
    return jsonify(error="internal server error"), 500


@app.get("/health")
def health():
    return jsonify(status="ok", version=APP_VERSION)


@app.post("/api/orders")
def create_order():
    simulate = request.args.get("simulate", "")
    payload = request.get_json(silent=True)

    if not isinstance(payload, dict):
        ORDERS_FAILED.labels(reason="validation").inc()
        log_event(logging.WARNING, "order_rejected", reason="validation",
                  detail="body must be a JSON object", request_id=g.request_id)
        return jsonify(error="request body must be a JSON object"), 400

    product = payload.get("product")
    quantity = payload.get("quantity", 1)
    if not isinstance(quantity, int) or isinstance(quantity, bool) or not 1 <= quantity <= 100:
        ORDERS_FAILED.labels(reason="validation").inc()
        log_event(logging.WARNING, "order_rejected", reason="validation",
                  detail="quantity must be an integer 1-100", request_id=g.request_id)
        return jsonify(error="quantity must be an integer between 1 and 100"), 400
    if product not in CATALOGUE:
        ORDERS_FAILED.labels(reason="unknown_product").inc()
        log_event(logging.WARNING, "order_rejected", reason="unknown_product",
                  request_id=g.request_id)
        return jsonify(error="unknown product", products=sorted(CATALOGUE)), 400

    time.sleep(random.uniform(0.02, 0.12))
    if simulate == "slow":
        time.sleep(random.uniform(0.8, 1.5))

    if simulate == "error" or (FAILURE_RATE > 0 and random.random() < FAILURE_RATE):
        ORDERS_FAILED.labels(reason="simulated_error").inc()
        log_event(logging.ERROR, "order_failed", reason="simulated_error",
                  product=product, request_id=g.request_id)
        return jsonify(error="order processing failed (simulated)"), 500

    order_id = uuid.uuid4().hex[:10]
    value = round(CATALOGUE[product] * quantity, 2)
    ORDERS_CREATED.labels(product=product).inc()
    ORDER_VALUE.inc(value)
    log_event(logging.INFO, "order_created", order_id=order_id, product=product,
              quantity=quantity, value_usd=value, request_id=g.request_id)
    return jsonify(order_id=order_id, product=product, quantity=quantity, value_usd=value), 201


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=int(os.getenv("PORT", "8000")))
