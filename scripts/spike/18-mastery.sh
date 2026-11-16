#!/usr/bin/env bash
# Spike 5: own champion mastery and ban actions (pick & ban options). Run with the League client open,
# ideally once in a Ranked/Normal Draft champ select during the planning or ban phase.
# Prints only counts and shapes – no names, no IDs of other players, no tokens.
source "$(dirname "$0")/lib.sh"
load_lcu
mastery="$(lcu GET /lol-champion-mastery/v1/local-player/champion-mastery)"
echo "champion-mastery: HTTP $(tail -n1 <<<"$mastery")"
sed '$d' <<<"$mastery" | jq -c 'if type == "array" then {count: length, keys: (.[0] // {} | keys)} else . end'
session="$(lcu GET /lol-champ-select/v1/session | sed '$d')"
if jq -e '.myTeam' >/dev/null 2>&1 <<<"$session"; then
  me="$(jq '.localPlayerCellId' <<<"$session")"
  jq -c '{queueId, phase: .timer.phase,
    actions: ([.actions[][] | .type] | group_by(.) | map({(.[0]): length}) | add // {})}' <<<"$session"
  echo "ban actions (actor is me / teammate / enemy, championId > 0, completed, inProgress):"
  jq -c --argjson me "$me" '[.myTeam[].cellId] as $team | [.actions[][] | select(.type == "ban")
    | .actorCellId as $actor
    | {who: (if $actor == $me then "me" elif any($team[]; . == $actor) then "team" else "enemy" end),
       champion: (.championId > 0), completed, isInProgress}]' <<<"$session"
else
  echo "Not in champ select – ban actions skipped."
fi
