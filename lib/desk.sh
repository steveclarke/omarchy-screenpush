#!/usr/bin/env bash
# Desk file reading and desk identity.
#
# Not standalone: desk_key() calls present_serials(), which lives in
# bin/monitor-input. Source this from there, not on its own.

# The fingerprint of the desk in front of us: every serial present, sorted,
# joined with '+'. Sorting matters because ddcutil's order is not stable
# across boots, and an unstable key would make a known desk look new.
desk_key() {
  present_serials | sort | paste -sd '+' -
}

# The stored object for a desk key, or the string "null".
#
# Exact key match first, which is the ordinary case. Failing that, among
# stored desks that share at least one serial with what is present, the one
# with the largest overlap - preferring, on a tie, the one with the fewest
# extras (stored serials that are not present).
#
# The fallback is not a nicety. desk_key is built from the monitors answering
# DDC, and that set moves in both directions: a monitor switched off at the
# wall stops answering (the key shrinks), and a monitor plugged in for the
# first time starts answering (the key grows). Either way an exact-key match
# fails, and requiring the stored desk to be a superset of what is present -
# the old rule - only covered the first direction. Someone who plugs in a
# third screen would find the desk "unknown", lose every computer and every
# input mapping, and have setup save a second entry under the new key while
# the original sat there orphaned. Matching on overlap covers both
# directions at once: `current` still returns null for any monitor that
# genuinely is not present, because that monitor's input is unknowable, but
# the desk itself - its computers, its labels - is not lost just because the
# hardware in front of it changed shape.
desk_json() {
  [ -f "$DESKS" ] || { echo "null"; return 0; }
  jq -c --arg k "$1" '
    ($k | split("+") | map(select(length > 0))) as $present
    | if ($present | length) == 0 then null
      elif (.desks[$k] // null) != null then .desks[$k]
      else
        ( [ .desks | to_entries[]
            | (.key | split("+")) as $serials
            | ($serials - ($serials - $present)) as $common
            | select(($common | length) > 0)
            | { common: ($common | length),
                extras: ((($serials - $present)) | length),
                desk: .value } ]
          | sort_by([-.common, .extras]) | first ) as $match
        | if $match == null then null else $match.desk end
      end' "$DESKS" 2>/dev/null || echo "null"
}
