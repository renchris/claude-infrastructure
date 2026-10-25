#!/usr/bin/env bats
# Pane 289 (2026-10-24): the integration replay of the husk class, against the POST-FIX interfaces.
#
# The session finished, said so, landed its two files and self-closed. Its pane was the last one of a
# native-fullscreen kitty window, so the fullscreen guard kept it as a bare shell, and then every reader
# of that shell judged the session by the whole cwd: six sibling changes under deadlines/items/ that it
# never touched. The closer refused it, the painter said RESUME, and the sweep offered to resume a
# finished session. docs/research/husk-history-2026-10-24/FIX-DESIGN.md §5 is this file's spec:
#   GOAL arms are RED on fa9cadc24, each with the HEAD symptom named above it, and GREEN after W1;
#   GUARD arms are GREEN on both trees, and each turns red under the mutant named above it.
# Replay an archived tree: CC_REPLAY_REPO=<extracted bin lib hooks scripts skills> bats <this file>.
# The world and every seam pin live in tests/helpers/fixture-289.bash.
# shellcheck disable=SC2030,SC2031  # per-test exports are deliberate: every @test is its own subshell

load helpers/cc-stub
load helpers/fixture-289

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off
  unset CC_PANE_CMD CC_PANE_CMD_DIR CC_PANE_CMD_INTERACTIVE   # every fired pane injects these
  fx289_world
}

# ── GOAL: the runner holds a refused pane, then closes it itself ──────────────────────────────────
# HEAD: status 7, the fallback shell ran, a `guard-fullscreen` husk row.
@test "A1 hold, then close: a refused-fs pane is held, re-asked, and closed after two safe reads" {
  fx_guard 3fs 3fs 0 0
  fx_runner claude
  [ "$status" -eq 0 ] || { echo "status=$status: $output"; false; }
  [ ! -e "$T/shell-ran" ]
  [ "$(wc -l < "$T/guard-log" | tr -d ' ')" -eq 4 ] || { cat "$T/guard-log"; false; }
  [ "$(sed -n 1p "$T/guard-log")" = "$FX_RUNNER_ARGV" ] || { cat "$T/guard-log"; false; }
  [ "$(sed -n '2,4p' "$T/guard-log" | grep -c -- '--window 289 .*--tool cc-pane-hold')" -eq 3 ] || { cat "$T/guard-log"; false; }
  [ "$(fx_tail)" = closed ] || { cat "$T/pane-exit/289.json"; false; }
  jq -r 'select(.tool == "cc-pane-verdict") | .state' "$CC_SAY_LOG" | grep -qx DONE || { cat "$CC_SAY_LOG"; false; }
  grep -qF 'closes itself when its window gains a pane' "$T/tty289" || { cat -v "$T/tty289"; false; }
  [ "$(fx_rows)" -eq 0 ] || { find "$CC_PANE_CLOSE_QUEUE_DIR" -type f; false; }
  fx_no_resume_words "$CC_SAY_LOG" "$T/tty289"
  run test -e "$T/git.log"; [ "$status" -eq 1 ]
}

