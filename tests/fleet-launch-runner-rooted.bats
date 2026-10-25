#!/usr/bin/env bats
# Every fleet launch is rooted in bin/cc-pane-runner (husk-history FIX-DESIGN §4 W2,
# docs/research/husk-history-2026-10-24/FIX-DESIGN.md).
#
# A pane's end is the runner's: it closes the pane after a clean exit, holds it until closing is safe,
# or keeps a shell for a reason a close would destroy, and records which. A launch site that roots its
# pane anywhere else brings back one of two failures — a root that exits takes the window with it
# (pane 32), or a root that ends in its own interactive shell leaves a husk nothing closes (pane 289).
#
# THE LINT is the design's: `git grep -nE '\|\| exec zsh -i|exec "\$\{SHELL' -- bin scripts lib`, run
# against the real tree (break 22), must name exactly the allowlist below. It is counted per FILE, not
# per line, so moving an allowed line does not trip it while adding one anywhere does:
#   bin/cc-pane-runner               _fallback, the runner's one shell
#   bin/kitty-split-cwd.sh           the operator's own ⌘D split (ruling 337e100f5c71)
#   bin/reso-resume-one          ×2  rr_pane_shell, and the tail of a typed (operator) launch
#   lib/pane-successor.sh        ×2  the successor loop's keep=1 tail and the zshexit hook (D2: unchanged)
#   scripts/limit-recover/lr-fire-resume.sh  the tail of a typed launch
# Under bats, every assertion is `[ ]`, `run`+status, or `… || false`.

load helpers/cc-stub

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  KSL="$REPO/bin/kitty-split-launch.sh"
  HF="$REPO/scripts/handoff-fire.sh"
  SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"
  export KITTY_ARGS_LOG="$BATS_TEST_TMPDIR/kitty-args.log"
  # kitty shim: one argv word per line, then a window id, as `kitty @ launch` prints it
  cc_stub "$SHIM" kitty "$(printf '#!/bin/bash\nprintf "%%s\\n" "$@" >> %q\necho 31\n' "$KITTY_ARGS_LOG")"
  export CC_TERM_KITTY="$SHIM/kitty"
  unset CC_PANE_RUNNER_BIN CC_PANE_CMD CC_PANE_CMD_INTERACTIVE CC_PANE_CMD_DIR
  # Hermeticity pins (scripts/test-hermeticity-lint.sh): handoff-fire.sh is read here, never run, but
  # the lint keys on the name, and a pinned seam costs nothing.
  export CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off CC_ADMIT_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
}

LINT_RE='\|\| exec zsh -i|exec "\$\{SHELL'

@test "LINT: the shell-tail sites in bin/ scripts/ lib/ are exactly the design's allowlist" {
  run git -C "$REPO" grep -cE "$LINT_RE" -- bin scripts lib
  [ "$status" -eq 0 ]
  local want
  want="$(printf '%s\n' \
    'bin/cc-pane-runner:1' \
    'bin/kitty-split-cwd.sh:1' \
    'bin/reso-resume-one:2' \
    'lib/pane-successor.sh:2' \
    'scripts/limit-recover/lr-fire-resume.sh:1')"
  [ "$output" = "$want" ] || { printf 'got:\n%s\nwant:\n%s\n' "$output" "$want"; false; }
}

@test "LINT CONTROL: the pattern matches both old root shapes, so the allowlist case cannot pass vacuously" {
  # shellcheck disable=SC2016  # literal source text
  printf '%s\n' 'KARGS+=(-- zsh -ic "$CMD || exec zsh -i")' 'exec "${SHELL:-/bin/zsh}" -l -i' > "$BATS_TEST_TMPDIR/old.sh"
  run grep -cE "$LINT_RE" "$BATS_TEST_TMPDIR/old.sh"
  [ "$output" = 2 ]
}

# ── bin/kitty-split-launch.sh (W2.6) ─────────────────────────────────────────────────────────────

@test "kitty-split-launch: the pane's root is the runner, and CC_PANE_CMD carries the exact argv" {
  run bash "$KSL" --anchor 7 --cwd "$BATS_TEST_TMPDIR" -- claude --name "a b" "it's"
  [ "$status" -eq 0 ]
  [ "$output" = 31 ]
  local cmd
  cmd="$(sed -n 's/^CC_PANE_CMD=//p' "$KITTY_ARGS_LOG")"
  [ -n "$cmd" ]
  grep -qx "CC_PANE_RUNNER=$REPO/bin/cc-pane-runner" "$KITTY_ARGS_LOG"
  grep -qx 'CC_PANE_CMD_INTERACTIVE=0' "$KITTY_ARGS_LOG"
  # shellcheck disable=SC2016  # the literal argv word, expanded by the pane's shell
  grep -qx 'exec /bin/bash "$CC_PANE_RUNNER"' "$KITTY_ARGS_LOG"
  # the argv after `--` is the login shell, never the command itself
  [ "$(sed -n '/^--$/{n;p;}' "$KITTY_ARGS_LOG")" != claude ]
  # ROUND TRIP: the runner evals CC_PANE_CMD in bash; it must rebuild the caller's argv word for word
  # shellcheck disable=SC2016  # expands in the child bash
  run /bin/bash -c 'c="$1"; eval "set -- $c"; printf "<%s>" "$@"' _ "$cmd"
  [ "$output" = "<claude><--name><a b><it's>" ]
}

