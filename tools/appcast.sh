#!/bin/zsh
# Writes the update feed for one download (#583, as mac4DSTEM#122): tools/appcast.sh <notarized DMG> <version> <out.xml>
#
# The website serves the feed at https://mac4dstem.com/appcast/macem.xml (the app's SUFeedURL, macTEM/Info-Direct.plist), so
# the file this writes is committed to the website repo as appcast/macem.xml in the same PR that sets the download's
# version and size. One item, the newest release: Sparkle needs only that. The DMG is signed with Sparkle's sign_update,
# which reads the private EdDSA key from the login keychain (macOS asks once to allow it); the key never leaves the Mac.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DMG="$1" VERSION="$2" FEED="$3"
# sign_update from the pinned tag's official Swift Package Manager zip, held to the checksum Sparkle's Package.swift states for it
# (tools/lib/sparkle-pin.sh): the binary SwiftPM fetched while the app linked that package. The app's own Sparkle is built from
# source (Vendor/Sparkle, #761), and signing a DMG does not depend on how the framework was built.
. "$ROOT/tools/lib/sparkle-pin.sh"
TOOLS="$ROOT/build/sparkle-tools/$SPARKLE_TAG"
SIGN_UPDATE="$TOOLS/bin/sign_update"
if [[ ! -x "$SIGN_UPDATE" ]]; then
  mkdir -p "$TOOLS"
  curl -fsSL -o "$TOOLS/spm.zip" "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_TAG/Sparkle-for-Swift-Package-Manager.zip" \
    || { echo "Could not download Sparkle $SPARKLE_TAG's Swift Package Manager zip." >&2; exit 1; }
  [[ "$(shasum -a 256 "$TOOLS/spm.zip" | cut -d' ' -f1)" == "$SPARKLE_SPM_ZIP_SHA256" ]] \
    || { echo "Sparkle $SPARKLE_TAG's zip does not match the checksum in tools/lib/sparkle-pin.sh." >&2; rm -f "$TOOLS/spm.zip"; exit 1; }
  ditto -x -k "$TOOLS/spm.zip" "$TOOLS"
  rm -f "$TOOLS/spm.zip"
fi
[[ -x "$SIGN_UPDATE" ]] || { echo "No $SIGN_UPDATE in Sparkle $SPARKLE_TAG's zip." >&2; exit 1; }

# sign_update prints the enclosure's two attributes: sparkle:edSignature="…" length="…".
ATTRIBUTES="$("$SIGN_UPDATE" "$DMG")"
[[ "$ATTRIBUTES" == *'sparkle:edSignature="'*'length="'* ]] || { echo "sign_update printed no signature: $ATTRIBUTES" >&2; exit 1; }
FLOOR="$(grep -m1 'MACOSX_DEPLOYMENT_TARGET = ' "$ROOT/macTEM.xcodeproj/project.pbxproj" | sed 's/.*= \(.*\);/\1/')"

# The release notes: this version's CHANGELOG section as plain text (headings and links reduced to their words).
/usr/bin/python3 -I - "$ROOT/CHANGELOG.md" "$VERSION" "$FLOOR" "$ATTRIBUTES" "$FEED" <<'PY'
import re, sys
from email.utils import formatdate
from xml.sax.saxutils import escape
changelog, version, floor, attributes, feed = sys.argv[1:]
lines, inside = [], False
for line in open(changelog, encoding="utf-8"):
    if line.startswith("## "):
        if inside:
            break
        inside = re.match(r"## \[?" + re.escape(version) + r"\]?[ (]", line + " ") is not None
        continue
    if inside:
        line = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", line)
        line = re.sub(r"^#+ ", "", line).replace("**", "")
        lines.append(line.rstrip())
notes = "\n".join(lines).strip()
if not notes:
    sys.exit(f"CHANGELOG.md has no section for {version}")
tag = f"v{version}"
item = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Electron Microscopy Studio</title>
    <link>https://mac4dstem.com/mactem/</link>
    <item>
      <title>Electron Microscopy Studio {version}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{version}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{floor}</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://github.com/EMSuite/Electron-Microscopy-Studio/releases/tag/{tag}</sparkle:fullReleaseNotesLink>
      <description sparkle:format="plain-text">{escape(notes)}</description>
      <enclosure url="https://github.com/EMSuite/Electron-Microscopy-Studio/releases/download/{tag}/Electron-Microscopy-Studio-{version}.dmg" type="application/octet-stream" {attributes}/>
    </item>
  </channel>
</rss>
"""
open(feed, "w", encoding="utf-8").write(item)
PY
echo "$FEED"
