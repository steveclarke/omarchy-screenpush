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
