#!/usr/bin/env bats
# fsevents-top.py — unprivileged sampler of which paths dominate the FSEvents stream.
#
# WHY: fseventsd's footprint reached 64 GB on 2026-10-04 (scripts/fseventsd-watch.sh); its history
# and fs_usage are root-only, so this names the event sources from a user-level FSEvents stream.
# These tests subscribe to a private temp dir (never "/") and write into it, so the counts are
# exact and nothing outside the test's own directory is read.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  T="$REPO/scripts/fsevents-top.py"
  D="$(cd "$BATS_TEST_TMPDIR" && pwd -P)/watched"; mkdir -p "$D/hot" "$D/cold"
}

# write <n> files into <dir> once the sampler says its stream is open (--ready-file): a fixed head
# start lost the first write under load 48, when python's own startup took longer than the sleep
writer() {
  ( i=0; while [ ! -e "$BATS_TEST_TMPDIR/ready" ] && [ "$i" -lt 300 ]; do sleep 0.1; i=$(( i + 1 )); done
    for i in $(seq 1 "$2"); do echo x > "$1/f$i"; done ) 3>&- &
}

@test "every file write under the root is one event, bucketed by path depth, largest bucket first" {
  writer "$D/hot" 30; writer "$D/cold" 5
  run python3 "$T" --ready-file "$BATS_TEST_TMPDIR/ready" --root "$D" --seconds 4 --depth "$(( $(printf '%s' "$D" | tr -cd / | wc -c) + 1 ))" --json
  wait
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["events"] == 35, d
assert d["top"][0]["path"].endswith("/watched/hot") and d["top"][0]["events"] == 30, d["top"]
assert d["top"][1]["path"].endswith("/watched/cold") and d["top"][1]["events"] == 5, d["top"]
'
}

@test "the table form prints the total and a percentage per bucket" {
  writer "$D/hot" 4
  run python3 "$T" --ready-file "$BATS_TEST_TMPDIR/ready" --root "$D" --seconds 4 --depth 99
  wait
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "fsevents-top: 4 events in "* ]] || false
  [[ "$output" == *"25.0%  $D/hot/f1"* ]] || false
}

@test "a quiet root yields zero events, not an error" {
  run python3 "$T" --root "$D" --seconds 1 --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"events": 0'* ]] || false
}
