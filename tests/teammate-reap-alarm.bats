#!/usr/bin/env bats
# teammate-reap-alarm.bats — the outcome alarm for the teammate idle-close path.
#
# What this suite is FOR. The subject exists because nine days of zero teammate pane closes went
# unnoticed while four investigations each fixed a real defect and declared the class resolved.
# So the property that matters is not "the script runs" — it is that the SAME parser reports ALARM
# on a dead path and OK on a live one. A checker that cannot emit its own failing verdict is not
# evidence, and that is what these tests pin.
#
# Assertion style: `[ ]` throughout — a non-final `[[ ]]`/`(( ))` is errexit-EXEMPT under bats and
# therefore a DEAD assertion (memory: bats-dead-assertions-errexit-exemptions).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  S="$REPO/scripts/teammate-reap-alarm.sh"
  # Fixture HOME so the suite can never read — or be swayed by — the operator's live lifecycle log.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  TODAY=$(date +%Y-%m-%d)
  LOG="$BATS_TEST_TMPDIR/lifecycle.log"
  # This suite never fires anything. It is in the hermeticity ratchet's scope only TEXTUALLY: the
  # last test greps the subject for `handoff-fire` to assert the subject does NOT call it, and
  # references_fire() (scripts/test-hermeticity-lint.sh:432) is a literal grep over the whole file,
  # so a mention that asserts ABSENCE reads identically to one that exercises it. The ratchet is
  # deliberately coarse and fail-safe toward flagging, which is the right default — so pin the gate
  # rather than weaken the lint. Costs nothing here and keeps the suite honest if it ever does fire.
  export CC_FIRE_CAPACITY_GATE=off
}

# refusals <n>  — a refusal in the REAL log's shape: a bare `defer` line with NO
# `Auto-shutdown idle teammate` header above it. That asymmetry is the whole point: the header is
# written only on the success path (teammate-auto-shutdown.sh:837, after every gate), so a fixture
# that supplies one for every refusal cannot reproduce the outage.
refusals() { local i; for i in $(seq 1 "$1"); do
  echo "[$TODAY 09:00:00] defer m$i (1/3): dirty tree" >> "$LOG"; done; }
closes()   { local i; for i in $(seq 1 "$1"); do
  echo "[$TODAY 09:00:01] Auto-shutdown idle teammate: c$i (team: t)" >> "$LOG"
  echo "[$TODAY 09:00:01]   ✓ closed pane U$i (c$i)" >> "$LOG"; done; }

@test "embedded selftest passes end to end" {
  run "$S" --selftest
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "selftest: all pass"
}

@test "a dead close path ALARMs (exit 2)" {
  refusals 30
  run "$S" --log "$LOG"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "ALARM"
}

@test "a healthy close path reads OK (exit 0) — the control that can distinguish it" {
  refusals 2; closes 20
  run "$S" --log "$LOG"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "VERDICT:             OK"
}

@test "a quiet fleet is NOT-EXERCISED, never a quiet OK" {
  refusals 2
  run "$S" --log "$LOG"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "NOT-EXERCISED"
}

@test "an unreadable log is NO-DATA (exit 3), never 'fine'" {
  run "$S" --log "$BATS_TEST_TMPDIR/absent.log"
  [ "$status" -eq 3 ]
  echo "$output" | grep -q "NO-DATA"
}

# REGRESSION: this instrument's own first defect. Keyed on `Auto-shutdown idle teammate`, it counted
# ~0 attempts during a total outage — because that line is only written when a close SUCCEEDS — and
# reported NOT-EXERCISED at the exact moment it was built to fire. Invert the guard and this test
# goes red; that is what makes it live rather than decorative.
@test "an outage with zero header lines still ALARMs (the denominator regression)" {
  refusals 30
  run grep -c "Auto-shutdown idle teammate" "$LOG"
  [ "$output" -eq 0 ]           # the fixture really does lack the header
  run "$S" --log "$LOG"
  [ "$status" -eq 2 ]
}

# Deferring a BUSY teammate is the system working, not a refusal to close a finished one. If these
# counted, a healthy fleet under load would drift toward ALARM and the alarm would lose its meaning.
@test "busy-marker and tool-in-flight defers are not refusals" {
  local i; for i in $(seq 1 30); do
    echo "[$TODAY 09:00:00] defer m$i (team=t): .teammate-busy marker present" >> "$LOG"
    echo "[$TODAY 09:00:01] defer m$i (team=t): tool in flight — teammate is live, not idle" >> "$LOG"
  done
  run "$S" --log "$LOG"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "NOT-EXERCISED"
}

@test "the window bounds: old closes cannot rescue a dead window" {
  local old i; old=$(date -v-30d +%Y-%m-%d)
  for i in $(seq 1 20); do echo "[$old 09:00:01]   ✓ closed pane U$i (c$i)" >> "$LOG"; done
  refusals 30
  run "$S" --log "$LOG"
  [ "$status" -eq 2 ]
}

@test "json output carries the verdict and the days-since figure" {
  refusals 30
  run "$S" --log "$LOG" --json
  [ "$status" -eq 2 ]
  echo "$output" | grep -q '"verdict":"ALARM"'
  echo "$output" | grep -q '"closes":0'
}

@test "it never closes a pane or refuses a spawn — no actuator verbs in the subject" {
  run grep -nE "it2 session close|kill -9|handoff-fire|exit 1;.*refus" "$S"
  [ "$status" -ne 0 ]
}
