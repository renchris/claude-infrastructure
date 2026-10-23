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
  export KITTY_WINDOW_ID=42 CC_PANE_WEDGE_WATCH=0
  export CC_PANE_EXIT_DIR="$T/pane-exit" CC_REGISTRY_DIR="$T/reg" CC_BEAT_DIR="$T/beats"
  unset KITTY_LISTEN_ON CC_TERM_KITTY_TO CC_PANE_CLOSE_ON_EXIT CC_PANE_CMD_INTERACTIVE CC_PANE_CMD CC_PANE_CMD_DIR
  unset CC_PANE_RUNNER_OWNS_CLOSE KITTY_PID LR_RUN_DIR CC_PANE_STARTED_FILE CC_PANE_EXIT_OWED
  export PATH="$S:/usr/bin:/bin"
  # the guard records its argv and answers $GUARD_RC (0 = safe to close)
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> %q\n[ -n "${GUARD_ERR:-}" ] && printf "%%s\\n" "$GUARD_ERR" >&2\nexit "${GUARD_RC:-0}"\n' "$T/guard-log" > "$S/fsguard"
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
  [ "$(jq -r 'keys | join(",")' "$CC_PANE_EXIT_DIR/42.json")" = "claude_started,launch_sha,rc,ts" ]
}

@test "rc 75 with the guard REFUSING (last pane of a fullscreen window) keeps the shell — never a raw close" {
  GUARD_RC=3 GUARD_ERR='kitty-fullscreen-guard: refused (refused-fs) kitty window 42 scope=pane mode=refuse: state=FS types=[4] onscreen=True' LAUNCH_RC=75 run_fleet "bash $S/lr-launch"
  [ "$status" -eq 7 ]
  [ -e "$T/shell-ran" ]
  [[ "$output" == *"⚠ last pane of a fullscreen window · ⌘W closes it"* ]] || { echo "$output"; false; }
  said "guard: kitty-fullscreen-guard: refused (refused-fs)"
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