# HEAD: killed by the TERM while the guard is still answering.
@test "A1g signal during the gate: TERM then INT to the runner's process group cannot end it undecided" {
  fx_guard 3fs 0 0; echo 3 > "$T/guard-sleep"
  env KITTY_WINDOW_ID=289 KITTY_PID="$FX_KPID" SHELL="$S/fakeshell" CC_PANE_CMD=claude \
    /usr/bin/perl -e 'setpgrp(0, 0); exec @ARGV' /bin/bash "$REPO/bin/cc-pane-runner" </dev/null >"$T/a1g.out" 2>&1 3>&- &
  local pid=$! i=0 st=0
  while [ ! -s "$T/guard-log" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
  kill -TERM -- "-$pid" 2>/dev/null || true; sleep 0.3; kill -INT -- "-$pid" 2>/dev/null || true
  wait "$pid" || st=$?
  [ "$st" -eq 0 ] || { echo "runner ended $st"; cat "$T/a1g.out"; false; }
  [ "$(grep -c -- '--tool cc-pane-hold' "$T/guard-log")" -ge 2 ] || { cat "$T/guard-log"; false; }
  [ "$(fx_tail)" = closed ]
  run test -e "$T/shell-ran"; [ "$status" -eq 1 ]
}

# ── GOAL: the self-close watcher stands down for a runner-owned pane ──────────────────────────────
# HEAD: `it2 session close` refused rc 70, a husk-fs alarm and a husk row.
@test "A2 watcher: a runner-owned pane whose record says hold:fs is left to its runner" {
  fx_watcher_home; fx_exit 0 289 $(( $(date +%s) + 1 )) hold:fs
  fx_watcher
  [ "$(fx_alarms)" -eq 0 ] || { echo "$output"; false; }
  [ "$(fx_rows)" -eq 0 ] || { echo "$output"; false; }
  run grep -q 'session close' "$T/it2.log"; [ "$status" -eq 1 ]
}

# HEAD: as A2 — the watcher closes at once, before the tail exists.
@test "A2d delayed tail: the record gains its tail 3 s after the watcher starts, and the watcher waits for it" {
  fx_watcher_home
  ( sleep 3; fx_exit 0 289 "$(date +%s)" hold:fs ) 3>&- &
  fx_watcher
  wait
  [ "$(fx_alarms)" -eq 0 ] || { echo "$output"; false; }
  [ "$(fx_rows)" -eq 0 ] || { echo "$output"; false; }
  run grep -q 'session close' "$T/it2.log"; [ "$status" -eq 1 ]
}

# ── GOAL: one verdict, from the session's own facts ──────────────────────────────────────────────
# HEAD: `REFUSED — … holds 6 uncommitted change(s)`.
@test "B1 closer: the finished session's pane would close; sibling dirt is not its work" {
  fx_close --pane 289 --dry-run
  [ "$status" -eq 0 ] || { echo "status=$status: $output"; false; }
  [[ "$output" == *"pane 289: WOULD CLOSE"*"Good to close: yes"* ]] || { echo "$output"; false; }
}

# HEAD: gate 4 refuses first, on the 6 sibling changes.
@test "B1fs closer: under a refused-fs guard the refusal names the guard and carries [state=DONE]" {
  fx_guard 3fs
  fx_close --pane 289 --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"refused-fs"*"[state=DONE]"* ]] || { echo "$output"; false; }
  [[ "$output" != *uncommitted* ]] || { echo "$output"; false; }
}

# HEAD: RESUME, "stopped mid-task · 138 unsaved files", the --resume line.
@test "B2 painter: HEAD's whole-cwd refusal has no state token, so it paints CANTTELL, never RESUME" {
  fx_paint --pane 289 --recompute --closer-out "pane 289: REFUSED — $P holds 138 uncommitted change(s)" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"state=CANTTELL"* ]] || { echo "$output"; false; }
  [[ "$output" != *"stopped mid-task"* && "$output" != *unsaved* ]] || { echo "$output"; false; }
  local o="$output"; run grep -qF -- '--resume' <<<"$o"; [ "$status" -eq 1 ]
}

# HEAD: work dirty, verdict RESUME, and --resume types it.
@test "B3 sweep: clean work and DONE; --resume types nothing; a custody return makes it COLLECTED" {
  fx_sweep --json --pane 289
  [[ "$output" == *'"work":"clean"'*'"verdict":"DONE"'* ]] || { echo "$output"; false; }
  fx_sweep --resume --yes --pane 289
  [ ! -e "$T/husk-it2.log" ] || { cat "$T/husk-it2.log"; false; }
  fx_custody_return
  fx_sweep --json --pane 289
  [ "$(fx_verdict)" = COLLECTED ] || { echo "$output"; false; }
}

# HEAD: CANTTELL (RECYCLE over 6 dirty).
@test "B4 watchdog: a clean exit over its own landed work paints DONE" {
  fx_watchdog RECYCLE clean-exit 0
  [ "$(fx_pvs)" = DONE ] || { echo "$output"; cat "$T/pv/"*.json; false; }
}

