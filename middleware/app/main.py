"""FastAPI app for the Workday protocol adapter (middleware).

Exposes a clean, well-typed REST + OpenAPI view over the cached Workday
``workers`` subset. APIM imports ``/openapi.json`` and points its backend here.
"""

from __future__ import annotations

from contextlib import asynccontextmanager
from datetime import datetime
from typing import List, Optional

from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field

from app import db

API_TITLE = "Workday Protocol Adapter"
API_DESCRIPTION = (
    "Read-only REST facade over the cached Workday worker subset stored in "
    "Azure Postgres. Backed by a managed-identity (passwordless) database "
    "connection and imported into Azure API Management as the workers API."
)
API_VERSION = "1.0.0"


class Worker(BaseModel):
    """A single worker record.

    Python attributes are snake_case (matching the Postgres columns); the JSON
    representation and OpenAPI schema use the camelCase aliases below.
    """

    model_config = ConfigDict(populate_by_name=True)

    employee_id: str = Field(alias="employeeID", description="Workday Employee_ID (primary key).")
    cwid: Optional[str] = Field(default=None, alias="cwid", description="Custom ID (CWID).")
    email: Optional[str] = Field(default=None, alias="email", description="Work email address.")
    internal_full_name: Optional[str] = Field(default=None, alias="internalFullName")
    internal_first_name: Optional[str] = Field(default=None, alias="internalFirstName")
    internal_last_name: Optional[str] = Field(default=None, alias="internalLastName")
    business_address_site: Optional[str] = Field(default=None, alias="businessAddressSite")
    business_address_site_id: Optional[str] = Field(default=None, alias="businessAddressSiteID")
    business_address_country: Optional[str] = Field(
        default=None, alias="businessAddressCountry", description="ISO 3166-1 alpha-2 country code."
    )
    company_code: Optional[str] = Field(default=None, alias="companyCode")
    company_name: Optional[str] = Field(default=None, alias="companyName")
    cost_center: Optional[str] = Field(default=None, alias="costCenter")
    country_code: Optional[str] = Field(default=None, alias="countryCode")
    active: bool = Field(default=True, alias="active", description="Present in the latest sync.")
    updated_at: Optional[datetime] = Field(
        default=None, alias="updatedAt", description="Last time this row was upserted."
    )


class Health(BaseModel):
    """Liveness/readiness response body."""

    status: str = Field(examples=["ok"])
    detail: Optional[str] = Field(default=None, description="Optional human-readable reason.")


@asynccontextmanager
async def lifespan(_: FastAPI):
    # Nothing to warm up eagerly — the pool is created lazily on first use so the
    # app boots even if Postgres is briefly unavailable.
    yield
    db.close_pool()


app = FastAPI(
    title=API_TITLE,
    description=API_DESCRIPTION,
    version=API_VERSION,
    lifespan=lifespan,
)


@app.get(
    "/workers",
    response_model=List[Worker],
    tags=["workers"],
    summary="List workers",
    description="Return a page of workers. Use `limit` (default 50, max 500) and `offset` (default 0).",
)
def list_workers(
    limit: int = Query(50, ge=1, le=500, description="Max rows to return (capped at 500)."),
    offset: int = Query(0, ge=0, description="Number of rows to skip."),
) -> List[Worker]:
    try:
        rows = db.list_workers(limit=limit, offset=offset)
    except db.SchemaNotReady:
        # Table not bootstrapped yet — behave as an empty dataset.
        return []
    except db.DatabaseUnavailable:
        raise HTTPException(status_code=503, detail="database unavailable")
    return [Worker.model_validate(row) for row in rows]


@app.get(
    "/workers/{employee_id}",
    response_model=Worker,
    tags=["workers"],
    summary="Get a worker by employee ID",
    responses={404: {"description": "Worker not found"}},
)
def get_worker(employee_id: str) -> Worker:
    try:
        row = db.get_worker(employee_id)
    except db.SchemaNotReady:
        row = None
    except db.DatabaseUnavailable:
        raise HTTPException(status_code=503, detail="database unavailable")
    if row is None:
        raise HTTPException(status_code=404, detail="worker not found")
    return Worker.model_validate(row)


@app.get(
    "/healthz",
    response_model=Health,
    response_model_exclude_none=True,
    tags=["health"],
    summary="Liveness probe",
    description="Always returns 200 while the process is up; does not touch the database.",
)
def healthz() -> Health:
    return Health(status="ok")


@app.get(
    "/readyz",
    response_model=Health,
    response_model_exclude_none=True,
    tags=["health"],
    summary="Readiness probe",
    description="Returns 200 when Postgres is reachable and the workers table exists, else 503.",
    responses={503: {"model": Health, "description": "Not ready"}},
)
def readyz():
    try:
        db.check_ready()
    except db.SchemaNotReady:
        return JSONResponse(
            status_code=503,
            content={"status": "not ready", "detail": "schema not initialized"},
        )
    except db.DatabaseUnavailable:
        return JSONResponse(
            status_code=503,
            content={"status": "not ready", "detail": "database unavailable"},
        )
    return Health(status="ready")
