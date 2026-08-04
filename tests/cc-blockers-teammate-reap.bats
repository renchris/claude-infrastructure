#!/usr/bin/env /Users/chrisren/.claude/bin/cc-bats
# cc-blockers × teammate-reap — the OUTCOME row for the idle-close path.
#
# The row exists because the close path already had a pager and it did not work: `⚑ SURFACE` fired
# 156 times between 2026-07-25 and 2026-08-03 and was read ZERO times (the desk role was repointed
# on 07-26 and nothing has drained the new box since), so 156 pages produced 0 manual closes. A
# 157th unread line is not a backstop. cc-blockers is PULL-rendered from disk truth at close time
# and needs no live consumer, which is the entire reason the row lives here.
#
# What these tests pin is POLARITY, not plumbing: the row must appear on ALARM/WARN and must be
# SILENT on OK, NOT-EXERCISED and NO-DATA. An alarm that fires on every state carries exactly as
# many bits as one that never fires (memory: alarm-polarity-and-attention-budget), and NO-DATA in
# particular must not read as a blocker — an unreadable log is a gap in evidence, not a verdict.
#
# Assertion style: `[ ]` throughout — a non-final `[[ ]]` is errexit-EXEMPT under /Users/chrisren/.claude/bin/cc-bats and therefore
# a DEAD assertion.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  B="$REPO/bin/cc-blockers"
  D="$BATS_TEST_TMPDIR"
  export HOME="$D/home"; mkdir -p "$HOME/.claude"
  # A stub subject, so these tests pin the WIRING and never re-measure the fleet. The subject's own
  # suite (tests/teammate-reap-alarm.bats) owns the verdict logic; two implementations of one
  # predicate would be two answers.
  stub_verdict() { # $1 = verdict, $2 = exit code
    cat > "$D/reap-alarm" <<EOF
#!/bin/bash
echo '{"ts":"t","verdict":"$1","window_d":3,"idle_events":582,"closes":0,"last_close":"2026-07-25","days_since_last_close":9,"detail":"d"}'
exit $2
EOF
    chmod +x "$D/reap-alarm"
    export CC_REAP_ALARM_SH="$D/reap-alarm"
  }
}

@test "ALARM renders the TEAMMATE-REAP section" {
  stub_verdict ALARM 2
  run "$B"
  echo "$output" | grep -q "TEAMMATE-REAP"
  echo "$output" | grep -q "teammate-reap"
}

@test "WARN renders it too — a path closing almost nothing is still news" {
  stub_verdict WARN 1
  run "$B"
  echo "$output" | grep -q "TEAMMATE-REAP"
}

@test "OK is SILENT — no row, no section" {
  stub_verdict OK 0
  run "$B"
  run grep -c "TEAMMATE-REAP" <<<"$output"
  [ "$output" -eq 0 ]
}

@test "NOT-EXERCISED is SILENT — a quiet fleet is not a broken one" {
  stub_verdict NOT-EXERCISED 0
  run "$B"
  run grep -c "TEAMMATE-REAP" <<<"$output"
  [ "$output" -eq 0 ]
}

# The one that matters most for polarity: an unreadable log asserts NOTHING. If NO-DATA rendered a
# blocker, deleting the log would manufacture one, and the board would be reporting its own blindness
# as a fleet defect.
@test "NO-DATA is SILENT — 'could not measure' is not a blocker" {
  stub_verdict NO-DATA 3
  run "$B"
  run grep -c "TEAMMATE-REAP" <<<"$output"
  [ "$output" -eq 0 ]
}

@test "an undeployed subject is SILENT — no premise, no row" {
  export CC_REAP_ALARM_SH="$D/definitely-not-here"
  run "$B"
  run grep -c "TEAMMATE-REAP" <<<"$output"
  [ "$output" -eq 0 ]
}

# A subject that emits garbage must not crash the board or invent a row. cc-blockers fails OPEN by
# design everywhere else; this family must match.
@test "a garbage subject is SILENT and does not break the board" {
  printf '#!/bin/bash\necho "not json at all"\nexit 2\n' > "$D/reap-alarm"; chmod +x "$D/reap-alarm"
  export CC_REAP_ALARM_SH="$D/reap-alarm"
  run "$B"
  [ "$status" -lt 2 ] || [ "$status" -ge 0 ]
  run grep -c "TEAMMATE-REAP" <<<"$output"
  [ "$output" -eq 0 ]
}
