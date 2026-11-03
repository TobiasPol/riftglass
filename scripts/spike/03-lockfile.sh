#!/usr/bin/env bash
# Lockfile location, format and staleness (password redacted).
source "$(dirname "$0")/lib.sh"
args="$(ux_args || true)"
dir="$(arg_value install-directory "$args")"
for f in "${dir:+${dir%/}/lockfile}" "$LOL_APP/Contents/LoL/lockfile" \
  "/Users/Shared/Riot Games/Metadata/league_of_legends.live/league_of_legends.live.lockfile"; do
  if [[ -z "$f" || ! -f "$f" ]]; then continue; fi
  IFS=: read -r name pid port _ proto <"$f" || true  # file has no trailing newline
  alive="dead (stale)"; kill -0 "$pid" 2>/dev/null && alive="alive ($(ps -p "$pid" -o comm=))"
  echo "$f"
  echo "  name=$name pid=$pid port=$port protocol=$proto password=<redacted>  -> pid $alive"
  echo "  mtime: $(stat -f '%Sm' "$f")"
done