# HEAD: RESUME (sweep) and CANTTELL (watchdog), on the dirt and the unlanded sibling commit.
@test "B5 a sibling commit ahead of trunk, deadlines/ only, is not the session's: sweep and watchdog DONE" {
  fx_remote; echo d9 > "$P/deadlines/items/d9.md"; fx_git add deadlines/items/d9.md; fx_git commit -q -m sibling
  fx_sweep --json --pane 289
  [[ "$output" == *'"work":"clean"'*'"verdict":"DONE"'* ]] || { echo "$output"; false; }
  fx_watchdog RECYCLE clean-exit 0
  [ "$(fx_pvs)" = DONE ] || { echo "$output"; false; }
}

# HEAD: RESUME / CANTTELL. A two-dot diff would also read trunk's NOTES.md change as the session's.
@test "B5b the checkout behind origin by a sibling commit to NOTES.md: sweep and watchdog DONE" {
  fx_remote; fx_peer_push "$NOTES"; fx_git fetch -q origin
  fx_sweep --json --pane 289
  [[ "$output" == *'"work":"clean"'*'"verdict":"DONE"'* ]] || { echo "$output"; false; }
  fx_watchdog RECYCLE clean-exit 0
  [ "$(fx_pvs)" = DONE ] || { echo "$output"; false; }
}

# HEAD: UNKNOWN, and --resume types it.
@test "B6 the cwd removed after landing: DONE, and nothing is typed" {
  mv "$P" "$T/personal.gone"
  fx_sweep --json --pane 289
  [ "$(fx_verdict)" = DONE ] || { echo "$output"; false; }
  fx_sweep --resume --yes --pane 289
  run test -e "$T/husk-it2.log"; [ "$status" -eq 1 ]
}

# HEAD: RESUME, typed.
@test "B7 a peer edits NOTES.md after the exit: never RESUME; the closer names the session's own files" {
  echo peer >> "$P/$NOTES"
  fx_sweep --json --pane 289
  [ "$(fx_verdict)" = UNKNOWN ] || { echo "$output"; false; }
  fx_close --pane 289 --dry-run
  [[ "$output" == *"in files session 7555024a wrote"* ]] || { echo "$output"; false; }
  [[ "$output" != *RESUME* ]] || { echo "$output"; false; }
  fx_sweep --resume --yes --pane 289
  run test -e "$T/husk-it2.log"; [ "$status" -eq 1 ]
}

# HEAD: RESUME (sweep), REFUSED on the dirt (closer).
@test "B8 a RECYCLE deliberate-teardown end is a clean end: sweep DONE, closer would close" {
  fx_crash RECYCLE deliberate-teardown
  fx_sweep --json --pane 289
  [ "$(fx_verdict)" = DONE ] || { echo "$output"; false; }
  fx_close --pane 289 --dry-run
  [[ "$output" == *"pane 289: WOULD CLOSE"* ]] || { echo "$output"; false; }
}

# HEAD: no assistant-text close, so UNKNOWN/RESUME, typed.
@test "B9 the yes only in a thinking block, plus a self-close stamp: sweep DONE, nothing typed" {
  { fx_tx_head; fx_think "Good to close: yes — scenes landed"; fx_selfclose; } > "$TX"
  printf '{"closedAt":"%s","transcript":"%s","succession":{"kind":"terminal"}}\n' \
    "$(TZ=UTC date -r "$XT" +%Y-%m-%dT%H:%M:%SZ)" "$TX" > "$T/fired/289.json"
  fx_sweep --json --pane 289
  [ "$(fx_verdict)" = DONE ] || { echo "$output"; false; }
  fx_sweep --resume --yes --pane 289
  run test -e "$T/husk-it2.log"; [ "$status" -eq 1 ]
}

# HEAD: closer `REFUSED — no transcript for session` (33× live) / `nothing says session`; sweep RESUME.
b10() { # the pane-304 assertions (§2 row 1b), for either transcript variant
  fx_close --pane 304 --dry-run
  [ "$status" -eq 0 ] || { echo "status=$status: $output"; false; }
  [[ "$output" == *"pane 304: WOULD CLOSE"* ]] || { echo "$output"; false; }
  fx_paint --pane 304 --recompute --closer-out "$output" --dry-run
  [[ "$output" != *"state=RESUME"* ]] || { echo "$output"; false; }
  fx_sweep --json --pane 304
  case "$(fx_verdict 304)" in DONE|COLLECTED) ;; *) echo "$output"; false ;; esac
  fx_sweep --resume --yes --pane 304
  run test -e "$T/husk-it2.log"; [ "$status" -eq 1 ]
}
@test "B10 pane 304: a clean end with NO transcript anywhere never received a turn — DONE" {
  fx_pane304 none; b10
}
@test "B10z pane 304: a clean end with a 0-record transcript never received a turn — DONE" {
  fx_pane304 empty; b10
}

