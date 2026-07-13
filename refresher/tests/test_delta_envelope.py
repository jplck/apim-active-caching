"""Offline tests for the SOAP request builder (delta + full envelopes)."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from app.soap import (
    NSMAP,
    PASSWORD_TEXT_TYPE,
    WD,
    build_get_workers_request,
    serialize,
)

USERNAME = "isu_integration@contoso"
PASSWORD = "s3cr3t-isu-pw"
WATERMARK = datetime(2024, 6, 1, 12, 0, 0, tzinfo=timezone.utc)
NOW = datetime(2024, 6, 2, 8, 30, 0, tzinfo=timezone.utc)


def _text(element, xpath):
    found = element.xpath(xpath, namespaces=NSMAP)
    return found[0] if found else None


def _dt(element, xpath):
    value = _text(element, xpath)
    return datetime.fromisoformat(value) if value is not None else None


def _build_delta(**overrides):
    params = dict(
        page=1,
        count=100,
        mode="delta",
        watermark=WATERMARK,
        now=NOW,
        lookback_seconds=60,
        effective_floor="1900-01-01",
        effective_lookahead_days=0,
        api_version="v46.2",
    )
    params.update(overrides)
    return build_get_workers_request(USERNAME, PASSWORD, **params)


def test_ws_security_username_token():
    env = _build_delta()
    assert _text(env, "//wsse:Username/text()") == USERNAME
    assert _text(env, "//wsse:Password/text()") == PASSWORD
    assert _text(env, "//wsse:Password/@Type") == PASSWORD_TEXT_TYPE


def test_request_version_and_paging():
    env = _build_delta(page=3, count=250)
    assert _text(env, "//wd:Get_Workers_Request/@wd:version") == "v46.2"
    assert _text(env, "//wd:Response_Filter/wd:Page/text()") == "3"
    assert _text(env, "//wd:Response_Filter/wd:Count/text()") == "250"


def test_response_group_flags_present():
    env = _build_delta()
    for flag in (
        "Include_Reference",
        "Include_Personal_Information",
        "Include_Employment_Information",
        "Include_Organizations",
    ):
        assert _text(env, f"//wd:Response_Group/wd:{flag}/text()") == "true", flag


def test_delta_has_both_effective_and_updated_pairs():
    env = _build_delta()
    base = (
        "//wd:Request_Criteria/wd:Transaction_Log_Criteria/"
        "wd:Transaction_Date_Range_Data/"
        "wd:Effective_And_Updated_DateTime_Data"
    )
    window = env.xpath(base, namespaces=NSMAP)
    assert len(window) == 1

    # Updated window: watermark - lookback .. now.
    assert _dt(env, f"{base}/wd:Updated_From/text()") == WATERMARK - timedelta(seconds=60)
    assert _dt(env, f"{base}/wd:Updated_Through/text()") == NOW
    # Effective window: floor .. now + lookahead(0).
    assert _dt(env, f"{base}/wd:Effective_From/text()") == datetime(
        1900, 1, 1, tzinfo=timezone.utc
    )
    assert _dt(env, f"{base}/wd:Effective_Through/text()") == NOW


def test_delta_effective_lookahead_and_lookback_configurable():
    env = _build_delta(lookback_seconds=300, effective_lookahead_days=7)
    base = (
        "//wd:Effective_And_Updated_DateTime_Data"
    )
    assert _dt(env, f"{base}/wd:Updated_From/text()") == WATERMARK - timedelta(seconds=300)
    assert _dt(env, f"{base}/wd:Effective_Through/text()") == NOW + timedelta(days=7)


def test_full_mode_has_empty_criteria_and_no_window():
    env = build_get_workers_request(
        USERNAME, PASSWORD, page=1, count=100, mode="full", now=NOW
    )
    # Request_Criteria exists but is empty (no transaction-log window).
    criteria = env.xpath("//wd:Request_Criteria", namespaces=NSMAP)
    assert len(criteria) == 1
    assert len(criteria[0]) == 0
    assert env.xpath(
        "//wd:Effective_And_Updated_DateTime_Data", namespaces=NSMAP
    ) == []
    # Response_Group flags are still present in full mode.
    assert _text(env, "//wd:Response_Group/wd:Include_Reference/text()") == "true"


def test_serialize_returns_xml_bytes():
    env = _build_delta()
    body = serialize(env)
    assert isinstance(body, bytes)
    assert body.startswith(b"<?xml")
    assert WD.encode() in body
