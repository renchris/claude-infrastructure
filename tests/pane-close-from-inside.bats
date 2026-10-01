#!/usr/bin/env bats
# A pane closes from inside when its claude exits on purpose (2026-09-30).
#
# docs/research/husk-panes-2026-09-30.md root cause 2 / fix F-a: nothing closed a pane from inside,
# so every intentional claude exit left a bare shell (a "husk") unless an external kitty remote-control
# close happened to land. bin/cc-pane-runner now exits — closing its pane — after a CLEAN claude exit
# with no recycle pending; bin/cc-close-attrib does the same for operator-opened windows, opt-in.
#
# Hermetic: every external effect is a stub in $BATS_TEST_TMPDIR. The "shell" the runner falls back
# to is a stub that writes a sentinel, the ancestry cc-close-attrib walks is a stub ps reading a table,
# and the signal it sends goes to a stub kill that only logs. Nothing here signals a real process.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  RUNNER="$REPO/bin/cc-pane-runner"
  WRAP="$REPO/bin/cc-close-attrib"
  T="$BATS_TEST_TMPDIR"
  S="$T/stub"
  mkdir -p "$S" "$T/home" "$T/locks"
  export HOME="$T/home" LR_LOCKS_DIR="$T/locks" CC_CLOSE_RECORDS_DIR="$T/records"
  export KITTY_WINDOW_ID=42 CC_PANE_WEDGE_WATCH=0
  unset KITTY_LISTEN_ON CC_TERM_KITTY_TO CC_PANE_CLOSE_ON_EXIT CC_PANE_CMD_INTERACTIVE CC_PANE_CMD CC_PANE_CMD_DIR
  unset CC_PANE_RUNNER_OWNS_CLOSE CC_CLOSE_PANE_ON_EXIT CC_MEMDIR_REALPATH CC_CLOSE_ATTRIB_DISABLED
  export PATH="$S:/usr/bin:/bin"

  # `claude` — records what it saw of the ownership marker, then exits $STUB_RC.
  # shellcheck disable=SC2016  # stub bodies are literal; they expand when the STUB runs
  printf '#!/bin/bash\n[ "${1:-}" = --version ] && { echo "stub 9.9.9"; exit 0; }\nprintf "%%s\\n" "${CC_PANE_RUNNER_OWNS_CLOSE:-}" > %q\nexit "${STUB_RC:-0}"\n' \
    "$T/claude-saw" > "$S/claude"
  printf '#!/bin/bash\nexit 0\n' > "$S/notclaude"
  # The fallback shell: proves it was exec'd, and what it inherited.
  # shellcheck disable=SC2016
  # With `-c <line>` (the interactive delivery mode) it RUNS the line and returns its status, the way
  # `zsh -l -i -c` does; bare (the fallback) it records that it was exec'd and exits 7.
  printf '#!/bin/bash\nfor a; do [ "${prev:-}" = -c ] && exec /bin/bash -c "$a"; prev="$a"; done\nprintf "%%s\\n" "${CC_PANE_RUNNER_OWNS_CLOSE:-}" > %q\nexit 7\n' "$T/shell-ran" > "$S/fakeshell"
  # ps: `-o ppid=,comm= -p <pid>` → "<ppid> <comm>" from $T/ps-table; any pid not in it is the
  # wrapper's own parent, answered by the `*` row.
  # shellcheck disable=SC2016
  printf '#!/bin/bash\nfor a; do pid="$a"; done\nwhile read -r p pp cm; do [ "$p" = "$pid" ] && { echo "$pp $cm"; exit 0; }; done < %q\nwhile read -r p pp cm; do [ "$p" = "*" ] && { echo "$pp $cm"; exit 0; }; done < %q\n' \
    "$T/ps-table" "$T/ps-table" > "$S/fakeps"
  # shellcheck disable=SC2016
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> %q\n' "$T/kill-log" > "$S/fakekill"
  chmod +x "$S"/*
  # The live shape: wrapper ← zsh subshell ← login -zsh ← kitty.
  printf '%s\n' '* 5001 zsh' '5001 5000 -zsh' '5000 1 /Applications/kitty.app/Contents/MacOS/kitty' > "$T/ps-table"
}

# The lock dir handoff-fire would take for this pane under recycle key $1 ("<key>:42").
lock_dir() { printf '%s/pane-%s.recycle' "$LR_LOCKS_DIR" "$(printf '%s' "$1:42" | shasum -a 1 | cut -c1-40)"; }
lstart_of() { TZ=UTC LC_ALL=C ps -o lstart= -p "$1" | tr -s ' ' | sed 's/^ *//; s/ *$//'; }
hold() { # $1=key $2=pid $3=lstart
  local d; d="$(lock_dir "$1")"; mkdir -p "$d"
  printf '{"pid":%s,"lstart":"%s","role":"recycle"}\n' "$2" "$3" > "$d/holder"
}
run_runner() { SHELL="$S/fakeshell" CC_PANE_CMD="$1" run "$RUNNER"; }
run_wrap() { CC_CLOSE_ATTRIB_PS_BIN="$S/fakeps" CC_CLOSE_ATTRIB_KILL_BIN="$S/fakekill" run "$WRAP" "$S/claude" "$@"; }

