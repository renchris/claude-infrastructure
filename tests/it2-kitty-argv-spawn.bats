#!/usr/bin/env bats
# it2-kitty argv delivery — the pane's COMMAND must never be typed at a prompt (plan §9.1).
#
# WHY THIS SUITE EXISTS. On 2026-08-03 a 7-way fan-out started 5 agents. Claude Code's ITermBackend
# spawns a teammate by TYPING — `session send -s <id> ^U`, then `session run -s <id> <cmd>` — which
# is two process spawns against one mutable resource the human also owns. The operator's in-flight
# keystroke landed between them twice, producing `ccd …` (command not found) and `tcd …` (parked on
# `correct 'tcd' to 'cd' [nyae]?`). Both single-character corruptions; both reported as
# "Spawned successfully", because the backend checks only that the KEYSTROKES were accepted.
#
# The subject under test is therefore not "does the text arrive intact" — no amount of escaping makes
# a shared prompt line safe. It is that a split pane runs bin/cc-pane-runner instead of an interactive
# shell, so `run` hands the command over as a FILE and there is no prompt line to collide with.
#
# The tests that MATTER here are the pairs: every claim about the new transport is stated alongside
# its opposite (armed vs. unarmed, consumed vs. never-consumed), because an assertion that the file
# was written is worth nothing unless something also proves the shim can still notice it was not.
#
# Every assertion is `[ ]` or `… || false` — `[[ ]]` and `(( ))` are errexit-EXEMPT in bats and are
# silently DEAD anywhere but a body's last line (plan §7.8 learning 1; §8.8 defect 2).

setup() {
  # handoff-fire's capacity_gate() refuses a net-new fire above 2.0/core and this box lives well
  # above that. Named by test-hermeticity-lint, which blocks the land on it.
  export CC_FIRE_CAPACITY_GATE=off
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  K="$REPO/bin/it2-kitty"
  RUNNER="$REPO/bin/cc-pane-runner"
  # A fake socket + a fake kitty. CC_TERM_KITTY_TO also bypasses the ancestry gate, which is what
  # makes this suite independent of WHICH terminal the developer is sitting in — the dependency that
  # silently decided the verdict in five sibling suites (plan §8.7).
  export CC_TERM_KITTY_TO="unix:$BATS_TEST_TMPDIR/sock"
  export CC_TERM_KITTY="$BATS_TEST_TMPDIR/fake-kitty"
  export CC_PANE_CMD_DIR="$BATS_TEST_TMPDIR/cmd"
  export CC_PANE_RUNNER_BIN="$RUNNER"
  # The terminal dependency named above has an exact twin one layer in, and this suite had it too
  # (item 4c5eddc16c2d): the four variables the SUBJECT puts on a pane are inherited by every
  # descendant of a pane it launched, so three tests here went red when — and only when — bats ran
  # inside a pane this feature created. `arm()` and the file-transport tests key on the ABSENCE of
  # CC_PANE_CMD, which an ambient value silently supplies. Same fix, same reasoning, fuller account
  # in tests/handoff-fire-argv-launch.bats's setup.
  #
  # The half that account does not reach, measured under item 22a170cc62aa: the same ambient value is
  # read by bin/it2-kitty:626 as its own CALLER's intent, so a split forwards
  # `--env CC_PANE_CMD=<the ancestor's own launch line>` into the new pane and takes the pre-delivered
  # path, which never ARMS — case 1's failure here, and in production a child re-running its parent's
  # launch while the command meant for it is typed at a pane with no prompt. bin/cc-pane-runner now
  # CONSUMES the record at delivery (its `_launch`), so it can no longer be inherited at all; this
  # line stays regardless, because a subject's fix is not a suite's hermeticity.
  unset CC_PANE_CMD CC_PANE_CMD_INTERACTIVE CC_PANE_CMD_WAIT_S CC_PANE_RUNNER
  KLOG="$BATS_TEST_TMPDIR/kitty.log"
  fake_kitty
}

# Records every invocation, answers the four verbs the shim uses. `launch` always yields pane 42, so
# the arming assertions have a fixed key to look for.
fake_kitty() {
  cat > "$CC_TERM_KITTY" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$KLOG"
verb=""
for a in "$@"; do
  case "$a" in @|--to|unix:*) continue ;; *) verb="$a"; break ;; esac
