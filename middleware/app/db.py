"""Postgres access for the middleware.

Connectivity contract (shared across components — do not deviate):

* Connection is configured from the standard ``PG*`` environment variables.
* Authentication is **Entra managed identity ONLY** — there is no database
  password. At connection time we mint a short-lived Entra access token for the
  scope ``https://ossrdbms-aad.database.windows.net/.default`` and hand it to
  libpq as the password.
* Access is via a :class:`psycopg_pool.ConnectionPool`. Because the token
  rotates, a custom connection class fetches a **fresh token every time a new
  physical connection is opened** by the pool, and ``max_lifetime`` recycles
  pooled connections periodically so tokens never go stale. We never cache a
  token for the lifetime of the process; ``DefaultAzureCredential`` owns caching
  and refresh internally.

The middleware only ever issues ``SELECT`` statements.
"""

from __future__ import annotations

import os
from typing import Any, Dict, List, Optional

import psycopg
from psycopg.conninfo import make_conninfo
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool, PoolTimeout
from azure.identity import DefaultAzureCredential

# Entra token scope for Azure Database for PostgreSQL.
PG_AAD_SCOPE = "https://ossrdbms-aad.database.windows.net/.default"

# Columns selected from ``workers`` (snake_case), in a stable order. The
# snake_case -> camelCase JSON mapping lives in the Pydantic models in app.main.
WORKER_COLUMNS: List[str] = [
    "employee_id",
    "cwid",
    "email",
    "internal_full_name",
    "internal_first_name",
    "internal_last_name",
    "business_address_site",
    "business_address_site_id",
    "business_address_country",
    "company_code",
    "company_name",
    "cost_center",
    "country_code",
    "active",
    "updated_at",
]
_SELECT_COLUMNS = ", ".join(WORKER_COLUMNS)


class DatabaseUnavailable(Exception):
    """The database could not be reached (connect/pool timeout, network, etc.)."""


class SchemaNotReady(Exception):
    """The ``workers`` table does not exist yet (refresher hasn't bootstrapped)."""


# --- Entra token acquisition ------------------------------------------------

_credential: Optional[DefaultAzureCredential] = None


def _get_credential() -> DefaultAzureCredential:
    """Return a process-wide credential.

    ``DefaultAzureCredential`` honors ``AZURE_CLIENT_ID`` to select the
    user-assigned managed identity. The credential object is reused (it manages
    token caching/refresh internally); the *token* itself is never cached by us.
    """
    global _credential
    if _credential is None:
        _credential = DefaultAzureCredential()
    return _credential


def _get_access_token() -> str:
    """Mint a fresh Entra access token to use as the Postgres password."""
    return _get_credential().get_token(PG_AAD_SCOPE).token


class _TokenConnection(psycopg.Connection):
    """Connection that injects a fresh Entra token as the password on connect.

    The pool calls ``connection_class.connect(...)`` for every new physical
    connection, so each new connection authenticates with a freshly minted
    token.
    """

    @classmethod
    def connect(cls, conninfo: str = "", **kwargs: Any) -> "psycopg.Connection":
        kwargs.setdefault("password", _get_access_token())
        return super().connect(conninfo, **kwargs)


# --- Connection pool --------------------------------------------------------

_pool: Optional[ConnectionPool] = None


def _build_conninfo() -> str:
    return make_conninfo(
        host=os.environ.get("PGHOST", ""),
        port=os.environ.get("PGPORT", "5432"),
        dbname=os.environ.get("PGDATABASE", "workday"),
        user=os.environ.get("PGUSER", ""),
        sslmode=os.environ.get("PGSSLMODE", "require"),
    )


def _create_pool() -> ConnectionPool:
    pool = ConnectionPool(
        _build_conninfo(),
        connection_class=_TokenConnection,
        kwargs={"autocommit": True},  # read-only SELECTs, no long transactions
        min_size=int(os.environ.get("PGPOOL_MIN_SIZE", "1")),
        max_size=int(os.environ.get("PGPOOL_MAX_SIZE", "10")),
        # Recycle connections so a fresh token is minted well within its lifetime.
        max_lifetime=float(os.environ.get("PGPOOL_MAX_LIFETIME", "3600")),
        timeout=float(os.environ.get("PGPOOL_TIMEOUT", "10")),
        check=ConnectionPool.check_connection,
        name="workers-pool",
        open=False,
    )
    # Open without blocking: if the DB is briefly unavailable the pool fills in
    # the background and readiness reports "not ready" until it recovers.
    pool.open(wait=False)
    return pool


def get_pool() -> ConnectionPool:
    """Return the lazily-created connection pool."""
    global _pool
    if _pool is None:
        _pool = _create_pool()
    return _pool


def close_pool() -> None:
    """Close the pool if it was created (called on app shutdown)."""
    global _pool
    if _pool is not None:
        _pool.close()
        _pool = None


# --- Query helpers ----------------------------------------------------------


def list_workers(limit: int = 50, offset: int = 0) -> List[Dict[str, Any]]:
    """Return a page of workers ordered by employee_id.

    Raises :class:`SchemaNotReady` if the table is missing and
    :class:`DatabaseUnavailable` if the database can't be reached.
    """
    sql = (
        f"SELECT {_SELECT_COLUMNS} FROM workers "
        "ORDER BY employee_id LIMIT %s OFFSET %s"
    )
    try:
        with get_pool().connection() as conn:
            with conn.cursor(row_factory=dict_row) as cur:
                cur.execute(sql, (limit, offset))
                return cur.fetchall()
    except psycopg.errors.UndefinedTable as exc:
        raise SchemaNotReady(str(exc)) from exc
    except (psycopg.OperationalError, PoolTimeout) as exc:
        raise DatabaseUnavailable(str(exc)) from exc


def get_worker(employee_id: str) -> Optional[Dict[str, Any]]:
    """Return a single worker by primary key, or ``None`` if not found.

    Raises :class:`SchemaNotReady` / :class:`DatabaseUnavailable` on DB issues.
    """
    sql = f"SELECT {_SELECT_COLUMNS} FROM workers WHERE employee_id = %s"
    try:
        with get_pool().connection() as conn:
            with conn.cursor(row_factory=dict_row) as cur:
                cur.execute(sql, (employee_id,))
                return cur.fetchone()
    except psycopg.errors.UndefinedTable as exc:
        raise SchemaNotReady(str(exc)) from exc
    except (psycopg.OperationalError, PoolTimeout) as exc:
        raise DatabaseUnavailable(str(exc)) from exc


def check_ready() -> None:
    """Readiness probe: verify DB connectivity and that ``workers`` exists.

    Returns ``None`` when ready; otherwise raises :class:`SchemaNotReady` or
    :class:`DatabaseUnavailable`.
    """
    try:
        with get_pool().connection() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1 FROM workers LIMIT 1")
                cur.fetchone()
    except psycopg.errors.UndefinedTable as exc:
        raise SchemaNotReady(str(exc)) from exc
    except (psycopg.OperationalError, PoolTimeout) as exc:
        raise DatabaseUnavailable(str(exc)) from exc
