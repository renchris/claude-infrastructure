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

# ── run: the ECHO-VERIFY, and the pane class it must refuse to use it on (item d90bbcd9e01f) ─────
#
# prove_target already answers "the text went NOWHERE". These cover the other half — the window
# EXISTS and the text arrived MANGLED — and, just as load-bearing, the pane class where the fix is
# itself the hazard: `run` is the verb handoff-fire's as_write types `/exit` through into a LIVE
# Claude Code composer, where `: <nonce>; /exit` is not a command but a CHAT MESSAGE. So half these
# cases assert the guard FIRES and half assert it STANDS DOWN, and neither set is meaningful alone.

# The base fake answers ls with a constant and get-text with a fixed string, so it can say nothing
# about either axis this feature reads. This one models a pty instead: send-text APPENDS its payload
# to a screen file and get-text cats it, so "arrived intact" and "arrived mangled" are the SAME code
# path with one variable changed. FAKE_ALT drives in_alternate_screen; FAKE_MANGLE drops the payload's
# first character, which is the reproduced defect's shape (a stray keystroke merging with the first
# word: `cd /tmp` read back as `acd /tmp`).
fake_kitty_pty() {
  SCREEN="$BATS_TEST_TMPDIR/screen"; : > "$SCREEN"; export SCREEN
  cat > "$CC_TERM_KITTY" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$KLOG"
verb=""; args=()
for a in "$@"; do
  case "$a" in @|--to|unix:*) continue ;; esac
  if [ -z "$verb" ]; then verb="$a"; else args+=("$a"); fi
done
case "$verb" in
  launch) echo 42 ;;
  ls)     printf '[{"id":1,"tabs":[{"id":1,"windows":[{"id":42,"title":"t","cwd":"/tmp","pid":9,"in_alternate_screen":%s}]}]}]\n' "${FAKE_ALT:-false}" ;;
  send-text)
    payload=""
    [ "${#args[@]}" -gt 0 ] && payload="${args[$((${#args[@]}-1))]}"
    [ "${FAKE_MANGLE:-0}" = 1 ] && payload="${payload:1}"
    printf '%s' "$payload" >> "$SCREEN" ;;
  get-text) cat "$SCREEN" ;;
esac
exit 0
SH
  chmod +x "$CC_TERM_KITTY"
  export KLOG
  export CC_KITTY_TYPE_SETTLE=0 CC_KITTY_TYPE_PRESETTLE=0
}

# Every case below asserts its own locator found something before asserting anything about it: with
# a pattern-located subject, a rename makes the extract EMPTY and every grep over it passes over
# nothing (memory: absent-range-endpoint-selects-everything).
klog_sends() { [ -f "$KLOG" ] || { echo 0; return 0; }; grep -c -- 'send-text' "$KLOG" || true; }
# THE SUBMIT ORACLE. A carriage return is the ONLY payload that executes what is on the line, and it
# is sent as its own send-text — so "was anything submitted" is exactly "does any logged line carry a
# CR". Counting send-texts cannot answer it (the ^U scrubs are send-texts too) and a `-- .?$` regex
# cannot either: ^U is also one character, so that pattern reds on the scrub and reads as a submit.
klog_submitted() { [ -f "$KLOG" ] && grep -qF -- $'\r' "$KLOG"; }

@test "run on a proven SHELL pane types a nonce-anchored wire, reads it back, then submits" {
  fake_kitty_pty
  FAKE_ALT=false run "$K" session run -s 42 'echo hello'
  [ "$status" -eq 0 ]
  # The command never goes out bare-with-a-CR on this path…
  ! grep -qF -- 'echo hello'$'\r' "$KLOG" || false
  # …it goes out behind a `: <nonce>; ` prefix, and the CR is a SEPARATE send that only a successful
  # read-back can reach. Both halves matter: the prefix alone would not prove the CR was gated.
  grep -qE -- '-- : ktv-[0-9]+-1-[0-9]+; echo hello$' "$KLOG" || false
  grep -qF -- 'get-text' "$KLOG" || false
  # The positive half of the pair whose negative is the MANGLED case below: one predicate, both
  # directions. A verified read-back submits.
  klog_submitted || false
}

