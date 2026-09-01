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
