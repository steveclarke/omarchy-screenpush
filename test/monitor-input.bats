#!/usr/bin/env bats

load fixtures/two-monitors.env

setup() {
  setup_two_monitors
  ENGINE="$BATS_TEST_DIRNAME/../bin/monitor-input"
}

@test "detect lists both monitors with their valid input codes" {
  run "$ENGINE" detect
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.monitors | length == 2'
  echo "$output" | jq -e '.monitors[] | select(.serial == "AAA0001") | .inputs == ["0x0f","0x11","0x12"]'
}

@test "detect reports each monitor's model" {
  run "$ENGINE" detect
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.monitors[] | select(.serial == "AAA0001") | .model == "STUB MONITOR"'
}

@test "state reports the desk key from the serials present" {
  run "$ENGINE" state
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.deskKey == "AAA0001+BBB0002"'
}

@test "state says the desk is unknown when there is no desks.json" {
  run "$ENGINE" state
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.known == false'
  echo "$output" | jq -e '.computers == []'
}

@test "state reads computers back from a saved desk" {
  cat > "$XDG_CONFIG_HOME/monitor-input/desks.json" <<'JSON'
{"version":1,"desks":{"AAA0001+BBB0002":{"label":"Office",
 "monitors":[{"serial":"AAA0001","label":"Left","model":"STUB MONITOR"},
             {"serial":"BBB0002","label":"Right","model":"STUB MONITOR"}],
 "computers":[{"id":"this","label":"This machine","host":null,
               "inputs":{"AAA0001":"0x0f","BBB0002":"0x0f"}},
              {"id":"mac","label":"Mac","host":null,
               "inputs":{"AAA0001":"0x11","BBB0002":"0x11"}}]}}}
JSON
  run "$ENGINE" state
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.known == true'
  echo "$output" | jq -e '.computers | length == 2'
  echo "$output" | jq -e '.live["AAA0001"] == "0x0f"'
}

@test "a desk is still recognised when one monitor is switched off" {
  cat > "$XDG_CONFIG_HOME/monitor-input/desks.json" <<'JSON'
{"version":1,"desks":{"AAA0001+BBB0002":{"label":"Office","monitors":[],
 "computers":[{"id":"this","label":"This machine","host":null,
               "inputs":{"AAA0001":"0x0f","BBB0002":"0x0f"}}]}}}
JSON
  # A monitor switched off at the wall stops answering DDC and drops out of
  # `detect`, so the key shrinks to "AAA0001". Without subset matching the desk
  # would look unconfigured and the menu would be empty.
  rm "$STUB_STATE/BBB0002"
  run "$ENGINE" state
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.known == true'
  echo "$output" | jq -e '.label == "Office"'
  echo "$output" | jq -e '.computers | length == 1'
  echo "$output" | jq -e '.current == null'
}

@test "a desk is still recognised when a monitor is added" {
  cat > "$XDG_CONFIG_HOME/monitor-input/desks.json" <<'JSON'
{"version":1,"desks":{"AAA0001+BBB0002":{"label":"Office","monitors":[],
 "computers":[{"id":"this","label":"This machine","host":null,
               "inputs":{"AAA0001":"0x0f","BBB0002":"0x0f"}},
              {"id":"mac","label":"Mac","host":null,
               "inputs":{"AAA0001":"0x11","BBB0002":"0x11"}}]}}}
JSON
  # A third monitor plugged in grows the key to "AAA0001+BBB0002+CCC0003",
  # which matches nothing exactly. Without overlap matching this desk would
  # look brand-new and every computer would be lost.
  echo "0x0f" > "$STUB_STATE/CCC0003"
  echo "CCC0003 0x0f 0x11" >> "$STUB_CAPS"
  run "$ENGINE" state
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.known == true'
  echo "$output" | jq -e '.label == "Office"'
  echo "$output" | jq -e '.computers | length == 2'
}

