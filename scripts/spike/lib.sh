#!/usr/bin/env bash
# Shared helpers for the spike scripts. Source, don't execute.
# Never prints the remoting auth token.
set -euo pipefail

LOL_APP="${LOL_APP:-/Applications/League of Legends.app}"
SPIKE_OUT="${SPIKE_OUT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/out}"
FIXTURES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/tests/fixtures"
mkdir -p "$SPIKE_OUT"

ux_pid() {
  pgrep -x LeagueClientUx | head -n1 || true
}

ux_args() {
  local pid
  pid="$(ux_pid)"
  [[ -z "$pid" ]] && return 1
  ps -ww -o args= -p "$pid"
}

# Values may contain spaces (install dir), so cut at the next " --" instead of the next space.
arg_value() { # arg_value <name> <args>
  grep -oE -- "--$1=.*" <<<"$2" | sed -E 's/ --[a-z].*//' | head -n1 | cut -d= -f2-
}

# --riotgamesapi-settings is base64 JSON that embeds further tokens (riotclient, rso_auth).
redact() {
  sed -E 's/(--(remoting-auth-token|riotclient-auth-token|riotgamesapi-settings)=)[^ ]+/\1<redacted>/g'
}

load_lcu() {
  local args
  if ! args="$(ux_args)"; then
    echo "LeagueClientUx is not running – start League first." >&2
    exit 2
  fi
  LCU_PORT="$(arg_value app-port "$args")"
  LCU_TOKEN="$(arg_value remoting-auth-token "$args")"
  export LCU_PORT LCU_TOKEN
}

lcu() { # lcu <METHOD> <path> [curl args...]
  local method="$1" path="$2"
  shift 2
  curl -sk -u "riot:${LCU_TOKEN}" -X "$method" -w '\n%{http_code}\n' \
    "https://127.0.0.1:${LCU_PORT}${path}" "$@"
}

# Replace personal identifiers so recordings can be committed as fixtures.
anonymize() { # anonymize [jq flags...]
  jq "$@" 'walk(
    if type == "object" then
      with_entries(
        if (.key | test("^(puuid|accountId|summonerId|gameName|tagLine|displayName|internalName|summonerName|playerId|riotId|riotIdGameName|riotIdTagLine|obfuscatedPuuid|obfuscatedSummonerId|nameVisibilityType)$"))
        then .value = (if (.value | type) == "number" then 1000 else "anon" end)
        # Credentials inside payloads, e.g. champ-select chatDetails (mucJwtDto.jwt, multiUserChatPassword).
        elif (.key | test("(?i)(jwt|password|token|secret|claim|multiUserChatId)"))
        then .value = "redacted"
        else . end)
    else . end)'
}
