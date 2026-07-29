#!/usr/bin/env bats
# capacity-alarm.bats — row 13 M6 (MACHINE_CAPACITY_V2.md §4). The ceiling alarm.
#
# The properties that matter, in priority order:
#   1. A broken instrument reports NO-DATA, never a false OK. ("could not measure" != "fine")
#   2. Every rung is reachable — proven by a positive control, not asserted.
#   3. It NEVER waits, sleeps, or polls (R1: a shedder that waits amplifies; the landed
#      capacity_gate is the cautionary case at REFUSE 10/10).
#   4. The session counter actually sees the population (pgrep silently returned 0 here).
#
# `|| false` on every non-final [[ ]]/[ ] chain — errexit-exempt assertions are DEAD (memory
# bats-dead-assertions-errexit-exemptions).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  ALARM="$REPO/scripts/capacity-alarm.sh"
  # Hermeticity ratchet: the alarm's default log lives under $HOME.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  export CC_CAP_LOG="$BATS_TEST_TMPDIR/cap.jsonl"
}

@test "(i) selftest GREEN — all four rungs + NO-DATA are reachable (positive control, R6)" {
  run /bin/bash "$ALARM" --selftest
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ "selftest GREEN" ]] || false
  # each rung must be named, so a silently-unreachable rung cannot hide behind an aggregate pass
  [[ "$output" =~ "→ OK" ]] || false
  [[ "$output" =~ "→ WARN" ]] || false
  [[ "$output" =~ "→ ALARM" ]] || false
  [[ "$output" =~ "→ NO-DATA" ]] || false
}