@test "an unknown desk is still reported as unknown" {
  cat > "$XDG_CONFIG_HOME/monitor-input/desks.json" <<'JSON'
{"version":1,"desks":{"ZZZ9999+YYY8888":{"label":"Elsewhere","monitors":[],
 "computers":[{"id":"this","label":"This machine","host":null,
               "inputs":{"ZZZ9999":"0x0f","YYY8888":"0x0f"}}]}}}
JSON
  run "$ENGINE" state
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.known == false'
}

@test "state reports no current computer while a monitor is not answering" {
  cat > "$XDG_CONFIG_HOME/monitor-input/desks.json" <<'JSON'
{"version":1,"desks":{"AAA0001+BBB0002":{"label":"Office","monitors":[],
 "computers":[{"id":"this","label":"This machine","host":null,
               "inputs":{"AAA0001":"0x0f","BBB0002":"0x0f"}},
              {"id":"mac","label":"Mac","host":null,
               "inputs":{"AAA0001":"0x11","BBB0002":"0x11"}}]}}}
JSON
  # Keyed normally: subset matching in desk_json resolves it even though only
  # one serial is present, so this test exercises `current` rather than
  # passing because the desk lookup missed.
  # Second panel asleep. Its input is unknowable, so the honest answer is
  # "I cannot tell" - not "this", inferred from the one panel still talking.
  rm "$STUB_STATE/BBB0002"
  run "$ENGINE" state
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.current == null'
}

@test "state marks which computer is currently on screen" {
  cat > "$XDG_CONFIG_HOME/monitor-input/desks.json" <<'JSON'
{"version":1,"desks":{"AAA0001+BBB0002":{"label":"Office","monitors":[],
 "computers":[{"id":"this","label":"This machine","host":null,
               "inputs":{"AAA0001":"0x0f","BBB0002":"0x0f"}},
              {"id":"mac","label":"Mac","host":null,
               "inputs":{"AAA0001":"0x11","BBB0002":"0x11"}}]}}}
JSON
  run "$ENGINE" state
  echo "$output" | jq -e '.current == "this"'
}

@test "switch moves every monitor to the named computer" {
  save_office_desk
  run "$ENGINE" switch mac
  [ "$status" -eq 0 ]
  [ "$(cat "$STUB_STATE/AAA0001")" = "0x11" ]
  [ "$(cat "$STUB_STATE/BBB0002")" = "0x11" ]
}

@test "switch refuses when a monitor is detected but will not answer" {
  save_office_desk
  # Listed by `detect`, silent on getvcp: a real DDC fault. The desk can see
  # this monitor, so moving its neighbour without it would split the desk.
  echo "UNRESPONSIVE" > "$STUB_STATE/BBB0002"
  run "$ENGINE" switch mac
  [ "$status" -ne 0 ]
  [[ "$output" == *"not switching"* ]]
  [ "$(cat "$STUB_STATE/AAA0001")" = "0x0f" ]   # untouched
}

@test "switch proceeds when a monitor is switched off at the wall" {
  save_office_desk
  # Off at the wall: absent from `detect` entirely, so it is not part of the
  # desk right now. Refusing here would mean nobody who turns a screen off can
  # ever change computers, which is worse than the split this guard prevents -
  # a dark screen shows nothing either way.
  rm "$STUB_STATE/BBB0002"
  run "$ENGINE" switch mac
  [ "$status" -eq 0 ]
  [ "$(cat "$STUB_STATE/AAA0001")" = "0x11" ]
}

@test "switch refuses a code the monitor does not report having" {
  save_office_desk
  cat > "$STUB_CAPS" <<'CAPS'
AAA0001 0x0f 0x12
BBB0002 0x0f 0x11 0x12
CAPS
  run "$ENGINE" switch mac
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not have input"* ]]
  [ "$(cat "$STUB_STATE/AAA0001")" = "0x0f" ]
}

@test "switch rejects an unknown computer id" {
  save_office_desk
  run "$ENGINE" switch nosuch
  [ "$status" -ne 0 ]
  [[ "$output" == *"no computer"* ]]
}

