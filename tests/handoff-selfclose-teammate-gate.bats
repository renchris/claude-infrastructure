#!/usr/bin/env bats
# handoff-fire.sh self-close — LIVE-TEAMMATE GATE + HUSK-PANE RETRY (2026-07-26).
#
# THE INCIDENT THAT IS THE SPEC (team session-a3f68174, 2026-07-26T01:36Z):
#   A lead finished its own work, force-removed its assignees' worktrees
#   (`git worktree remove --force /private/tmp/wt-gr-t{1..6}`), and one tool call later ran
#   `handoff-fire.sh self-close --terminal`. Its EIGHT assignees were still running. Four hours
#   later all eight were alive, holding 3.4 GB, their lead gone, every final report reachable only
#   by digging its transcript off disk. The pre-close inventory saw none of it: it counts unread
#   mail and orphaned FIRES, and it only ever WARNs.
#   Then the second half failed too — `it2 session close` returned "There was a problem connecting
#   to iTerm2" (1 of 16 real self-closes that day), so `/exit` had already killed CC but the pane
#   stayed open at a shell prompt. That husk is precisely what an operator reads as "my session
#   ended abruptly", and it strands a FRESH teardown marker on a reusable pane — the precondition
#   for the crash-watchdog false-absolution class (marker_owns_sid).
#
# G1-G4 lock the gate (blocking, not warning). H1-H3 lock the retry + the loud husk page.
#
# Isolation: `ps` is PATH-shimmed to serve a synthetic process table (the argv oracle
# `--team-name session-<sid8>` is the whole contract); the registry dir is redirected via
# CC_REGISTRY_DIR; `sleep` is shimmed to a no-op so the retry ladder costs no wall-clock. The
# helper units are sed-extracted and sourced, mirroring tests/handoff-selfclose.bats.

setup() {
  # M11 (MACHINE_CAPACITY_V2 §11.3) — a test's environment is PINNED, not ambient. handoff-fire.sh's
  # capacity_gate reads the box's live loadavg AND (M10) its memory headroom, exiting 9 when either is
  # past its bar, so an unpinned suite goes RED purely because the box is busy — the corpus deciding a
  # verdict on machine state instead of on the tree. Both terms are pinned off here (they are the two
  # TERMS of one exit 9, handoff-fire.sh:4487); tests/handoff-fire-capacity-gate.bats is the ONE place
  # the gate runs ON, against synthetic inputs.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  # HERMETIC $HOME (scripts/test-hermeticity-lint.sh — the ratchet that binds every NEW suite):
  # the subject resolves its own state under ~, so unfixtured this suite reads/writes the
  # operator's LIVE layer. Everything this suite asserts is already redirected elsewhere.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"

  export PSTAB="$BATS_TEST_TMPDIR/pstab"; : > "$PSTAB"
  # ps shim: `-Ao pid=,args=` emits the synthetic table; `-o comm= -t <tty>` reports the pane
  # liveness the watcher polls. EMPTY means the tty is UNREADABLE, which is `unknown` — not "CC
  # already gone", the conflation this comment carried until 2026-08-08 (item 71909cbeee08). Both
  # states skip the 180s loop identically (pane_cc_state != cc), so nothing about these tests'
  # timing depends on the distinction; only the post-close DIAGNOSIS does, and H2 asserts it.
  cat > "$SHIM/ps" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *"-Ao"*) cat "${PSTAB:-/dev/null}" ;;
  *"-t"*)  [ "${PS_CC_ALIVE:-0}" = 1 ] && echo claude ;;
  *"eww"*) printf '%s\n' "${PS_ENV_BLOB:-}" ;;   # G3b: cc_sid_for_pane's pane→pid env probe
  *)       : ;;
