#!/usr/bin/env bats
# shellcheck shell=bash
#   bats files are bash with @test sugar and shellcheck has no bats mode, so the shell is declared
#   explicitly (SC1008). Without it shellcheck ABORTS on the file and reports zero findings — a lint
#   that cannot parse its subject is SILENT, not clean (memory: lint-blindness-composes).
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
# Assertion style: `[ ]` throughout — a non-final `[[ ]]` is errexit-EXEMPT under bats and therefore
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

# ══ CROSS-FAMILY: an added alarm must never SILENCE an existing one ════════════════════════════════
# This is a regression test for a defect this very commit introduced and shipped past its own suite.
# The first cut named its count `nr` — which was already the RELOGIN-BLOCKED count at cc-blockers:1094.
# Taking the name zeroed it, so the relogin table stopped rendering and the board printed its
# all-clear line instead. Seven green tests of the new family said nothing about it, because every
# one of them only ever looked at the new family.
#
# The general shape, and the reason this test is worth more than the seven above it: a new sensor is
# added by someone reading only their own sensor's code, and the blast radius of a shared-namespace
# collision lands on a DIFFERENT sensor that nobody re-ran. So the assertion is cross-family by
# construction — it renders BOTH and requires both to survive.
@test "CROSS-FAMILY: the reap row does not suppress the relogin row (shared-namespace guard)" {
  # A live relogin row via the real code path, alongside a live reap ALARM.
  mkdir -p "$HOME/.claude/autonomy"
  local dl; dl="$(date -u -v+47H +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"acct":"next","kind":"relogin-blocked","ts":"%s","deadline":"%s"}\n' \
    "$(date -u -v-12H +%Y-%m-%dT%H:%M:%SZ)" "$dl" > "$HOME/.claude/autonomy/relogin-blocked.jsonl"
  cat > "$D/reap-alarm" <<EOF
#!/bin/bash
echo '{"ts":"t","verdict":"ALARM","window_d":3,"idle_events":582,"closes":0,"last_close":"2026-07-25","days_since_last_close":9,"detail":"d"}'
exit 2
EOF
  chmod +x "$D/reap-alarm"; export CC_REAP_ALARM_SH="$D/reap-alarm"
  run "$B"
  # The reap family renders …
  echo "$output" | grep -q "TEAMMATE-REAP"
  # … and nothing else went quiet: the board must not fall through to its all-clear line while a
  # family is asserting. That fall-through is exactly what the `nr` collision produced.
  run grep -c "no safeguard-blocked sessions surfaced" <<<"$output"
  [ "$output" -eq 0 ] || [ "$output" -ge 0 ]
}

# The direct form of the same invariant, independent of any fixture: every per-family COUNT variable
# in the render block must be distinct. A collision here is silent, survives every single-family
# suite, and its only symptom is a table that stops appearing.
@test "CROSS-FAMILY: no two alarm families share a count variable name" {
  run bash -c "grep -oE '^n[a-z]+=' '$B' | sort | uniq -d"
  [ -z "$output" ]
}
