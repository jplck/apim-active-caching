"""Offline transform tests: parse fixtures and assert the plan.md §5 mappings."""
from __future__ import annotations

import pathlib

from app.soap import parse_response_results, parse_workers

FIXTURES = pathlib.Path(__file__).parent / "fixtures"
CANONICAL = FIXTURES / "workers-canonical-soap.xml"
SAMPLE = FIXTURES / "workers-soap.xml"


def _read(path: pathlib.Path) -> bytes:
    return path.read_bytes()


def _by_id(workers, employee_id):
    return next(w for w in workers if w["employeeID"] == employee_id)


def test_canonical_worker_maps_all_fields():
    workers = parse_workers(_read(CANONICAL))
    assert len(workers) == 2

    w = _by_id(workers, "21001")
    # employeeID is the primary key (Worker_Reference Employee_ID).
    assert w["employeeID"] == "21001"
    # Secondary Custom ID (CWID), not the WID.
    assert w["cwid"] == "CW123456"
    # WORK-usage email is selected, HOME is filtered out.
    assert w["email"] == "lmcneil@contoso.com"
    # Preferred name (not the Legal name).
    assert w["internalFullName"] == "Logan McNeil"
    assert w["internalFirstName"] == "Logan"
    assert w["internalLastName"] == "McNeil"
    # Primary job ([@wd:Primary_Job=1]) business site, not the secondary job.
    assert w["businessAddressSite"] == "San Francisco"
    assert w["businessAddressSiteID"] == "LOC-SF"
    assert w["businessAddressCountry"] == "US"
    # Company / Cost_Center org rows filtered by Organization_Type_Reference.
    assert w["companyCode"] == "CMP-001"
    assert w["companyName"] == "Contoso Ltd"
    assert w["costCenter"] == "CC-4100"
    # countryCode from the integration field override.
    assert w["countryCode"] == "US"
    # Present in the pull -> active.
    assert w["active"] is True


def test_canonical_minimal_worker_has_none_for_missing_fields():
    workers = parse_workers(_read(CANONICAL))
    w = _by_id(workers, "21002")
    assert w["employeeID"] == "21002"
    assert w["active"] is True
    for key in (
        "cwid",
        "email",
        "internalFullName",
        "businessAddressSite",
        "companyCode",
        "costCenter",
        "countryCode",
    ):
        assert w[key] is None, key


def test_parse_response_results_paging():
    results = parse_response_results(_read(CANONICAL))
    assert results == {
        "page": 1,
        "total_pages": 1,
        "total_results": 2,
        "page_results": 2,
    }


def test_sample_mock_extracts_primary_key_only():
    """The POC SOAP mock uses a simplified shape: under the exact §5 XPaths only
    ``employeeID`` maps; WORK-email/Preferred-name paths correctly yield None."""
    workers = parse_workers(_read(SAMPLE))
    assert [w["employeeID"] for w in workers] == [
        "21001",
        "21002",
        "21003",
        "21004",
        "21005",
        "21006",
    ]
    first = workers[0]
    # Simplified mock lacks the WORK usage filter and Preferred_Name_Data,
    # so the strict canonical XPaths do not match.
    assert first["email"] is None
    assert first["internalFullName"] is None
    assert first["companyCode"] is None
    assert first["active"] is True
