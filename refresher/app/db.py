"""Postgres access for the refresher.

Auth is **Entra managed identity ONLY** (no DB password): an Entra access token
for the ``ossrdbms`` scope is fetched at connect time via ``azure-identity`` and
passed to ``psycopg`` (v3) as the connection password. Connection parameters
follow the shared contract in ``plan.md`` §2.1 / §4.
"""
from __future__ import annotations

import os
from datetime import datetime
from typing import Iterable, List, Optional

import psycopg
from azure.identity import DefaultAzureCredential

from app.soap import COLUMNS, FIELD_XPATHS

# Entra token scope for Azure Database for PostgreSQL Flexible Server.
AAD_SCOPE = "https://ossrdbms-aad.database.windows.net/.default"

WORKERS_DDL = """
CREATE TABLE IF NOT EXISTS workers (
  employee_id             text PRIMARY KEY,
  cwid                    text,
  email                   text,
  internal_full_name      text,
  internal_first_name     text,
  internal_last_name      text,
  business_address_site   text,
  business_address_site_id text,
  business_address_country text,
  company_code            text,
  company_name            text,
  cost_center             text,
  country_code            text,
  active                  boolean NOT NULL DEFAULT true,
  updated_at              timestamptz NOT NULL DEFAULT now()
)
"""

SYNC_STATE_DDL = """
CREATE TABLE IF NOT EXISTS sync_state (
  entity                text PRIMARY KEY DEFAULT 'workers',
  last_updated_through  timestamptz,
  last_sync_mode        text,
  last_run_at           timestamptz,
  rows_upserted         integer
)
"""


def _fetch_token(client_id: Optional[str]) -> str:
    """Fetch a short-lived Entra access token for the Postgres MI login."""
    if client_id:
        credential = DefaultAzureCredential(managed_identity_client_id=client_id)
    else:
        credential = DefaultAzureCredential()
    return credential.get_token(AAD_SCOPE).token


def connect() -> psycopg.Connection:
    """Open a psycopg (v3) connection using an Entra MI token as the password.

    Reads the shared connection contract from the environment: ``PGHOST``,
    ``PGPORT`` (5432), ``PGDATABASE`` (``workday``), ``PGUSER`` (MI role name),
    ``PGSSLMODE`` (``require``), ``AZURE_CLIENT_ID`` (user-assigned MI).
    """
    client_id = os.environ.get("AZURE_CLIENT_ID")
    token = _fetch_token(client_id)
    return psycopg.connect(
        host=os.environ["PGHOST"],
        port=os.environ.get("PGPORT", "5432"),
        dbname=os.environ.get("PGDATABASE", "workday"),
        user=os.environ["PGUSER"],
        password=token,
        sslmode=os.environ.get("PGSSLMODE", "require"),
        autocommit=False,
    )


def bootstrap_schema(conn: psycopg.Connection) -> None:
    """Create the ``workers`` and ``sync_state`` tables if they do not exist."""
    with conn.cursor() as cur:
        cur.execute(WORKERS_DDL)
        cur.execute(SYNC_STATE_DDL)
    conn.commit()


def read_watermark(
    conn: psycopg.Connection, entity: str = "workers"
) -> Optional[datetime]:
    """Return ``sync_state.last_updated_through`` (the watermark), or ``None``."""
    with conn.cursor() as cur:
        cur.execute(
            "SELECT last_updated_through FROM sync_state WHERE entity = %s",
            (entity,),
        )
        row = cur.fetchone()
    return row[0] if row else None


def _build_upsert_sql() -> str:
    all_cols = list(COLUMNS) + ["active"]
    insert_cols = ", ".join(all_cols)
    placeholders = ", ".join(["%s"] * len(all_cols))
    updates = ", ".join(
        f"{col} = EXCLUDED.{col}" for col in all_cols if col != "employee_id"
    )
    return (
        f"INSERT INTO workers ({insert_cols}, updated_at) "
        f"VALUES ({placeholders}, now()) "
        f"ON CONFLICT (employee_id) DO UPDATE SET {updates}, updated_at = now()"
    )


UPSERT_SQL = _build_upsert_sql()

ADVANCE_SQL = (
    "INSERT INTO sync_state "
    "(entity, last_updated_through, last_sync_mode, last_run_at, rows_upserted) "
    "VALUES (%s, %s, %s, now(), %s) "
    "ON CONFLICT (entity) DO UPDATE SET "
    "last_updated_through = EXCLUDED.last_updated_through, "
    "last_sync_mode = EXCLUDED.last_sync_mode, "
    "last_run_at = EXCLUDED.last_run_at, "
    "rows_upserted = EXCLUDED.rows_upserted"
)


def upsert_workers_and_advance(
    conn: psycopg.Connection,
    workers: Iterable[dict],
    *,
    updated_through: datetime,
    sync_mode: str,
    entity: str = "workers",
) -> int:
    """UPSERT workers and advance the watermark in a **single** transaction.

    On any error the whole transaction rolls back, so the watermark never
    advances past a failed run (at-least-once; the UPSERT makes replays
    idempotent). Returns the number of rows upserted.
    """
    json_keys = [json_key for json_key, _col, _xpath in FIELD_XPATHS]
    rows = 0
    try:
        with conn.cursor() as cur:
            for worker in workers:
                values = [worker.get(key) for key in json_keys]
                values.append(worker.get("active", True))
                cur.execute(UPSERT_SQL, values)
                rows += 1
            cur.execute(ADVANCE_SQL, (entity, updated_through, sync_mode, rows))
        conn.commit()
        return rows
    except Exception:
        conn.rollback()
        raise
