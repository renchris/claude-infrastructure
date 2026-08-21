#!/usr/bin/env bats
# browser-spin-guard — the arm that would have caught the 2026-08-17 wedged-Chrome incident.
#
# Harness laws (adopted from tests/reaper-horizon-lint.bats): L1 the fixture is the REAL artifact —
# every pegged row below is a verbatim `ps` row measured during the live incident, not a
# hand-written approximation (memory: control-must-replay-the-real-artifact); L2 every assertion is
# failure-distinct, so the fixture that RED-proves a branch goes green when the defect is undone;
# L3 `[ ]` / `grep -q` only; L4 the silent-blindness path (no snapshot) is tested, not just the
# loud ones.
#
# WHY THE NEGATIVE CONTROLS CARRY THE WEIGHT HERE. A detector that fires is easy; this one's risk is
# that it fires on the operator's OWN browser, or on a warm idle automation browser that is working
# exactly as designed. Tests 3-5 pin all three ways it must stay silent, and each is derived from a
# real population on this box (Dia at 55 processes, a warm agent-browser daemon, a young burst).
# Test 6 is the control's control: it proves the quiet cases are quiet for the RIGHT reason by
# moving one field and watching the same fixture go loud.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  GUARD="$REPO/scripts/browser-spin-guard.sh"
  FIX="$BATS_TEST_TMPDIR/ps.txt"
  export CC_SPIN_GUARD_LOG="$BATS_TEST_TMPDIR/guard.log"
  # Pin the floors so a future default change cannot silently rewrite what these cases mean.
  export CC_SPIN_PCT=80
  export CC_SPIN_AGE_S=900
}

# The incident, verbatim: an agent-browser-owned headless Chrome. Root at 0.1% (it was NOT the
# spinner — the helpers were), eight helpers at 86-103% against lifetimes of 8h-1d15h.
write_incident_fixture() {
  cat > "$FIX" <<'EOF'
80986  3153 01-15:08:10   0.1 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome --remote-debugging-port=0 --no-first-run --no-default-browser-check
81066 80986 01-15:08:10 100.6 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper (GPU).app/Contents/MacOS/Google Chrome Helper (GPU) --type=gpu-process --headless=new
81128 80986 01-15:08:10  99.3 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer) --type=renderer --top-chrome-webui
81067 80986 01-15:08:10  91.2 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper --type=utility --utility-sub-type=network.mojom.NetworkService
81070 80986 01-15:08:10  92.2 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper --type=utility --utility-sub-type=storage.mojom.StorageService
52816 80986 01-12:30:13  90.2 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper --type=utility --utility-sub-type=audio.mojom.AudioService
53208 80986 01-12:30:11  92.4 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper --type=utility --utility-sub-type=video_capture.mojom.VideoCaptureService
 8785 80986    08:36:25  98.2 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer) --type=renderer
59523 80986    08:37:38  99.7 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer) --type=renderer
 3153     1 02-21:09:01   0.0 /Users/x/Library/Application Support/fnm/node-versions/v22.21.1/installation/lib/node_modules/agent-browser/bin/agent-browser-darwin-arm64
EOF
}

@test "1: the real incident is detected — verdict=spin over all 8 pegged helpers" {
  write_incident_fixture
  CC_SPIN_GUARD_PS="$FIX" run bash "$GUARD"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'verdict=spin'
  # 8 helpers pegged; the 0.1% root and the 0.0% daemon are NOT among them.
  echo "$output" | grep -q '8 processes'
  # 764 = the eight fixture rows summed (763.8). NOT the 761 quoted in the incident narrative:
  # that figure was the live aggregate over EVERY Chrome process at a slightly later instant, a
  # different population from these eight rows. Asserting the narrative's number here would have
  # pinned the test to a quantity the fixture cannot produce.
  echo "$output" | grep -q '764%'
}

