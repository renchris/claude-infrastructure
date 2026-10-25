#!/usr/bin/env bats
# bin/cc-pane-runner — a fleet pane that never ran Claude closes, through the fullscreen guard, and
# every exit leaves the K3 exit record (lr-wake incident 2026-10-18, REPORT §4 Wave B step 6).
#
# THE DEFECT. Overnight 13 refusal panes sat as plain shells, each ending
# `cc-pane-runner: the fleet launch line exited 9 — keeping a shell for diagnosis/resume`: no session
# in them, the transcript safe on disk, and nothing that would ever close them (c2 §2.2). The
# operator's rule is that a pane which leaves Claude either runs Claude or is closed. K3: rc 75
# (queued) closes; so does "claude never started" when a durable record owns the retry; any other
# failure keeps the shell; an in-place pane is never closed; and the close goes through
# kitty-fullscreen-guard in refuse mode at pane scope — never a raw close (h defect 7, the
# 2026-10-15 kitty-crash trigger).
#
# Hermetic: the guard, the fallback shell and the launch line are stubs in $BATS_TEST_TMPDIR. The
# shape is tests/pane-close-from-inside.bats's.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  RUNNER="$REPO/bin/cc-pane-runner"
  T="$BATS_TEST_TMPDIR"
  S="$T/stub"
  mkdir -p "$S" "$T/home" "$T/locks"
  export HOME="$T/home" LR_LOCKS_DIR="$T/locks"
  export T KITTY_WINDOW_ID=42 CC_PANE_WEDGE_WATCH=0 CC_PANE_HOLD_STEP_S=0
  export CC_PANE_EXIT_DIR="$T/pane-exit" CC_REGISTRY_DIR="$T/reg" CC_BEAT_DIR="$T/beats"
  unset KITTY_LISTEN_ON CC_TERM_KITTY_TO CC_PANE_CLOSE_ON_EXIT CC_PANE_CMD_INTERACTIVE CC_PANE_CMD CC_PANE_CMD_DIR
  unset CC_PANE_RUNNER_OWNS_CLOSE KITTY_PID LR_RUN_DIR CC_PANE_STARTED_FILE CC_PANE_EXIT_OWED CC_PANE_HOLD_MAX_POLLS
  export PATH="$S:/usr/bin:/bin"
  # the guard records its argv and answers $GUARD_RC (0 = safe to close) — or, when $T/guard-seq
  # exists, one rc per call from it, the last repeating (a refusal now HOLDS and re-asks)
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> %q\nif [ -s "$T/guard-seq" ]; then n=$(( $(cat "$T/guard-n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$T/guard-n"; GUARD_RC="$(sed -n "${n}p" "$T/guard-seq")"; [ -n "$GUARD_RC" ] || GUARD_RC="$(tail -n 1 "$T/guard-seq")"; fi\n[ "${GUARD_RC:-0}" != 0 ] && [ -n "${GUARD_ERR:-}" ] && printf "%%s\\n" "$GUARD_ERR" >&2\nexit "${GUARD_RC:-0}"\n' "$T/guard-log" > "$S/fsguard"
  export CC_KITTY_FS_GUARD="$S/fsguard"
  # the launch line: exits $LAUNCH_RC; LAUNCH_OWED=1 touches the owed-record path the runner exports,
  # LAUNCH_STARTED=1 the started path — the two facts only a launcher can supply
  printf '#!/bin/bash\n[ "${LAUNCH_OWED:-0}" = 1 ] && : > "$CC_PANE_EXIT_OWED"\n[ "${LAUNCH_STARTED:-0}" = 1 ] && : > "$CC_PANE_STARTED_FILE"\nexit "${LAUNCH_RC:-0}"\n' > "$S/lr-launch"
  # the interactive shell: `-c <line>` runs the line; bare (the fallback) it records that it ran, exits 7
  printf '#!/bin/bash\nfor a; do [ "${prev:-}" = -c ] && exec /bin/bash -c "$a"; prev="$a"; done\n: > %q\nexit 7\n' "$T/shell-ran" > "$S/fakeshell"
  chmod +x "$S"/*
}

# the fleet delivery mode: handoff-fire / lr-lib hand over a shell line, interactive
run_fleet() { SHELL="$S/fakeshell" CC_PANE_CMD_INTERACTIVE=1 CC_PANE_CMD="$1" run "$RUNNER"; }
record() { cat "$CC_PANE_EXIT_DIR/42.json"; }
# The runner's routine decisions are detail since lr-wake Wave H2: logged, never painted.
said() { grep -qF -- "$1" "$HOME/.claude/logs/pane-say.jsonl" || { echo "not in the cc-say log: $1"; cat "$HOME/.claude/logs/pane-say.jsonl" 2>/dev/null; false; }; }
field() { jq -r ".$1" "$CC_PANE_EXIT_DIR/42.json"; }

@test "rc 75 (queued) closes the pane — through the guard, in refuse mode, at pane scope — and records the exit" {
  LAUNCH_RC=75 run_fleet "bash $S/lr-launch"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -e "$T/shell-ran" ]
  said "the fleet launch line exited 75 (queued — one durable request retries it) — closing this pane"
  [[ "$output" != *"keeping a shell"* ]] || false
  [ -z "$output" ] || { echo "a queued close painted the pane: $output"; false; }
  [ "$(cat "$T/guard-log")" = "--window 42 --mode refuse --scope pane --tool cc-pane-runner" ]
  [ "$(field rc)" = 75 ]
  [ "$(field claude_started)" = false ]
  [ "$(field launch_sha)" = "$(printf '%s' "bash $S/lr-launch" | shasum -a 256 | cut -d' ' -f1)" ]
  [[ "$(field ts)" =~ ^[0-9]+$ ]] || false
  [ "$(jq -r 'keys | join(",")' "$CC_PANE_EXIT_DIR/42.json")" = "claude_started,launch_sha,rc,tail,ts" ]
  [ "$(field tail)" = closed ]
}

@test "rc 75 with the guard REFUSING (last pane of a fullscreen window) holds, then closes once safe — never a raw close, never a shell" {
  printf '3\n0\n0\n' > "$T/guard-seq"
  GUARD_ERR='kitty-fullscreen-guard: refused (refused-fs) kitty window 42 scope=pane mode=refuse: state=FS types=[4] onscreen=True' LAUNCH_RC=75 run_fleet "bash $S/lr-launch"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -e "$T/shell-ran" ]
  [[ "$output" == *"done · closes itself when safe"*"⌘W closes it now"* ]] || { echo "$output"; false; }
  said "guard: kitty-fullscreen-guard: refused (refused-fs)"
  [ "$(wc -l < "$T/guard-log" | tr -d ' ')" = 3 ]
  [ "$(field tail)" = closed ]
}

@test "a hold whose poll budget runs out keeps the shell (keep:fallback) — the only refusal that ends in one" {
  CC_PANE_HOLD_MAX_POLLS=1 GUARD_RC=3 GUARD_ERR='kitty-fullscreen-guard: refused (refused-fs) kitty window 42 scope=pane mode=refuse: state=FS types=[4] onscreen=True' LAUNCH_RC=75 run_fleet "bash $S/lr-launch"
  [ "$status" -eq 7 ]
  [ -e "$T/shell-ran" ]
  [ "$(field tail)" = keep:fallback ]
}

@test "an in-place shell survives: rc 75 while a recycle is pending for this pane keeps the shell, guard never asked" {
  # handoff-fire takes this lock while it is about to type the relaunch at THIS pane's shell
  d="$LR_LOCKS_DIR/pane-$(printf '%s' "iterm2:42" | shasum -a 1 | cut -c1-40).recycle"; mkdir -p "$d"
  printf '{"pid":%s,"lstart":"%s","role":"recycle"}\n' "$$" "$(TZ=UTC LC_ALL=C ps -o lstart= -p $$ | tr -s ' ' | sed 's/^ *//; s/ *$//')" > "$d/holder"
  LAUNCH_RC=75 run_fleet "bash $S/lr-launch"
  [ "$status" -eq 7 ]
  [ -e "$T/shell-ran" ]
  said "recycle pending, keeping the shell"
  [ ! -e "$T/guard-log" ]
  [ "$(field rc)" = 75 ]
}

@test "rc 1 with no owed record keeps the shell (an unexplained failure stays readable)" {
  LAUNCH_RC=1 run_fleet "bash $S/lr-launch"
  [ "$status" -eq 7 ]
  [ -e "$T/shell-ran" ]
  # claude never started, and only this runner can see it: one ✗ line with one command (Wave H2)
  [[ "$output" == "✗ launch failed (exit 1) · ▶ cc-husk-sweep --pane 42" ]] || { echo "$output"; false; }
  said "the fleet launch line exited 1 — keeping a shell for diagnosis/resume"
  [ ! -e "$T/guard-log" ]
  [ "$(field rc)" = 1 ]
  [ "$(field claude_started)" = false ]
}

@test "claude never started and a durable record owns the retry (rc 9, owed) closes through the guard" {
  LAUNCH_RC=9 LAUNCH_OWED=1 run_fleet "bash $S/lr-launch"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  said "exited 9 before claude started, and a durable record owns the retry — closing this pane"
  [ "$(cat "$T/guard-log")" = "--window 42 --mode refuse --scope pane --tool cc-pane-runner" ]
}

@test "rc 9 owed but claude DID start (the launcher said so) keeps the shell: a session ran here" {
  LAUNCH_RC=9 LAUNCH_OWED=1 LAUNCH_STARTED=1 run_fleet "bash $S/lr-launch"
  [ "$status" -eq 7 ]
  [ "$(field claude_started)" = true ]
  [ "$(field tail)" = keep:crash ]
}

@test "claude_started also reads this pane's registry row written after the launch began" {
  mkdir -p "$CC_REGISTRY_DIR"
  printf '#!/bin/bash\nprintf "{\\"session_id\\":\\"x\\"}" > %q\nexit 1\n' "$CC_REGISTRY_DIR/42.json" > "$S/reg-launch"; chmod +x "$S/reg-launch"
  run_fleet "bash $S/reg-launch"
  [ "$(field claude_started)" = true ]
}

@test "a clean exit still closes, and still writes its record (rc 0)" {
  run_fleet "bash $S/lr-launch"
  [ "$status" -eq 0 ]
  [ "$(field rc)" = 0 ]
}

# ── husk rows (husk-panes-2026-10-22 F3): a keep that is not on purpose leaves a durable retry row ──
husk() { jq -r ".$1" "$CC_PANE_CLOSE_QUEUE_DIR/husk-42.json"; }

@test "claude ran and died: the kept pane leaves a husk row (reason crash) for the reconciler" {
  export CC_PANE_CLOSE_QUEUE_DIR="$T/q" KITTY_PID=610
  LAUNCH_RC=143 LAUNCH_STARTED=1 run_fleet "bash $S/lr-launch"
  [ "$status" -eq 7 ]
  [ "$(husk kind)" = husk ]
  [ "$(husk reason)" = crash ]
  [ "$(husk rc)" = 143 ]
  [ "$(husk kitty_pid)" = 610 ]
  [ "$(husk producer)" = cc-pane-runner ]
}

@test "a guard refusal on a clean exit holds with no row; only a hold that escapes leaves one (runner-escape)" {
  export CC_PANE_CLOSE_QUEUE_DIR="$T/q"
  printf '3\n0\n0\n' > "$T/guard-seq"
  GUARD_ERR='kitty-fullscreen-guard: refused (kitten-failed) could not read kitty window 42: x' run_fleet "bash $S/lr-launch"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -e "$CC_PANE_CLOSE_QUEUE_DIR/husk-42.json" ]
  rm -f "$T/guard-seq"
  CC_PANE_HOLD_MAX_POLLS=1 GUARD_RC=3 GUARD_ERR='kitty-fullscreen-guard: refused (kitten-failed) could not read kitty window 42: x' run_fleet "bash $S/lr-launch"
  [ "$status" -eq 7 ]
  [ "$(husk reason)" = runner-escape ]
  [ "$(husk what)" = "the fleet launch line" ]
}

@test "CONTROL: keeps on purpose leave no row (CC_PANE_CLOSE_ON_EXIT=0; claude never started, no owed record)" {
  export CC_PANE_CLOSE_QUEUE_DIR="$T/q"
  CC_PANE_CLOSE_ON_EXIT=0 run_fleet "bash $S/lr-launch"
  [ "$status" -eq 7 ]
  LAUNCH_RC=1 run_fleet "bash $S/lr-launch"
  [ "$status" -eq 7 ]
  [ ! -e "$CC_PANE_CLOSE_QUEUE_DIR/husk-42.json" ]
}

@test "STRUCTURAL PIN: every keep arm in _end but the on-purpose ones writes a husk row" {
  # A new keep without a row is a pane nobody will ever retry. Each keep arm of _end's case (and its
  # catch-all) must call _husk_row or _kept_line (which writes the crash row), unless it is a keep on
  # purpose: the kill switch, a pending recycle, a command that is not a session.
  run awk '/^_end\(\) \{/{f=1} f&&/^\}/{exit}
           f && /^    (keep:[a-z:|-]+|\*)\)/ { arm=$0; while (arm !~ /;;/ && (getline l) > 0) arm = arm " " l; k++
             if (arm ~ /_husk_row |_kept_line / || arm ~ /^    keep:(kill-switch|recycle[|]keep:not-a-session)\)/) next
             print "BARE KEEP: " arm; bad=1 }
           END { print "keeps=" k; exit bad }' "$RUNNER"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "keeps=5" ] || { echo "$output"; false; }
  # and the EXIT trap's keep writes one too
  run awk '/^_escape\(\) \{/{f=1} f&&/^\}/{exit} f&&/_husk_row runner-escape/{print "row"}' "$RUNNER"
  [ "$output" = row ]
}

@test "F5: a crash keep prints no resume line and no exit code — the watchdog paints that verdict" {
  LAUNCH_RC=143 LAUNCH_STARTED=1 run_fleet "bash $S/lr-launch"
  [ "$status" -eq 7 ]
  [[ "$output" != *"shell kept for resume"* ]] || { echo "$output"; false; }
  [[ "$output" != *"143"* ]] || { echo "$output"; false; }
}