done
case "$verb" in
  launch)    echo 42 ;;
  ls)        echo '[{"id":1,"tabs":[{"id":1,"windows":[{"id":42,"title":"t","cwd":"/tmp","pid":9}]}]}]' ;;
  get-text)  echo "fake pane text" ;;
esac
exit 0
SH
  chmod +x "$CC_TERM_KITTY"
  export KLOG
}

arm() { mkdir -p "$CC_PANE_CMD_DIR"; : > "$CC_PANE_CMD_DIR/$1.armed"; }

# ── split: the pane's argv, and the focus it must not steal ──────────────────────────────────────

@test "split ARMS the pane: it launches the runner, not an interactive shell" {
  run "$K" session split -v -s 7
  [ "$status" -eq 0 ]
  [ "$output" = "Created new pane: 42" ]
  [ -f "$CC_PANE_CMD_DIR/42.armed" ]
  grep -q -- 'cc-pane-runner' "$KLOG" || false
  grep -q -- 'CC_PANE_CMD_DIR=' "$KLOG" || false
}

@test "CC_KITTY_ARGV_SPAWN=0 restores the interactive-shell split verbatim" {
  CC_KITTY_ARGV_SPAWN=0 run "$K" session split -v -s 7
  [ "$status" -eq 0 ]
  [ ! -f "$CC_PANE_CMD_DIR/42.armed" ]
  # The control that makes the test above non-vacuous: same command, same fake, no runner in the argv.
  ! grep -q -- 'cc-pane-runner' "$KLOG" || false
}

@test "split never steals focus — on BOTH transports" {
  # `--keep-focus` is 0999c8bb's, landed independently while this work was in flight; the arming path
  # must carry it too, or the transport that still types would be the only one protected. The two
  # fixes are complements, not rivals: 0999c8bb removes the operator's keystrokes as a SOURCE, arming
  # removes the line buffer they landed in.
  run "$K" session split -v -s 7
  [ "$status" -eq 0 ]
  grep -q -- '--keep-focus' "$KLOG" || false
  : > "$KLOG"
  CC_KITTY_ARGV_SPAWN=0 run "$K" session split -s 7
  [ "$status" -eq 0 ]
  grep -q -- '--keep-focus' "$KLOG" || false
}

# ── send: an armed pane has no line to clear ─────────────────────────────────────────────────────

@test "send on an ARMED pane types nothing (the ^U has nothing to clear)" {
  arm 42
  run "$K" session send -s 42 "$(printf '\025')"
  [ "$status" -eq 0 ]
  ! grep -q -- 'send-text' "$KLOG" || false
}

@test "send on an UNARMED pane still types — the legacy transport is intact" {
  run "$K" session send -s 42 "$(printf '\025')"
  [ "$status" -eq 0 ]
  grep -q -- 'send-text' "$KLOG" || false
}

# ── run: the file drop, and the assertion that it was picked up ──────────────────────────────────

@test "run on an ARMED pane writes the command to a file and types nothing" {
  arm 42
  CC_KITTY_SPAWN_VERIFY_S=0 run "$K" session run -s 42 'echo hello'
  [ "$status" -eq 0 ]
  [ "$(cat "$CC_PANE_CMD_DIR/42.cmd")" = "echo hello" ]
  ! grep -q -- 'send-text' "$KLOG" || false
}

@test "run on an UNARMED pane still types the text plus a CR" {
  run "$K" session run -s 42 'echo hello'
  [ "$status" -eq 0 ]
  grep -q -- 'send-text' "$KLOG" || false
  grep -q -- 'echo hello' "$KLOG" || false
}

@test "the liveness assertion FAILS when the pane never picks the command up" {
  arm 42
  CC_KITTY_SPAWN_VERIFY_S=1 run "$K" session run -s 42 'echo hello'
  [ "$status" -eq 1 ]
  # The whole point is that the operator is TOLD. A silent non-zero would be no better than the
  # "Spawned successfully" this replaces.
  printf '%s\n' "$output" | grep -q 'never picked up its launch command' || false
  printf '%s\n' "$output" | grep -q 'did NOT start' || false
}

