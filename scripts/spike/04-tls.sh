#!/usr/bin/env bash
# Certificates presented by the LCU (app-port) and the Live Client API (2999).
source "$(dirname "$0")/lib.sh"
show() { # show <label> <port>
  local label="$1" port="$2" pem="$SPIKE_OUT/$1.pem"
  echo "== $label (127.0.0.1:$port)"
  if ! openssl s_client -connect "127.0.0.1:$port" -showcerts </dev/null 2>/dev/null \
      | awk '/BEGIN CERT/,/END CERT/' >"$pem" || [[ ! -s "$pem" ]]; then
    echo "  no TLS listener"; return
  fi
  echo "  certs in chain: $(grep -c 'BEGIN CERT' "$pem")"
  openssl x509 -in "$pem" -noout -subject -issuer -dates -ext subjectAltName,basicConstraints 2>&1 | sed 's/^/  /'
  if [[ -f "$SPIKE_OUT/riotgames.pem" ]]; then
    echo "  verify against riotgames.pem (no hostname check):"
    openssl verify -CAfile "$SPIKE_OUT/riotgames.pem" -partial_chain "$pem" 2>&1 | sed 's/^/    /'
  fi
}
load_lcu
show lcu "$LCU_PORT"
show liveclient 2999
