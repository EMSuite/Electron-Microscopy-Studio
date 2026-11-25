#!/bin/zsh
# tools/parity/size-table/measure.sh: the size table's whole run (#904, plan row X12), one size at a time so the disk holds one size's files:
# write the six generated files of that size, measure each through the agent door (size_table.py), delete them, go on.
#
#   tools/parity/size-table/measure.sh --app <path to the .app> [--sizes 1,4,16] [--kinds image-tiff,...]
#
# The harness holds the cap itself: it ends the app by its pid when its footprint passes this Mac's memory minus 4 GB (the size
# rule's margin) and writes that row. An outer memory guard, if one is used, should be looser (memory minus 2 GB), since such a
# guard sums resident pages over the whole tree, mapped file pages included, and ends the harness too.
#
# Sizes are whole GB. Each size's files are deleted when it is measured, and on any exit (a trap), so no 16 GB file stays behind.
#
# The Agent folder (Settings > Agents) must be $TMPDIR/size-table, the folder the files are written to; the door token in
# $TMPDIR/door-token as tools/door/README.md (suite) says. Python: the reference venv (tools/lib/python.sh) writes the files,
# the system python3 runs the harness. The rows land in $TMPDIR/size-table-out/<size>gb/table.md for docs/performance.md.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$ROOT/tools/lib/python.sh"
resolve_mactem_python "$ROOT"
app=""
sizes="1,4,16"
kinds="image-tiff,image-mrc,stack-tiff,eels-hspy,eds-hspy,patterns-h5"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) app="$2"; shift 2 ;;
    --sizes) sizes="$2"; shift 2 ;;
    --kinds) kinds="$2"; shift 2 ;;
    *) echo "run.sh: unknown option $1" >&2; exit 2 ;;
  esac
done
[[ -n "$app" ]] || { echo "run.sh: --app is needed" >&2; exit 2; }
folder="${TMPDIR%/}/size-table"
out="${TMPDIR%/}/size-table-out"
mkdir -p "$folder" "$out"
rc=0
trap 'rm -f -- "$folder"/*gb.(tif|mrc|hspy|h5)(N)' EXIT INT TERM HUP
for size in ${(s:,:)sizes}; do
  [[ "$size" == <-> ]] || { echo "run.sh: sizes are whole GB, not $size" >&2; exit 2; }
  "$PYTHON_BIN" -I -B "$ROOT/tools/parity/size-table/make_files.py" "$folder" --gb "$size" --kinds "$kinds"
  files=("$folder"/*-${size}gb.*)
  python3 -I -B "$ROOT/tools/parity/size-table/size_table.py" --app "$app" --agent-folder "$folder" --out "$out/${size}gb" "${files[@]}" || rc=$?
  rm -f -- "${files[@]}"
done
cat "$out"/*gb/table.md
exit $rc