@test "switch --monitor moves only that panel" {
  save_office_desk
  run "$ENGINE" switch mac --monitor AAA0001
  [ "$status" -eq 0 ]
  [ "$(cat "$STUB_STATE/AAA0001")" = "0x11" ]
  [ "$(cat "$STUB_STATE/BBB0002")" = "0x0f" ]
}

@test "switch --monitor still refuses a code that panel lacks" {
  save_office_desk
  cat > "$STUB_CAPS" <<'CAPS'
AAA0001 0x0f 0x12
BBB0002 0x0f 0x11 0x12
CAPS
  run "$ENGINE" switch mac --monitor AAA0001
  [ "$status" -ne 0 ]
  # Assert the reason, not just the failure. A missing subcommand also exits
  # non-zero and also leaves the panel alone, so without this the test passes
  # against an engine that cannot switch at all.
  [[ "$output" == *"does not have input"* ]]
  [ "$(cat "$STUB_STATE/AAA0001")" = "0x0f" ]
}

@test "switch refuses a desk file with two computers sharing an id" {
  # A duplicate id is possible from a hand-edited desks.json, or a future
  # version that stops deriving ids from what's already present. Whatever the
  # cause, `select(.id == $id)` then returns two JSON documents instead of
  # one, and every field read afterwards inherits both values joined by a
  # newline - including the code handed to `ddcutil setvcp`. The engine must
  # refuse outright rather than send a garbled code to a real monitor.
  cat > "$XDG_CONFIG_HOME/monitor-input/desks.json" <<'JSON'
{"version":1,"desks":{"AAA0001+BBB0002":{"label":"Office",
 "monitors":[{"serial":"AAA0001","label":"Left","model":"STUB MONITOR"},
             {"serial":"BBB0002","label":"Right","model":"STUB MONITOR"}],
 "computers":[{"id":"mac","label":"Mac A","host":null,
               "inputs":{"AAA0001":"0x11","BBB0002":"0x11"}},
              {"id":"mac","label":"Mac B","host":null,
               "inputs":{"AAA0001":"0x12","BBB0002":"0x12"}}]}}}
JSON
  run "$ENGINE" switch mac
  [ "$status" -ne 0 ]
  [[ "$output" == *"more than one computer"* ]]
  [[ "$output" == *"mac"* ]]
  [ "$(cat "$STUB_STATE/AAA0001")" = "0x0f" ]   # untouched
  [ "$(cat "$STUB_STATE/BBB0002")" = "0x0f" ]   # untouched
}

@test "switch refuses a malformed input code outright" {
  # Exactly the shape a duplicate-id lookup produces: two valid codes joined
  # by a newline. `grep -qx` treats an embedded newline as alternation, so
  # the membership check alone would accept this - it has to be rejected by
  # its shape before membership is even checked.
  jq -n --arg code "$(printf '0x11\n0x12')" \
    '{"version":1,"desks":{"AAA0001+BBB0002":{"label":"Office",
       "monitors":[{"serial":"AAA0001","label":"Left","model":"STUB MONITOR"},
                   {"serial":"BBB0002","label":"Right","model":"STUB MONITOR"}],
       "computers":[{"id":"mac","label":"Mac","host":null,
                     "inputs":{"AAA0001":$code,"BBB0002":"0x11"}}]}}}' \
    > "$XDG_CONFIG_HOME/monitor-input/desks.json"
  run "$ENGINE" switch mac
  [ "$status" -ne 0 ]
  [[ "$output" == *"malformed"* ]]
  [ "$(cat "$STUB_STATE/AAA0001")" = "0x0f" ]   # untouched
}

@test "reachable succeeds when the computer has no host recorded" {
  save_office_desk
  run "$ENGINE" reachable mac
  [ "$status" -eq 0 ]
}

@test "reachable fails when the host does not answer" {
  cat > "$XDG_CONFIG_HOME/monitor-input/desks.json" <<'JSON'
{"version":1,"desks":{"AAA0001+BBB0002":{"label":"Office","monitors":[],
 "computers":[{"id":"mac","label":"Mac","host":"192.0.2.1",
               "inputs":{"AAA0001":"0x11","BBB0002":"0x11"}}]}}}
JSON
  run "$ENGINE" reachable mac
  [ "$status" -ne 0 ]
  # A bare non-zero exit is not enough: an unimplemented subcommand exits
  # non-zero too, by printing a usage error, so this test passed before
  # `reachable` existed at all. cmd_reachable is silent on both paths and
  # returns ping's own status, so an empty output is what distinguishes a
  # real unreachable host from the command simply not being there.
  [ -z "$output" ]
}

