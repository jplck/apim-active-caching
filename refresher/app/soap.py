"""Workday ``Get_Workers`` SOAP: build the request envelope and parse responses.

The transform (:func:`parse_workers`) is a pure function so it can be tested
offline against a fixture without any network or database access.

All field extraction uses the *exact* canonical XPaths from ``plan.md`` §5
(namespace prefix ``wd`` = ``urn:com.workday/bsvc``). ``employeeID`` is the
primary key.
"""
from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
from typing import Iterable, List, Optional, Sequence, Tuple, Union

from lxml import etree

# --- Namespaces -------------------------------------------------------------
WD = "urn:com.workday/bsvc"
SOAPENV = "http://schemas.xmlsoap.org/soap/envelope/"
WSSE = (
    "http://docs.oasis-open.org/wss/2004/01/"
    "oasis-200401-wss-wssecurity-secext-1.0.xsd"
)
WSU = (
    "http://docs.oasis-open.org/wss/2004/01/"
    "oasis-200401-wss-wssecurity-utility-1.0.xsd"
)
PASSWORD_TEXT_TYPE = (
    "http://docs.oasis-open.org/wss/2004/01/"
    "oasis-200401-wss-username-token-profile-1.0#PasswordText"
)

NS = {"wd": WD}
NSMAP = {"env": SOAPENV, "wd": WD, "wsse": WSSE, "wsu": WSU}

# --- Field mapping (JSON key, DB column, XPath relative to wd:Worker) --------
# Exact canonical XPaths from plan.md §5. ``employeeID`` -> ``employee_id`` is
# the primary key.
FIELD_XPATHS: Sequence[Tuple[str, str, str]] = (
    (
        "employeeID",
        "employee_id",
        "wd:Worker_Reference/wd:ID[@wd:type='Employee_ID']",
    ),
    (
        "cwid",
        "cwid",
        "wd:Worker_Data/wd:Personal_Data/wd:Identification_Data/wd:Custom_ID/"
        "wd:Custom_ID_Data[wd:Custom_ID_Type_Reference/"
        "wd:ID[@wd:type='Custom_ID_Type_ID']='CWID']/wd:ID",
    ),
    (
        "email",
        "email",
        "wd:Worker_Data/wd:Personal_Data/wd:Contact_Data/"
        "wd:Email_Address_Data[wd:Usage_Data/wd:Type_Data/wd:Type_Reference/"
        "wd:ID='WORK']/wd:Email_Address",
    ),
    (
        "internalFullName",
        "internal_full_name",
        "wd:Worker_Data/wd:Personal_Data/wd:Name_Data/wd:Preferred_Name_Data/"
        "wd:Name_Detail_Data/wd:Formatted_Name",
    ),
    (
        "internalFirstName",
        "internal_first_name",
        "wd:Worker_Data/wd:Personal_Data/wd:Name_Data/wd:Preferred_Name_Data/"
        "wd:Name_Detail_Data/wd:First_Name",
    ),
    (
        "internalLastName",
        "internal_last_name",
        "wd:Worker_Data/wd:Personal_Data/wd:Name_Data/wd:Preferred_Name_Data/"
        "wd:Name_Detail_Data/wd:Last_Name",
    ),
    (
        "businessAddressSite",
        "business_address_site",
        "wd:Worker_Data/wd:Employment_Data/"
        "wd:Worker_Job_Data[@wd:Primary_Job=1]/wd:Position_Data/"
        "wd:Business_Site_Summary_Data/wd:Name",
    ),
    (
        "businessAddressSiteID",
        "business_address_site_id",
        "wd:Worker_Data/wd:Employment_Data/"
        "wd:Worker_Job_Data[@wd:Primary_Job=1]/wd:Position_Data/"
        "wd:Business_Site_Summary_Data/wd:Location_Reference/"
        "wd:ID[@wd:type='Location_ID']",
    ),
    (
        "businessAddressCountry",
        "business_address_country",
        "wd:Worker_Data/wd:Employment_Data/"
        "wd:Worker_Job_Data[@wd:Primary_Job=1]/wd:Position_Data/"
        "wd:Business_Site_Summary_Data/wd:Address_Data/wd:Country_Reference/"
        "wd:ID[@wd:type='ISO_3166-1_Alpha-2_Code']",
    ),
    (
        "companyCode",
        "company_code",
        "wd:Worker_Data/wd:Employment_Data/"
        "wd:Worker_Job_Data[@wd:Primary_Job=1]/wd:Position_Organizations_Data/"
        "wd:Position_Organization_Data/"
        "wd:Organization_Data[wd:Organization_Type_Reference/"
        "wd:ID='Company']/wd:Organization_Code",
    ),
    (
        "companyName",
        "company_name",
        "wd:Worker_Data/wd:Employment_Data/"
        "wd:Worker_Job_Data[@wd:Primary_Job=1]/wd:Position_Organizations_Data/"
        "wd:Position_Organization_Data/"
        "wd:Organization_Data[wd:Organization_Type_Reference/"
        "wd:ID='Company']/wd:Organization_Name",
    ),
    (
        "costCenter",
        "cost_center",
        "wd:Worker_Data/wd:Employment_Data/"
        "wd:Worker_Job_Data[@wd:Primary_Job=1]/wd:Position_Organizations_Data/"
        "wd:Position_Organization_Data/"
        "wd:Organization_Data[wd:Organization_Type_Reference/"
        "wd:ID='Cost_Center']/wd:Organization_Code",
    ),
    (
        "countryCode",
        "country_code",
        "wd:Worker_Data/wd:Integration_Field_Override_Data[wd:Field_Reference/"
        "wd:ID[@wd:parent_id='Sailpoint_AdditionalService']="
        "'Company_Address_Country']/wd:Value",
    ),
)

