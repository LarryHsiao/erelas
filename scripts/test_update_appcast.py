"""Tests for update_appcast.py. Run: python3 -I -m unittest discover -s scripts

Platforms: any with Python 3.9+ (standard library only).
"""
import os
import tempfile
import unittest
import xml.etree.ElementTree as ET

import update_appcast as appcast

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def item_args(build, version="1.1.0", url="https://example.com/erelas.dmg"):
    return dict(
        version=version,
        build=build,
        pub_date="Fri, 06 Nov 2026 12:00:00 +0000",
        url=url,
        length=1234,
        ed_signature="SIG==",
        min_system="12.0",
    )


class AddItemTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.path = os.path.join(self.dir.name, "appcast.xml")

    def items(self):
        return ET.parse(self.path).getroot().findall("./channel/item")

    def builds(self):
        return [i.find(f"{{{SPARKLE}}}version").text for i in self.items()]

    def test_creates_a_feed_with_one_item(self):
        appcast.add_item(self.path, **item_args(2))
        expected = ["2"]
        self.assertEqual(self.builds(), expected)

    def test_item_carries_the_fields_sparkle_reads(self):
        appcast.add_item(self.path, **item_args(2))
        item = self.items()[0]
        enclosure = item.find("enclosure")
        expected = {
            "short": "1.1.0",
            "min": "12.0",
            "url": "https://example.com/erelas.dmg",
            "signature": "SIG==",
            "length": "1234",
        }
        actual = {
            "short": item.find(f"{{{SPARKLE}}}shortVersionString").text,
            "min": item.find(f"{{{SPARKLE}}}minimumSystemVersion").text,
            "url": enclosure.get("url"),
            "signature": enclosure.get(f"{{{SPARKLE}}}edSignature"),
            "length": enclosure.get("length"),
        }
        self.assertEqual(actual, expected)

    def test_a_higher_build_goes_first(self):
        appcast.add_item(self.path, **item_args(2))
        appcast.add_item(self.path, **item_args(3, version="1.1.1"))
        expected = ["3", "2"]
        self.assertEqual(self.builds(), expected)

    def test_the_same_build_is_replaced_not_duplicated(self):
        appcast.add_item(self.path, **item_args(2))
        appcast.add_item(self.path, **item_args(2, url="https://example.com/new.dmg"))
        urls = [i.find("enclosure").get("url") for i in self.items()]
        expected = ["https://example.com/new.dmg"]
        self.assertEqual(urls, expected)

    def test_a_lower_build_than_the_latest_is_refused(self):
        appcast.add_item(self.path, **item_args(3, version="1.1.1"))
        with self.assertRaises(appcast.AppcastError):
            appcast.add_item(self.path, **item_args(2))
        expected = ["3"]
        self.assertEqual(self.builds(), expected)

    def test_an_ampersand_in_the_url_stays_valid_xml(self):
        url = "https://example.com/erelas.dmg?a=1&b=2"
        appcast.add_item(self.path, **item_args(2, url=url))
        actual = self.items()[0].find("enclosure").get("url")
        self.assertEqual(actual, url)

    def test_a_non_numeric_build_is_refused(self):
        with self.assertRaises(appcast.AppcastError):
            appcast.add_item(self.path, **item_args("abc"))


def windows_args(build, version="1.1.1", url="https://example.com/setup.exe"):
    return dict(
        version=version,
        build=build,
        pub_date="Fri, 06 Nov 2026 12:00:00 +0000",
        url=url,
        length=4321,
        dsa_signature="DSA==",
    )


class WindowsItemTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.path = os.path.join(self.dir.name, "appcast.xml")

    def enclosures(self):
        root = ET.parse(self.path).getroot()
        return [i.find("enclosure") for i in root.findall("./channel/item")]

    def oses(self):
        return [e.get(f"{{{SPARKLE}}}os") for e in self.enclosures()]

    def test_windows_item_carries_what_winsparkle_reads(self):
        appcast.add_windows_item(self.path, **windows_args(3))
        enclosure = self.enclosures()[0]
        expected = {
            "os": "windows",
            "version": "1.1.1+3",
            "signature": "DSA==",
            "length": "4321",
            "url": "https://example.com/setup.exe",
        }
        actual = {
            "os": enclosure.get(f"{{{SPARKLE}}}os"),
            "version": enclosure.get(f"{{{SPARKLE}}}version"),
            "signature": enclosure.get(f"{{{SPARKLE}}}dsaSignature"),
            "length": enclosure.get("length"),
            "url": enclosure.get("url"),
        }
        self.assertEqual(actual, expected)

    def test_macos_item_is_labelled_macos(self):
        appcast.add_item(self.path, **item_args(3, version="1.1.1"))
        expected = ["macos"]
        self.assertEqual(self.oses(), expected)

    def test_windows_item_leaves_the_macos_item_alone(self):
        appcast.add_item(self.path, **item_args(3, version="1.1.1"))
        appcast.add_windows_item(self.path, **windows_args(3))
        expected = {"macos", "windows"}
        self.assertEqual(set(self.oses()), expected)

    def test_windows_item_may_trail_the_macos_build(self):
        appcast.add_item(self.path, **item_args(5, version="1.2.0"))
        appcast.add_windows_item(self.path, **windows_args(3))
        expected = 2
        self.assertEqual(len(self.enclosures()), expected)

    def test_the_same_windows_build_is_replaced(self):
        appcast.add_windows_item(self.path, **windows_args(3))
        appcast.add_windows_item(self.path, **windows_args(3, url="https://example.com/new.exe"))
        urls = [e.get("url") for e in self.enclosures()]
        expected = ["https://example.com/new.exe"]
        self.assertEqual(urls, expected)

    def test_a_lower_windows_build_is_refused(self):
        appcast.add_windows_item(self.path, **windows_args(3))
        with self.assertRaises(appcast.AppcastError):
            appcast.add_windows_item(self.path, **windows_args(2, version="1.1.0"))
        expected = 1
        self.assertEqual(len(self.enclosures()), expected)

    def test_a_legacy_unlabelled_item_counts_as_macos(self):
        with open(self.path, "w") as feed:
            feed.write(
                "<rss xmlns:sparkle='%s' version='2.0'><channel><item>"
                "<title>x</title><sparkle:version>9</sparkle:version>"
                "<enclosure url='u' length='1'/></item></channel></rss>" % SPARKLE
            )
        appcast.add_windows_item(self.path, **windows_args(3))
        expected = 2
        self.assertEqual(len(self.enclosures()), expected)


class HandEditedFeedTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.path = os.path.join(self.dir.name, "appcast.xml")

    def test_an_item_without_a_build_is_a_named_error_not_a_traceback(self):
        with open(self.path, "w") as feed:
            feed.write(
                "<rss version='2.0'><channel><item><title>x</title></item>"
                "</channel></rss>"
            )
        with self.assertRaises(appcast.AppcastError):
            appcast.add_item(self.path, **item_args(2))

    def test_a_feed_without_a_channel_is_a_named_error(self):
        with open(self.path, "w") as feed:
            feed.write("<rss version='2.0'></rss>")
        with self.assertRaises(appcast.AppcastError):
            appcast.add_item(self.path, **item_args(2))


if __name__ == "__main__":
    unittest.main()