# ── GOAL: the launch paths return the session's real status to the runner ────────────────────────
# HEAD: the tail execs the shell (status 7, shell-ran).
@test "L1 lr tail: under runner ownership the relaunch's own status ends the pane process, no shell" {
  [ -x /usr/bin/script ] || skip "script(1) is absent"
  fx_lr_tail 0
  grep -q 'exec "${SHELL:-/bin/zsh}" -l -i' "$T/lr-tail.sh" || { cat "$T/lr-tail.sh"; false; }
  run env KITTY_WINDOW_ID=289 CC_PANE_RUNNER_OWNS_CLOSE=289 SHELL="$S/fakeshell" \
    /usr/bin/script -q /dev/null /bin/bash "$T/lr-tail.sh" </dev/null
  [ "$status" -eq 0 ] || { echo "status=$status: $output"; false; }
  run test -e "$T/shell-ran"; [ "$status" -eq 1 ]
}

# HEAD: the loop returns 0, so the runner closes the pane through the guard.
@test "S1 successor loop: a successor that dies 143 reaches the runner as 143 — kept, guard never asked" {
  printf '%q\n' "$S/claude" > "$T/succ/ttys046.claimed.1"
  FX_INTERACTIVE=1 CLAUDE_RC=143 fx_runner ". $(printf %q "$REPO/lib/pane-successor.sh"); cc_pane_successor_exec $(printf %q "$T/succ/ttys046.claimed.1") 0"
  [ "$status" -eq 7 ] || { echo "status=$status: $output"; false; }
  [ "$(fx_tail)" = keep:crash ] || { cat "$T/pane-exit/289.json"; false; }
  run test -e "$T/guard-log"; [ "$status" -eq 1 ]
}

# HEAD: A1 leaves a guard-fullscreen husk row, and the drainer hands it to the closer and the painter.
# (§5 lists D among the guards; with A1 as its precondition it cannot be green on HEAD — see the report.)
@test "D composed: after A1 the pane-close drainer has nothing to do — closer and repaint never called" {
  fx_guard 3fs 3fs 0 0; fx_runner claude
  run env -i HOME="$HOME" PATH=/usr/bin:/bin FX_T="$T" FX_KPID="$FX_KPID" \
    CC_PANE_CLOSE_QUEUE_DIR="$CC_PANE_CLOSE_QUEUE_DIR" CC_PCQ_PANE_CLOSE_BIN="$S/pcq-close" \
    CC_PCQ_VERDICT_BIN="$S/pcq-verdict" CC_PCQ_KITTY_BIN="$S/kitty" CC_PCQ_IT2_BIN="$S/it2" \
    CC_PCQ_KITTY_SOCKET_BIN="$S/pcq-sock" CC_PCQ_CUSTODY_BIN="$S/cc-find" CC_PCQ_PAGE_BIN="$S/pager" \
    CC_PCQ_NOTIFY_BIN="$S/pager" CC_PCQ_LOG="$T/pcq.jsonl" CC_PCQ_PS_FILE="$T/ps.txt" \
    CC_PCQ_KITTY_START_EPOCH="$KST" CC_PCQ_REGISTRY_DIR="$T/reg" /bin/bash "$REPO/scripts/pane-close-retry.sh"
  [ ! -e "$T/pcq-close.log" ] || { cat "$T/pcq-close.log" "$T/pcq.jsonl"; false; }
  run test -e "$T/pcq-verdict.log"; [ "$status" -eq 1 ]
}

