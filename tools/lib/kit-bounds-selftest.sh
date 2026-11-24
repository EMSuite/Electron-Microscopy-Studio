#!/bin/zsh
# Self-test of tools/lib/kit-bounds.sh (#806): on planted manifests, bounds equal to both Package.resolved files pass and name each
# package once; a Package.swift bound below the root pin fails, and so does one below the workspace pin only; Sparkle's project
# minimum below the workspace pin fails; a requirement that is not a lower bound (exact:, .upToNextMinor) fails; a package no
# Package.resolved pins fails; a manifest with no package is "NOT CHECKED", never a pass. Needs no build; the inventory runs it on
# every push.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/kit-bounds.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/kit-bounds-selftest.XXXXXX")"
trap 'rm -rf "$work"' EXIT
out=""
fail() { echo "kit-bounds-selftest: $1"; print -r -- "$out"; exit 1; }

# A Package.resolved pinning each "identity version" given.
resolved() {
  local file="$1"; shift
  { echo '{'; echo '  "originHash" : "0",'; echo '  "pins" : ['
    local pin
    for pin in "$@"; do
      echo '    {'; echo "      \"identity\" : \"${pin%% *}\","; echo '      "kind" : "remoteSourceControl",'
      echo "      \"location\" : \"https://github.com/x/${pin%% *}\","; echo '      "state" : {'
      echo '        "revision" : "0123456789abcdef0123456789abcdef01234567",'; echo "        \"version\" : \"${pin#* }\""
      echo '      }'; echo '    },'
    done
    echo '  ],'; echo '  "version" : 3'; echo '}'; } > "$file"
}
# A project file whose one remote reference is Sparkle with the given kind and minimum.
project() {
  cat > "$work/project.pbxproj" <<PBX
/* Begin XCRemoteSwiftPackageReference section */
		B00000000000000000000182 /* XCRemoteSwiftPackageReference "Sparkle" */ = {
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/sparkle-project/Sparkle";
			requirement = {
				kind = $1;
				minimumVersion = $2;
			};
		};
/* End XCRemoteSwiftPackageReference section */
PBX
}
# A Package.swift taking FormatoKit and MacEMUI with the requirements given.
manifest() {
  cat > "$work/Package.swift" <<SWIFT
    dependencies: [
        .package(url: "https://github.com/EMSuite/FormatoKit", $1),
        .package(url: "https://github.com/EMSuite/EMSuiteUI.git", $2),
    ],
SWIFT
}
check() { kit_bounds "$work/Package.swift" "$work/root.resolved" "$work/project.pbxproj" "$work/ws.resolved"; }

# Green: every bound equals every pin of it.
manifest 'from: "0.18.1"' 'from: "1.0.0"'
project upToNextMajorVersion 2.10.1
resolved "$work/root.resolved" "formatokit 0.18.1" "emsuiteui 1.0.0"
resolved "$work/ws.resolved" "formatokit 0.18.1" "emsuiteui 1.0.0" "sparkle 2.10.1"
out="$(check)" || fail "bounds equal to every pin must pass"
[[ "$out" == $'  formatokit 0.18.1\n  emsuiteui 1.0.0\n  sparkle 2.10.1' ]] || fail "the green run does not name each package once with its bound"

# A bound below the root pin (a release took the newer kit, the range was left behind).
manifest 'from: "0.18.0"' 'from: "1.0.0"'
out="$(check)" && fail "a lower bound below the root pin must fail"
[[ "$out" == *"formatokit: Package.swift's lower bound is 0.18.0, the root Package.resolved pins 0.18.1"* ]] \
  || fail "the root mismatch is not named"

# A bound equal to the root pin and below the workspace pin (the Xcode build would take another version).
manifest 'from: "0.18.1"' 'from: "1.0.0"'
resolved "$work/ws.resolved" "formatokit 0.18.2" "emsuiteui 1.0.0" "sparkle 2.10.1"
out="$(check)" && fail "a lower bound below the workspace pin must fail"
[[ "$out" == *"formatokit: Package.swift's lower bound is 0.18.1, the workspace Package.resolved pins 0.18.2"* ]] \
  || fail "the workspace mismatch is not named"
resolved "$work/ws.resolved" "formatokit 0.18.1" "emsuiteui 1.0.0" "sparkle 2.10.1"

# Sparkle's project minimum below its pin.
project upToNextMajorVersion 2.9.0
out="$(check)" && fail "a project minimum below its pin must fail"
[[ "$out" == *"sparkle: project's lower bound is 2.9.0, the workspace Package.resolved pins 2.10.1"* ]] \
  || fail "the project mismatch is not named"
project upToNextMinorVersion 2.10.1
out="$(check)" && fail "a project requirement that is not up to next major must fail"
[[ "$out" == *"project takes sparkle by a requirement other than a lower bound"* ]] || fail "the project's other requirement is not named"
project upToNextMajorVersion 2.10.1

# A requirement that is not a lower bound.
manifest 'exact: "0.18.1"' '.upToNextMinor(from: "1.0.0")'
out="$(check)" && fail "exact: and .upToNextMinor must fail"
[[ "$out" == *"Package.swift takes formatokit by a requirement other than a lower bound"* \
   && "$out" == *"Package.swift takes emsuiteui by a requirement other than a lower bound"* ]] || fail "the other requirements are not named"

# A package no Package.resolved pins.
manifest 'from: "0.18.1"' 'from: "1.0.0"'
resolved "$work/root.resolved" "formatokit 0.18.1"
resolved "$work/ws.resolved" "formatokit 0.18.1" "sparkle 2.10.1"
out="$(check)" && fail "a package no Package.resolved pins must fail"
[[ "$out" == *"emsuiteui: Package.swift requires it and no Package.resolved pins it"* ]] || fail "the unpinned package is not named"

# Nothing read is a check that did not run.
: > "$work/Package.swift"; : > "$work/project.pbxproj"
out="$(check)" && fail "a manifest with no package must not pass"
[[ "$out" == *"NOT CHECKED"* ]] || fail "nothing read does not say NOT CHECKED"

echo "kit-bounds-selftest: ok"
