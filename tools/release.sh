#!/bin/zsh
# Builds the macEM download: archive, Developer ID signature, notarized and stapled app, then a signed, notarized and
# stapled DMG. the owner runs it on the Mac with the certificate; it pushes nothing and uploads nothing to GitHub.
#
#   tools/release.sh
#
# Needs the "Developer ID Application" certificate in the login keychain (DEVELOPER_ID_APPLICATION overrides its name; the
# built app's signature is checked against that name) and a notarytool keychain profile (default macem-notary; override
# with NOTARY_PROFILE). Output: build/release/<stamp>/macEM-<version>.dmg and a copy named macEM.dmg for the "latest"
# link. The steps follow mac4DSTEM's tools/release (build-developer-id.sh, notarize.sh, make-dmg.sh, appcast.sh); the DMG here
# is a plain hdiutil image with an Applications link, no dmgbuild. Last, macem.xml, the website's update feed (tools/appcast.sh,
# #583), signed with the EdDSA key in the login keychain.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tools/lib/developer-dir.sh"
. "$ROOT/tools/lib/release-checks.sh"
resolve_mactem_developer_dir

IDENTITY="${DEVELOPER_ID_APPLICATION:-Developer ID Application: Paul Lobpreis (3B8SMSSAX4)}"
PROFILE="${NOTARY_PROFILE:-macem-notary}"
OUT="$ROOT/build/release/$(date +%Y%m%d-%H%M%S)"   # a new folder per run, so a rerun never deletes an earlier archive
ARCHIVE="$OUT/macEM.xcarchive"
APP="$ARCHIVE/Products/Applications/macEM.app"
mkdir -p "$OUT"

[[ -z "$(git -C "$ROOT" status --porcelain)" ]] || { echo "The working tree is not clean; commit first so the build has a commit." >&2; exit 1; }
security find-identity -v -p codesigning | grep -q "$IDENTITY" || { echo "No certificate \"$IDENTITY\" in the keychain." >&2; exit 1; }
# A download is built from a release tag, and the app must carry that tag's version (Config/Version.xcconfig, which
# release-please bumps): checked here before the archive and again on the built app.
TAG="$(git -C "$ROOT" describe --exact-match --tags HEAD 2>/dev/null)" || { echo "HEAD is not a release tag; check out the tag to build (git worktree add … vX.Y.Z)." >&2; exit 1; }
EXPECTED="${TAG#v}"
SET="$(sed -n 's/^MARKETING_VERSION = \([0-9.]*\).*/\1/p' "$ROOT/Config/Version.xcconfig")"
[[ "$SET" == "$EXPECTED" ]] || { echo "Config/Version.xcconfig says $SET but the tag is $TAG." >&2; exit 1; }

echo "== Archive ($(git -C "$ROOT" rev-parse --short HEAD))"
# ARCHS=arm64 on the command line: the project's setting does not reach the package targets, and the HDF5
# frameworks FormatoKit embeds are arm64 only (mac4DSTEM tools/lib/release-arch.sh has the story).
# The download's build number is its version (#583): Sparkle compares the feed's sparkle:version with CFBundleVersion, and the
# project's CURRENT_PROJECT_VERSION does not move between releases. The packages are cloned to build/SourcePackages so
# tools/appcast.sh finds Sparkle's sign_update at one path.
xcodebuild archive -project "$ROOT/macTEM.xcodeproj" -scheme macTEM -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" ARCHS=arm64 \
  -clonedSourcePackagesDirPath "$ROOT/build/SourcePackages" CURRENT_PROJECT_VERSION="$EXPECTED" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" OTHER_CODE_SIGN_FLAGS="--timestamp" > "$OUT/archive.log" 2>&1 \
  || { tail -30 "$OUT/archive.log"; exit 1; }

echo "== Sign the updater"
# Sparkle (#583), the download's updater. The package ships its helpers (the installer and downloader services, Autoupdate,
# Updater.app) signed by the Sparkle project; the archive copies the framework without signing inside it. Each helper is
# signed here with the Developer ID, the hardened runtime and a timestamp, inside out, as Sparkle's documentation says for a
# build that is not exported by Xcode; the downloader keeps its own entitlements. Then the app again, keeping its
# entitlements, because its seal covers the framework. As mac4DSTEM's tools/release/build-developer-id.sh does.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
[[ -d "$SPARKLE" ]] || { echo "The download has no Sparkle.framework (the updater, #583)." >&2; exit 1; }
KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist" 2>/dev/null || true)"
[[ -n "$KEY" && "$KEY" != SET-BEFORE-RELEASE ]] || { echo "The download has no public EdDSA key (SUPublicEDKey in Info-Direct.plist)." >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")" == "$EXPECTED" ]] \
  || { echo "The download's build number is not its version." >&2; exit 1; }
