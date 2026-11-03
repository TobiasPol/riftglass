#!/usr/bin/env bash
# Subscribes to the specific topics AND the catch-all "OnJsonApiEvent" and prints, per event,
# which topic delivered it and its URI – shows whether the specific topic names are valid.
source "$(dirname "$0")/lib.sh"
load_lcu
LCU_TOPICS="OnJsonApiEvent,OnJsonApiEvent_lol-gameflow_v1_gameflow-phase,OnJsonApiEvent_lol-champ-select_v1_session" \
  swift "$(dirname "$0")/09-record-events.swift" "${1:-120}" \
  | jq -c --unbuffered 'if .[0] == 8 then [.[1], .[2].eventType, .[2].uri] else . end' \
  | grep --line-buffered -E 'gameflow|champ-select|^\[0' | tee "$SPIKE_OUT/topics.log"