@test "kitty-split-launch: with no runner it degrades to the bare argv, and says so" {
  CC_PANE_RUNNER_BIN="$BATS_TEST_TMPDIR/absent" run bash "$KSL" --anchor 7 -- claude --x
  [ "$status" -eq 0 ]
  [[ "$output" == *"cc-pane-runner not found"* ]] || false
  [ "$(sed -n '/^--$/{n;p;}' "$KITTY_ARGS_LOG")" = claude ]
  run grep -c '^CC_PANE_CMD=' "$KITTY_ARGS_LOG"
  [ "$output" = 0 ]
}

# ── scripts/handoff-fire.sh hf_runner_typed_line (W2.5) ─────────────────────────────────────────
# Extracted alone (the established idiom: nothing here runs a fire). in_kitty is the real one-liner.

typed() { # $@ = env assignments; prints hf_runner_typed_line's answer for $LINE
  local fn ik
  fn="$(sed -n '/^hf_runner_typed_line() {/,/^}/p' "$HF")"
  ik="$(sed -n '/^in_kitty() {/p' "$HF")"
  [ -n "$fn" ] && [ -n "$ik" ] || { echo "subject functions not found in $HF"; return 2; }
  # shellcheck disable=SC2016  # "$1" expands in the child bash
  run env -u IT2_WRAPPER_NO_KITTY "$@" /bin/bash -c "$ik"$'\n'"$fn"$'\n''hf_runner_typed_line "$1"' _ "$LINE"
}
mk_runner() { # $1=body — a plain file: the typed line runs it as `/bin/bash <runner>`, never by path
  RUNNER="$BATS_TEST_TMPDIR/runner"; printf '%s\n' "$1" > "$RUNNER"; chmod +x "$RUNNER"
}
LINE="cd /tmp/wt\\ 1 && nocorrect env LR_LAUNCH_LOCK=/x bash /tmp/launch.sh"

@test "typed relaunch (kitty + runner): exec env CC_PANE_CMD=<line> CC_PANE_CMD_INTERACTIVE=1 /bin/bash <runner>" {
  # shellcheck disable=SC2016  # expands when the runner runs
  mk_runner 'printf "%s\n" "$CC_PANE_CMD" "$CC_PANE_CMD_INTERACTIVE"'
  typed KITTY_WINDOW_ID=5 CC_RUNNER_BIN="$RUNNER"
  [ "$status" -eq 0 ]
  [[ "$output" == "exec env CC_PANE_CMD="*" CC_PANE_CMD_INTERACTIVE=1 /bin/bash $RUNNER" ]] || { echo "$output"; false; }
  # ROUND TRIP through a real shell, as the pane's zsh would run the typed line
  local t="$output"
  run /bin/bash -c "$t"
  [ "${lines[0]}" = "$LINE" ]
  [ "${lines[1]}" = 1 ]
}

@test "typed relaunch outside kitty, with no runner, or with HF_TYPED_RUNNER=off: the line is unchanged" {
  mk_runner 'exit 0'
  typed -u KITTY_WINDOW_ID CC_RUNNER_BIN="$RUNNER"
  [ "$output" = "$LINE" ]
  typed KITTY_WINDOW_ID=5 CC_RUNNER_BIN="$BATS_TEST_TMPDIR/absent"
  [ "$output" = "$LINE" ]
  typed KITTY_WINDOW_ID=5 CC_RUNNER_BIN="$RUNNER" HF_TYPED_RUNNER=off
  [ "$output" = "$LINE" ]
}

@test "the recycle watcher types a RESUME relaunch through hf_runner_typed_line, and only a resume" {
  # shellcheck disable=SC2016  # literal source text
  run grep -c 'if \[ -n "\${RCY_RESUME_SID:-}" \]; then rcy_typed="\$(hf_runner_typed_line "\$rcy_typed")"; fi' "$HF"
  [ "$output" = 1 ]
  # shellcheck disable=SC2016  # literal source text
  run grep -c 'it2_type_verified "\$IT2" "\$RSID" "\$rcy_typed"' "$HF"
  [ "$output" = 1 ]
}