# DB column order used by the writer (see ``app.db``). ``active`` is derived
# and ``updated_at`` is set to ``now()`` at UPSERT time.
COLUMNS: Tuple[str, ...] = tuple(col for _json, col, _xpath in FIELD_XPATHS)

Source = Union[bytes, bytearray, str, etree._Element, etree._ElementTree]


# --- Datetime helpers -------------------------------------------------------
def _to_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _fmt_dt(value: datetime) -> str:
    """Format a datetime as an ISO-8601 UTC ``xsd:dateTime`` string."""
    return _to_utc(value).isoformat()


def _parse_floor(value: str) -> datetime:
    """Parse ``EFFECTIVE_FLOOR`` (``YYYY-MM-DD`` or full ISO) to UTC datetime."""
    try:
        day = date.fromisoformat(value)
    except ValueError:
        return _to_utc(datetime.fromisoformat(value))
    return datetime(day.year, day.month, day.day, tzinfo=timezone.utc)


# --- Request builder --------------------------------------------------------
def _qn(namespace: str, tag: str) -> etree.QName:
    return etree.QName(namespace, tag)


def _sub(parent: etree._Element, namespace: str, tag: str) -> etree._Element:
    return etree.SubElement(parent, _qn(namespace, tag))


def build_get_workers_request(
    username: str,
    password: str,
    *,
    page: int = 1,
    count: int = 100,
    mode: str = "full",
    watermark: Optional[datetime] = None,
    now: Optional[datetime] = None,
    lookback_seconds: int = 60,
    effective_floor: str = "1900-01-01",
    effective_lookahead_days: int = 0,
    api_version: str = "v46.2",
) -> etree._Element:
    """Build a ``Get_Workers_Request`` SOAP envelope Element.

    * WS-Security ``UsernameToken`` header (``PasswordText``).
    * ``Response_Filter`` with 1-based ``Page`` and ``Count``.
    * ``Response_Group`` include flags (reference, personal, employment, orgs).
    * ``mode='delta'`` adds
      ``Request_Criteria/Transaction_Log_Criteria/Transaction_Date_Range_Data/
      Effective_And_Updated_DateTime_Data`` with **all four** bounds:
      ``Updated_From`` (watermark minus ``lookback_seconds``),
      ``Updated_Through`` (``now``), ``Effective_From`` (``effective_floor``),
      ``Effective_Through`` (``now`` plus ``effective_lookahead_days``).
    * ``mode='full'`` leaves ``Request_Criteria`` empty.
    """
    now = _to_utc(now) if now is not None else datetime.now(timezone.utc)

    envelope = etree.Element(_qn(SOAPENV, "Envelope"), nsmap=NSMAP)

    header = _sub(envelope, SOAPENV, "Header")
    security = _sub(header, WSSE, "Security")
    security.set(_qn(SOAPENV, "mustUnderstand"), "1")
    token = _sub(security, WSSE, "UsernameToken")
    _sub(token, WSSE, "Username").text = username
    password_el = _sub(token, WSSE, "Password")
    password_el.set("Type", PASSWORD_TEXT_TYPE)
    password_el.text = password

    body = _sub(envelope, SOAPENV, "Body")
    request = _sub(body, WD, "Get_Workers_Request")
    request.set(_qn(WD, "version"), api_version)

    criteria = _sub(request, WD, "Request_Criteria")
    if mode == "delta":
        if watermark is None:
            raise ValueError("delta mode requires a watermark datetime")
        updated_from = _to_utc(watermark) - timedelta(seconds=lookback_seconds)
        updated_through = now
        effective_from = _parse_floor(effective_floor)
        effective_through = now + timedelta(days=effective_lookahead_days)

        tlog = _sub(criteria, WD, "Transaction_Log_Criteria")
        date_range = _sub(tlog, WD, "Transaction_Date_Range_Data")
        window = _sub(date_range, WD, "Effective_And_Updated_DateTime_Data")
        _sub(window, WD, "Updated_From").text = _fmt_dt(updated_from)
        _sub(window, WD, "Updated_Through").text = _fmt_dt(updated_through)
        _sub(window, WD, "Effective_From").text = _fmt_dt(effective_from)
        _sub(window, WD, "Effective_Through").text = _fmt_dt(effective_through)

    response_filter = _sub(request, WD, "Response_Filter")
    _sub(response_filter, WD, "Page").text = str(page)
    _sub(response_filter, WD, "Count").text = str(count)

    response_group = _sub(request, WD, "Response_Group")
    for flag in (
        "Include_Reference",
        "Include_Personal_Information",
        "Include_Employment_Information",
        "Include_Organizations",
    ):
        _sub(response_group, WD, flag).text = "true"

    return envelope


