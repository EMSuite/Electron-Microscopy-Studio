#!/bin/zsh
# Builds Vendor/Sparkle/Sparkle.xcframework, the updater the website download links (#761): Sparkle at the pinned tag
# (tools/lib/sparkle-pin.sh), archived as Sparkle's own Configurations/make-xcframework.sh archives the framework of its Swift
# Package Manager zip, with one override: SPARKLE_NORMALIZE_INSTALLED_APPLICATION_NAME=1 (Configurations/ConfigCommon.xcconfig,
# 0 upstream). With it, Sparkle's installer moves an updated app to <SUBundleName>.app, so a copy installed as macEM.app becomes
# "Electron Microscopy Studio.app" on its next update (SUBundleName, macTEM/Info-Direct.plist, #759). The installer that runs
# is the installed app's own, so the rename happens on the update after the first release that carries this build. Sparkle's
# note on the flag: turn it off again once the rename is done (Vendor/Sparkle/README.md says how).
#
#   tools/build-sparkle.sh [output folder]      default: Vendor/Sparkle
#
# Writes <output>/Sparkle.xcframework and <output>/build-info.txt (the tag, the commit, the override, the Xcode, and the SHA-256
# of every file in the framework, which tools/run-tests.sh inventory checks against the tree). No dSYMs: each file stays
# under 1 MiB, and nobody symbolicates Sparkle's helpers. Signed ad hoc, as Sparkle's project signs a local build; Xcode signs
# the framework when it embeds it, and tools/release.sh signs each helper with the Developer ID. GitHub's macOS runner builds
# it (.github/workflows/sparkle.yml, on a branch that changes the pin or this script), and its artifact is what gets committed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tools/lib/developer-dir.sh"
resolve_mactem_developer_dir
. "$ROOT/tools/lib/sparkle-pin.sh"

OUT="${1:-$ROOT/Vendor/Sparkle}"
OVERRIDE=SPARKLE_NORMALIZE_INSTALLED_APPLICATION_NAME
WORK="$(mktemp -d "${TMPDIR:-/tmp}/sparkle-build.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
fail() { echo "build-sparkle: $*" >&2; exit 1; }

echo "== Sparkle $SPARKLE_TAG"
git clone --quiet --depth 1 --branch "$SPARKLE_TAG" https://github.com/sparkle-project/Sparkle "$WORK/src" 2> "$WORK/clone.log" \
  || { cat "$WORK/clone.log" >&2; fail "could not clone Sparkle $SPARKLE_TAG"; }
[[ "$(git -C "$WORK/src" rev-parse HEAD)" == "$SPARKLE_COMMIT" ]] \
  || fail "tag $SPARKLE_TAG is $(git -C "$WORK/src" rev-parse HEAD), not $SPARKLE_COMMIT (tools/lib/sparkle-pin.sh)"

echo "== Archive with $OVERRIDE=1"
# A build setting on the command line wins over every xcconfig, for every target the scheme builds: the framework, Autoupdate,
# Updater.app and the two XPC services.
xcodebuild archive -project "$WORK/src/Sparkle.xcodeproj" -scheme Sparkle -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$WORK/Sparkle.xcarchive" -derivedDataPath "$WORK/DerivedData" \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES SKIP_INSTALL=NO "$OVERRIDE=1" > "$WORK/archive.log" 2>&1 \
  || { tail -40 "$WORK/archive.log" >&2; fail "the archive failed"; }

# The override, read from the compiler's own command lines: each file that reads the flag was compiled with 1, and nothing with 0.
# xcodebuild logs a define as `-D<name>\=<value>`, on the command line or in the response file (`@<path>.resp`) it names.
compiled_with() { # compiled_with <source> <value>
  local resp
  grep -F -- "/$1" "$WORK/archive.log" | grep -E -- "-D$OVERRIDE\\\\?=$2" > /dev/null && return 0
  for resp in ${(f)"$(grep -F -- "/$1" "$WORK/archive.log" | grep -oE -- '@[^ ]+\.resp' | cut -c2- | sort -u || true)"}; do
    [[ -f "$resp" ]] && grep -E -- "-D$OVERRIDE\\\\?=$2" "$resp" > /dev/null && return 0
  done
  return 1
}
for src in Autoupdate/SUInstaller.m Autoupdate/SUPlainInstaller.m Sparkle/InstallerProgress/InstallerProgressAppController.m; do
  if ! compiled_with "$src" 1; then
    echo "build-sparkle: the log's lines for $src:" >&2
    grep -F -- "/$src" "$WORK/archive.log" | cut -c1-1500 | head -6 >&2
    fail "$src was not compiled with -D$OVERRIDE=1"
  fi
done
if { cat "$WORK/archive.log"; find "$WORK/DerivedData" -name '*.resp' -exec cat {} + 2> /dev/null; } | grep -E -- "-D$OVERRIDE\\\\?=0" > /dev/null; then
  fail "a file was compiled with -D$OVERRIDE=0"
fi

FRAMEWORK="$WORK/Sparkle.xcarchive/Products/Library/Frameworks/Sparkle.framework"
[[ -d "$FRAMEWORK" ]] || fail "the archive holds no Library/Frameworks/Sparkle.framework"
for helper in Versions/B/Autoupdate Versions/B/Updater.app Versions/B/XPCServices/Installer.xpc Versions/B/XPCServices/Downloader.xpc; do
  [[ -e "$FRAMEWORK/$helper" ]] || fail "the framework has no $helper"
done

echo "== XCFramework"
xcodebuild -create-xcframework -framework "$FRAMEWORK" -output "$WORK/Sparkle.xcframework" > "$WORK/xcframework.log" 2>&1 \
  || { cat "$WORK/xcframework.log" >&2; fail "xcodebuild -create-xcframework failed"; }

mkdir -p "$OUT"
rm -rf "$OUT/Sparkle.xcframework"
ditto "$WORK/Sparkle.xcframework" "$OUT/Sparkle.xcframework"
{
  echo "# Written by tools/build-sparkle.sh; tools/run-tests.sh inventory checks it against the tree. Rebuild, never edit."
  echo "tag $SPARKLE_TAG"
  echo "commit $SPARKLE_COMMIT"
  echo "override $OVERRIDE=1"
  echo "xcode $(xcodebuild -version | tr '\n' ' ' | sed 's/ *$//')"
  if [[ -n "${GITHUB_RUN_ID:-}" ]]; then
    echo "built ${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
  else
    echo "built locally"
  fi
  (cd "$OUT" && find Sparkle.xcframework -type f | LC_ALL=C sort | while IFS= read -r f; do
    echo "sha256 $(shasum -a 256 "$f" | cut -d' ' -f1) $f"
  done)
} > "$OUT/build-info.txt"

echo "== Built"
sed -n '2,6p' "$OUT/build-info.txt"
xcrun dwarfdump --uuid "$OUT"/Sparkle.xcframework/*/Sparkle.framework/Versions/B/Autoupdate \
  "$OUT"/Sparkle.xcframework/*/Sparkle.framework/Versions/B/Updater.app/Contents/MacOS/Updater
echo "$OUT/Sparkle.xcframework"
