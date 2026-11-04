"""Fetch TWSE's daily index closes and write the Erelas today.json.

Source: TWSE OpenAPI /exchangeReport/MI_INDEX (open government data).
Fails loud: any malformed or missing input raises, and the existing
output file is left untouched.
"""
import json
import os
import re
import sys
import tempfile
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

MI_INDEX_URL = "https://openapi.twse.com.tw/v1/exchangeReport/MI_INDEX"
FETCH_TIMEOUT_SECONDS = 60
CONTRACT_VERSION = 1
SOURCE = "TWSE"
TAIEX_NAME = "發行量加權股價指數"
ROC_YEAR_OFFSET = 1911
ROC_DATE_PATTERN = re.compile(r"^(\d{3})(\d{2})(\d{2})$")
TAIPEI_TZ = timezone(timedelta(hours=8))
DEFAULT_OUTPUT = Path(__file__).resolve().parent.parent / "docs" / "today.json"
TICKER_CONFIG = Path(__file__).resolve().parent / "ticker.json"
VOLATILE_KEYS = ("asOf",)


def parse_number(text):
    return float(text.replace(",", ""))


def _signed(sign, magnitude):
    if sign == "+":
        return magnitude
    if sign == "-":
        return -magnitude if magnitude else 0.0
    if magnitude == 0:
        return 0.0
    raise ValueError(f"unknown sign {sign!r} with non-zero change")


def parse_row(raw):
    points = abs(parse_number(raw["漲跌點數"]))
    percent = abs(parse_number(raw["漲跌百分比"]))
    sign = raw["漲跌"].strip()
    return {
        "name": raw["指數"],
        "close": parse_number(raw["收盤指數"]),
        "change": _signed(sign, points),
        "changePct": _signed(sign, percent),
    }


def iso_date(roc_date):
    match = ROC_DATE_PATTERN.match(roc_date)
    if match is None:
        raise ValueError(f"unexpected date format {roc_date!r}")
    year, month, day = (int(part) for part in match.groups())
    return f"{year + ROC_YEAR_OFFSET:04d}-{month:02d}-{day:02d}"


def build_payload(rows, ticker_names, as_of):
    by_name = {}
    for raw in rows:
        by_name.setdefault(raw["指數"], raw)
    if TAIEX_NAME not in by_name:
        raise ValueError(f"row {TAIEX_NAME!r} missing from response")
    date = iso_date(by_name[TAIEX_NAME]["日期"])
    wanted = [by_name[name] for name in ticker_names if name in by_name]
    for raw in wanted:
        if iso_date(raw["日期"]) != date:
            raise ValueError(f"row {raw['指數']!r} is dated {raw['日期']}")
    items = [parse_row(raw) for raw in wanted]
    return {
        "v": CONTRACT_VERSION,
        "source": SOURCE,
        "asOf": as_of,
        "index": {"date": date, **parse_row(by_name[TAIEX_NAME])},
        "ticker": {"date": date, "items": items},
        "topic": None,
    }


def _stable(payload):
    return {k: v for k, v in payload.items() if k not in VOLATILE_KEYS}


def write_if_changed(path, payload):
    path = Path(path)
    if path.exists():
        existing = json.loads(path.read_text(encoding="utf-8"))
        if _stable(existing) == _stable(payload):
            return False
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    with tempfile.NamedTemporaryFile(
            "w", encoding="utf-8", dir=path.parent, delete=False) as tmp:
        tmp.write(text)
    try:
        os.replace(tmp.name, path)
    except OSError:
        os.unlink(tmp.name)
        raise
    return True


def fetch_rows():
    request = urllib.request.Request(
        MI_INDEX_URL, headers={"User-Agent": "erelas-writer"})
    with urllib.request.urlopen(request, timeout=FETCH_TIMEOUT_SECONDS) as reply:
        return json.load(reply)


def main(argv, fetch=fetch_rows):
    output = Path(argv[1]) if len(argv) > 1 else DEFAULT_OUTPUT
    names = json.loads(TICKER_CONFIG.read_text(encoding="utf-8"))
    as_of = datetime.now(TAIPEI_TZ).isoformat(timespec="seconds")
    payload = build_payload(fetch(), names, as_of)
    wrote = write_if_changed(output, payload)
    print("updated" if wrote else "unchanged", payload["index"]["date"])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
