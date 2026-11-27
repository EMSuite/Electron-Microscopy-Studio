#!/bin/bash
# tools/check-old-names.sh — no sentence on screen names the app by an old name (#759).
#
# The app is "Electron Microscopy Studio" in both builds since 2.1.1; up to 2.1.0 the website download was macEM, up to 1.3
# macTEM, and the sibling app is "4DSTEM Studio" (was mac4DSTEM). A sentence on screen takes the name from AppName.display.
# This fails on a Swift string literal in EMStudio/ or Sources/ that names macEM, macTEM or mac4DSTEM, unless the line holds a
# fragment that tools/old-names.allow lists: what a written file says about its writer (provenance the readers rely on), the
# bundle identifier, and names that are never shown. Comment lines are skipped. Plain grep, no build.
# Exit 0 clean, 1 on a violation, 2 when the allowlist is missing or a row has no reason.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ALLOW="$ROOT/tools/old-names.allow"
[ -f "$ALLOW" ] || { echo "old-names: $ALLOW missing" >&2; exit 2; }
cd "$ROOT" || exit 2

# Allowlist rows: fragment<TAB>reason.
rows="$(grep -vE '^[[:space:]]*(#|$)' "$ALLOW")"
fragments="$(mktemp)"
trap 'rm -f "$fragments"' EXIT
while IFS=$'\t' read -r fragment reason; do
  [ -n "$fragment" ] || continue
  [ -n "${reason:-}" ] || { echo "old-names: allowlist row without a reason: $fragment" >&2; exit 2; }
  printf '%s\n' "$fragment" >> "$fragments"
done <<< "$rows"

hits="$(git grep -n -I -E '"[^"]*(macEM|macTEM|mac4DSTEM)[^"]*"' -- 'EMStudio/*.swift' 'Sources/*.swift' \
  | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' \
  | grep -v -F -f "$fragments")"
if [ -n "$hits" ]; then
  echo "$hits"
  echo
  echo "old-names: the lines above name the app by an old name. A sentence on screen uses AppName.display (\"Electron Microscopy"
  echo "Studio\"); the sibling app is \"4DSTEM Studio\". A file's provenance that must keep the old name goes in tools/old-names.allow."
  exit 1
fi
echo "old-names: no old app name in a string on screen"