esac
exit 0
SH
  chmod +x "$SHIM/ps"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$SHIM/sleep"; chmod +x "$SHIM/sleep"
  # Re-point $PANE's fired-peer stamp at the CURRENT cwd. The origin gate tenancy-binds the stamp on
  # cwd (item aba6bcbff6de), so the several tests below that deliberately `cd` to a NON-GIT directory
  # (to reach the dirty-tree contract) must re-stamp after moving, or they are refused at the origin
  # gate and never reach the teammate gate they exist to test. Called once in setup for the tests
  # that stay put, and again after each `cd`.
  stamp_pane_here() {
    printf '{"paneUUID":"%s","cwd":"%s","firedBy":"ORIGINATOR","firedAt":"2026-07-26T18:00:00Z","selfRetire":true}\n' \
      "$PANE" "$PWD" > "$CC_FIRED_DIR/$PANE.json"
  }
  export BATS_SAVED_PATH="$PATH"     # G7 drops the shim to hit the REAL process table
  export PATH="$SHIM:$PATH"

  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/registry"; mkdir -p "$CC_REGISTRY_DIR"
  PANE="1FBFCD05-FF27-4B8E-958C-47753BC90D2A"
  CCSID="a3f68174-77a6-425b-b499-b2b7d4c86a0e"
  export PANE CCSID
  printf '{\n    "paneUUID": "%s",\n    "session_id": "%s"\n}\n' "$PANE" "$CCSID" \
    > "$CC_REGISTRY_DIR/$PANE.json"

  # ORIGIN GATE (2026-07-26): only a session FIRED BY an originator may self-close. This suite
  # exercises the LIVE-TEAMMATE gate on a peer that is legitimately entitled to retire, so stamp
  # $PANE as a fired peer — otherwise the origin gate refuses first and masks what these tests
  # assert. (An unstamped LEAD is exactly what the origin gate is meant to stop; that is covered
  # in tests/handoff-selfclose.bats.)
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/cc-fired"; mkdir -p "$CC_FIRED_DIR"
  # cwd is THIS PANE's cwd, not a hardcoded "/tmp": the origin gate tenancy-binds the stamp on cwd
  # (item aba6bcbff6de), so a placeholder path makes $PANE a stale tenant and the tests below refuse
  # at the ORIGIN gate before reaching the teammate gate they are about.
  stamp_pane_here

  # sed-extract the two helpers so the units are testable without running the whole script.
  HELPERS="$BATS_TEST_TMPDIR/helpers.sh"
  sed -n '/^cc_sid_for_pane() {/,/^}/p;/^live_teammates_of() {/,/^}/p' "$HF" > "$HELPERS"
  # shellcheck disable=SC1090
  . "$HELPERS"
}

seed_teammate() { # $1=agent-name $2=pid $3=team-sid8
  printf '%s /Users/x/.claude-219/node_modules/@anthropic-ai/claude-code/bin/claude.exe --agent-id %s@session-%s --agent-name %s --team-name session-%s --model opus\n' \
    "$2" "$1" "$3" "$1" "$3" >> "$PSTAB"
}

# ── G1: the argv oracle finds live assignees ──────────────────────────────────────────────
@test "G1: live_teammates_of returns one name+pid line per live assignee" {
  seed_teammate t2-shipland 5375 a3f68174
  seed_teammate t6-flakefixes 51563 a3f68174
  run live_teammates_of "$CCSID"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 2 ]
  printf '%s\n' "$output" | grep -q "^t2-shipland	5375$"
  printf '%s\n' "$output" | grep -q "^t6-flakefixes	51563$"
}

