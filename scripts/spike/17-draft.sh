#!/usr/bin/env bash
# Spike 4: enemy team in draft (matchup briefing). Run in a Normal Draft or Ranked champ select, ideally
# once before and once after the enemy laners locked in. Shows what the client reveals about the enemy
# team (positions? hovers?) and records an anonymized session to $SPIKE_OUT/draft-<n>.json.
source "$(dirname "$0")/lib.sh"
load_lcu
session="$(lcu GET /lol-champ-select/v1/session | sed '$d')"
if [[ -z "$session" ]] || ! jq -e '.myTeam' >/dev/null 2>&1 <<<"$session"; then
  echo "Not in champ select." >&2
  exit 2
fi
jq -c '{queueId, phase: .timer.phase}' <<<"$session"
echo "enemy team (cellId, championId, pickIntent, assignedPosition):"
jq -c '.theirTeam[] | {cellId, championId, championPickIntent, assignedPosition}' <<<"$session"
echo "own pick in progress:"
jq -c --argjson me "$(jq '.localPlayerCellId' <<<"$session")" \
  '[.actions[][] | select(.actorCellId == $me and .type == "pick") | {completed, isInProgress}]' <<<"$session"
pickable="$(lcu GET /lol-champ-select/v1/pickable-champion-ids)"
echo "pickable-champion-ids: HTTP $(tail -n1 <<<"$pickable"), $(sed '$d' <<<"$pickable" | jq 'length') champions"
n="$(find "$SPIKE_OUT" -name 'draft-*.json' | wc -l | tr -d ' ')"
anonymize <<<"$session" >"$SPIKE_OUT/draft-$n.json"
echo "Saved $SPIKE_OUT/draft-$n.json"
