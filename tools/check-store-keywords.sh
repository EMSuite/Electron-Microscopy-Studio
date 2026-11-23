#!/bin/bash
# The App Store keyword line (docs/app-store/keywords.txt) must stay within 100 characters and repeat no word of the app's
# name or subtitle: Apple indexes those already, so a repeated word wastes keyword space. Words are compared whole,
# case-insensitively, so "TEM" in the subtitle does not rule out "HRTEM". Fails with the offending keyword.
# Usage: tools/check-store-keywords.sh [directory holding keywords.txt, name.txt, subtitle.txt]
set -euo pipefail
dir="${1:-$(cd "$(dirname "$0")/.." && pwd)/docs/app-store}"
rc=0
keywords="$(cat "$dir/keywords.txt")"
count="$(printf '%s' "$keywords" | wc -m | tr -d ' ')"
if (( count > 100 )); then echo "keywords.txt: $count characters, the limit is 100"; rc=1; fi
used=" $( (cat "$dir/name.txt"; echo; cat "$dir/subtitle.txt"; echo) | tr 'A-Z' 'a-z' | tr -c 'a-z0-9\n' ' ' | tr -s ' \n' '  ') "
IFS=',' read -ra list <<< "$keywords"
for kw in "${list[@]}"; do
  for word in $(printf '%s' "$kw" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9\n' ' '); do
    if [[ "$used" == *" $word "* ]]; then echo "keywords.txt: \"$kw\" repeats \"$word\" from the name or subtitle"; rc=1; fi
  done
done
if [[ "$keywords" == *", "* || "$keywords" == *" ,"* ]]; then echo "keywords.txt: no spaces around the commas"; rc=1; fi
(( rc == 0 )) && echo "keywords.txt: $count / 100, no word of the name or subtitle"
exit $rc