# ── G2: a foreign team must never count as ours ───────────────────────────────────────────
@test "G2: assignees of a DIFFERENT team are not attributed to this session" {
  seed_teammate x1-other 4242 deadbeef
  run live_teammates_of "$CCSID"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── G3: the pane→CC-sid recovery the gate depends on ──────────────────────────────────────
@test "G3: cc_sid_for_pane recovers the CC session id from the registry row" {
  run cc_sid_for_pane "$PANE"
  [ "$status" -eq 0 ]
  [ "$output" = "$CCSID" ]
}

# ── G3b: a PROVISIONAL row must not silently disarm the gate ──────────────────────────────
# RED before the fix. ensure_registration (P0-12) writes {paneUUID,name,cwd,cmd,provisional} with
# NO session_id when no SessionStart row lands inside FIRE_REG_TIMEOUT — the steady state for a
# fired peer (measured 2026-08-05: 10 of 19 live rows provisional-or-backfilled). cc_sid_for_pane
# returned EMPTY, so the gate took its "missing row" branch, WARNed to a stderr no retiring peer
# reads, and live_teammates_of "" returned nothing — a PASS. The sid was recoverable the whole
# time from CC's own per-pid registry, which is what this locks.
@test "G3b: cc_sid_for_pane falls back to CC's own session file when the row is provisional" {
  printf '{"paneUUID":"%s","name":"peer","cwd":"/tmp","cmd":"claude","provisional":true}\n' \
    "$PANE" > "$CC_REGISTRY_DIR/$PANE.json"
  run cc_sid_for_pane "$PANE"                      # control: the row alone cannot answer
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  export CC_SESSIONS_DIRS="$BATS_TEST_TMPDIR/sessions"; mkdir -p "$CC_SESSIONS_DIRS"
  printf '{"pid":%s,"sessionId":"%s","kind":"interactive"}\n' "$$" "$CCSID" \
    > "$CC_SESSIONS_DIRS/$$.json"                  # $$ is live, so kill -0 passes
  export PS_ENV_BLOB="ITERM_SESSION_ID=w0t0p0:$PANE"
  run cc_sid_for_pane "$PANE"
  [ "$status" -eq 0 ]
  [ "$output" = "$CCSID" ]
}

# ── G3c: the fallback must never resurrect a DEAD session's sid ───────────────────────────
# A pane id is not a tenancy (7c049231): kitty reuses ids, so a session file naming a dead pid must
# not authorise anything on the pane that inherited its number. kill -0 is the guard.
@test "G3c: cc_sid_for_pane ignores a session file whose pid is dead" {
  printf '{"paneUUID":"%s","name":"peer","cwd":"/tmp","cmd":"claude","provisional":true}\n' \
    "$PANE" > "$CC_REGISTRY_DIR/$PANE.json"
  export CC_SESSIONS_DIRS="$BATS_TEST_TMPDIR/sessions"; mkdir -p "$CC_SESSIONS_DIRS"
  # pid 2^31-1: reserved-high, never live on darwin — a dead-pid row by construction
  printf '{"pid":2147483647,"sessionId":"%s","kind":"interactive"}\n' "$CCSID" \
    > "$CC_SESSIONS_DIRS/dead.json"
  export PS_ENV_BLOB="ITERM_SESSION_ID=w0t0p0:$PANE"
  run cc_sid_for_pane "$PANE"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── G4: THE GATE — self-close REFUSES while assignees live, and names them ────────────────
# RED before the fix: self-close proceeded (the inventory only WARNed), exit 0 under --dry-run.
@test "G4: self-close is REFUSED (exit 4) with live teammates, and names each one" {
  seed_teammate t2-shipland 5375 a3f68174
  seed_teammate t5-deploy   26319 a3f68174
  run bash "$HF" self-close --terminal --session-id "$PANE" --dry-run
  [ "$status" -eq 4 ]
  [[ "$output" == *"REFUSED"* ]] || false
  [[ "$output" == *"2 LIVE teammate(s)"* ]] || false
  [[ "$output" == *"t2-shipland"* ]] || false
  [[ "$output" == *"t5-deploy"* ]]
}

# ── G5: the escape hatch works, and is LOUD ───────────────────────────────────────────────
# G5/G6 run from a NON-git cwd: past the gate, self-close still applies its dirty-tree guard,
# and the bats worktree itself is dirty — that refusal is a different (pre-existing) contract.
@test "G5: --allow-live-teammates proceeds but announces the deliberate orphaning" {
  seed_teammate t2-shipland 5375 a3f68174
  cd "$BATS_TEST_TMPDIR"; stamp_pane_here
  run bash "$HF" self-close --terminal --session-id "$PANE" --dry-run --allow-live-teammates
  [ "$status" -eq 0 ]
  [[ "$output" == *"ORPHANED deliberately"* ]]
}

# ── G6: no team ⇒ the gate is invisible (no behaviour change for solo sessions) ────────────
@test "G6: a session with no live teammates self-closes exactly as before" {
  cd "$BATS_TEST_TMPDIR"; stamp_pane_here
  run bash "$HF" self-close --terminal --session-id "$PANE" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"REFUSED"* ]] || false
  [[ "$output" == *"dry run (self-close)"* ]]
}

