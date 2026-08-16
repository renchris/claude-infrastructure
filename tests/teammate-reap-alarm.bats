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

# ══ THE NUMERATOR SWAP (2026-08-04) ═══════════════════════════════════════════════════════════════
# Every test above drives the LOG arithmetic, and every one of them still passes — that arithmetic is
# unchanged and is still printed. What changed is which numbers reach the verdict. The old pair
# counted `✓ closed pane` and `defer`/`⚑ SURFACE`: lines this subsystem writes ABOUT ITSELF, so the
# metric is satisfiable without a pane going away. Two blind spots, both measured on this box:
#   1. six members of team session-57342265 were closed and de-registered with ZERO `✓ closed pane`
#      lines — six real closes the instrument could not see;
#   2. the log's last two lines assert `Pane NOT closed` for panes that were already gone — refusals
#      counted against members that had already left.
# So EVENTS/CLOSES now come from the residency join. These arms pin that the WORLD wins, that the
# attribution survives the trip up, and that a missing join degrades LOUDLY rather than silently.
#
# The join is STUBBED here on purpose. The suite owns the WIRING; tests/assignee-pane-residency.bats
# owns the verdict logic. Two implementations of one predicate would be two answers.
stub_world() { # stub_world <token-tail…>
  printf '#!/bin/bash\necho "verdict=%s"\nexit 0\n' "$*" > "$BATS_TEST_TMPDIR/res.sh"
  chmod +x "$BATS_TEST_TMPDIR/res.sh"
  export CC_RESIDENCY_SH="$BATS_TEST_TMPDIR/res.sh"
}

@test "a healthy-looking LOG cannot launder a dead WORLD" {
  refusals 2; closes 20            # 20 closes in 22 attempts — the healthiest log there is
  stub_world "ALARM members=15 resident=12 stale=12 departed=0 ours=0 vendor=0"
  run "$S" --log "$LOG"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "ALARM"
  echo "$output" | grep -q "measured against the WORLD"
  # And the log figures are still shown — the GAP between the two is the finding, not a thing to hide.
  echo "$output" | grep -q "log-grep says:"
}

# THE TWIN, and the reason the arm above means something: the SAME log, a world where panes actually
# left. One parser, opposite verdicts. If these ever agree, the world source is not being read.
@test "the same healthy log with a LIVE world reads OK" {
  refusals 2; closes 20
  stub_world "OK members=15 resident=3 stale=3 departed=12 ours=12 vendor=0"
  run "$S" --log "$LOG"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "VERDICT:             OK"
}

# The mirror: a log of nothing but refusals, where the world says the panes did leave. This is blind
# spot #1 exactly — six real closes with no log line — and a log-grep alarm would fire on it.
@test "a dead-looking LOG does not fire against a live WORLD" {
  refusals 30
  stub_world "OK members=8 resident=1 stale=1 departed=6 ours=6 vendor=0"
  run "$S" --log "$LOG"
  [ "$status" -eq 0 ]
}

# Attribution carries all the way up: `ours` is the numerator, never `departed`. Six panes gone with
# nothing claiming them is the VENDOR closing panes, not our chain working.
@test "unattributed departures never satisfy the OK arm" {
  refusals 2; closes 20
  stub_world "WARN members=20 resident=14 stale=14 departed=6 ours=0 vendor=6"
  run "$S" --log "$LOG"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "6 unattributed"
}

# A join that cannot see a world falls back to the log — and SAYS so. A degraded reading that
# labels itself is worth more than an instrument that goes quiet, but an unlabelled one is worse
# than both: a reader would take claims for outcomes.
@test "no world reading ⇒ the log fallback labels itself as degraded" {
  refusals 30
  stub_world "NOT-EXERCISED members=0 resident=0 stale=0 departed=0 ours=0 vendor=0"
  run "$S" --log "$LOG"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "log-grep only, no world reading"
  if printf '%s\n' "$output" | grep -q "measured against the WORLD"; then
    echo "the fallback claimed a world reading it does not have" >&2; false
  fi
}

@test "an undeployed join degrades — it never crashes the alarm" {
  refusals 30
  export CC_RESIDENCY_SH="$BATS_TEST_TMPDIR/definitely-not-deployed"
  run "$S" --log "$LOG"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "no world reading (absent)"
}

@test "json carries the source and the world figures alongside the original keys" {
  refusals 2; closes 20
  stub_world "ALARM members=15 resident=12 stale=12 departed=0 ours=0 vendor=0"
  run "$S" --log "$LOG" --json
  [ "$status" -eq 2 ]
  # The original keys keep their meaning — cc-blockers:734 reads these.
  echo "$output" | grep -q '"verdict":"ALARM"'
  echo "$output" | grep -q '"closes":0'
  # …and the provenance is now legible, including the log figures the verdict did NOT use.
  echo "$output" | grep -q '"source":"world"'
  echo "$output" | grep -q '"stale":12'
  echo "$output" | grep -q '"log_closes":20'
}

