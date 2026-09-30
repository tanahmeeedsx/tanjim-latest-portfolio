#!/usr/bin/env python3
"""Fail CI when index.html references a missing local asset."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit
import sys

SITE = Path(sys.argv[1] if len(sys.argv) > 1 else "site").resolve()
INDEX = SITE / "index.html"

class RefParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.refs = []

    def handle_starttag(self, tag, attrs):
        data = dict(attrs)
        for key in ("href", "src"):
            value = data.get(key)
            if value:
                self.refs.append((tag, key, value))

parser = RefParser()
parser.feed(INDEX.read_text(encoding="utf-8"))

skip_schemes = {"http", "https", "mailto", "tel", "data", "javascript"}
missing = []
for tag, key, raw in parser.refs:
    if raw.startswith("#"):
        continue
    parsed = urlsplit(raw)
    if parsed.scheme in skip_schemes or parsed.netloc:
        continue
    path = unquote(parsed.path)
    if not path or path == "/":
        continue
    target = (SITE / path.lstrip("/")).resolve()
    try:
        target.relative_to(SITE)
    except ValueError:
        missing.append((raw, "escapes site directory"))
        continue
    if not target.exists():
        missing.append((raw, str(target)))

if missing:
    print("Missing local references:")
    for raw, target in missing:
        print(f"  - {raw} -> {target}")
    sys.exit(1)

print(f"Local reference validation passed ({len(parser.refs)} href/src references checked).")
