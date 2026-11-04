import json
import tempfile
import unittest
from pathlib import Path

import build_today

TAIEX_NAME = "發行量加權股價指數"
SEMI_NAME = "半導體類指數"
FETCHED_AT = "2026-11-04T14:35:00+08:00"


def row(name, close, sign, points, pct, date="1151103"):
    return {
        "日期": date, "指數": name, "收盤指數": close,
        "漲跌": sign, "漲跌點數": points, "漲跌百分比": pct,
        "特殊處理註記": "",
    }


DOWN_DAY = [
    row(TAIEX_NAME, "43307.54", "-", "1,612.60", "-3.59"),
    row(SEMI_NAME, "1446.44", "-", "45.17", "-3.03"),
    row("發行量加權股價報酬指數", "100144.27", "-", "3,728.97", "-3.59"),
]


class ParseRowTest(unittest.TestCase):
    def test_down_row_takes_sign_from_the_sign_column(self):
        expected = {"name": TAIEX_NAME, "close": 43307.54,
                    "change": -1612.6, "changePct": -3.59}
        actual = build_today.parse_row(DOWN_DAY[0])
        self.assertEqual(expected, actual)

    def test_up_row_with_unsigned_percent_comes_out_positive(self):
        expected = {"name": "水泥窯製類指數", "close": 692.91,
                    "change": 7.23, "changePct": 1.05}
        actual = build_today.parse_row(
            row("水泥窯製類指數", "692.91", "+", "7.23", "1.05"))
        self.assertEqual(expected, actual)

    def test_percent_sign_is_ignored_in_favour_of_the_sign_column(self):
        actual = build_today.parse_row(
            row("X", "10.00", "+", "1.00", "-9.99"))
        self.assertEqual(9.99, actual["changePct"])

    def test_flat_row_is_zero_change(self):
        actual = build_today.parse_row(row("X", "10.00", "", "0.00", "0.00"))
        self.assertEqual(0.0, actual["change"])
        self.assertEqual(0.0, actual["changePct"])

    def test_unknown_sign_with_nonzero_points_fails_loud(self):
        with self.assertRaises(ValueError):
            build_today.parse_row(row("X", "10.00", "?", "1.00", "1.00"))


class IsoDateTest(unittest.TestCase):
    def test_roc_date_converts_to_iso(self):
        self.assertEqual("2026-11-03", build_today.iso_date("1151103"))

    def test_malformed_date_fails_loud(self):
        with self.assertRaises(ValueError):
            build_today.iso_date("2026-11-03")


class BuildPayloadTest(unittest.TestCase):
    def test_payload_carries_index_ticker_and_empty_topic(self):
        expected = {
            "v": 1, "source": "TWSE", "asOf": FETCHED_AT,
            "index": {"date": "2026-11-03", "name": TAIEX_NAME,
                      "close": 43307.54, "change": -1612.6,
                      "changePct": -3.59},
            "ticker": {"date": "2026-11-03", "items": [
                {"name": SEMI_NAME, "close": 1446.44,
                 "change": -45.17, "changePct": -3.03}]},
            "topic": None,
        }
        actual = build_today.build_payload(DOWN_DAY, [SEMI_NAME], FETCHED_AT)
        self.assertEqual(expected, actual)

    def test_missing_taiex_row_fails_loud(self):
        with self.assertRaises(ValueError):
            build_today.build_payload(DOWN_DAY[1:], [SEMI_NAME], FETCHED_AT)

    def test_missing_ticker_name_is_skipped_not_fatal(self):
        actual = build_today.build_payload(
            DOWN_DAY, [SEMI_NAME, "不存在指數"], FETCHED_AT)
        self.assertEqual(1, len(actual["ticker"]["items"]))

    def test_exact_name_match_ignores_the_return_index_variant(self):
        actual = build_today.build_payload(DOWN_DAY, [], FETCHED_AT)
        self.assertEqual(43307.54, actual["index"]["close"])


class WriteIfChangedTest(unittest.TestCase):
    def payload(self, as_of, close=43307.54):
        rows = [row(TAIEX_NAME, str(close), "-", "1.00", "-0.01")]
        return build_today.build_payload(rows, [], as_of)

    def test_first_write_creates_the_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "today.json"
            wrote = build_today.write_if_changed(path, self.payload("a"))
            self.assertTrue(wrote)
            self.assertEqual(43307.54,
                             json.loads(path.read_text())["index"]["close"])

    def test_same_data_with_new_as_of_does_not_rewrite(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "today.json"
            build_today.write_if_changed(path, self.payload("a"))
            wrote = build_today.write_if_changed(path, self.payload("b"))
            self.assertFalse(wrote)
            self.assertEqual("a", json.loads(path.read_text())["asOf"])

    def test_changed_data_rewrites(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "today.json"
            build_today.write_if_changed(path, self.payload("a"))
            wrote = build_today.write_if_changed(path, self.payload("b", 1.0))
            self.assertTrue(wrote)

    def test_failed_fetch_through_main_leaves_the_existing_file_untouched(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "today.json"
            build_today.write_if_changed(path, self.payload("a"))
            before = path.read_bytes()
            with self.assertRaises(ValueError):
                build_today.main(["x", str(path)], fetch=lambda: DOWN_DAY[1:])
            self.assertEqual(before, path.read_bytes())

    def test_main_writes_through_an_injected_fetch(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "today.json"
            build_today.main(["x", str(path)], fetch=lambda: DOWN_DAY)
            self.assertEqual(43307.54,
                             json.loads(path.read_text())["index"]["close"])

    def test_no_temp_file_is_left_behind(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "today.json"
            build_today.write_if_changed(path, self.payload("a"))
            self.assertEqual(["today.json"], [p.name for p in Path(tmp).iterdir()])


class TickerDateTest(unittest.TestCase):
    def test_ticker_row_with_a_different_date_fails_loud(self):
        rows = [row(TAIEX_NAME, "1.00", "+", "0", "0"),
                row(SEMI_NAME, "1.00", "+", "0", "0", date="1151102")]
        with self.assertRaises(ValueError):
            build_today.build_payload(rows, [SEMI_NAME], FETCHED_AT)

    def test_ticker_order_follows_the_config(self):
        rows = [row(TAIEX_NAME, "1.00", "+", "0", "0"),
                row("A", "1.00", "+", "0", "0"), row("B", "1.00", "+", "0", "0")]
        actual = build_today.build_payload(rows, ["B", "A"], FETCHED_AT)
        self.assertEqual(["B", "A"], [i["name"] for i in actual["ticker"]["items"]])


if __name__ == "__main__":
    unittest.main()
