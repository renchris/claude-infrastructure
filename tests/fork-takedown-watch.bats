#!/usr/bin/env bats
# fork-takedown-watch.sh — the weekly check that a takedown ask about a pre-cutover public copy worked.
#
# The cases that matter are the PAGE case, its threshold, and the NON-VERDICT case:
#
#   submitted >= 30 days ago, a probe answers 200 → rc 0   PAGE (the ask was ignored)
#   submitted 29 days ago, a probe answers 200    → rc 1   inside the window, NO fetch
#   not yet submitted                             → rc 1   no clock running, NO fetch
#   every probe gone (404/410/422/451)            → rc 1   GONE
#   no probe gave 200 or gone / state unreadable  → rc 2   NON-VERDICT, never "gone"
#
# Hermetic: CC_FORK_WATCH_CODE replaces every fetch, except the unreachable-API case, which points
# CC_FORK_WATCH_API at a closed loopback port (no network leaves the box). The "no fetch" cases set
# that same closed port: a fetch there would give 000 → rc 2, so rc 1 proves no fetch was made.

setup() {
  export HOME="${BATS_TEST_TMPDIR}/home"; mkdir -p "$HOME"
  SUBJECT="${BATS_TEST_DIRNAME}/../scripts/fork-takedown-watch.sh"
  export CC_FORK_WATCH_STATE="${BATS_TEST_TMPDIR}/fork-watch.json"
  # "Today" is PINNED, and pinned in the past, so no fixture date is ever in the future: the
  # 29/30-day arithmetic is fixed by construction and the wall-clock ratchet has nothing to age.
  export CC_FORK_WATCH_TODAY="2020-03-01"
  unset CC_FORK_WATCH_CODE CC_FORK_WATCH_DAYS
}

state() { # <submitted|null> → writes a fixture state file
  local sub='null'; [ "$1" = null ] || sub="\"$1\""
  printf '{"repo":"example/copy","probe_shas":["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"],"submitted":%s}' \
    "$sub" > "$CC_FORK_WATCH_STATE"
}

closed_api() { export CC_FORK_WATCH_API="http://127.0.0.1:9" CC_FORK_WATCH_FETCH_TIMEOUT_S=2; }

@test "30 days after the ask, a copy that still answers 200 PAGES: rc 0" {
  state 2020-01-31                                    # exactly 30 days before 2020-03-01 (leap Feb)
  CC_FORK_WATCH_CODE=200 run bash "$SUBJECT" --arm
  [ "$status" -eq 0 ]
}

@test "29 days after the ask is inside the window: rc 1 and no fetch" {
  state 2020-02-01                                    # 29 days
  closed_api
  run bash "$SUBJECT" --arm
  [ "$status" -eq 1 ]
}

@test "the window is CC_FORK_WATCH_DAYS, so the 30 is a default and not a constant" {
  state 2020-02-01
  CC_FORK_WATCH_DAYS=29 CC_FORK_WATCH_CODE=200 run bash "$SUBJECT" --arm
  [ "$status" -eq 0 ]
}

@test "not yet submitted: rc 1 and no fetch, however old the copy is" {
  state null
  closed_api
  run bash "$SUBJECT" --report
  [ "$status" -eq 1 ]
  [[ "$output" == *"not yet submitted"* ]]
}

@test "every probe gone (404) reads GONE: rc 1, and the report says so" {
  state 2019-09-01
  CC_FORK_WATCH_CODE=404 run bash "$SUBJECT" --report
  [ "$status" -eq 1 ]
  [[ "$output" == *"GONE"* ]]
}

@test "a 451 (taken down for legal reasons) also reads gone: rc 1" {
  state 2019-09-01
  CC_FORK_WATCH_CODE=451 run bash "$SUBJECT" --arm
  [ "$status" -eq 1 ]
}

@test "a rate limit (403) is a NON-VERDICT, never gone: rc 2" {
  state 2019-09-01
  CC_FORK_WATCH_CODE=403 run bash "$SUBJECT" --arm
  [ "$status" -eq 2 ]
}

@test "an unreachable API is a NON-VERDICT: rc 2" {
  state 2019-09-01
  closed_api
  run bash "$SUBJECT" --arm
  [ "$status" -eq 2 ]
}

@test "an unreadable state file is a NON-VERDICT: rc 2" {
  export CC_FORK_WATCH_STATE="${BATS_TEST_TMPDIR}/absent.json"
  CC_FORK_WATCH_CODE=200 run bash "$SUBJECT" --arm
  [ "$status" -eq 2 ]
}

@test "the report on a page names what is served and the next command" {
  state 2019-09-01
  CC_FORK_WATCH_CODE=200 run bash "$SUBJECT" --report
  [ "$status" -eq 0 ]
  [[ "$output" == *"STILL SERVED"*"aaaaaaaaaaaa"* ]] || false
  [[ "$output" == *"record-submission.sh --dmca"* ]]
}