@test "2: the report names the roles, so the operator sees it is the whole service tree" {
  write_incident_fixture
  CC_SPIN_GUARD_PS="$FIX" run bash "$GUARD"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'gpu'
  echo "$output" | grep -q 'renderer'
  echo "$output" | grep -q 'network.mojom.NetworkService'
  echo "$output" | grep -q 'video_capture.mojom.VideoCaptureService'
  # and it must hand over the one drivable remedy
  echo "$output" | grep -q 'agent-browser close --all'
}

@test "3: NEGATIVE — a warm IDLE automation browser is silent (this is the designed steady state)" {
  # Same tree, same ages, same flags. Only the CPU column differs. `agent-browser` keeps a browser
  # warm on purpose; if this fired, the guard would page on correct behaviour forever.
  cat > "$FIX" <<'EOF'
80986  3153 01-15:08:10   0.1 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome --remote-debugging-port=0 --no-first-run
81066 80986 01-15:08:10   0.3 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper (GPU).app/Contents/MacOS/Google Chrome Helper (GPU) --type=gpu-process --headless=new
81128 80986 01-15:08:10   1.2 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer) --type=renderer
EOF
  CC_SPIN_GUARD_PS="$FIX" run bash "$GUARD"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'verdict=clean'
}

@test "4: NEGATIVE — the operator's OWN pegged browser is out of population, not merely excused" {
  # Dia and a hand-launched Chrome never carry --remote-debugging-port. Pegged at 99% for hours and
  # the guard must still say nothing: this arm has no opinion about the operator's own browsing.
  cat > "$FIX" <<'EOF'
 1671     1 07:55:33  99.4 /Applications/Dia.app/Contents/MacOS/Dia
43167  1671 06:24:54  98.1 /Applications/Dia.app/Contents/Frameworks/ArcCore.framework/Helpers/Browser Helper (Renderer).app/Contents/MacOS/Browser Helper (Renderer) --type=renderer
  902     1 05:11:02  97.0 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
EOF
  CC_SPIN_GUARD_PS="$FIX" run bash "$GUARD"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'verdict=clean'
}

@test "5: NEGATIVE — a YOUNG pegged automation helper is silent (a burst is not a wedge)" {
  # 4 minutes old at 99%. Real automation pegs a core in bursts; the age floor is what separates a
  # working browser from a wedged one, and without it this guard would fire on every screenshot.
  cat > "$FIX" <<'EOF'
80986  3153 04:10   0.1 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome --remote-debugging-port=0
81066 80986 04:08  99.2 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper (GPU).app/Contents/MacOS/Google Chrome Helper (GPU) --type=gpu-process
EOF
  CC_SPIN_GUARD_PS="$FIX" run bash "$GUARD"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'verdict=clean'
}

@test "6: the quiet cases are quiet for the RIGHT reason — age it past the floor and it fires" {
  # The control's control (L2). Test 5's fixture, one field moved: 04:08 -> 04:08:00 (4h 8m). If
  # test 5 were passing because of a parse failure or a dropped row rather than the age floor, this
  # would stay clean too.
  cat > "$FIX" <<'EOF'
80986  3153 04:10:00   0.1 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome --remote-debugging-port=0
81066 80986 04:08:00  99.2 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper (GPU).app/Contents/MacOS/Google Chrome Helper (GPU) --type=gpu-process
EOF
  CC_SPIN_GUARD_PS="$FIX" run bash "$GUARD"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'verdict=spin'
  echo "$output" | grep -q '1 processes'
}

@test "7: no snapshot is 'unknown', never a failure exit (acquit-only detector)" {
  # L4, the silent-blindness path. An empty ps must not read as 'clean' — that would be a green
  # gate over an unread instrument — and must not exit non-zero either, because on this box a
  # non-zero exit is an inbox that mints work items (memory: null-result-must-not-use-the-error-channel).
  : > "$FIX"
  CC_SPIN_GUARD_PS="$FIX" run bash "$GUARD"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'verdict=unknown'
}

@test "8: the kill switch makes the arm inert" {
  write_incident_fixture
  CC_SPIN_GUARD=0 CC_SPIN_GUARD_PS="$FIX" run bash "$GUARD"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'verdict=clean'
  echo "$output" | grep -q 'disabled'
}

