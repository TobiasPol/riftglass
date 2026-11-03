#!/usr/bin/env bash
# LCU view of the running game: teams with PUUIDs (for loading-screen ranks) + one ranked lookup.
source "$(dirname "$0")/lib.sh"
load_lcu
session="$(lcu GET /lol-gameflow/v1/session | sed '$d')"
jq -c '{phase, teamOne: [.gameData.teamOne[]? | keys], teamTwo: (.gameData.teamTwo | length)}' <<<"$session" | cut -c1-400
anonymize <<<"$session" >"$FIXTURES/lcu/gameflow-session.json"
puuid="$(jq -r '.gameData.teamTwo[0].puuid // empty' <<<"$session")"
[[ -n "$puuid" ]] && lcu GET "/lol-ranked/v1/ranked-stats/$puuid" | tail -n1 | sed 's/^/ranked-stats for enemy puuid: HTTP /'