# ── bin/cc-pane-runner ────────────────────────────────────────────────────────────────────────────

@test "runner: claude exiting 0 closes the pane — the runner exits 0 and never execs the shell" {
  run_runner "claude --resume x"
  [ "$status" -eq 0 ]
  [ ! -e "$T/shell-ran" ]
  [[ "$output" == *"claude exited 0 — closing this pane"* ]]
}

@test "runner: claude exiting 143 keeps a shell for the resume verdict" {
  STUB_RC=143 run_runner "claude"
  [ "$status" -eq 7 ]
  [ -e "$T/shell-ran" ]
  [[ "$output" == *"claude exited 143 — keeping a shell for diagnosis/resume"* ]]
}

@test "runner: a vendor teammate line (cd … && env VAR=… …/claude.exe --agent-id …) in FILE mode closes on exit 0" {
  # The 2.1.284 teammate launch shape, verbatim in panes 69 and 76's scrollback. FILE mode: not interactive.
  cp "$S/claude" "$S/claude.exe"
  run_runner "cd $(printf %q "$T") && env CLAUDECODE=1 CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 $S/claude.exe --agent-id x@session-y --agent-name x --team-name session-y"
  [ "$status" -eq 0 ]
  [ ! -e "$T/shell-ran" ]
  [[ "$output" == *"claude.exe exited 0 — closing this pane"* ]]
}

@test "runner: a cd … && env … prefix in front of a NON-claude command still becomes a shell" {
  run_runner "cd $(printf %q "$T") && env FOO=1 notclaude --agent-id x"
  [ "$status" -eq 7 ]
  [ -e "$T/shell-ran" ]
}

@test "runner: a handoff-fire launch line (cd … && launcher …) exiting 0 closes the pane" {
  # The interactive mode is handoff-fire's and lr-lib's: the verb is `cd`, the status is the session's.
  CC_PANE_CMD_INTERACTIVE=1 run_runner "cd $(printf %q "$T") && claude --resume x"
  [ "$status" -eq 0 ]
  [ ! -e "$T/shell-ran" ]
  [[ "$output" == *"claude exited 0 — closing this pane"* ]]
}

@test "runner: an interactive launch line the verb parse cannot read ({ cd … ; } && launcher) still closes" {
  CC_PANE_CMD_INTERACTIVE=1 run_runner "{ cd $(printf %q "$T") 2>/dev/null || cd / ; } && claude --resume x"
  [ "$status" -eq 0 ]
  [ ! -e "$T/shell-ran" ]
  [[ "$output" == *"the fleet launch line exited 0 — closing this pane"* ]]
}

@test "runner: a fleet launch line whose session exits 143 keeps the shell" {
  STUB_RC=143 CC_PANE_CMD_INTERACTIVE=1 run_runner "cd $(printf %q "$T") && claude"
  [ "$status" -eq 7 ]
  [ -e "$T/shell-ran" ]
}

@test "runner: a fleet launch line whose cd fails keeps the shell" {
  CC_PANE_CMD_INTERACTIVE=1 run_runner "cd $(printf %q "$T/no-such-dir") && claude"
  [ "$status" -eq 7 ]
  [ -e "$T/shell-ran" ]
}

@test "runner: a non-claude command exiting 0 still becomes a shell, silently" {
  run_runner "notclaude"
  [ "$status" -eq 7 ]
  [ -e "$T/shell-ran" ]
  [[ "$output" != *"cc-pane-runner:"* ]]
}

