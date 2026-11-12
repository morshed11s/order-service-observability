import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app import app  # noqa: E402
from prometheus_client import REGISTRY  # noqa: E402


@pytest.fixture()
def client():
    app.config["TESTING"] = True
    with app.test_client() as c:
        yield c


def sample(name, **labels):
    value = REGISTRY.get_sample_value(name, labels)
    return value or 0.0


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.get_json()["status"] == "ok"


def test_create_order_increments_business_counter(client):
    before = sample("orders_created_total", product="widget")
    r = client.post("/api/orders", json={"product": "widget", "quantity": 2})
    assert r.status_code == 201
    assert r.get_json()["value_usd"] == 19.98
    assert sample("orders_created_total", product="widget") == before + 1
    assert sample("http_requests_total", method="POST", endpoint="/api/orders", status="201") >= 1


def test_validation_failure(client):
    before = sample("orders_failed_total", reason="validation")
    r = client.post("/api/orders", json={"product": "widget", "quantity": 0})
    assert r.status_code == 400
    assert sample("orders_failed_total", reason="validation") == before + 1


def test_unknown_product(client):
    r = client.post("/api/orders", json={"product": "spaceship"})
    assert r.status_code == 400


def test_non_json_body(client):
    r = client.post("/api/orders", data="not json", content_type="text/plain")
    assert r.status_code == 400


def test_simulated_error_counts_as_5xx(client):
    before = sample("http_requests_total", method="POST", endpoint="/api/orders", status="500")
    r = client.post("/api/orders?simulate=error", json={"product": "gizmo"})
    assert r.status_code == 500
    assert sample("http_requests_total", method="POST", endpoint="/api/orders", status="500") == before + 1


def test_latency_histogram_observed(client):
    before = sample("http_request_duration_seconds_count", method="GET", endpoint="/health")
    client.get("/health")
    assert sample("http_request_duration_seconds_count", method="GET", endpoint="/health") == before + 1


def test_unmatched_paths_use_bounded_label(client):
    client.get("/random/path/12345")
    client.get("/another/random/path")
    assert sample("http_requests_total", method="GET", endpoint="unmatched", status="404") >= 2


def test_metrics_endpoint_exposes_custom_metrics_and_is_not_counted(client):
    r = client.get("/metrics")
    body = r.get_data(as_text=True)
    assert r.status_code == 200
    for name in ("http_requests_total", "http_request_duration_seconds_bucket",
                 "orders_created_total", "orders_failed_total", "orders_value_usd_total"):
        assert name in body
    assert 'endpoint="/metrics"' not in body
