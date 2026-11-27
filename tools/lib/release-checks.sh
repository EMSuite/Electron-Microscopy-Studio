#!/bin/zsh
# tools/lib/release-checks.sh — what both release scripts check on the app they built: the product, not the settings.
# Adapted from mac4DSTEM (tools/lib/release-arch.sh, assert_mac4dstem_bundle_arm64_only).
#
#   assert_mactem_bundle_arm64_only <app>      the executable, FormatoKit's three HDF5 frameworks and the two Quick Look
#                                              extensions: each there, each arm64 alone
#   assert_mactem_demo_data <app>              the four shipped demo files (DemoDocuments.Shipped) in Contents/Resources/DemoData
#   assert_mactem_store_entitlements <plist>   the store app's sandbox entitlements (com.apple.security.*): exactly these four
#   assert_mactem_store_names <app> <root>     the store app's names (Config/Version.xcconfig), none with "mac", and its identifier
#   assert_mactem_bundle_developer_id_signed <app> <identity>
#                                              the app, the three frameworks and the two extensions: each signed by the
#                                              Developer ID identity, with the hardened runtime and a secure timestamp
#
# tools/release.sh calls the first two and the last, tools/release-store.sh the first three (its package is signed for the store,
# not with Developer ID). Each prints one line per failure and returns non-zero after checking everything, so a caller under
# `set -e` and one in an `if` stop alike. No counter is called `status`, which zsh aliases to `$?`.
#
# The three frameworks are named, not globbed. The loop this replaces took them from a brace expansion with zsh's (N) qualifier,
# which drops a path that does not exist, so an app that had lost a framework passed (the store script checked none by name).
# FormatoKit loads libhdf5 at run time rather than linking it: such an app launches, then fails every HDF5, EMD and h5ebsd open.
# mac4DSTEM's release-arch.sh records the same defect. The demo files are named for the same reason: Help > Open Demo Data opens
# nothing, and says nothing, when one is missing (EMStudio/App/DemoData.swift).
#
# The store check reads only the com.apple.security.* keys: automatic signing adds com.apple.application-identifier and
# com.apple.developer.team-identifier from the profile. They are the five of EMStudio/EMStudio.entitlements (AppStoreReleaseTests
# holds the two lists together); network.client reaches the Materials Project and nothing else (#778, docs/app-store/app-privacy.txt),
# and network.server is the agent door's loopback listener. The Developer ID build signs with EMStudio-Direct.entitlements (these plus the updater's installer exception, #583) and is not held to the exact set.

# Fails unless $1 is a Mach-O holding arm64 and nothing else.
assert_mactem_arm64_only() {  # <Mach-O>
  local archs
  archs="$(lipo -archs "$1" 2>/dev/null || true)"
  if [[ "$archs" != arm64 ]]; then
    echo "Not arm64 alone: $1 is '${archs:-unreadable}'." >&2
    return 1
  fi
}

# Every Mach-O a user receives: the executable and the three frameworks, each named.
# The app extensions every build embeds in Contents/PlugIns (#903: Quick Look's thumbnail and preview).
MACTEM_EXTENSIONS=(QuickLookThumbnail QuickLookPreview)

assert_mactem_bundle_arm64_only() {  # <app>
  local app="$1" library arch_failures=0
  # The executable is named after the app ("Electron Microscopy Studio" since 2.1.1; macEM before): read it.
  local exe
  exe="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist" 2>/dev/null)"
  [[ -n "$exe" ]] || { echo "$app/Contents/Info.plist names no executable." >&2; return 1; }
  assert_mactem_arm64_only "$app/Contents/MacOS/$exe" || arch_failures=1
  for library in FormatoLibHDF5 FormatoLibSZ FormatoLibAEC; do
    if [[ ! -f "$app/Contents/Frameworks/$library.framework/$library" ]]; then
      echo "The app is missing $library.framework." >&2
      arch_failures=1
      continue
    fi
    assert_mactem_arm64_only "$app/Contents/Frameworks/$library.framework/$library" || arch_failures=1
  done
  # The two Quick Look extensions (#903), each by name.
  for extension in "${MACTEM_EXTENSIONS[@]}"; do
    if [[ ! -f "$app/Contents/PlugIns/$extension.appex/Contents/MacOS/$extension" ]]; then
      echo "The app is missing $extension.appex." >&2
      arch_failures=1
      continue
    fi
    assert_mactem_arm64_only "$app/Contents/PlugIns/$extension.appex/Contents/MacOS/$extension" || arch_failures=1
  done
  return $arch_failures
}

# The demo files Help > Open Demo Data opens, each named and not empty.
assert_mactem_demo_data() {  # <app>
  local app="$1" file demo_failures=0
  for file in nickel_ebsd_large/patterns_v2.h5 EDS_SEM_TM002.hspy ni_mc_mp_20kv_uint8_gzip_opts9.h5 sdss_ferrite_austenite.ang twinned_nanowire_frame.hspy silicon_Fd-3m.cif gallium_arsenide_F-43m.cif; do
    if [[ ! -s "$app/Contents/Resources/DemoData/$file" ]]; then
      echo "The app is missing its demo file DemoData/$file." >&2
      demo_failures=1
    fi
  done
  return $demo_failures
}

