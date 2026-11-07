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


MACOS = "macos"
WINDOWS = "windows"


def _os_of(item):
    """The platform an item serves. Items from before the label existed are
    macOS ones: that was the only platform the feed carried."""
    enclosure = item.find("enclosure")
    label = enclosure.get(_tag("os")) if enclosure is not None else None
    return label or MACOS


def _build_of(item):
    title = item.findtext("title", default="(untitled)")
    if _os_of(item) == WINDOWS:
        text = item.find("enclosure").get(_tag("version"), "")
        text = text.rpartition("+")[2]
    else:
        node = item.find(_tag("version"))
        text = node.text if node is not None else None
    try:
        return int(text)
    except (TypeError, ValueError):
        raise AppcastError(f"feed item {title!r} has no integer build number")


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
        _tag("os"): MACOS,
        "length": str(length),
        "type": "application/octet-stream",
    })
    return item


def _make_windows_item(version, build, pub_date, url, length, dsa_signature):
    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Version {version}"
    ET.SubElement(item, "pubDate").text = pub_date
    ET.SubElement(item, "enclosure", {
        "url": url,
        _tag("dsaSignature"): dsa_signature,
        _tag("version"): f"{version}+{build}",
        _tag("os"): WINDOWS,
        "length": str(length),
        "type": "application/octet-stream",
    })
    return item


def _insert(path, os_name, build, make_item):
    try:
        build = int(build)
    except (TypeError, ValueError):
        raise AppcastError(f"build number must be an integer, got {build!r}")
    tree = _load(path)
    channel = tree.getroot().find("channel")
    if channel is None:
        raise AppcastError("feed has no <channel>")
    items = channel.findall("item")
    mine = [i for i in items if _os_of(i) == os_name]
    latest = max((_build_of(i) for i in mine), default=None)
    if latest is not None and build < latest:
        raise AppcastError(
            f"{os_name} build {build} is older than the feed's latest {latest}")
    for old in [i for i in mine if _build_of(i) == build]:
        channel.remove(old)
    first_item = len(channel) - len(channel.findall("item"))
    channel.insert(first_item, make_item(build))
    ET.indent(tree, space="    ")
    tree.write(path, encoding="UTF-8", xml_declaration=True)


def add_item(path, *, version, build, pub_date, url, length, ed_signature,
             min_system="12.0"):
    _insert(path, MACOS, build, lambda n: _make_item(
        version, n, pub_date, url, length, ed_signature, min_system))


def add_windows_item(path, *, version, build, pub_date, url, length,
                     dsa_signature):
    _insert(path, WINDOWS, build, lambda n: _make_windows_item(
        version, n, pub_date, url, length, dsa_signature))


def _add_for(parser, args):
    common = dict(version=args.version, build=args.build,
                  pub_date=args.pub_date, url=args.url, length=args.length)
    if args.os == WINDOWS:
        if not args.dsa_signature:
            parser.error("--os windows requires --dsa-signature")
        add_windows_item(args.appcast, dsa_signature=args.dsa_signature,
                         **common)
        return
    if not args.ed_signature:
        parser.error("--os macos requires --ed-signature")
    add_item(args.appcast, ed_signature=args.ed_signature,
             min_system=args.min_system, **common)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--appcast", required=True)
    parser.add_argument("--os", choices=[MACOS, WINDOWS], default=MACOS)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--pub-date", required=True)
    parser.add_argument("--url", required=True)
    parser.add_argument("--length", required=True)
    parser.add_argument("--ed-signature", help="macOS only")
    parser.add_argument("--dsa-signature", help="Windows only")
    parser.add_argument("--min-system", default="12.0")
    args = parser.parse_args(argv)
    try:
        _add_for(parser, args)
    except AppcastError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
