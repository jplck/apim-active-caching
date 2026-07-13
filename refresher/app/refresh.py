"""Refresher entrypoint (Container Apps Job).

On each cron run:
  1. Read Workday ISU creds and config from the environment (already injected
     from Key Vault at container startup -- no Key Vault SDK call here).
  2. Connect to Postgres (Entra MI token), bootstrap schema, read the watermark.
  3. Decide sync mode (``auto`` -> full when no watermark else delta).
  4. Page through ``Get_Workers`` over SOAP, transform each worker.
  5. UPSERT rows and advance the watermark in one transaction.

Run: ``python -m app.refresh``.
"""
from __future__ import annotations

import os
import sys
from datetime import datetime, timezone

import httpx

from app import db, soap


def _int_env(name: str, default: int) -> int:
    value = os.environ.get(name)
    if value is None or value == "":
        return default
    return int(value)


def decide_mode(sync_mode: str, watermark) -> str:
    """Resolve the effective sync mode.

    ``full`` forces a full sync; ``delta`` requires a watermark (falls back to
    ``full`` when none exists); ``auto`` is delta when a watermark exists.
    """
    sync_mode = (sync_mode or "auto").lower()
    if sync_mode == "full":
        return "full"
    if watermark is None:
        return "full"
    if sync_mode == "delta":
        return "delta"
    return "delta"  # auto with a watermark


def _post_soap(client: httpx.Client, url: str, body: bytes) -> bytes:
    headers = {"Content-Type": "text/xml; charset=utf-8", "SOAPAction": ""}
    response = client.post(url, content=body, headers=headers)
    response.raise_for_status()
    return response.content


def _fetch_all_workers(
    url: str,
    username: str,
    password: str,
    *,
    mode: str,
    watermark,
    now: datetime,
    count: int,
    lookback_seconds: int,
    effective_floor: str,
    effective_lookahead_days: int,
    api_version: str,
) -> list:
    workers: list = []
    page = 1
    with httpx.Client(timeout=60.0) as client:
        while True:
            envelope = soap.build_get_workers_request(
                username,
                password,
                page=page,
                count=count,
                mode=mode,
                watermark=watermark,
                now=now,
                lookback_seconds=lookback_seconds,
                effective_floor=effective_floor,
                effective_lookahead_days=effective_lookahead_days,
                api_version=api_version,
            )
            content = _post_soap(client, url, soap.serialize(envelope))
            page_workers = soap.parse_workers(content)
            results = soap.parse_response_results(content)
            workers.extend(page_workers)
            total_pages = results["total_pages"] or 1
            print(
                f"[refresher] page {page}/{total_pages}: "
                f"{len(page_workers)} workers"
            )
            if page >= total_pages:
                break
            page += 1
    return workers


def run() -> None:
    username = os.environ["WORKDAY_USERNAME"]
    password = os.environ["WORKDAY_PASSWORD"]
    url = os.environ["WORKDAY_SOAP_URL"]
    api_version = os.environ.get("WORKDAY_API_VERSION", "v46.2")
    sync_mode_env = os.environ.get("SYNC_MODE", "auto")
    lookback_seconds = _int_env("WATERMARK_LOOKBACK_SECONDS", 60)
    count = _int_env("PAGE_COUNT", 100)
    effective_floor = os.environ.get("EFFECTIVE_FLOOR", "1900-01-01")
    effective_lookahead_days = _int_env("EFFECTIVE_LOOKAHEAD_DAYS", 0)

    # A single run-start timestamp is the delta ``Updated_Through`` and the new
    # watermark, so the stored watermark exactly matches the queried upper bound.
    now = datetime.now(timezone.utc).replace(microsecond=0)

    conn = db.connect()
    try:
        db.bootstrap_schema(conn)
        watermark = db.read_watermark(conn)
        mode = decide_mode(sync_mode_env, watermark)
        print(
            f"[refresher] mode={mode} watermark={watermark} "
            f"now={now.isoformat()}"
        )

        workers = _fetch_all_workers(
            url,
            username,
            password,
            mode=mode,
            watermark=watermark,
            now=now,
            count=count,
            lookback_seconds=lookback_seconds,
            effective_floor=effective_floor,
            effective_lookahead_days=effective_lookahead_days,
            api_version=api_version,
        )

        rows = db.upsert_workers_and_advance(
            conn, workers, updated_through=now, sync_mode=mode
        )
        print(
            f"[refresher] done: upserted {rows} workers; "
            f"watermark -> {now.isoformat()}"
        )
    finally:
        conn.close()


def main() -> None:
    try:
        run()
    except Exception as exc:  # noqa: BLE001 - top-level job failure logging
        print(f"[refresher] FAILED: {exc}", file=sys.stderr)
        raise


if __name__ == "__main__":
    main()
