#!/usr/bin/env bats
# cc-dispatch selftest: its FIRE NARRATION must not land in the production census.
#
# The defect (measured 2026-09-08, A11 skeptic row 9). `selftest()` pins every seam it knew about —
# CC_DISPATCH_IDL, CC_DISPATCH_SPAWN_BIN, CC_DISPATCH_PAGES_DIR, the declaration store — but not
# CC_DISPATCH_FIRE_LOG. fire_log_keep (bin/cc-dispatch:681) therefore resolved its default,
# $HOME/.claude/logs/dispatch-fires.log, and the selftest's own spawn stub (`echo "handoff-fire: no
# pane anchor resolved" >&2`, STUB_SPAWN_RC=7) was appended to the operator's LIVE log on every run.
#
# The cost was not disk. It was a corrupted denominator: 36 of that day's 91 fire headers were six
# fixture ids x six 3-hourly cron runs, and ALL 12 `rc=7 no pane anchor resolved` records — the rows
# an axis report read as production evidence, and from which it recommended reserving a headless pane
# anchor — were stubs. None of the six ids exists in backlog.jsonl. The real dominant fire failure
# was the INC-4 cold-worktree autosubmit race (13 of 20), which that diagnosis never named.
# Memory: control-must-replay-the-real-artifact / positive-control-the-denominator — a census whose
# population admits fixtures measures the harness, not the fleet.
#
# The assertion is on the DEFAULT PATH, deliberately. Asserting the pinned path is non-empty would
# pass pre-fix too (the writes happened either way); what was broken is that an UNPINNED caller
# environment leaked. So this suite unsets CC_DISPATCH_FIRE_LOG and proves the default is untouched.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DISPATCH="$REPO/bin/cc-dispatch"
  [ -f "$DISPATCH" ] || skip "bin/cc-dispatch not found at $DISPATCH"
  # hermeticity: the "live" log this suite protects is a FIXTURE $HOME's copy, at the very path the
  # unpinned default resolves. Running the real selftest against the operator's own $HOME to prove
  # it does not write there would be the defect performing itself.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  LIVE="$HOME/.claude/logs/dispatch-fires.log"
  unset CC_DISPATCH_FIRE_LOG
}

@test "the live fire log is byte-identical across a selftest run (pre-existing content)" {
  printf 'a real fire record from before the selftest\n' > "$LIVE"
  before="$(shasum -a 256 "$LIVE" | awk '{print $1}')"
  run env -u CC_DISPATCH_FIRE_LOG bash "$DISPATCH" selftest
  [ "$status" -eq 0 ]
  after="$(shasum -a 256 "$LIVE" | awk '{print $1}')"
  [ "$before" = "$after" ]
}

@test "a selftest run creates no default-path fire log where none existed" {
  [ ! -e "$LIVE" ]
  run env -u CC_DISPATCH_FIRE_LOG bash "$DISPATCH" selftest
  [ "$status" -eq 0 ]
  [ ! -e "$LIVE" ]
}

@test "CONTROL: the default the selftest used to reach is exactly the path this suite protects" {
  # Without this, tests 1-2 would also pass if fire_log_keep's DEFAULT moved somewhere else
  # entirely — a green that proves nothing about the leak. Extract the real function from the
  # shipped binary and call it with the seam UNSET: it must land on $LIVE, byte for byte the file
  # the two assertions above guard. (Same replay-the-real-artifact technique as
  # tests/cc-dispatch-fire-evidence.bats, and its reason: a reimplementation would grade itself.)
  lib="$BATS_TEST_TMPDIR/lib.sh"
  sed -n '/^fire_log_keep()/,/^}/p' "$DISPATCH" > "$lib"
  grep -q '^fire_log_keep()' "$lib" || skip "could not extract fire_log_keep from $DISPATCH"
  cap="$BATS_TEST_TMPDIR/cap.txt"
  printf 'handoff-fire: no pane anchor resolved\n' > "$cap"
  run env -u CC_DISPATCH_FIRE_LOG bash -c ". '$lib'; fire_log_keep stub next3 7 '$cap'"
  [ "$status" -eq 0 ]
  [ -s "$LIVE" ]
  grep -q 'no pane anchor resolved' "$LIVE"
}

@test "CONTROL: the leak still has a payload — the spawn stub narrates on stderr" {
  # The seam is only worth pinning while the fixture still emits something a census could count.
  # Asserted against the shipped source because the selftest now pins the log to its OWN scratch
  # dir and removes it on exit, so no external observer can read it — which is precisely the
  # property tests 1-2 assert. If this stub ever stops narrating, tests 1-2 go vacuous silently.
  grep -q 'handoff-fire: no pane anchor resolved' "$DISPATCH"
  grep -q 'STUB_SPAWN_RC' "$DISPATCH"
}