@test "run on a TUI pane ABSTAINS — a composer must never receive the nonce wire" {
  fake_kitty_pty
  FAKE_ALT=true run "$K" session run -s 42 '/exit'
  [ "$status" -eq 0 ]
  # This is the destructive case, so it is asserted POSITIVELY (the legacy transport ran) as well as
  # negatively (no nonce anywhere). A pane in the alternate screen is a live CC session: `: n; /exit`
  # would be entered as chat text and submitted.
  grep -qF -- '/exit' "$KLOG" || false
  ! grep -q -- 'ktv-' "$KLOG" || false
  # …and it never even reached the read: abstention happens BEFORE any keystroke.
  ! grep -q -- 'get-text' "$KLOG" || false
}

@test "a payload with NO in_alternate_screen key abstains — identity against False, not truthiness" {
  # The BASE fake, whose ls payload omits the key entirely. An absent field must read as "a TUI may
  # be up", never as "no TUI": guessing permissive here is the composer case above with no warning.
  run "$K" session run -s 42 'echo hello'
  [ "$status" -eq 0 ]
  ! grep -q -- 'ktv-' "$KLOG" || false
}

@test "MANGLED text on a shell pane fails LOUD and submits nothing" {
  fake_kitty_pty
  FAKE_ALT=false FAKE_MANGLE=1 CC_KITTY_TYPE_ATTEMPTS=2 run "$K" session run -s 42 'echo hello'
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not read it back"* ]] || false
  # The point of the whole feature: no CR was ever sent, so the mangled fragment did not execute.
  run klog_submitted
  [ "$status" -ne 0 ]
}

@test "each ATTEMPT mints a FRESH nonce, so residue from attempt 1 cannot satisfy attempt 2" {
  fake_kitty_pty
  # The pty fake ACCUMULATES (a real ^U clears; this one appends), which is precisely the residue
  # condition the anchoring exists for: attempt 1's echoed wire is still on the screen when attempt 2
  # reads it. A fixed-string check would pass there. Distinct nonces are what make it impossible.
  #
  # This case is COUPLED to the one above and the coupling is real, not an accident of the fixture:
  # a second nonce only exists if attempt 1 declined to submit. The mutant that sends the CR
  # unconditionally therefore reds BOTH, which is the correct reading — measured, after it was
  # predicted to red only the loud-failure case.
  FAKE_ALT=false FAKE_MANGLE=1 CC_KITTY_TYPE_ATTEMPTS=2 run "$K" session run -s 42 'echo hello'
  [ "$status" -eq 1 ]
  local n; n="$(grep -o -- 'ktv-[0-9]*-[0-9]*-[0-9]*' "$KLOG" | sort -u | wc -l | tr -d ' ')"
  [ "${n:-0}" -eq 2 ] || false
}

@test "CC_KITTY_TYPE_VERIFY=off restores the legacy single send on a shell pane" {
  fake_kitty_pty
  # The control that makes the first case non-vacuous: same pane class, same command, no verification
  # — so a green suite cannot be explained by the fake refusing to look like a shell.
  FAKE_ALT=false CC_KITTY_TYPE_VERIFY=off run "$K" session run -s 42 'echo hello'
  [ "$status" -eq 0 ]
  ! grep -q -- 'ktv-' "$KLOG" || false
  [ "$(klog_sends)" -eq 1 ]
}

@test "an ARMED pane never reaches the verifier — the file transport still wins" {
  fake_kitty_pty
  arm 42
  FAKE_ALT=false CC_KITTY_SPAWN_VERIFY_S=0 run "$K" session run -s 42 'echo hello'
  [ "$status" -eq 0 ]
  [ "$(cat "$CC_PANE_CMD_DIR/42.cmd")" = "echo hello" ]
  [ "$(klog_sends)" -eq 0 ]
}
