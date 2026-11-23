#!/usr/bin/env bash
# Self-test of tools/lib/fetch-public-data.sh (#807): on a planted manifest of file:// URLs, a file whose sha256 or md5 matches is
# fetched and named with its sha256, a second run fetches nothing, `--check` passes; a hash that does not match fails, leaves no
# file and no .part behind; `--check` fails on a missing file; a line without a licence or DOI, with an unknown hash kind, or with
# a destination outside the folder fails before anything is fetched. Last, the repo's own manifest is well formed and its first
# entry is the 2.3 demo pattern's source (#804). Needs no network; the inventory runs it on every push, and so does the
# public-data workflow before it fetches.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
fetch="$here/fetch-public-data.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/fetch-public-data-selftest.XXXXXX")"
trap 'rm -rf "$work"' EXIT
out=""
fail() { echo "fetch-public-data-selftest: $1"; printf '%s\n' "$out"; exit 1; }
sha256_of() { if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
md5_of() { if command -v md5sum >/dev/null; then md5sum "$1" | cut -d' ' -f1; else md5 -q "$1"; fi; }

mkdir -p "$work/src" "$work/data"
printf 'a pattern\n' > "$work/src/a.bin"
printf 'a structure\n' > "$work/src/b.cif"
a256="$(sha256_of "$work/src/a.bin")"; bmd5="$(md5_of "$work/src/b.cif")"
T=$'\t'
good() {
  printf '# planted\n'
  printf 'x/a.bin%ssha256:%s%sfile://%s/src/a.bin%sCC-BY-4.0%s10.5281/zenodo.1\n' "$T" "$a256" "$T" "$work" "$T" "$T"
  printf 'b.cif%smd5:%s%sfile://%s/src/b.cif%sCC-BY-4.0%s10.5281/zenodo.2\n' "$T" "$bmd5" "$T" "$work" "$T" "$T"
}
good > "$work/good.tsv"

# A matching sha256 and a matching md5: both fetched, each named with its sha256.
out="$("$fetch" "$work/good.tsv" "$work/data" 2>&1)" || fail "a manifest whose hashes match must fetch"
[[ -f "$work/data/x/a.bin" && -f "$work/data/b.cif" ]] || fail "the files are not at their destinations"
[[ "$out" == *"ok       x/a.bin  sha256 $a256  CC-BY-4.0  doi:10.5281/zenodo.1"* ]] || fail "a fetched file is not named with its sha256"
[[ "$out" == *"fetching x/a.bin"* && "$out" == *"fetching b.cif"* ]] || fail "the first run does not fetch both files"
out="$("$fetch" "$work/good.tsv" "$work/data" 2>&1)" || fail "a second run must pass"
[[ "$out" != *fetching* ]] || fail "a second run fetches a file whose hash already matches"
out="$("$fetch" --check "$work/good.tsv" "$work/data" 2>&1)" || fail "--check must pass with every file present"

# A hash that does not match: the run fails and nothing is left at the destination.
sed "s/sha256:$a256/sha256:$(printf '0%.0s' {1..64})/" "$work/good.tsv" > "$work/wrong.tsv"
rm -rf "$work/data2"
out="$("$fetch" "$work/wrong.tsv" "$work/data2" 2>&1)" && fail "a hash that does not match must fail the run"
[[ "$out" == *"MISMATCH x/a.bin"* ]] || fail "the mismatch is not named"
[[ ! -e "$work/data2/x/a.bin" && ! -e "$work/data2/x/a.bin.part" ]] || fail "a file that did not match is left behind"
[[ -f "$work/data2/b.cif" ]] || fail "one mismatch stops the other files"

# --check on a missing file.
rm -f "$work/data/b.cif"
out="$("$fetch" --check "$work/good.tsv" "$work/data" 2>&1)" && fail "--check must fail on a missing file"
[[ "$out" == *"MISSING  b.cif"* ]] || fail "--check does not name the missing file"
[[ ! -e "$work/data/b.cif" ]] || fail "--check fetched a file"

# Malformed lines fail before anything is fetched.
malformed() {  # <what> <line>
  { good; printf '%s\n' "$2"; } > "$work/bad.tsv"
  rm -rf "$work/data3"
  out="$("$fetch" "$work/bad.tsv" "$work/data3" 2>&1)" && fail "$1 must fail"
  [[ "$out" == *"line 4:"* ]] || fail "$1 is not named by its line"
  [[ ! -e "$work/data3" ]] || fail "$1: a file was fetched before the manifest was read"
}
malformed "a line without a DOI" "c.bin${T}sha256:$a256${T}file://$work/src/a.bin${T}CC-BY-4.0"
malformed "a line without a licence" "c.bin${T}sha256:$a256${T}file://$work/src/a.bin${T}${T}10.5281/zenodo.3"
malformed "a sha1 hash" "c.bin${T}sha1:0123456789012345678901234567890123456789${T}file://$work/src/a.bin${T}CC-BY-4.0${T}10.5281/zenodo.3"
malformed "a destination outside the folder" "../c.bin${T}sha256:$a256${T}file://$work/src/a.bin${T}CC-BY-4.0${T}10.5281/zenodo.3"
malformed "a plain http URL" "c.bin${T}sha256:$a256${T}http://example.org/c.bin${T}CC-BY-4.0${T}10.5281/zenodo.3"
malformed "a DOI that is a URL" "c.bin${T}sha256:$a256${T}file://$work/src/a.bin${T}CC-BY-4.0${T}https://doi.org/10.5281/zenodo.3"

# An empty manifest is not a pass.
printf '# nothing\n' > "$work/empty.tsv"
out="$("$fetch" --lint "$work/empty.tsv" 2>&1)" && fail "a manifest with no file must not pass"

# The repo's manifest: well formed, and its first entry is the 2.3 demo pattern's source.
out="$("$fetch" --lint 2>&1)" || fail "tools/public-data.tsv is not well formed"
first="$(grep -v '^#' "$here/../public-data.tsv" | grep -v '^$' | head -1 | cut -f1,5)"
[[ "$first" == "pyxem/twinned_nanowire.hdf5${T}10.5281/zenodo.15490547" ]] \
  || fail "the manifest's first entry is not pyxem's twinned nanowire scan (DOI 10.5281/zenodo.15490547): $first"

echo "fetch-public-data-selftest: ok"
