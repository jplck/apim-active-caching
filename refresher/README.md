# Refresher — Workday → Postgres ETL (Container Apps Job)

Python ETL job that pulls workers from Workday over SOAP (`Get_Workers`),
transforms each `wd:Worker` into a normalized row, and UPSERTs into Azure
Postgres. It supports **full** and **delta** (watermark) syncs and advances the
watermark atomically with the UPSERT so a failed run never loses ground
(at-least-once + idempotent UPSERT). See `plan.md` §2.1, §5, §5.1.

* SOAP POST via `httpx`, XML build/parse via `lxml`.
* Postgres via `psycopg` (v3) using an **Entra managed-identity token** as the
  password — **no DB password** anywhere.
* Transform (`app.soap.parse_workers`) is a pure function, tested offline.

## Layout

```
refresher/
  app/
    soap.py     # build Get_Workers_Request envelope; parse response -> worker dicts (§5 XPaths)
    db.py       # Entra-token psycopg connection, schema bootstrap, UPSERT+watermark txn
    refresh.py  # entrypoint: decide mode, read watermark, page loop, write txn
  tests/        # offline transform + delta-envelope tests (+ fixtures)
  requirements.txt / requirements-dev.txt
  Dockerfile
```

## Environment variables

Workday (ISU credentials injected from Key Vault at container startup):

| Var | Default | Notes |
|-----|---------|-------|
| `WORKDAY_USERNAME` | — (required) | ISU user, e.g. `isu_integration@tenant` |
| `WORKDAY_PASSWORD` | — (required) | ISU password |
| `WORKDAY_SOAP_URL` | — (required) | Human_Resources WWS endpoint (POC: in-APIM SOAP mock) |
| `WORKDAY_API_VERSION` | `v46.2` | request `version` attribute |
| `SYNC_MODE` | `auto` | `auto` \| `full` \| `delta` |
| `WATERMARK_LOOKBACK_SECONDS` | `60` | subtracted from `Updated_From` for clock-skew safety |
| `PAGE_COUNT` | `100` | `Response_Filter/Count` page size |
| `EFFECTIVE_FLOOR` | `1900-01-01` | delta `Effective_From` |
| `EFFECTIVE_LOOKAHEAD_DAYS` | `0` | delta `Effective_Through` = run start + N days |

Postgres (Entra managed-identity auth only — shared connection contract):

| Var | Default | Notes |
|-----|---------|-------|
| `PGHOST` | — (required) | Flexible Server host |
| `PGPORT` | `5432` | |
| `PGDATABASE` | `workday` | |
| `PGUSER` | — (required) | MI Postgres role name |
| `PGSSLMODE` | `require` | |
| `AZURE_CLIENT_ID` | — | user-assigned MI client id (token audience `ossrdbms`) |

## Sync modes

* **full** — empty `Request_Criteria`; pages through all workers. First run
  (no watermark) or `SYNC_MODE=full`. Re-anchors the watermark to run start.
* **delta** — adds
  `Request_Criteria/Transaction_Log_Criteria/Transaction_Date_Range_Data/Effective_And_Updated_DateTime_Data`
  with **both** pairs: `Updated_From` (watermark − lookback) / `Updated_Through`
  (run start) **and** `Effective_From` (`EFFECTIVE_FLOOR`) / `Effective_Through`
  (run start + `EFFECTIVE_LOOKAHEAD_DAYS`). Workday requires both halves of each
  pair, so all four bounds are always sent together.
* **auto** — delta when a watermark exists, otherwise full.

The watermark (`sync_state.last_updated_through`) and the UPSERTs commit in one
transaction; on failure the whole run rolls back.

## Run tests (offline — no cloud, no network)

```bash
cd refresher
python -m venv .venv && . .venv/bin/activate
pip install -r requirements-dev.txt
python -c "import app.refresh, app.soap, app.db"   # import smoke check
pytest -q
```

`tests/test_transform.py` parses the fixtures and asserts the §5 field
mappings; `tests/test_delta_envelope.py` asserts a delta envelope carries both
date pairs and the `Response_Group` flags.

> **Fixture note:** `tests/fixtures/workers-soap.xml` is a copy of the POC SOAP
> mock, which uses a *simplified* shape (no WORK-usage email, no
> `Preferred_Name_Data`, no CWID / primary-job / org structure). Under the exact
> §5 XPaths only `employeeID` maps from it. `tests/fixtures/workers-canonical-soap.xml`
> is a §5-shaped response used to assert the full field mapping.

## Build

```bash
docker build -t refresher .
```

Runs as non-root; `CMD` is `python -m app.refresh`.
