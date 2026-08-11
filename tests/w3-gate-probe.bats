#!/usr/bin/env bats
# A probe suite for the W3 refusal loop. It exists to be gated, not to be useful.

setup() {
  WORKDIR="$HOME/.w3-gate-probe"
  mkdir -p "$WORKDIR"
}

@test "the probe workdir exists" {
  [ -d "$WORKDIR" ]
}