@test "9: --reap kills exactly the pegged members, never the root or the daemon" {
  write_incident_fixture
  COLLECT="$BATS_TEST_TMPDIR/killed.txt"; : > "$COLLECT"
  cat > "$BATS_TEST_TMPDIR/killer.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$1" >> "$COLLECT"
EOF
  chmod +x "$BATS_TEST_TMPDIR/killer.sh"
  cat > "$BATS_TEST_TMPDIR/closer.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/closer.sh"
  CC_SPIN_GUARD_PS="$FIX" \
  CC_SPIN_GUARD_KILL="$BATS_TEST_TMPDIR/killer.sh" \
  CC_SPIN_GUARD_CLOSE="$BATS_TEST_TMPDIR/closer.sh" \
    run bash "$GUARD" --reap
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'reaped 8 of 8'
  # the eight spinners are in
  grep -q '^81066$' "$COLLECT"
  grep -q '^53208$' "$COLLECT"
  grep -q '^59523$' "$COLLECT"
  # the browser ROOT (0.1%) and the agent-browser DAEMON (0.0%) are NOT — killing the root would
  # be defensible, killing the daemon would break the next session's browser for no reason.
  #
  # NOT `! grep -q …`: bash suppresses errexit for any command in a tested context, and `!` is one,
  # so a bare negation here can never fail the test — it reads as an assertion and is dead code.
  # The land gate's dead-assertion ratchet caught exactly this on these two lines. `run` + an
  # explicit `[ ]` puts the check back in a context errexit CAN kill the test from. Both directions
  # mutant-verified: flipping -ne to -eq reds this test, so the assertion is genuinely live.
  run grep -q '^80986$' "$COLLECT"
  [ "$status" -ne 0 ]
  run grep -q '^3153$' "$COLLECT"
  [ "$status" -ne 0 ]
}

@test "11: --notify speaks on the EDGE (clean -> spin)" {
  write_incident_fixture
  SENT="$BATS_TEST_TMPDIR/sent.txt"; : > "$SENT"
  cat > "$BATS_TEST_TMPDIR/notifier.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$1" >> "$SENT"
EOF
  chmod +x "$BATS_TEST_TMPDIR/notifier.sh"
  CC_SPIN_GUARD_PS="$FIX" \
  CC_SPIN_GUARD_NOTIFY="$BATS_TEST_TMPDIR/notifier.sh" \
  CC_SPIN_GUARD_STATE="$BATS_TEST_TMPDIR/state" \
    run bash "$GUARD" --notify
  [ "$status" -eq 0 ]
  [ -s "$SENT" ]
  grep -q 'agent-browser close --all' "$SENT"
}

@test "12: --notify is DAMPED on a repeat while still spinning" {
  write_incident_fixture
  SENT="$BATS_TEST_TMPDIR/sent.txt"; : > "$SENT"
  cat > "$BATS_TEST_TMPDIR/notifier.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$1" >> "$SENT"
EOF
  chmod +x "$BATS_TEST_TMPDIR/notifier.sh"
  for _ in 1 2 3; do
    CC_SPIN_GUARD_PS="$FIX" \
    CC_SPIN_GUARD_NOTIFY="$BATS_TEST_TMPDIR/notifier.sh" \
    CC_SPIN_GUARD_STATE="$BATS_TEST_TMPDIR/state" \
      run bash "$GUARD" --notify
  done
  # three ticks, ONE message — a 5-minute job must not page every tick for a day and a half
  [ "$(wc -l < "$SENT" | tr -d ' ')" = "1" ]
}

