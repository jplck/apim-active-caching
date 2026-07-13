"""Workday protocol adapter (middleware).

A small FastAPI service that exposes a clean, well-typed REST + OpenAPI view over
the cached Workday ``workers`` subset stored in Azure Postgres. It is read-only
and authenticates to Postgres with an Entra managed-identity access token (no
password). See ``app.main`` for the API and ``app.db`` for data access.
"""

__version__ = "1.0.0"
