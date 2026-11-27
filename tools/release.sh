#!/bin/zsh
# Builds the Electron Microscopy Studio download: archive, Developer ID signature, notarized and stapled app, then a signed, notarized and
# stapled DMG. the owner runs it on the Mac with the certificate; it pushes nothing and uploads nothing to GitHub.
#
#   tools/release.sh
#
# Needs the "Developer ID Application" certificate in the login keychain (DEVELOPER_ID_APPLICATION overrides its name; the
# built app's signature is checked against that name) and a notarytool keychain profile (default macem-notary; override
# with NOTARY_PROFILE). Output: build/release/<stamp>/Electron-Microscopy-Studio-<version>.dmg and a copy named
# Electron-Microscopy-Studio.dmg for the "latest" link. From 2.6.1 no copies under the old app names are made.
# The steps follow mac4DSTEM's tools/release (build-developer-id.sh, notarize.sh, make-dmg.sh, appcast.sh); the DMG here
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
# The app's name (Config/Version.xcconfig; "Electron Microscopy Studio" since 2.1.1, #759); the DMGs take it with hyphens,
# as the repository does, so a download URL has no spaces.
NAME="$(sed -n 's/^MACEM_APP_NAME_NO = //p' "$ROOT/Config/Version.xcconfig")"
[[ -n "$NAME" ]] || { echo "Config/Version.xcconfig sets no MACEM_APP_NAME_NO." >&2; exit 1; }
FILE="${NAME// /-}"
ARCHIVE="$OUT/$FILE.xcarchive"
APP="$ARCHIVE/Products/Applications/$NAME.app"
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
# project's CURRENT_PROJECT_VERSION does not move between releases. The packages are cloned to build/SourcePackages, apart
# from any other checkout's.
xcodebuild archive -project "$ROOT/EMStudio.xcodeproj" -scheme EMStudio -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" ARCHS=arm64 \
  -clonedSourcePackagesDirPath "$ROOT/build/SourcePackages" CURRENT_PROJECT_VERSION="$EXPECTED" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" OTHER_CODE_SIGN_FLAGS="--timestamp" > "$OUT/archive.log" 2>&1 \
  || { tail -30 "$OUT/archive.log"; exit 1; }

echo "== Sign the updater"
# Sparkle (#583), the download's updater: Vendor/Sparkle's build, which renames an updated macEM.app (#761). Its helpers (the
# installer and downloader services, Autoupdate, Updater.app) come signed ad hoc; the archive copies the framework without
# signing inside it. First, the helpers must be that build: each one's Mach-O UUIDs as in Vendor/Sparkle (signing and Xcode's
# copy change the bytes, never the UUIDs), so a project that went back to the stock package cannot ship unnoticed. Each helper is
# signed here with the Developer ID, the hardened runtime and a timestamp, inside out, as Sparkle's documentation says for a
# build that is not exported by Xcode; the downloader keeps its own entitlements. Then the app again, keeping its
# entitlements, because its seal covers the framework. As mac4DSTEM's tools/release/build-developer-id.sh does.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
[[ -d "$SPARKLE" ]] || { echo "The download has no Sparkle.framework (the updater, #583)." >&2; exit 1; }
VENDOR=("$ROOT"/Vendor/Sparkle/Sparkle.xcframework/macos-*/Sparkle.framework(N))
(( ${#VENDOR} == 1 )) || { echo "Vendor/Sparkle holds no one macOS Sparkle.framework (tools/build-sparkle.sh, #761)." >&2; exit 1; }
for helper in Versions/B/Autoupdate Versions/B/Updater.app/Contents/MacOS/Updater \
    Versions/B/XPCServices/Installer.xpc/Contents/MacOS/Installer Versions/B/XPCServices/Downloader.xpc/Contents/MacOS/Downloader; do
  # The arm64 slice's UUID: the download is arm64, whether or not the copy kept the framework's other slice.
  shipped="$(xcrun dwarfdump --uuid --arch arm64 "$SPARKLE/$helper" 2>/dev/null | awk '{ print $2 }')"
  vendored="$(xcrun dwarfdump --uuid --arch arm64 "${VENDOR[1]}/$helper" 2>/dev/null | awk '{ print $2 }')"
  [[ -n "$vendored" && "$shipped" == "$vendored" ]] \
    || { echo "The download's Sparkle $helper is not Vendor/Sparkle's build (the app-name rename, #761)." >&2; exit 1; }
done
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
# The sandboxed installer is reached through the download's one exception (EMStudio-Direct.entitlements).
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
echo "$NAME $VERSION"

echo "== Notarize the app"
ditto -c -k --keepParent "$APP" "$OUT/$FILE-submission.zip"
xcrun notarytool submit "$OUT/$FILE-submission.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute "$APP"

echo "== DMG"
DMG="$OUT/$FILE-$VERSION.dmg"
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$NAME.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$NAME $VERSION" -srcfolder "$STAGE" -format UDZO -ov "$DMG" > /dev/null
codesign --sign "$IDENTITY" --timestamp "$DMG"

echo "== Notarize the DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature "$DMG"
cp "$DMG" "$OUT/$FILE.dmg"

echo "== Update feed (Sparkle, #583)"
"$ROOT/tools/appcast.sh" "$DMG" "$VERSION" "$OUT/macem.xml"

echo
echo "Done: $DMG"
echo "Also: $OUT/$FILE.dmg (for releases/latest/download/$FILE.dmg)"
echo "SHA-256: $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
echo "Size: $(stat -f%z "$DMG") bytes"
echo "Feed: $OUT/macem.xml (commit it to the website as appcast/macem.xml once the DMGs are on the release)"
