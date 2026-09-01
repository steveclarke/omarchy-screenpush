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