# The store app's com.apple.security.* entitlements, as `codesign -d --entitlements :-` wrote them to $1: exactly the five below,
# each true.
assert_mactem_store_entitlements() {  # <entitlements plist>
  local plist="$1" key keys entitlement_failures=0
  local -a expected=(com.apple.security.app-sandbox com.apple.security.files.bookmarks.app-scope com.apple.security.files.user-selected.read-write com.apple.security.network.client com.apple.security.network.server)
  keys="$(plutil -convert xml1 -o - "$plist" 2>/dev/null \
    | sed -nE 's#^[[:space:]]*<key>(com\.apple\.security\.[^<]+)</key>[[:space:]]*$#\1#p' | LC_ALL=C sort | tr '\n' ' ' || true)"
  keys="${keys% }"
  if [[ "$keys" != "${expected[*]}" ]]; then
    echo "The store app's sandbox entitlements are [$keys], not [${expected[*]}]." >&2
    entitlement_failures=1
  fi
  for key in "${expected[@]}"; do
    if [[ "$(/usr/libexec/PlistBuddy -c "Print :$key" "$plist" 2>/dev/null)" != true ]]; then
      echo "The store app's $key is not true." >&2
      entitlement_failures=1
    fi
  done
  return $entitlement_failures
}

# Fails unless $1, an app or a framework, is signed by the identity $2 with the hardened runtime and a secure timestamp, as
# `codesign -dvv` reports them: the certificate's name on an Authority line, `(runtime)` among the flags, a Timestamp line (a
# signature without a secure timestamp has a "Signed Time" line in its place). Adapted from mac4DSTEM
# (tools/release/build-developer-id.sh, check_signed), which holds the frameworks to all three as well: the archive signs every
# piece with the app's settings. Notarization refuses a download that lacks them, but only after the upload; this names the piece
# and the mark before it.
assert_mactem_developer_id_signed() {  # <app or framework> <identity>
  local details sign_failures=0
  details="$(codesign -dvv "$1" 2>&1 || true)"
  if [[ "$details" != *"Authority=$2"* ]]; then
    echo "Not signed by $2: $1." >&2
    sign_failures=1
  fi
  if [[ "$details" != *"(runtime)"* ]]; then
    echo "Not signed with the hardened runtime: $1." >&2
    sign_failures=1
  fi
  if [[ "$details" != *"Timestamp="* ]]; then
    echo "No secure timestamp: $1." >&2
    sign_failures=1
  fi
  return $sign_failures
}

# Every signed piece of the download: the app and the three frameworks, each named. A framework that is not there is
# assert_mactem_bundle_arm64_only's to report; here its signature cannot be read and each mark fails.
assert_mactem_bundle_developer_id_signed() {  # <app> <identity>
  local app="$1" identity="$2" library bundle_sign_failures=0
  assert_mactem_developer_id_signed "$app" "$identity" || bundle_sign_failures=1
  for library in FormatoLibHDF5 FormatoLibSZ FormatoLibAEC; do
    assert_mactem_developer_id_signed "$app/Contents/Frameworks/$library.framework" "$identity" || bundle_sign_failures=1
  done
  for extension in "${MACTEM_EXTENSIONS[@]}"; do
    assert_mactem_developer_id_signed "$app/Contents/PlugIns/$extension.appex" "$identity" || bundle_sign_failures=1
  done
  return $bundle_sign_failures
}

# The App Store build's names (guideline 5.2.5: no "Mac" in an App Store app's name), as Config/Version.xcconfig sets them, under
# the unchanged bundle identifier. Prints each failure; returns 1 on any.
assert_mactem_store_names() {  # <app> <root>
  local app="$1" root="$2" failures=0 key want got
  for key in CFBundleDisplayName:MACEM_APP_NAME_YES CFBundleExecutable:MACEM_APP_NAME_YES CFBundleName:MACEM_MENU_NAME_YES; do
    want="$(sed -n "s/^${key#*:} = //p" "$root/Config/Version.xcconfig")"
    got="$(/usr/libexec/PlistBuddy -c "Print :${key%%:*}" "$app/Contents/Info.plist" 2>/dev/null || true)"
    [[ -n "$want" && "$got" == "$want" ]] || { echo "  NAME      ${key%%:*} is '$got', Config/Version.xcconfig says '$want'" >&2; failures=1; }
    [[ "${got:l}" != *mac* ]] || { echo "  NAME      ${key%%:*} '$got' contains \"mac\" (guideline 5.2.5)" >&2; failures=1; }
  done
  got="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null || true)"
  [[ "$got" == com.mac4dstem.macTEM ]] || { echo "  BUNDLEID  the store app is '$got'; App Store updates need com.mac4dstem.macTEM" >&2; failures=1; }
  return $failures
}
