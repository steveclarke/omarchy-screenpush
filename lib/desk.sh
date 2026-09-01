#!/usr/bin/env bash
# Desk file reading. Pure jq; knows nothing about DDC.

# The fingerprint of the desk in front of us: every serial present, sorted,
# joined with '+'. Sorting matters because ddcutil's order is not stable
# across boots, and an unstable key would make a known desk look new.
desk_key() {
  present_serials | sort | paste -sd '+' -
}

# The stored object for a desk key, or the string "null".
#
# Exact key match first, which is the ordinary case. Failing that, the stored
# desk whose monitors are a SUPERSET of what is present, preferring the one
# with the fewest extras.
#
# The fallback is not a nicety. desk_key is built from the monitors answering
# DDC, and a monitor that is switched off at the wall stops answering entirely
# - so a desk with one dark panel produces a shorter key that matches nothing,
# and the menu would report a brand-new unconfigured desk and offer no
# computers at all. Someone who turns one screen off overnight would find the
# plugin empty in the morning. Matching on subset keeps the desk recognised,
# and `current` still returns null because the dark panel's input is genuinely
# unknowable.
desk_json() {
  [ -f "$DESKS" ] || { echo "null"; return 0; }
  jq -c --arg k "$1" '
    ($k | split("+") | map(select(length > 0))) as $present
    | if ($present | length) == 0 then null
      elif (.desks[$k] // null) != null then .desks[$k]
      else
        ( [ .desks | to_entries[]
            | (.key | split("+")) as $serials
            | select((($present - $serials) | length) == 0)
            | { extras: ((($serials - $present)) | length), desk: .value } ]
          | sort_by(.extras) | first ) as $match
        | if $match == null then null else $match.desk end
      end' "$DESKS" 2>/dev/null || echo "null"
}
