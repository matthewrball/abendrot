#!/usr/bin/env python3
"""Validate Abendrot's public Sparkle appcast."""

import base64
import binascii
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
NS = "{" + SPARKLE + "}"
FEED_URL = "https://raw.githubusercontent.com/matthewrball/abendrot/main/appcast.xml"
ANCHOR = "release.sh inserts new <item> elements directly below this line."
VERSION_RE = re.compile(r"[0-9]+(?:\.[0-9]+){1,3}(?:-[0-9A-Za-z][0-9A-Za-z.-]*)?")
MINIMUM_OS_RE = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+")
ENCLOSURE_RE = re.compile(
    r"https://github\.com/matthewrball/abendrot/releases/download/"
    r"v(?P<tag>[0-9]+(?:\.[0-9]+){1,3}(?:-[0-9A-Za-z][0-9A-Za-z.-]*)?)/"
    r"Abendrot-(?P<file>[0-9]+(?:\.[0-9]+){1,3}(?:-[0-9A-Za-z][0-9A-Za-z.-]*)?)\.dmg"
)


def fail(message: str) -> None:
    print(f"appcast: {message}", file=sys.stderr)
    raise SystemExit(1)


def one_text(item: ET.Element, tag: str, label: str) -> str:
    nodes = item.findall(tag)
    if len(nodes) != 1 or not (nodes[0].text or "").strip():
        fail(f"every item must have exactly one non-empty {label}.")
    return (nodes[0].text or "").strip()


def validate(path: Path) -> int:
    try:
        parser = ET.XMLParser(target=ET.TreeBuilder(insert_comments=True))
        root = ET.parse(path, parser=parser).getroot()
    except (OSError, ET.ParseError) as error:
        fail(f"invalid XML: {error}")

    if root.tag != "rss" or root.get("version") != "2.0":
        fail("must have one RSS 2.0 root.")
    channels = [node for node in root if node.tag == "channel"]
    if len(channels) != 1:
        fail("must have exactly one direct channel.")
    channel = channels[0]

    titles = [node for node in channel if node.tag == "title"]
    if len(titles) != 1 or (titles[0].text or "").strip() != "Abendrot":
        fail("channel title must be 'Abendrot'.")
    links = [node for node in channel if node.tag == "link"]
    if len(links) != 1 or (links[0].text or "").strip() != FEED_URL:
        fail(f"channel link must be {FEED_URL}.")

    children = list(channel)
    anchors = [
        index
        for index, node in enumerate(children)
        if node.tag is ET.Comment and (node.text or "").strip() == ANCHOR
    ]
    if len(anchors) != 1:
        fail("must contain exactly one direct release insertion anchor.")
    item_indexes = [index for index, node in enumerate(children) if node.tag == "item"]
    if item_indexes and anchors[0] > min(item_indexes):
        fail("release insertion anchor must precede every item.")

    builds: list[int] = []
    versions: set[str] = set()
    for item in (children[index] for index in item_indexes):
        build_text = one_text(item, f"{NS}version", "sparkle:version")
        if not build_text.isascii() or not build_text.isdigit() or int(build_text) <= 0:
            fail("every sparkle:version must be a positive integer.")
        builds.append(int(build_text))

        version = one_text(item, f"{NS}shortVersionString", "sparkle:shortVersionString")
        if VERSION_RE.fullmatch(version) is None or version in versions:
            fail("every sparkle:shortVersionString must be valid and unique.")
        versions.add(version)

        minimum_os = one_text(item, f"{NS}minimumSystemVersion", "sparkle:minimumSystemVersion")
        if MINIMUM_OS_RE.fullmatch(minimum_os) is None:
            fail("every sparkle:minimumSystemVersion must use major.minor.patch.")
        if tuple(map(int, minimum_os.split("."))) < (12, 0, 0):
            fail("every sparkle:minimumSystemVersion must be at least 12.0.0.")

        enclosures = item.findall("enclosure")
        if len(enclosures) != 1:
            fail("every item must have exactly one enclosure.")
        enclosure = enclosures[0]
        url = enclosure.get("url", "")
        match = ENCLOSURE_RE.fullmatch(url)
        if match is None or match.group("tag") != version or match.group("file") != version:
            fail("every enclosure URL must match its Abendrot GitHub release version.")
        length = enclosure.get("length", "")
        if not length.isascii() or not length.isdigit() or int(length) <= 0:
            fail("every enclosure length must be a positive integer.")
        if enclosure.get("type") != "application/octet-stream":
            fail("every enclosure type must be application/octet-stream.")
        signature = enclosure.get(f"{NS}edSignature", "")
        try:
            signature_bytes = base64.b64decode(signature, validate=True)
        except (ValueError, binascii.Error):
            signature_bytes = b""
        if len(signature_bytes) != 64:
            fail("every enclosure sparkle:edSignature must decode to 64 bytes.")

    if len(builds) != len(set(builds)) or builds != sorted(builds, reverse=True):
        fail("sparkle:version values must be unique and newest-first.")

    print(f"appcast: valid channel and {len(builds)} signed release item(s).")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        fail("usage: validate-appcast.py <appcast.xml>")
    raise SystemExit(validate(Path(sys.argv[1])))
