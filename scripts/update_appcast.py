#!/usr/bin/env python3
"""Add or replace one release's <item> in a Sparkle appcast feed.

Usage:
  python3 -I scripts/update_appcast.py --appcast docs/appcast.xml \
    --version 1.1.0 --build 2 --pub-date "<RFC 2822>" --url <dmg url> \
    --length <bytes> --ed-signature <sig> [--min-system 12.0]

Items are keyed by build number (sparkle:version), because that is what
Sparkle compares. The same build replaces its item; a lower build than the
feed's latest is refused, so a re-run can never roll the feed back.
Standard library only, so it runs wherever Python 3.9+ does (macOS, Windows).
"""
import argparse
import os
import sys
import xml.etree.ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)


class AppcastError(Exception):
    pass


def _tag(name):
    return f"{{{SPARKLE}}}{name}"


def _new_feed():
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "Erelas"
    ET.SubElement(channel, "description").text = "Erelas release feed"
    ET.SubElement(channel, "language").text = "en"
    return ET.ElementTree(rss)


def _load(path):
    return ET.parse(path) if os.path.exists(path) else _new_feed()


def _build_of(item):
    node = item.find(_tag("version"))
    try:
        return int(node.text)
    except (AttributeError, TypeError, ValueError):
        title = item.findtext("title", default="(untitled)")
        raise AppcastError(f"feed item {title!r} has no integer sparkle:version")


def _make_item(version, build, pub_date, url, length, ed_signature, min_system):
    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Version {version}"
    ET.SubElement(item, _tag("version")).text = str(build)
    ET.SubElement(item, _tag("shortVersionString")).text = version
    ET.SubElement(item, _tag("minimumSystemVersion")).text = min_system
    ET.SubElement(item, "pubDate").text = pub_date
    ET.SubElement(item, "enclosure", {
        "url": url,
        _tag("edSignature"): ed_signature,
        "length": str(length),
        "type": "application/octet-stream",
    })
    return item


def add_item(path, *, version, build, pub_date, url, length, ed_signature,
             min_system="12.0"):
    try:
        build = int(build)
    except (TypeError, ValueError):
        raise AppcastError(f"build number must be an integer, got {build!r}")
    tree = _load(path)
    channel = tree.getroot().find("channel")
    if channel is None:
        raise AppcastError("feed has no <channel>")
    items = channel.findall("item")
    latest = max((_build_of(i) for i in items), default=None)
    if latest is not None and build < latest:
        raise AppcastError(f"build {build} is older than the feed's latest {latest}")
    for old in [i for i in items if _build_of(i) == build]:
        channel.remove(old)
    first_item = len(channel) - len(channel.findall("item"))
    channel.insert(first_item, _make_item(
        version, build, pub_date, url, length, ed_signature, min_system))
    ET.indent(tree, space="    ")
    tree.write(path, encoding="UTF-8", xml_declaration=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--appcast", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--pub-date", required=True)
    parser.add_argument("--url", required=True)
    parser.add_argument("--length", required=True)
    parser.add_argument("--ed-signature", required=True)
    parser.add_argument("--min-system", default="12.0")
    args = parser.parse_args(argv)
    try:
        add_item(args.appcast, version=args.version, build=args.build,
                 pub_date=args.pub_date, url=args.url, length=args.length,
                 ed_signature=args.ed_signature, min_system=args.min_system)
    except AppcastError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
