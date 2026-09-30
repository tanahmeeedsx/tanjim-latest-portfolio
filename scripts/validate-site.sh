#!/usr/bin/env bash
set -euo pipefail

SITE_DIR="${1:-site}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

[[ -d "$SITE_DIR" ]] || fail "Site directory not found: $SITE_DIR"
[[ -s "$SITE_DIR/index.html" ]] || fail "Missing or empty $SITE_DIR/index.html"
[[ -s "$SITE_DIR/resume.pdf" ]] || fail "Missing or empty $SITE_DIR/resume.pdf"

grep -Eqi '<!doctype html>' "$SITE_DIR/index.html" || fail "index.html is missing <!DOCTYPE html>"
grep -Eqi '<html([[:space:]>])' "$SITE_DIR/index.html" || fail "index.html is missing <html>"
grep -Eqi '</html>' "$SITE_DIR/index.html" || fail "index.html is missing </html>"

# The current portfolio intentionally links to the local resume.
grep -Eq "href=[\"']resume\\.pdf[\"']" "$SITE_DIR/index.html" || fail "index.html does not link to resume.pdf"

# Catch accidental macOS metadata in deployable content.
if find "$SITE_DIR" -name '.DS_Store' -o -name '__MACOSX' | grep -q .; then
  fail "macOS metadata found under $SITE_DIR"
fi

echo "Site validation passed."
