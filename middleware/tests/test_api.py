"""Offline API tests.

These run with **no real Postgres and no cloud** — the ``app.db`` data-access
layer is monkeypatched. They cover the snake_case -> camelCase mapping, the
single-worker 404, the liveness probe, readiness on DB failure, graceful
behaviour when the schema is missing, and that the OpenAPI document is served.
"""

from datetime import datetime, timezone

from fastapi.testclient import TestClient

from app import db
from app.main import app

client = TestClient(app)

# A DB row as returned by app.db (snake_case keys, tz-aware datetime).
SAMPLE_ROW = {
    "employee_id": "21001",
    "cwid": "CWID-001",
    "email": "lmcneil@contoso.com",
    "internal_full_name": "Logan McNeil",
    "internal_first_name": "Logan",
    "internal_last_name": "McNeil",
    "business_address_site": "San Francisco",
    "business_address_site_id": "LOC-SF",
    "business_address_country": "US",
    "company_code": "CMP-001",
    "company_name": "Contoso Ltd",
    "cost_center": "CC-100",
    "country_code": "US",
    "active": True,
    "updated_at": datetime(2024, 1, 2, 3, 4, 5, tzinfo=timezone.utc),
}

CAMEL_KEYS = [
    "employeeID",
    "cwid",
    "email",
    "internalFullName",
    "internalFirstName",
    "internalLastName",
    "businessAddressSite",
    "businessAddressSiteID",
    "businessAddressCountry",
    "companyCode",
    "companyName",
    "costCenter",
    "countryCode",
    "active",
    "updatedAt",
]


def test_list_workers_maps_snake_to_camel(monkeypatch):
    def fake_list(limit=50, offset=0):
        return [SAMPLE_ROW]

    monkeypatch.setattr(db, "list_workers", fake_list)

    resp = client.get("/workers")
    assert resp.status_code == 200
    body = resp.json()
    assert isinstance(body, list) and len(body) == 1

    worker = body[0]
    # All camelCase JSON keys present...
    for key in CAMEL_KEYS:
        assert key in worker, f"missing key {key}"
    # ...and no snake_case keys leaked through.
    assert "employee_id" not in worker
    assert "internal_full_name" not in worker
    assert "business_address_site_id" not in worker

    assert worker["employeeID"] == "21001"
    assert worker["businessAddressSiteID"] == "LOC-SF"
    assert worker["internalFullName"] == "Logan McNeil"
    assert worker["updatedAt"].startswith("2024-01-02")


def test_list_workers_passes_limit_and_offset(monkeypatch):
    captured = {}

    def fake_list(limit=50, offset=0):
        captured["limit"] = limit
        captured["offset"] = offset
        return []

    monkeypatch.setattr(db, "list_workers", fake_list)

    resp = client.get("/workers?limit=10&offset=5")
    assert resp.status_code == 200
    assert captured == {"limit": 10, "offset": 5}


def test_list_workers_rejects_limit_over_cap(monkeypatch):
    monkeypatch.setattr(db, "list_workers", lambda limit=50, offset=0: [])
    resp = client.get("/workers?limit=1000")
    assert resp.status_code == 422


def test_list_workers_empty_when_schema_not_ready(monkeypatch):
    def fake_list(limit=50, offset=0):
        raise db.SchemaNotReady("relation \"workers\" does not exist")

    monkeypatch.setattr(db, "list_workers", fake_list)
    resp = client.get("/workers")
    assert resp.status_code == 200
    assert resp.json() == []


def test_list_workers_503_when_db_unavailable(monkeypatch):
    def fake_list(limit=50, offset=0):
        raise db.DatabaseUnavailable("connection refused")

    monkeypatch.setattr(db, "list_workers", fake_list)
    resp = client.get("/workers")
    assert resp.status_code == 503


def test_get_worker_found(monkeypatch):
    monkeypatch.setattr(
        db, "get_worker", lambda employee_id: SAMPLE_ROW if employee_id == "21001" else None
    )
    resp = client.get("/workers/21001")
    assert resp.status_code == 200
    assert resp.json()["employeeID"] == "21001"


def test_get_worker_404(monkeypatch):
    monkeypatch.setattr(db, "get_worker", lambda employee_id: None)
    resp = client.get("/workers/does-not-exist")
    assert resp.status_code == 404
    assert resp.json()["detail"] == "worker not found"


def test_healthz_ok():
    resp = client.get("/healthz")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


def test_readyz_ready(monkeypatch):
    monkeypatch.setattr(db, "check_ready", lambda: None)
    resp = client.get("/readyz")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ready"


def test_readyz_503_when_db_unavailable(monkeypatch):
    def boom():
        raise db.DatabaseUnavailable("down")

    monkeypatch.setattr(db, "check_ready", boom)
    resp = client.get("/readyz")
    assert resp.status_code == 503
    assert resp.json()["status"] == "not ready"


def test_openapi_served():
    resp = client.get("/openapi.json")
    assert resp.status_code == 200
    spec = resp.json()
    assert spec["info"]["title"]
    assert spec["info"]["version"]
    assert "/workers" in spec["paths"]
    assert "/workers/{employee_id}" in spec["paths"]
    # Response schema uses the camelCase alias property names.
    worker_schema = spec["components"]["schemas"]["Worker"]
    assert "employeeID" in worker_schema["properties"]
    assert "businessAddressSiteID" in worker_schema["properties"]


def test_docs_served():
    resp = client.get("/docs")
    assert resp.status_code == 200