@test "13: a clean tick re-arms the edge — the damped alarm does not go permanently silent" {
  # THE FAILURE THIS PINS: if the clean branch did not write state, the state file would stay
  # 'spin' forever after the first fire, and the NEXT genuine wedge — hours or days later, a
  # separate incident — would be swallowed as a continuation of the old one. That is a damped
  # alarm degrading into no alarm, which is strictly worse than never having damped it.
  SENT="$BATS_TEST_TMPDIR/sent.txt"; : > "$SENT"
  cat > "$BATS_TEST_TMPDIR/notifier.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$1" >> "$SENT"
EOF
  chmod +x "$BATS_TEST_TMPDIR/notifier.sh"
  run_tick() {
    CC_SPIN_GUARD_PS="$FIX" \
    CC_SPIN_GUARD_NOTIFY="$BATS_TEST_TMPDIR/notifier.sh" \
    CC_SPIN_GUARD_STATE="$BATS_TEST_TMPDIR/state" \
      bash "$GUARD" --notify
  }
  write_incident_fixture;                  run_tick    # spin  -> sends (1)
  printf '' > "$FIX"; printf '1 1 01:00 0.0 /sbin/launchd\n' > "$FIX"; run_tick   # clean -> re-arms
  write_incident_fixture;                  run_tick    # spin  -> must send AGAIN (2)
  [ "$(wc -l < "$SENT" | tr -d ' ')" = "2" ]
}

@test "10: --json emits parseable output carrying the same verdict" {
  write_incident_fixture
  CC_SPIN_GUARD_PS="$FIX" run bash "$GUARD" --json
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"verdict":"spin"'
  echo "$output" | grep -q '"pegged":8'
  # the push/pull renderers must not drift: JSON and text agree on the aggregate
  echo "$output" | grep -q '"cpu_pct_total":764'
}

# ── the 2026-08-20 recurrence: a perfect detector wired to nothing ────────────────────────────
# The guard was loaded, correct and ignored for 2 d 20 h. Two defects made that possible and each
# gets a case here. 14/15: the log ASSERTED delivery it never checked, so the one artifact that
# could have shown the alarm was going nowhere instead read "SENT". 16: the reap is what makes an
# undelivered alarm survivable, so the arming itself must be pinned — it has been reverted once
# already (b1a46b713) and a silent second revert returns the box to the incident.

@test "14: a FAILING transport is logged UNDELIVERED, never SENT" {
  # RED-PROOF: pre-fix this logged "SENT" unconditionally after `|| true` — the claimed-outcome
  # class. The whole incident log carries one "SENT" line and it is a claim, not an observation.
  write_incident_fixture
  cat > "$BATS_TEST_TMPDIR/notifier.sh" <<'EOF'
#!/usr/bin/env bash
exit 3
EOF
  chmod +x "$BATS_TEST_TMPDIR/notifier.sh"
  CC_SPIN_GUARD_PS="$FIX" \
  CC_SPIN_GUARD_NOTIFY="$BATS_TEST_TMPDIR/notifier.sh" \
  CC_SPIN_GUARD_STATE="$BATS_TEST_TMPDIR/state" \
    run bash "$GUARD" --notify
  [ "$status" -eq 0 ]
  grep -q 'notify: UNDELIVERED rc=3' "$CC_SPIN_GUARD_LOG"
  # failure-distinct: the false claim must be ABSENT, not merely accompanied by the truth
  ! grep -q 'notify: SENT' "$CC_SPIN_GUARD_LOG"
}

@test "15: no transport on PATH is NO-TRANSPORT — a launchd env defect, not a quiet box" {
  write_incident_fixture
  CC_SPIN_GUARD_PS="$FIX" \
  CC_SPIN_GUARD_STATE="$BATS_TEST_TMPDIR/state" \
    run env PATH=/usr/bin:/bin bash "$GUARD" --notify
  [ "$status" -eq 0 ]
  grep -q 'notify: NO-TRANSPORT' "$CC_SPIN_GUARD_LOG"
  ! grep -q 'notify: SENT' "$CC_SPIN_GUARD_LOG"
}

@test "16: the shipped plist ARMS the reap — detect-only is what let the box burn twice" {
  PLIST="$REPO/launchd/com.claude.browser-spin-guard.plist"
  [ -f "$PLIST" ]
  # the flag must be on the EXECUTED line, not merely somewhere in the prose header
  run grep -E '^\s*<string>export PATH=.*browser-spin-guard\.sh.*--reap' "$PLIST"
  [ "$status" -eq 0 ]
  # and --notify must survive alongside it: reaping silently is how the operator stops learning
  echo "$output" | grep -q -- '--notify'
}
