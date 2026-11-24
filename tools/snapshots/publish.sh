#!/bin/bash
# publish.sh <snapshots folder> <PR number>
# Attaches the new and changed snapshot pictures of a CI run to its pull request: they go on the repo's one pr-pictures
# branch under <PR>/snapshots/ (created on first use, never merged), and one comment on the PR, kept up to date, shows
# them. A run with no new or changed picture removes nothing and says so. Needs GH_TOKEN with contents and
# pull-requests write, GITHUB_REPOSITORY and GITHUB_SHA (set by Actions). Used by .github/workflows/ci.yml.
set -euo pipefail
folder=$1 pr=$2
marker="<!-- snapshots -->"
pictures=()  # bash 3.2 (macOS): no mapfile
while IFS= read -r line; do pictures+=("$line"); done < <(cd "$folder" 2>/dev/null && find . -name '*.png' | sed 's#^\./##' | sort)
if [ ${#pictures[@]} -eq 0 ]; then echo "publish: no new or changed snapshots"; exit 0; fi

work=$(mktemp -d)
remote="https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
if ! git clone -q --depth 1 --branch pr-pictures "$remote" "$work" 2>/dev/null; then
  git init -q "$work"
  git -C "$work" checkout -q --orphan pr-pictures
  git -C "$work" remote add origin "$remote"
  printf '%s\n' "# PR pictures" "" "Pictures for pull request bodies, one folder per PR number. Never merged." > "$work/README.md"
fi
rm -rf "${work:?}/$pr/snapshots"
mkdir -p "$work/$pr/snapshots"
cp -R "$folder"/. "$work/$pr/snapshots/"
git -C "$work" add -A
git -C "$work" -c user.name="github-actions[bot]" -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
  commit -q -m "PR #$pr: snapshots of ${GITHUB_SHA:0:8}"
for attempt in 1 2 3 4; do
  git -C "$work" push -q origin HEAD:pr-pictures && break
  [ $attempt = 4 ] && { echo "publish: could not push pr-pictures"; exit 1; }
  sleep $((attempt * 3))
  git -C "$work" pull -q --rebase origin pr-pictures
done
sha=$(git -C "$work" rev-parse HEAD)

body="$marker
**Snapshots** that are new or differ from their reference at ${GITHUB_SHA:0:8} (light and dark, drawn on macos-26 at 2x). After review, commit each under \`__Snapshots__/\` beside its test.
"
for picture in "${pictures[@]}"; do
  body+="
\`$picture\`

![$picture](https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/$sha/$pr/snapshots/$picture)
"
done
id=$(gh api "repos/$GITHUB_REPOSITORY/issues/$pr/comments" --paginate \
  --jq ".[] | select(.body | startswith(\"$marker\")) | .id" | head -1)
if [ -n "$id" ]; then
  gh api -X PATCH "repos/$GITHUB_REPOSITORY/issues/comments/$id" -f body="$body" > /dev/null
else
  gh api -X POST "repos/$GITHUB_REPOSITORY/issues/$pr/comments" -f body="$body" > /dev/null
fi
echo "publish: ${#pictures[@]} pictures on pr-pictures/$pr/snapshots ($sha), comment updated"