# ══ THE CADENCE ═══════════════════════════════════════════════════════════════════════════════════
# The defect this commit exists to fix is not in the alarm's logic — it is that nothing ever RAN it.
# Its only caller was bin/cc-blockers:161, a board rendered on PULL when an agent happens to invoke
# /ship, and the label was in no launchctl list at all. So the plist is part of the deliverable, and
# so is its DECLARATION: an undeclared plist makes launchd/fleet.manifest go red on whoever lands
# next (capacity-alarm and scratchpad-reaper each cost that), and install.sh refuses to activate what
# the manifest does not declare.
@test "the plist exists and is well-formed" {
  [ -f "$REPO/launchd/com.claude.teammate-reap-alarm.plist" ]
  run plutil -lint "$REPO/launchd/com.claude.teammate-reap-alarm.plist"
  [ "$status" -eq 0 ]
}

# The two commands must run in this order: the alarm reads the cursor left by the PREVIOUS tick,
# THEN the sampler advances it. Reversed, every tick differences against a set written moments
# earlier by itself, `departed` is 0 by construction forever, and a healthy fleet reports a dead
# close path. This is invisible in any single run, so it is pinned textually.
@test "the plist runs the alarm BEFORE the sampler advances the cursor" {
  local args; args="$(sed -n '/<string>export PATH/p' "$REPO/launchd/com.claude.teammate-reap-alarm.plist")"
  local a s
  a="$(printf '%s' "$args" | grep -o 'teammate-reap-alarm.sh' | head -1)"
  [ -n "$a" ]
  # The alarm's offset must be smaller than the sampler's.
  run bash -c "printf '%s' '$args' | awk '{ print index(\$0, \"teammate-reap-alarm.sh\"), index(\$0, \"assignee-pane-residency.sh\") }'"
  s="$output"
  [ "${s%% *}" -lt "${s##* }" ]
}

@test "the plist is DECLARED in the fleet manifest, staged, with its verdict exits" {
  run grep -E "^com\.claude\.teammate-reap-alarm[[:space:]]*\|" "$REPO/launchd/fleet.manifest"
  [ "$status" -eq 0 ]
  # staged, not run: loading a launchd job is a C10 operator decision, and this commit does not make
  # it. `staged` renders as exactly ONE UNDECIDED row — "declared, decision pending", never silent.
  echo "$output" | grep -qE "\|[[:space:]]*staged[[:space:]]*\|"
  # ok_exits must cover every DESIGNED verdict. Without it cc-fleet files a permanent, unfixable
  # daemon-fault row for as long as the outage the alarm is correctly reporting lasts.
  echo "$output" | grep -qE "\|[[:space:]]*0,1,2,3[[:space:]]*$"
}

@test "the activation script exists and its dry run refuses to act without CONFIRM" {
  local A="$REPO/docs/activation/pending-activation/30-teammate-reap-alarm-activate.sh"
  [ -f "$A" ]
  run bash -n "$A"
  [ "$status" -eq 0 ]
  # SAMPLE THE LOAD STATE FIRST. The final assertion used to be `[ "$status" -ne 0 ]` on a bare
  # `launchctl print` — i.e. "this service is not loaded", which is a statement about the BOX, not
  # about the dry run. Once the alarm is genuinely activated here (it is, today) that assertion is
  # false no matter how perfectly the dry run behaves: the suite reds on pristine origin/main, and
  # it takes down any land whose diff merely touches launchd/fleet.manifest. The subject is "the dry
  # run did not ACT", so the assertion has to be UNCHANGED-ness across the call, which is true on a
  # box where the service is loaded and on one where it is not (memory:
  # assertion-span-must-equal-its-subject).
  local before after
  /bin/launchctl print "gui/$(id -u)/com.claude.teammate-reap-alarm" >/dev/null 2>&1 && before=loaded || before=absent
  run env CC_REPO="$REPO" bash "$A"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "dry run"
  # A dry run must not have loaded anything (memory: dry-run-cannot-preview-what-it-gates — side
  # effects inside an `if ! $DRY_RUN` are invisible BY CONSTRUCTION, so assert the EFFECT's absence).
  if printf '%s\n' "$output" | grep -q "bootstrap failed\|Load failed"; then
    echo "the dry run touched launchctl" >&2; false
  fi
  /bin/launchctl print "gui/$(id -u)/com.claude.teammate-reap-alarm" >/dev/null 2>&1 && after=loaded || after=absent
  [ "$after" = "$before" ] || {
    echo "the dry run CHANGED the load state: $before -> $after" >&2; false; }
}
