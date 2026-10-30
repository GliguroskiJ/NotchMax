#!/usr/bin/env python3
"""Vygeneruje Sparkle appcast.xml pro jedno vydání (poslední verze)."""
import argparse
import os
import re
from datetime import datetime, timezone
from email.utils import format_datetime
from xml.sax.saxutils import escape, quoteattr


def notes_html(changelog_path: str, version: str) -> str:
    """Vezme sekci `## <verze>` z CHANGELOG.md a udělá z ní jednoduché HTML (nadpisy, odrážky)."""
    items, headings = [], []
    try:
        text = open(changelog_path, encoding="utf-8").read()
    except OSError:
        text = ""
    m = re.search(r"^##\s+v?" + re.escape(version) + r"\b.*?$(.*?)(?=^##\s|\Z)", text, re.S | re.M)
    body = m.group(1).strip() if m else ""
    html = []
    in_list = False
    for line in body.splitlines():
        line = line.strip()
        if not line:
            continue
        if line.startswith("- "):
            if not in_list:
                html.append("<ul>")
                in_list = True
            html.append(f"<li>{escape(line[2:].strip())}</li>")
        else:
            if in_list:
                html.append("</ul>")
                in_list = False
            title = line.lstrip("#").strip()
            html.append(f"<h4>{escape(title)}</h4>")
    if in_list:
        html.append("</ul>")
    if not html:
        html.append("<p>Vylepšení a opravy.</p>")
    style = "<style>body{font-family:-apple-system,sans-serif;font-size:13px;line-height:1.45}h4{margin:12px 0 4px}ul{padding-left:18px;margin:4px 0}li{margin:2px 0}</style>"
    return style + "".join(html)


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
    p.add_argument("--changelog", default="CHANGELOG.md")
    a = p.parse_args()

    sig = re.search(r'sparkle:edSignature="([^"]+)"', a.sign_output)
    length = re.search(r'length="(\d+)"', a.sign_output)
    if not sig or not length:
        raise SystemExit(f"Nepodařilo se přečíst podpis z výstupu sign_update: {a.sign_output!r}")

    base = f"https://github.com/{a.repo}"
    pub_date = format_datetime(datetime.now(timezone.utc), usegmt=True)  # RFC 2822, nezávislé na locale

    notes = notes_html(a.changelog, a.version).replace("]]>", "]]&gt;")

    xml = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>{escape(a.app)}</title>
    <item>
      <title>Version {escape(a.version)}</title>
      <sparkle:version>{escape(a.build)}</sparkle:version>
      <sparkle:shortVersionString>{escape(a.version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{escape(a.min_os)}</sparkle:minimumSystemVersion>
      <description><![CDATA[{notes}]]></description>
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
