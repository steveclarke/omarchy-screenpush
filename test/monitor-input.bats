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
  [ "$(cat "$STUB_STATE/AAA0001")" = "0x0f" ]
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
}
