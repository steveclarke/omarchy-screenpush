#!/usr/bin/env bash
# Desk file reading. Pure jq; knows nothing about DDC.

# The fingerprint of the desk in front of us: every serial present, sorted,
# joined with '+'. Sorting matters because ddcutil's order is not stable
# across boots, and an unstable key would make a known desk look new.
desk_key() {
  present_serials | sort | paste -sd '+' -
}

# The stored object for a desk key, or the string "null".
desk_json() {
  [ -f "$DESKS" ] || { echo "null"; return 0; }
  jq -c --arg k "$1" '.desks[$k] // null' "$DESKS" 2>/dev/null || echo "null"
}