# ── G7: SELF-MATCH — the one every shimmed test is blind to ───────────────────────────────
# The first implementation used `awk -v tag="--team-name session-<sid8>"`, which puts the tag
# verbatim into awk's OWN argv — so awk matched itself and the function returned >=1 for EVERY
# session. The gate would then have refused every self-close, including solo sessions. G2/G6
# stayed GREEN throughout, because a shimmed `ps` serves a static fixture that contains no
# pipeline. Only the REAL process table exposes it. This test therefore drops the shim on
# purpose — it is the fixture-parity guard for this function (cf. tests/*: a fixture is a
# contract claim; assert once against the producer's literal live emission).
@test "G7: against the REAL process table, a session with no team returns EXACTLY zero (no self-match)" {
  PATH="$BATS_SAVED_PATH" run live_teammates_of "cd122396-8ed1-4f29-92be-20dad7b4c6c7"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "G7b: against the REAL process table, a nonexistent team returns zero" {
  PATH="$BATS_SAVED_PATH" run live_teammates_of "deadbeef-0000-0000-0000-000000000000"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── G8: fail-open must never be SILENT ────────────────────────────────────────────────────
# The oracle needs the CC session id, and only the pane's registry row carries it. With no row
# the gate passes — correct (fail-closed would deadlock every self-close when the registry is
# unavailable) but it must SAY SO, or a lead silently orphans its team on a false all-clear.
@test "G8: a missing registry row WARNS that the teammate check could not run (fail-open, never silent)" {
  rm -f "$CC_REGISTRY_DIR/$PANE.json"
  seed_teammate t2-shipland 5375 a3f68174        # a team IS live, but unresolvable from the pane
  cd "$BATS_TEST_TMPDIR"; stamp_pane_here
  run bash "$HF" self-close --terminal --session-id "$PANE" --dry-run
  [ "$status" -eq 0 ]                             # fail-OPEN: the close proceeds
  [[ "$output" == *"live-teammate check SKIPPED"* ]] || false # …but never silently
  [[ "$output" == *"ORPHANS"* ]]
}

@test "G8b: with a registry row present, no skip-warning is emitted (no false noise)" {
  cd "$BATS_TEST_TMPDIR"; stamp_pane_here
  run bash "$HF" self-close --terminal --session-id "$PANE" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"SKIPPED"* ]]
}

# ── H1-H3: the husk-pane retry ────────────────────────────────────────────────────────────
_arm_watcher_home() { # builds a $HOME with recording it2 + cc-notify stubs
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/bin"
  # PIN THE TERMINAL. handoff-fire's primitives branch on the terminal, so run from inside kitty —
  # or from an iTerm2 pane that merely INHERITED KITTY_* — this suite's verdict becomes a function
  # of the developer's environment rather than of its subject. Same pin, same reason, as
  # tests/handoff-selfclose.bats and tests/handoff-fire-pane-proof.bats.
  unset KITTY_WINDOW_ID; export IT2_WRAPPER_NO_KITTY=1; unset CC_TERM
  export STUB_PANE="$PANE"     # the listing must enumerate the pane these tests model
  export IT2_LOG="$BATS_TEST_TMPDIR/it2.log";     : > "$IT2_LOG"
  export NOTIFY_LOG="$BATS_TEST_TMPDIR/notify.log"; : > "$NOTIFY_LOG"
  # it2 stub: fails the first $IT2_FAIL_N `session close` calls, then succeeds.
  # `session list` must ENUMERATE the pane these tests model. H1-H3 are about what the CLOSE does
  # when it2 flakes — a stage the watcher only reaches once pane_proof has proven the pane
  # reachable. A stub answering the empty list refuses at the probe and never runs the retry loop
  # under test, which is why all three have been RED on trunk since the reachability handshake
  # landed (2026-08-02). Answers both shapes the real transports emit (`--json` and bare ids), so
  # the fixture cannot silently model only the transport that happened to work.
  cat > "$HOME/.claude/bin/it2" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${IT2_LOG:?}"
case "$*" in
  "session list"*)
    if [ "${3:-}" = --json ]; then printf '[{"id": "%s", "tty": "/dev/ttys999"}]\n' "${STUB_PANE:-PANE-A}"
    else printf '%s\n' "${STUB_PANE:-PANE-A}"; fi
    exit 0 ;;
  *"session close"*)
    n=$(grep -c "session close" "$IT2_LOG")
    if [ "$n" -le "${IT2_FAIL_N:-0}" ]; then
      echo "There was a problem connecting to iTerm2." >&2; exit 1
    fi ;;
