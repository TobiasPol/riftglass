#!/usr/bin/env bash
# Records WAMP events for N seconds (default 90) into an anonymized JSONL fixture.
# Specific topics deliver nothing on the macOS client (see docs/SPIKE.md), so subscribe to the
# catch-all "OnJsonApiEvent" and keep only the URIs Riftglass uses.
# Start it, then enter champ select (custom game / practice tool), pick, change runes/spells.
source "$(dirname "$0")/lib.sh"
load_lcu
out="$FIXTURES/lcu/ws-events.jsonl"
LCU_TOPICS=OnJsonApiEvent swift "$(dirname "$0")/09-record-events.swift" "${1:-90}" \
  | grep --line-buffered -E '"uri":"/lol-(gameflow/v1/gameflow-phase|champ-select/v1/session)"' \
  | while IFS= read -r line; do anonymize -c <<<"$line"; done | tee "$out" | cut -c1-160
echo "Recorded $(wc -l <"$out") events to $out"