# ── GUARDS: what must not change ──────────────────────────────────────────────────────────────────
# mutant: a crash routed to the hold.
@test "I1 guard: a crash over its own dirty NOTES.md keeps the shell, never asks the guard, stays RESUME" {
  echo dirty >> "$P/$NOTES"; fx_crash CRASH external-sigterm
  CLAUDE_RC=143 fx_runner claude
  [ "$status" -eq 7 ] || { echo "status=$status: $output"; false; }
  local tail; tail="$(fx_tail)"
  [ -z "$tail" ] || [ "$tail" = keep:crash ] || { echo "tail=$tail"; false; }
  [ ! -e "$T/guard-log" ]
  fx_close --pane 289 --dry-run
  [[ "$output" == *"pane 289: REFUSED"* ]] || { echo "$output"; false; }
  fx_sweep --json --pane 289
  [ "$(fx_verdict)" = RESUME ] || { echo "$output"; false; }
}

i2_world() { # a stale yes, then a write only a Bash call made; the session crashed with rc 143
  { fx_tx_head; fx_text "Good to close: yes"; fx_tool tu5 Bash '{"command":"echo x > deadlines/items/i2.md"}'; } > "$TX"
  echo x > "$P/deadlines/items/i2.md"; fx_crash CRASH external-sigterm; fx_exit 143
}
# mutant: strict ignores class.
@test "I2 guard: a crash after a stale yes and a Bash-only write is refused and stays RESUME" {
  i2_world
  [ "$(jq -r .rc "$CC_PANE_CLOSE_EXIT_DIR/289.json")" = 143 ]
  fx_close --pane 289 --dry-run
  [[ "$output" == *"pane 289: REFUSED"* ]] || { echo "$output"; false; }
  fx_sweep --json --pane 289
  [ "$(fx_verdict)" = RESUME ] || { echo "$output"; false; }
}

# mutant: as I2.
@test "I2n guard: the same crash on a pane with no exit record (not a runner pane) is refused" {
  i2_world; rm -f "$T/pane-exit/289.json"
  fx_close --pane 289 --dry-run
  [[ "$output" == *"pane 289: REFUSED"* ]] || { echo "$output"; false; }
}

# mutant: team not strict.
@test "I3 guard: a retired teammate with no recorded writes, over an untracked file, is refused and never closed" {
  { FX_X='{"teamName":"wave-c2","agentName":"m1"}'; _FX_N=0; fx_user "C2 brief"; fx_tool tu1 Bash '{"command":"ls"}'; fx_text "done"; } > "$TX"
  fx_close --pane 289
  [[ "$output" == *"pane 289: REFUSED"* ]] || { echo "$output"; false; }
  run grep -q 'session close' "$T/it2.log"; [ "$status" -eq 1 ]
}

# mutant: strict uses the per-path proof.
@test "I4 guard: a crash whose own work is a git mv of an old file is refused" {
  { fx_tx_head; fx_text "Good to close: yes"; fx_tool tu5 Bash '{"command":"git mv old.md notes/old.md"}'; } > "$TX"
  fx_git mv old.md notes/old.md; fx_crash CRASH external-sigterm; fx_exit 143
  fx_close --pane 289 --dry-run
  [[ "$output" == *"pane 289: REFUSED"* ]] || { echo "$output"; false; }
}

# mutant: trunk = origin/HEAD only.
@test "B5c guard: with no origin/HEAD symref, the session's own unpushed commit still blocks DONE" {
  fx_remote; fx_git remote set-head origin -d
  echo C3 >> "$P/$NOTES"; fx_git commit -q -am "own, unpushed"
  fx_sweep --json --pane 289
  [ -n "$(fx_verdict)" ] && [ "$(fx_verdict)" != DONE ] || { echo "$output"; false; }
  fx_watchdog RECYCLE clean-exit 0
  [ -n "$(fx_pvs)" ] && [ "$(fx_pvs)" != DONE ] || { echo "$output"; false; }
}

# mutant: a crash routed to the hold.
@test "C1 guard: no close line and a 143 exit keep the shell; the guard is never asked and nothing holds" {
  { fx_tx_head; fx_selfclose; } > "$TX"
  CLAUDE_RC=143 fx_runner claude
  [ "$status" -eq 7 ] || { echo "status=$status: $output"; false; }
  [ -e "$T/shell-ran" ]
  local tail; tail="$(fx_tail)"
  [ "${tail#hold}" = "$tail" ] || { echo "tail=$tail"; false; }
  run test -e "$T/guard-log"; [ "$status" -eq 1 ]
}