esac
exit 0
SH
  chmod +x "$HOME/.claude/bin/it2"
  cat > "$HOME/.claude/bin/cc-notify" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${NOTIFY_LOG:?}"
exit 0
SH
  chmod +x "$HOME/.claude/bin/cc-notify"
  export PS_CC_ALIVE=0   # CC already exited ⇒ watcher goes straight to the close
}

@test "H1: a transient it2 failure is retried and the pane still closes" {
  _arm_watcher_home; export IT2_FAIL_N=2
  run bash "$HF" __selfclose "$PANE" /dev/ttys022 "" ""
  [ "$status" -eq 0 ]
  [ "$(grep -c 'session close' "$IT2_LOG")" -eq 3 ]   # 2 failures + 1 success
  [[ "$output" == *"retrying in 2s"* ]] || false
  [ ! -s "$NOTIFY_LOG" ]                              # recovered ⇒ no page
}

@test "H2: 4/4 it2 failures page the desk LOUD instead of leaving a silent husk" {
  _arm_watcher_home; export IT2_FAIL_N=99
  run bash "$HF" __selfclose "$PANE" /dev/ttys022 "" ""
  [ "$(grep -c 'session close' "$IT2_LOG")" -eq 4 ]   # bounded — exactly 4 attempts
  [[ "$output" == *"PANE CLOSE FAILED"* ]] || false
  # THE DIAGNOSIS FOLLOWS THE FIXTURE (updated 2026-08-08, item 71909cbeee08). This used to assert
  # the literal word HUSK and the HANDOFF-HUSK-PANE page — i.e. "claude exited, the session is
  # already gone". But the ps shim above answers EVERY `-t` form empty when PS_CC_ALIVE=0, and
  # pane_cc_state's own rule is that a tty with no readable processes is `unknown`, never
  # shell-only ("Believing it 'shell-only' is the fail-dangerous default itself"). So this fixture
  # models an UNREADABLE tty, and the old assertion pinned the subject asserting a death it had
  # never checked — the exact false report of session c5f80b8b (2026-07-30), where the session was
  # live and answering. A test pinning behaviour the subject changed in order to PREVENT stops
  # being stale and starts guarding the bug (memory: stale-assertion-becomes-an-inverted-guard).
  # THE TEST'S INTENT IS UNCHANGED and still fully asserted: bounded retries, a loud failure line,
  # and a desk page. Only the claim about WHAT was found moved, to the one this fixture earns. The
  # husk and still-alive branches are pinned in tests/handoff-selfclose.bats §2b, over a ps model
  # rich enough to tell all three apart.
  [[ "$output" == *"is UNKNOWN"* ]] || false
  ! [[ "$output" == *"the session is already gone"* ]] || false
  grep -q "HANDOFF-CLOSE-FAILED-UNKNOWN" "$NOTIFY_LOG"
}

@test "H3: the happy path still closes on the FIRST attempt (no added latency)" {
  _arm_watcher_home; export IT2_FAIL_N=0
  run bash "$HF" __selfclose "$PANE" /dev/ttys022 "" ""
  [ "$status" -eq 0 ]
  [ "$(grep -c 'session close' "$IT2_LOG")" -eq 1 ]
  [[ "$output" != *"retrying"* ]] || false
  [ ! -s "$NOTIFY_LOG" ]
}
