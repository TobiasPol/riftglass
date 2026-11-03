#!/usr/bin/env bash
# Check the WAMP WebSocket handshake (subprotocol "wamp") and print the first events.
# Requires: websocat (optional). Without it only the HTTP upgrade response is shown.
source "$(dirname "$0")/lib.sh"
load_lcu
auth="$(printf 'riot:%s' "$LCU_TOKEN" | base64)"
echo "== Upgrade response"
curl -sk -i -N --http1.1 --max-time 3 -H "Authorization: Basic $auth" \
  -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' \
  -H "Sec-WebSocket-Key: $(openssl rand -base64 16)" -H 'Sec-WebSocket-Protocol: wamp' \
  "https://127.0.0.1:${LCU_PORT}/" | head -n 8 || true