@test "runner: a recycle lock with a LIVE holder keeps the shell" {
  hold iterm2 "$$" "$(lstart_of "$$")"
  run_runner "claude"
  [ "$status" -eq 7 ]
  [ -e "$T/shell-ran" ]
  [[ "$output" == *"recycle pending, keeping the shell"* ]]
}

@test "runner: a recycle lock whose holder is provably dead (pid reused: lstart differs) closes" {
  hold iterm2 "$$" "Thu Jan 1 00:00:00 1970"
  run_runner "claude"
  [ "$status" -eq 0 ]
  [ ! -e "$T/shell-ran" ]
}

@test "runner: a recycle lock with no holder yet reads as pending (fail safe)" {
  mkdir -p "$(lock_dir iterm2)"
  run_runner "claude"
  [ "$status" -eq 7 ]
  [[ "$output" == *"recycle pending"* ]]
}

@test "runner: the recycle key spelled as the socket without unix: is checked too" {
  export KITTY_LISTEN_ON="unix:/tmp/kitty-test-sock"
  hold /tmp/kitty-test-sock "$$" "$(lstart_of "$$")"
  run_runner "claude"
  [ "$status" -eq 7 ]
  [[ "$output" == *"recycle pending"* ]]
}

@test "runner: CC_PANE_CLOSE_ON_EXIT=0 keeps the shell after a clean claude exit" {
  CC_PANE_CLOSE_ON_EXIT=0 run_runner "claude"
  [ "$status" -eq 7 ]
  [ -e "$T/shell-ran" ]
  [[ "$output" == *"CC_PANE_CLOSE_ON_EXIT=0, keeping the shell"* ]]
}

@test "runner: the command sees CC_PANE_RUNNER_OWNS_CLOSE=1; the fallback shell does not" {
  STUB_RC=1 run_runner "claude"
  [ "$status" -eq 7 ]
  [ "$(cat "$T/claude-saw")" = 1 ]
  [ "$(cat "$T/shell-ran")" = "" ]
}

# ── bin/cc-close-attrib (opt-in, operator-opened windows) ─────────────────────────────────────────

@test "close-attrib: opt-in unset — no signal, exit code unchanged" {
  run_wrap
  [ "$status" -eq 0 ]
  [ ! -e "$T/kill-log" ]
}

@test "close-attrib: opt-in + exit 0 + kitty ancestry — HUPs the login shell whose parent is kitty" {
  CC_CLOSE_PANE_ON_EXIT=1 run_wrap --model x
  [ "$status" -eq 0 ]
  [ "$(cat "$T/kill-log")" = "-HUP 5001" ]
}

@test "close-attrib: opt-in + exit 1 — no signal, exit code still 1" {
  CC_CLOSE_PANE_ON_EXIT=1 STUB_RC=1 run_wrap
  [ "$status" -eq 1 ]
  [ ! -e "$T/kill-log" ]
}

@test "close-attrib: inside cc-pane-runner (CC_PANE_RUNNER_OWNS_CLOSE=1) — no signal" {
  CC_CLOSE_PANE_ON_EXIT=1 CC_PANE_RUNNER_OWNS_CLOSE=1 run_wrap
  [ "$status" -eq 0 ]
  [ ! -e "$T/kill-log" ]
}

@test "close-attrib: a claude nested under another session (non-shell ancestor) — no signal" {
  printf '%s\n' '* 5001 zsh' '5001 5000 node' '5000 4999 -zsh' '4999 1 kitty' > "$T/ps-table"
  CC_CLOSE_PANE_ON_EXIT=1 run_wrap
  [ "$status" -eq 0 ]
  [ ! -e "$T/kill-log" ]
}

@test "close-attrib: a headless claude -p typed at the prompt — no signal" {
  CC_CLOSE_PANE_ON_EXIT=1 run_wrap -p "hello"
  [ "$status" -eq 0 ]
  [ ! -e "$T/kill-log" ]
}

@test "close-attrib: a recycle pending for this window — no signal" {
  hold iterm2 "$$" "$(lstart_of "$$")"
  CC_CLOSE_PANE_ON_EXIT=1 run_wrap
  [ "$status" -eq 0 ]
  [ ! -e "$T/kill-log" ]
}
