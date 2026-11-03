#!/usr/bin/env bash
# Command-line arguments of LeagueClientUx (token redacted).
source "$(dirname "$0")/lib.sh"
args="$(ux_args)" || { echo "LeagueClientUx not running" >&2; exit 2; }
echo "PID: $(ux_pid)"
sed 's/ --/\n--/g' <<<"$args" | grep -E '^--' | redact | sort
echo
for k in app-port install-directory remoting-auth-token; do
  v="$(arg_value "$k" "$args")"
  [[ "$k" == remoting-auth-token ]] && v="${v:+<present, ${#v} chars>}"
  echo "$k => ${v:-<MISSING>}"
done