@test "the liveness assertion PASSES as soon as the command is consumed" {
  arm 42
  ( while [ ! -f "$CC_PANE_CMD_DIR/42.cmd" ]; do sleep 0.05; done
    rm -f "$CC_PANE_CMD_DIR/42.cmd" ) &
  CC_KITTY_SPAWN_VERIFY_S=10 run "$K" session run -s 42 'echo hello'
  wait
  [ "$status" -eq 0 ]
}

# ── the runner itself ────────────────────────────────────────────────────────────────────────────

@test "cc-pane-runner runs the delivered command, then consumes BOTH markers" {
  mkdir -p "$CC_PANE_CMD_DIR"
  : > "$CC_PANE_CMD_DIR/42.armed"
  printf '%s' "echo ran > $BATS_TEST_TMPDIR/ran.txt" > "$CC_PANE_CMD_DIR/42.cmd"
  SHELL="/bin/echo" KITTY_WINDOW_ID=42 run "$RUNNER"
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/ran.txt")" = "ran" ]
  # Both must go: a surviving .armed would silently swallow every LATER command into a file that,
  # after the exec below, nothing is left to read.
  [ ! -f "$CC_PANE_CMD_DIR/42.cmd" ]
  [ ! -f "$CC_PANE_CMD_DIR/42.armed" ]
}

@test "cc-pane-runner ends as a SHELL, never as an exit" {
  mkdir -p "$CC_PANE_CMD_DIR"
  printf '%s' "true" > "$CC_PANE_CMD_DIR/42.cmd"
  SHELL="/bin/echo" KITTY_WINDOW_ID=42 run "$RUNNER"
  [ "$status" -eq 0 ]
  # /bin/echo stands in for the login shell, so its own argv is the proof it was exec'd. A pane that
  # EXITED would take its diagnostic with it and read as a dead pane to the prune path.
  printf '%s\n' "$output" | grep -q -- '-l -i' || false
}

@test "cc-pane-runner with nothing to do says why, and still becomes a shell" {
  SHELL="/bin/echo" run env -u CC_PANE_CMD_DIR "$RUNNER"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'CC_PANE_CMD_DIR is unset' || false
  printf '%s\n' "$output" | grep -q -- '-l -i' || false
}

# ── the opt-out is a CONTRACT, and as of 2026-08-07 it has ONE wholesale caller, not two ─────────

@test "cc-pane's spawn opts out of arming — it types into a fresh pane" {
  # It splits a pane and then sends SEVERAL lines at it (the spawn/send pair). Arming it would leave
  # those keystrokes in a tty nobody reads, so this pins the opt-out rather than trusting a comment.
  grep -q 'CC_KITTY_ARGV_SPAWN=0' "$REPO/bin/cc-pane" || false
}

@test "handoff-fire no longer opts out WHOLESALE — it pre-delivers, and types only as a fallback" {
  # REWRITTEN (item 2f074ef14947). This test used to pin handoff as the second unconditional opt-out,
  # on the rationale that it types several accepted lines an armed pane could not service. That was
  # true of the typed transport and is now moot in the way that matters: the disarm line, `nocorrect`
  # and the echo-verify all exist ONLY to make typing survivable, so a command that is never typed
  # has nothing left for them to defend. handoff now hands $CMD over on the LAUNCH (CC_PANE_CMD),
  # which is strictly stronger than arming — there is no later delivery to race at all.
  #
  # Left as a passing-but-stale assertion this would have become an inverted guard: it would still go
  # green on the `CC_KITTY_ARGV_SPAWN=0` that survives in the fallback branch, while asserting a
  # contract the subject had deliberately stopped honouring.
  local split; split="$(sed -n '/^it2_split() {/,/^}/p' "$REPO/scripts/handoff-fire.sh")"
  [ -n "$split" ]
  # The argv branch is the DEFAULT and pre-delivers through the shim's environment…
  grep -q 'export CC_PANE_CMD="\$CMD"' <<<"$split" || false
  # …and the opt-out survives ONLY as the else-branch, for iTerm2 and for a box where the runner
  # cannot be resolved. Both branches must be present: one alone is either a regression or a cliff.
  grep -q 'CC_KITTY_ARGV_SPAWN=0' <<<"$split" || false
}
