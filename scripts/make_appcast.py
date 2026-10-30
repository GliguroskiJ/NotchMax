#!/usr/bin/env python3
"""Vygeneruje Sparkle appcast.xml pro jedno vydání (poslední verze)."""
import argparse
import re
from datetime import datetime, timezone
from email.utils import format_datetime
from xml.sax.saxutils import escape, quoteattr


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--app", required=True)
    p.add_argument("--version", required=True)
    p.add_argument("--build", required=True)
    p.add_argument("--repo", required=True, help="owner/repo")
    p.add_argument("--tag", required=True)
    p.add_argument("--zip", required=True)
    p.add_argument("--sign-output", required=True, help='výstup sign_update: sparkle:edSignature="..." length="..."')
    p.add_argument("--min-os", default="14.0")
    p.add_argument("--out", default="appcast.xml")
    a = p.parse_args()

    sig = re.search(r'sparkle:edSignature="([^"]+)"', a.sign_output)
    length = re.search(r'length="(\d+)"', a.sign_output)
    if not sig or not length:
        raise SystemExit(f"Nepodařilo se přečíst podpis z výstupu sign_update: {a.sign_output!r}")

    base = f"https://github.com/{a.repo}"
    pub_date = format_datetime(datetime.now(timezone.utc), usegmt=True)  # RFC 2822, nezávislé na locale

    xml = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>{escape(a.app)}</title>
    <item>
      <title>Version {escape(a.version)}</title>
      <sparkle:version>{escape(a.build)}</sparkle:version>
      <sparkle:shortVersionString>{escape(a.version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{escape(a.min_os)}</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>{escape(base)}/releases/tag/{escape(a.tag)}</sparkle:releaseNotesLink>
      <pubDate>{pub_date}</pubDate>
      <enclosure url={quoteattr(f"{base}/releases/download/{a.tag}/{a.zip}")}
                 type="application/octet-stream"
                 sparkle:edSignature={quoteattr(sig.group(1))}
                 length={quoteattr(length.group(1))}/>
    </item>
  </channel>
</rss>
"""
    with open(a.out, "w", encoding="utf-8") as f:
        f.write(xml)


if __name__ == "__main__":
    main()
