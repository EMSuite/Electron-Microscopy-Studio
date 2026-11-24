#!/usr/bin/env bash
# tools/lib/fetch-public-data.sh — download each file of a public-data manifest and check its hash (#807, plan row P14 of 2.3).
#   fetch-public-data.sh [manifest] [destination]      fetch what is missing or wrong; default tools/public-data.tsv into
#                                                        References/public-data (gitignored)
#   fetch-public-data.sh --check [manifest] [dest]     verify only: exit 1 when a file is missing or its hash is wrong
#   fetch-public-data.sh --lint [manifest]             every line well formed (five fields, a known hash kind, a licence, a DOI)
# Every line is read before anything is fetched: a malformed line fails the run with its line number and nothing is downloaded.
# A file whose hash already matches is not fetched again. A download is written to <name>.part and moved into place only once
# its hash matches, so a wrong or cut-off file never sits at the destination. Each file's sha256 is printed, so an `md5:` line
# can be pinned to sha256. Plain bash 3.2 and curl: macOS's own bash runs it, and so do GitHub's Linux runners
# (.github/workflows/public-data.yml). tools/lib/fetch-public-data-selftest.sh checks it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
mode=fetch
case "${1:-}" in --check) mode=check; shift ;; --lint) mode=lint; shift ;; esac
manifest="${1:-$ROOT/tools/public-data.tsv}"
dest_root="${2:-$ROOT/References/public-data}"

sha256_of() { if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
md5_of() { if command -v md5sum >/dev/null; then md5sum "$1" | cut -d' ' -f1; else md5 -q "$1"; fi; }
# hash_of <kind> <file>
hash_of() { if [[ "$1" == sha256 ]]; then sha256_of "$2"; else md5_of "$2"; fi; }

[[ -r "$manifest" ]] || { echo "fetch-public-data: cannot read $manifest" >&2; exit 2; }

# Pass 1: every line well formed, before any download.
bad=0 n=0 lineno=0
while IFS= read -r line || [[ -n "$line" ]]; do
  lineno=$(( lineno + 1 ))
  [[ -z "$line" || "$line" == \#* ]] && continue
  IFS=$'\t' read -r dest hash url licence doi extra <<< "$line"
  why=""
  if [[ -z "${doi:-}" || -n "${extra:-}" ]]; then why="not five tab-separated fields (destination, hash, URL, licence, DOI)"
  elif [[ "$dest" == /* || "$dest" == *..* ]]; then why="destination $dest is not a path below the data folder"
  elif ! [[ "$hash" =~ ^sha256:[0-9a-f]{64}$ || "$hash" =~ ^md5:[0-9a-f]{32}$ ]]; then why="hash $hash is not sha256:<64 hex> or md5:<32 hex>"
  elif ! [[ "$url" =~ ^(https|file):// ]]; then why="URL $url is not https (file:// only in the self-test)"
  elif ! [[ "$doi" =~ ^10\.[0-9]+/ ]]; then why="DOI $doi is not a DOI (10.<registrant>/<suffix>)"
  fi
  if [[ -n "$why" ]]; then echo "fetch-public-data: line $lineno: $why" >&2; bad=1; continue; fi
  n=$(( n + 1 ))
done < "$manifest"
(( bad == 0 )) || exit 2
(( n > 0 )) || { echo "fetch-public-data: $manifest lists no file" >&2; exit 2; }
if [[ "$mode" == lint ]]; then echo "fetch-public-data: $n files listed, every line well formed"; exit 0; fi

# Pass 2: fetch or check.
rc=0
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" || "$line" == \#* ]] && continue
  IFS=$'\t' read -r dest hash url licence doi <<< "$line"
  kind="${hash%%:*}" want="${hash#*:}" path="$dest_root/$dest"
  if [[ -f "$path" && "$(hash_of "$kind" "$path")" == "$want" ]]; then
    echo "fetch-public-data: ok       $dest  sha256 $(sha256_of "$path")  $licence  doi:$doi"; continue
  fi
  if [[ "$mode" == check ]]; then
    if [[ -f "$path" ]]; then echo "fetch-public-data: WRONG    $dest: its $kind is not $want"; else echo "fetch-public-data: MISSING  $dest"; fi
    rc=1; continue
  fi
  mkdir -p "$(dirname "$path")"
  echo "fetch-public-data: fetching $dest <- $url"
  rm -f "$path.part"
  if ! curl -sSfL --retry 4 --retry-delay 2 -o "$path.part" "$url"; then
    echo "fetch-public-data: FAILED   $dest: the download did not complete" >&2; rm -f "$path.part"; rc=1; continue
  fi
  have="$(hash_of "$kind" "$path.part")"
  if [[ "$have" != "$want" ]]; then
    echo "fetch-public-data: MISMATCH $dest: $kind want $want, got $have" >&2; rm -f "$path.part"; rc=1; continue
  fi
  mv -f "$path.part" "$path"
  echo "fetch-public-data: ok       $dest  sha256 $(sha256_of "$path")  $licence  doi:$doi"
done < "$manifest"
exit $rc
