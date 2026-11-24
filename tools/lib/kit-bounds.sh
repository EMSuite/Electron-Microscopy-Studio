# tools/lib/kit-bounds.sh — each package's lower bound equals the version built (#806, plan row P13 of 2.3). Sourced by
# tools/run-tests.sh; tools/lib/kit-bounds-selftest.sh checks it (the inventory runs that on every push).
#
# The app takes the kits and MacEMUI by `from:` range in Package.swift and Sparkle by an up-to-next-major requirement in the Xcode
# project; the two Package.resolved files hold the versions built. A lower bound below the resolved version claims the app builds
# with a kit it was never built or tested with, so each bound must equal the resolved version exactly, in every Package.resolved
# that pins the package. A package update (`chore(deps):`) therefore moves the bound and the pin together.
#
# kit_bounds <Package.swift> <Package.resolved> <project.pbxproj> <workspace Package.resolved>: prints one line per package checked
# and one per mismatch; exits 1 on a mismatch, on a package whose requirement is not a `from:` range or an up-to-next-major
# minimum, on a package no Package.resolved pins, or when it read no package at all. Plain POSIX awk: macOS's awk runs it, and so
# does Linux's mawk.
kit_bounds() {
  local swift="$1" resolved="$2" pbxproj="$3" workspace="$4" f
  for f in "$swift" "$resolved" "$pbxproj" "$workspace"; do
    [[ -r "$f" ]] || { echo "  NOT CHECKED  cannot read $f"; return 1; }
  done
  # "identity version" per pin: the identity is SwiftPM's (the URL's last part, lower case, without .git).
  local pins_root pins_ws
  pins_root="$(awk -F'"' '/"identity"/ { id = $4 } /"version" *: *"/ { print id, $4 }' "$resolved")"
  pins_ws="$(awk -F'"' '/"identity"/ { id = $4 } /"version" *: *"/ { print id, $4 }' "$workspace")"
  # "where identity bound" per requirement: Package.swift's `.package(url:` lines, then the project's remote references.
  local wants
  wants="$(
    awk '/\.package\(url:/ {
           url = $0; sub(/.*url: *"/, "", url); sub(/".*/, "", url)
           id = url; sub(/.*\//, "", id); sub(/\.git$/, "", id); id = tolower(id)
           if (match($0, /, from: *"[0-9][0-9.]*"/)) { v = substr($0, RSTART, RLENGTH); gsub(/[^0-9.]/, "", v) }
           else v = "-"
           print "Package.swift", id, v
         }' "$swift"
    awk '/isa = XCRemoteSwiftPackageReference;/ { inref = 1; url = ""; kind = ""; min = ""; next }
         inref && /repositoryURL = / { url = $0; sub(/.*repositoryURL = "?/, "", url); sub(/"?;.*/, "", url) }
         inref && /kind = / { kind = $0; sub(/.*kind = /, "", kind); sub(/;.*/, "", kind) }
         inref && /minimumVersion = / { min = $0; sub(/.*minimumVersion = "?/, "", min); sub(/"?;.*/, "", min) }
         inref && /^[[:space:]]*};[[:space:]]*$/ && url != "" && kind != "" {
           id = url; sub(/.*\//, "", id); sub(/\.git$/, "", id); id = tolower(id)
           print "project", id, (kind == "upToNextMajorVersion" && min != "" ? min : "-")
           inref = 0
         }' "$pbxproj"
  )"
  local rc=0 n=0 where id bound got file pins found bad
  while read -r where id bound; do
    [[ -n "$id" ]] || continue
    n=$(( n + 1 ))
    if [[ "$bound" == "-" ]]; then
      echo "  $where takes $id by a requirement other than a lower bound (from: / up to next major)"; rc=1; continue
    fi
    found=0 bad=0
    for file in root workspace; do
      if [[ "$file" == root ]]; then pins="$pins_root"; else pins="$pins_ws"; fi
      # The project's own references live only in the workspace's file; Package.swift's packages are in both.
      [[ "$where" == project && "$file" == root ]] && continue
      got="$(awk -v id="$id" '$1 == id { print $2; exit }' <<< "$pins")"
      [[ -n "$got" ]] || continue
      found=1
      if [[ "$got" != "$bound" ]]; then
        echo "  $id: $where's lower bound is $bound, the $file Package.resolved pins $got"; bad=1; rc=1
      fi
    done
    if (( found )); then (( bad )) || echo "  $id $bound"; else echo "  $id: $where requires it and no Package.resolved pins it"; rc=1; fi
  done <<< "$wants"
  (( n > 0 )) || { echo "  NOT CHECKED  no package requirement read"; return 1; }
  return $rc
}
