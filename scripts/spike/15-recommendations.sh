#!/usr/bin/env bash
# Riot's own recommendations exposed by the LCU (fallback build source). Works in lobby.
# Usage: 15-recommendations.sh [championId=103] [position=middle]
source "$(dirname "$0")/lib.sh"
load_lcu
champ="${1:-103}" pos="${2:-middle}"
echo "-- endpoints mentioning 'recommend' (from /help)"
lcu GET '/help?format=Console' | sed '$d' | grep -ioE '[a-z/{}_-]*recommend[a-z/{}_-]*' | sort -u | head -30
echo "-- recommended rune pages"
out="$(lcu GET "/lol-perks/v1/recommended-pages/champion/$champ/position/$pos/map/11")"
echo "HTTP $(tail -n1 <<<"$out")"
# Keep only IDs/names – descriptions are long localized texts.
sed '$d' <<<"$out" | anonymize | jq '[.[] | .perks |= map({id, name, styleId}) | .keystone |= {id, name}]' \
  >"$FIXTURES/lcu/recommended-pages.json"
jq -c '.[]? | {keystone: .keystone.name?, primaryPerkStyleId, secondaryPerkStyleId, summonerSpellIds, perkIds: [.perks[]?.id]}' \
  "$FIXTURES/lcu/recommended-pages.json" | head -5