def serialize(envelope: etree._Element) -> bytes:
    """Serialize an envelope Element to a UTF-8 XML document for the POST body."""
    return etree.tostring(envelope, xml_declaration=True, encoding="UTF-8")


# --- Response parser --------------------------------------------------------
def _to_element(source: Source) -> etree._Element:
    if isinstance(source, (bytes, bytearray)):
        return etree.fromstring(bytes(source))
    if isinstance(source, str):
        return etree.fromstring(source.encode("utf-8"))
    if isinstance(source, etree._ElementTree):
        return source.getroot()
    return source


def _first_text(worker: etree._Element, xpath: str) -> Optional[str]:
    nodes = worker.xpath(xpath, namespaces=NS)
    if not nodes:
        return None
    node = nodes[0]
    text = node if isinstance(node, str) else node.text
    if text is None:
        return None
    text = text.strip()
    return text or None


def _worker_to_dict(worker: etree._Element) -> dict:
    row = {json_key: _first_text(worker, xpath) for json_key, _col, xpath in FIELD_XPATHS}
    # Present in the latest pull -> active.
    row["active"] = True
    return row


def parse_workers(source: Source) -> List[dict]:
    """Parse a ``Get_Workers_Response`` into a list of normalized worker dicts.

    Each dict is keyed by the plan.md §5 JSON keys (``employeeID``, ``cwid``,
    ...) plus ``active``. Missing fields are ``None``. Pure function.
    """
    root = _to_element(source)
    workers = root.xpath("//wd:Response_Data/wd:Worker", namespaces=NS)
    return [_worker_to_dict(worker) for worker in workers]


def parse_response_results(source: Source) -> dict:
    """Parse ``Response_Results`` paging metadata (drives the page loop)."""
    root = _to_element(source)
    results = root.xpath("//wd:Response_Results", namespaces=NS)
    if not results:
        return {"page": 1, "total_pages": 1, "total_results": 0, "page_results": 0}
    node = results[0]

    def _int(tag: str, default: int) -> int:
        found = node.xpath(f"wd:{tag}/text()", namespaces=NS)
        try:
            return int(found[0]) if found else default
        except (TypeError, ValueError):
            return default

    return {
        "page": _int("Page", 1),
        "total_pages": _int("Total_Pages", 1),
        "total_results": _int("Total_Results", 0),
        "page_results": _int("Page_Results", 0),
    }