@test "(ii) healthy box → OK with rc 0 and a numeric headroom" {
  run /bin/bash "$ALARM" --json --no-append
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ \"verdict\":\"OK\" ]] || false
  # headroom must be a NUMBER, never null — null means the instrument silently failed
  ! [[ "$output" =~ \"headroom_gb\":null ]] || false
}

@test "(iii) forced WARN → rc 1" {
  run env CC_CAP_WARN_GB=999999 /bin/bash "$ALARM" --json --no-append
  [ "$status" -eq 1 ] || false
  [[ "$output" =~ \"verdict\":\"WARN\" ]] || false
}

@test "(iv) forced ALARM → rc 2, and ALARM outranks WARN" {
  run env CC_CAP_ALARM_GB=999999 CC_CAP_WARN_GB=999999 /bin/bash "$ALARM" --json --no-append
  [ "$status" -eq 2 ] || false
  [[ "$output" =~ \"verdict\":\"ALARM\" ]] || false
}

@test "(v) THE LOAD-BEARING ONE — a broken instrument reports NO-DATA (rc 3), never a false OK" {
  # A capacity alarm that reads OK when it cannot measure is worse than no alarm: it actively
  # asserts safety. This is why the verdict set has four members rather than a boolean.
  run env CC_CAP_PYTHON=/nonexistent/python /bin/bash "$ALARM" --json --no-append
  [ "$status" -eq 3 ] || false
  [[ "$output" =~ \"verdict\":\"NO-DATA\" ]] || false
  ! [[ "$output" =~ \"verdict\":\"OK\" ]] || false
}

@test "(vi) POSITIVE CONTROL for (v): the SAME code path yields OK with a working instrument" {
  # Without this, (v) could pass because the script always says NO-DATA.
  run /bin/bash "$ALARM" --json --no-append
  [[ "$output" =~ \"verdict\":\"OK\" ]] || [[ "$output" =~ \"verdict\":\"WARN\" ]] || false
  ! [[ "$output" =~ \"verdict\":\"NO-DATA\" ]] || false
}

@test "(vii) the session counter SEES the population — pgrep silently returned 0 here" {
  # Regression guard for a real defect: pgrep -cf returned 0 with 8 live sessions (macOS pgrep -f
  # matches a truncated argv), which would make this alarm report an empty fleet forever. The count
  # is compared against an INDEPENDENT instrument rather than asserted to be non-zero, so the test
  # is valid on a box with genuinely zero sessions too.
  expected="$(ps -eo args 2>/dev/null | grep -cE 'claude-code/bin/claude\.exe' || true)"
  run /bin/bash "$ALARM" --json --no-append
  [ "$status" -ne 64 ] || false
  [[ "$output" =~ \"sessions\":$expected ]] || false
}

@test "(viii) R1 — never sleeps, polls, or waits on load (EXECUTABLE lines only)" {
  # TWO defects the first version of this test had, both caught by running it:
  #  1. It matched the script's OWN PROSE — the header says "NEVER refuses, blocks, queues, sleeps,
  #     or polls-until-clear", so the guard convicted the very documentation of the property it
  #     checks. Text is never evidence (memory detector-matching-its-own-skill-description). Comments
  #     are therefore stripped before matching.
  #  2. It passed VACUOUSLY against a tree with no capacity-alarm.sh at all, because grep on a
  #     missing file also returns non-zero. Hence the existence guard.
  [ -f "$ALARM" ] || false
  run bash -c "sed 's/#.*//' '$ALARM' | grep -nE '\\bsleep\\b|while.*load|until.*load|loadavg'"
  [ "$status" -ne 0 ] || false
}

@test "(ix) POSITIVE CONTROL for (viii): the comment-stripped grep still catches a real sleep" {
  # Proves the stripping did not defang the guard: a genuine executable sleep must still be found,
  # while the same word inside a comment must not.
  printf '# we never sleep here\nsleep 5\n' > "$BATS_TEST_TMPDIR/bait.sh"
  run bash -c "sed 's/#.*//' '$BATS_TEST_TMPDIR/bait.sh' | grep -nE '\\bsleep\\b'"
  [ "$status" -eq 0 ] || false
  printf '# we never sleep here\n:\n' > "$BATS_TEST_TMPDIR/clean.sh"
  run bash -c "sed 's/#.*//' '$BATS_TEST_TMPDIR/clean.sh' | grep -nE '\\bsleep\\b'"
  [ "$status" -ne 0 ] || false
}

@test "(x) kill switch CC_CAPACITY_ALARM=off → rc 0 and NO log write" {
  run env CC_CAPACITY_ALARM=off CC_CAP_LOG="$BATS_TEST_TMPDIR/ks.jsonl" /bin/bash "$ALARM" --quiet
  [ "$status" -eq 0 ] || false
  [ ! -f "$BATS_TEST_TMPDIR/ks.jsonl" ] || false
}

@test "(xi) appends a durable row by default; --no-append writes nothing" {
  log="$BATS_TEST_TMPDIR/a.jsonl"
  run env CC_CAP_LOG="$log" /bin/bash "$ALARM" --quiet
  [ -f "$log" ] || false
  run grep -c '"verdict":' "$log"
  [ "$output" -ge 1 ] || false
  log2="$BATS_TEST_TMPDIR/b.jsonl"
  run env CC_CAP_LOG="$log2" /bin/bash "$ALARM" --quiet --no-append
  [ "$status" -ne 64 ] || false          # non-vacuity: it really ran
  [ ! -f "$log2" ] || false
}

@test "(xii) unknown arg → rc 64, never a silent ignore" {
  run /bin/bash "$ALARM" --definitely-not-a-flag
  [ "$status" -eq 64 ] || false
}

@test "(xiii) it is an ALARM, not a GATE — the header says so and no refusal verb exists" {
  # The design boundary this row exists to protect: refusing spawns on a load proxy was measured to
  # be a permanent outage. Anything that turns this reporter into a gate must break a test.
  run grep -qE 'ALARM, NOT A GATE' "$ALARM"
  [ "$status" -eq 0 ] || false
  run grep -nE '^\s*(exit 9|refuse|REFUSE)\b' "$ALARM"
  [ "$status" -ne 0 ] || false
}
