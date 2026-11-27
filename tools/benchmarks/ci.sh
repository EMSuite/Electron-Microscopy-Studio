#!/bin/bash
# The Audit workflow's nightly CPU benchmark (.github/workflows/audit.yml, the suite's app template): runs
# EMStudioTests/BenchmarkTests (open, the FFT spectrum, EDS Quantify, the EELS Run, Hough indexing, on generated data) and
# writes the cases to $1 as a JSON list of {name, dtype, size, ms: [median]}. Each case is already a median of a few runs;
# the job compares it with the previous night's and lists one more than 25 % slower.
#
#   tools/benchmarks/ci.sh <out.json>
#
# The test is skipped unless MACTEM_BENCHMARKS=1 reaches it; xcodebuild hands a TEST_RUNNER_ variable to the test runner
# without its prefix. -O as tools/run-tests.sh unit builds (the kits' hot loops are about 20x slower at -Onone).
set -euo pipefail
[ $# -eq 1 ] || { echo "usage: tools/benchmarks/ci.sh <out.json>" >&2; exit 2; }
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
out="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

rc=0
TEST_RUNNER_MACTEM_BENCHMARKS=1 xcodebuild test -project "$ROOT/EMStudio.xcodeproj" -scheme EMStudio \
  -configuration Debug -destination 'platform=macOS' -derivedDataPath "$work/DerivedData" \
  -only-testing:EMStudioTests/BenchmarkTests/testTheNightlyBenchmarks -parallel-testing-enabled NO \
  -testLanguage en -testRegion US SWIFT_OPTIMIZATION_LEVEL=-O CODE_SIGNING_ALLOWED=NO > "$work/bench.log" 2>&1 || rc=$?
grep -E "MACTEM_BENCH |error:|: error|\) failed |skipped|TEST (SUCCEEDED|FAILED)" "$work/bench.log" | tail -40 || true
if [ "$rc" -ne 0 ]; then echo "benchmarks: xcodebuild exit $rc"; tail -30 "$work/bench.log"; exit 1; fi

python3 -I - "$work/bench.log" "$out" <<'PY'
import json, re, sys
rows = []
for line in open(sys.argv[1], errors="replace"):
    m = re.search(r"MACTEM_BENCH name=(.+?) dtype=(\S+) size=(\S+) ms=([0-9.]+)", line)
    if m:
        rows.append({"name": m.group(1), "dtype": m.group(2), "size": m.group(3), "ms": [float(m.group(4))]})
if len(rows) != 5:
    sys.exit(f"expected 5 MACTEM_BENCH lines, found {len(rows)} (was the test skipped?)")
json.dump(rows, open(sys.argv[2], "w"), indent=1)
print(f"{len(rows)} cases written to {sys.argv[2]}")
PY
