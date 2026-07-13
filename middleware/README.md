# Middleware — Workday protocol adapter

A small **FastAPI** service that exposes a clean, well-typed REST + OpenAPI view
over the cached Workday `workers` subset stored in **Azure Postgres**. Azure API
Management imports this service's `/openapi.json` and points its backend here;
APIM does the passive request/response caching in front of it.

The service is **read-only** and connects to Postgres with an **Entra
managed-identity access token — there is no database password**.

## Endpoints

| Method & path            | Description                                                        |
|--------------------------|-------------------------------------------------------------------|
| `GET /workers`           | List workers. Query: `limit` (default 50, max 500), `offset` (default 0). |
| `GET /workers/{employee_id}` | Single worker by `employee_id` (primary key); `404` if not found. |
| `GET /healthz`           | Liveness. Always `200`; does not touch the database.              |
| `GET /readyz`            | Readiness. `200` when Postgres is reachable and `workers` exists, else `503`. |
| `GET /openapi.json`      | Auto-generated OpenAPI (imported by APIM).                        |
| `GET /docs`              | Swagger UI.                                                       |

Worker JSON uses camelCase keys (`employeeID`, `cwid`, `email`,
`internalFullName`, `internalFirstName`, `internalLastName`,
`businessAddressSite`, `businessAddressSiteID`, `businessAddressCountry`,
`companyCode`, `companyName`, `costCenter`, `countryCode`, `active`,
`updatedAt`), mapped from the snake_case Postgres columns.

## Environment variables

Postgres connection (shared contract across components):

| Var               | Default    | Notes                                                        |
|-------------------|------------|--------------------------------------------------------------|
| `PGHOST`          | *(none)*   | Postgres Flexible Server host.                               |
| `PGPORT`          | `5432`     |                                                              |
| `PGDATABASE`      | `workday`  |                                                              |
| `PGUSER`          | *(none)*   | The managed identity's Postgres role name.                  |
| `PGSSLMODE`       | `require`  |                                                              |
| `AZURE_CLIENT_ID` | *(none)*   | User-assigned MI client id used by `DefaultAzureCredential`. |
| `PORT`            | `8000`     | HTTP port uvicorn binds (`0.0.0.0:$PORT`).                   |

The database password is never set: at connection time the app mints a fresh
Entra access token for scope
`https://ossrdbms-aad.database.windows.net/.default` and uses it as the
password. A `psycopg_pool` connection pool fetches a **fresh token for every new
physical connection**, and pooled connections are recycled (`max_lifetime`) so
tokens never go stale.

Optional pool tuning: `PGPOOL_MIN_SIZE` (1), `PGPOOL_MAX_SIZE` (10),
`PGPOOL_MAX_LIFETIME` (3600s), `PGPOOL_TIMEOUT` (10s).

## Run locally

```bash
cd middleware
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# Point at a reachable Postgres with Entra auth and an Azure identity available
# to DefaultAzureCredential (e.g. `az login` for local dev):
export PGHOST=myserver.postgres.database.azure.com
export PGUSER=my-managed-identity-name
# export AZURE_CLIENT_ID=<user-assigned-mi-client-id>   # in Azure

uvicorn app.main:app --host 0.0.0.0 --port 8000
# open http://127.0.0.1:8000/docs
```

## Test (offline — no cloud, no Postgres)

Tests monkeypatch the DB layer, so they need no database or Azure access.

```bash
cd middleware
python -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
pytest -q
```

## Container

```bash
docker build -t middleware:local middleware
docker run --rm -p 8000:8000 \
  -e PGHOST=... -e PGUSER=... -e AZURE_CLIENT_ID=... \
  middleware:local
```

The image runs as a non-root user and starts uvicorn bound to `0.0.0.0:$PORT`.
In Azure it is built and pushed to ACR by `azd` and deployed as an
external-ingress Container App.