@test "save-desk creates desks.json when there is none" {
  echo '{"label":"Office","monitors":[],"computers":[]}' | "$ENGINE" save-desk
  run jq -e '.desks["AAA0001+BBB0002"].label == "Office"' "$XDG_CONFIG_HOME/monitor-input/desks.json"
  [ "$status" -eq 0 ]
}

@test "save-desk leaves other desks alone" {
  cat > "$XDG_CONFIG_HOME/monitor-input/desks.json" <<'JSON'
{"version":1,"desks":{"OTHER1+OTHER2":{"label":"Studio","monitors":[],"computers":[]}}}
JSON
  echo '{"label":"Office","monitors":[],"computers":[]}' | "$ENGINE" save-desk
  run jq -e '.desks | keys | length == 2' "$XDG_CONFIG_HOME/monitor-input/desks.json"
  [ "$status" -eq 0 ]
  run jq -e '.desks["OTHER1+OTHER2"].label == "Studio"' "$XDG_CONFIG_HOME/monitor-input/desks.json"
  [ "$status" -eq 0 ]
}

@test "save-desk rejects malformed json rather than truncating the file" {
  cat > "$XDG_CONFIG_HOME/monitor-input/desks.json" <<'JSON'
{"version":1,"desks":{"OTHER1+OTHER2":{"label":"Studio","monitors":[],"computers":[]}}}
JSON
  run bash -c "echo 'not json' | '$ENGINE' save-desk"
  [ "$status" -ne 0 ]
  # Assert the reason. An unimplemented `save-desk` exits non-zero too, and
  # also leaves the file untouched, so the survival check below passes either
  # way - this line is what makes the test about JSON validation.
  [[ "$output" == *"not valid JSON"* ]]
  run jq -e '.desks["OTHER1+OTHER2"].label == "Studio"' "$XDG_CONFIG_HOME/monitor-input/desks.json"
  [ "$status" -eq 0 ]
}

@test "switch-raw sets one panel to a literal code" {
  run "$ENGINE" switch-raw AAA0001 0x11
  [ "$status" -eq 0 ]
  [ "$(cat "$STUB_STATE/AAA0001")" = "0x11" ]
  [ "$(cat "$STUB_STATE/BBB0002")" = "0x0f" ]
}

@test "switch-raw refuses a code the panel lacks" {
  cat > "$STUB_CAPS" <<'CAPS'
AAA0001 0x0f 0x12
BBB0002 0x0f 0x11 0x12
CAPS
  run "$ENGINE" switch-raw AAA0001 0x11
  [ "$status" -ne 0 ]
  [ "$(cat "$STUB_STATE/AAA0001")" = "0x0f" ]
}

@test "detect reports a monitor with no input capabilities as an empty list" {
  cat > "$STUB_CAPS" <<'CAPS'
AAA0001 0x0f 0x11 0x12
CAPS
  run "$ENGINE" detect
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.monitors[] | select(.serial == "BBB0002") | .inputs == []'
}

@test "switch skips a monitor with no recorded input and moves the rest" {
  cat > "$XDG_CONFIG_HOME/monitor-input/desks.json" <<'JSON'
{"version":1,"desks":{"AAA0001+BBB0002":{"label":"Office","monitors":[],
 "computers":[{"id":"mac","label":"Mac","host":null,
               "inputs":{"AAA0001":"0x11"}}]}}}
JSON
  run "$ENGINE" switch mac
  [ "$status" -eq 0 ]
  [ "$(cat "$STUB_STATE/AAA0001")" = "0x11" ]
  [ "$(cat "$STUB_STATE/BBB0002")" = "0x0f" ]
}
