#!/usr/bin/env bash
# Live Client Data API (port 2999) – only reachable while a game is running.
# Records anonymized fixtures for the endpoints Riftglass polls (never `allgamedata`).
source "$(dirname "$0")/lib.sh"
for endpoint in activeplayer playerlist gamestats activeplayername; do
  out="$(curl -sk --max-time 3 -w '\n%{http_code}' "https://127.0.0.1:2999/liveclientdata/$endpoint")" || true
  code="$(tail -n1 <<<"$out")"
  printf '%-4s %s\n' "$code" "$endpoint"
  [[ "$code" == 200 ]] || continue
  if [[ "$endpoint" == activeplayername ]]; then # bare JSON string = the player's Riot ID
    echo '"anon#EUW"' >"$FIXTURES/liveclient/$endpoint.json"
  else
    sed '$d' <<<"$out" | anonymize >"$FIXTURES/liveclient/$endpoint.json"
  fi
done
