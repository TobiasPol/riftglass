#!/usr/bin/env bash
# Snapshot of rune pages + item sets, to prove that imports leave foreign data untouched.
# Usage: 12-snapshot-owned-data.sh before|after   (then: diff out/snapshot-before.txt out/snapshot-after.txt)
source "$(dirname "$0")/lib.sh"
load_lcu
sid="$(lcu GET /lol-summoner/v1/current-summoner | sed '$d' | jq -r .summonerId)"
{
  echo "# rune pages (id name current)"
  lcu GET /lol-perks/v1/pages | sed '$d' | jq -r '.[] | select(.isDeletable) | "\(.id) \(.name) \(.current)"'
  echo "# foreign item sets: count + hash"
  sets="$(lcu GET "/lol-item-sets/v1/item-sets/$sid/sets" | sed '$d')"
  foreign="$(jq -c '[.itemSets[] | select(.uid | startswith("52494654-474c-4153-53") | not)]' <<<"$sets")"
  echo "count=$(jq length <<<"$foreign") sha256=$(shasum -a 256 <<<"$foreign" | cut -d' ' -f1)"
  echo "# riftglass item sets"
  jq -r '.itemSets[] | select(.uid | startswith("52494654-474c-4153-53")) | "\(.uid) \(.title)"' <<<"$sets"
} >"$SPIKE_OUT/snapshot-${1:-now}.txt"
cat "$SPIKE_OUT/snapshot-${1:-now}.txt"
