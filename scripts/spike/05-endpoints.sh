#!/usr/bin/env bash
# Probe LCU endpoints (read-only) and record anonymized fixtures.
# Usage: 05-endpoints.sh            – lobby state
#        05-endpoints.sh champselect – additionally record the champ-select session
source "$(dirname "$0")/lib.sh"
load_lcu
probe() { # probe <fixture-name> <path>
  local out code body
  out="$(lcu GET "$2")"
  code="$(tail -n1 <<<"$out")"
  body="$(sed '$d' <<<"$out")"
  printf '%-4s GET %s\n' "$code" "$2"
  if [[ "$code" == 2* && -n "$1" ]]; then
    anonymize <<<"$body" >"$FIXTURES/lcu/$1.json" 2>/dev/null || echo "$body" >"$SPIKE_OUT/$1.raw"
  fi
}
probe gameflow-phase  /lol-gameflow/v1/gameflow-phase
probe current-summoner /lol-summoner/v1/current-summoner
probe perks-inventory /lol-perks/v1/inventory
probe perks-pages     /lol-perks/v1/pages
sid="$(lcu GET /lol-summoner/v1/current-summoner | sed '$d' | jq -r .summonerId)"
puuid="$(lcu GET /lol-summoner/v1/current-summoner | sed '$d' | jq -r .puuid)"
echo "-- item sets"
probe item-sets "/lol-item-sets/v1/item-sets/$sid/sets"
probe ""        "/lol-loadouts/v4/loadouts/scope/account"
echo "-- ranked"
probe ranked-stats "/lol-ranked/v1/ranked-stats/$puuid"
if [[ "${1:-}" == champselect ]]; then
  echo "-- champ select"
  probe champ-select-session /lol-champ-select/v1/session
  probe ""                   /lol-champ-select/v1/session/my-selection
fi
# Keep the fixture small: three sets are enough to test the merge.
jq '.itemSets |= .[0:3]' "$FIXTURES/lcu/item-sets.json" >"$SPIKE_OUT/is.tmp" \
  && mv "$SPIKE_OUT/is.tmp" "$FIXTURES/lcu/item-sets.json"
echo "Fixtures written to $FIXTURES/lcu (anonymized)."