sign_nested() { codesign --force --sign "$IDENTITY" --options runtime --timestamp "$@"; }
for helper in "$SPARKLE"/Versions/B/XPCServices/Installer.xpc "$SPARKLE"/Versions/B/Autoupdate "$SPARKLE"/Versions/B/Updater.app; do
  [[ -e "$helper" ]] || { echo "Sparkle has no ${helper#$SPARKLE/}." >&2; exit 1; }
  sign_nested "$helper"
done
[[ ! -e "$SPARKLE/Versions/B/XPCServices/Downloader.xpc" ]] \
  || sign_nested --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
sign_nested "$SPARKLE"
sign_nested --preserve-metadata=entitlements,requirements,flags "$APP"
for signed in "$SPARKLE" "$SPARKLE"/Versions/B/XPCServices/Installer.xpc "$SPARKLE"/Versions/B/Autoupdate "$SPARKLE"/Versions/B/Updater.app; do
  details="$(codesign -dvv "$signed" 2>&1)"
  [[ "$details" == *"Authority=$IDENTITY"* && "$details" == *"(runtime)"* && "$details" == *"Timestamp="* ]] \
    || { echo "$signed is not signed with the Developer ID, the hardened runtime and a timestamp." >&2; exit 1; }
done
# The sandboxed installer is reached through the download's one exception (macTEM-Direct.entitlements).
codesign -d --entitlements :- "$APP" > "$OUT/entitlements.plist" 2>/dev/null
/usr/libexec/PlistBuddy -c 'Print :com.apple.security.temporary-exception.mach-lookup.global-name' "$OUT/entitlements.plist" \
  | grep -q -- '-spki' || { echo "The download cannot reach Sparkle's installer (mach-lookup exception)." >&2; exit 1; }

echo "== Check the app"
# The executable and the three HDF5 frameworks, each by name, and the shipped demo files (tools/lib/release-checks.sh).
assert_mactem_bundle_arm64_only "$APP"
assert_mactem_demo_data "$APP"
# What notarization refuses, found before the upload instead of after it: the app and each of the three frameworks signed by the
# Developer ID certificate, with the hardened runtime and a secure timestamp.
assert_mactem_bundle_developer_id_signed "$APP" "$IDENTITY"
codesign --verify --deep --strict "$APP"
codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q "get-task-allow" && { echo "The app carries get-task-allow." >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[[ "$VERSION" == "$EXPECTED" ]] || { echo "The built app says $VERSION but the tag is $TAG." >&2; exit 1; }
echo "macEM $VERSION"

echo "== Notarize the app"
ditto -c -k --keepParent "$APP" "$OUT/macEM-submission.zip"
xcrun notarytool submit "$OUT/macEM-submission.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute "$APP"

echo "== DMG"
DMG="$OUT/macEM-$VERSION.dmg"
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/macEM.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "macEM $VERSION" -srcfolder "$STAGE" -format UDZO -ov "$DMG" > /dev/null
codesign --sign "$IDENTITY" --timestamp "$DMG"

echo "== Notarize the DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature "$DMG"
cp "$DMG" "$OUT/macEM.dmg"
# Up to 1.3 the app was macTEM and its DMG macTEM.dmg: the 2.x releases attach a copy under that name too, so the links and
# bookmarks to releases/latest/download/macTEM.dmg keep working.
cp "$DMG" "$OUT/macTEM.dmg"

echo "== Update feed (Sparkle, #583)"
"$ROOT/tools/appcast.sh" "$DMG" "$VERSION" "$OUT/macem.xml"

echo
echo "Done: $DMG"
echo "Also: $OUT/macEM.dmg (for releases/latest/download/macEM.dmg)"
echo "And:  $OUT/macTEM.dmg (the name up to 1.3; attach it too in 2.x)"
echo "SHA-256: $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
echo "Size: $(stat -f%z "$DMG") bytes"
echo "Feed: $OUT/macem.xml (commit it to the website as appcast/macem.xml once the DMGs are on the release)"
