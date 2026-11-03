#!/usr/bin/env bash
# Spike 3: queue detection. Run in a lobby or champ select of each mode (Ranked, ARAM, ARAM: Mayhem,
# Arena, League Classic, …). Prints what GameMode.classify sees and checks Riot recommendations on the
# mode's map. In game (LCU closed) it prints the Live Client's gameMode/mapNumber instead.
source "$(dirname "$0")/lib.sh"
if curl -sk --max-time 2 https://127.0.0.1:2999/liveclientdata/gamestats -o /dev/null; then
  curl -sk https://127.0.0.1:2999/liveclientdata/gamestats | jq -c '{liveGameMode: .gameMode, mapNumber}'
  exit 0
fi
load_lcu
session="$(lcu GET /lol-gameflow/v1/session | sed '$d')"
jq -c '{phase, queue: (.gameData.queue | {id, mapId, gameMode, type, description, isRanked})}' <<<"$session"
queue_id="$(jq -r '.gameData.queue.id' <<<"$session")"
map_id="$(jq -r '.gameData.queue.mapId' <<<"$session")"
jq -c '{queue: (.gameData.queue | {id, mapId, gameMode, type, description})}' <<<"$session" \
  >"$SPIKE_OUT/queue-$queue_id.json"
champ="$(lcu GET /lol-champ-select/v1/session | sed '$d' | jq -r '.queueId // empty' 2>/dev/null || true)"
[[ -n "$champ" ]] && echo "champ-select queueId: $champ"
# Ahri (103): which position/map combinations does the client answer for this mode?
for position in NONE MIDDLE; do
  lcu GET "/lol-perks/v1/recommended-pages/champion/103/position/$position/map/$map_id" | tail -n1 |
    sed "s|^|recommended-pages position=$position map=$map_id: HTTP |"
done
