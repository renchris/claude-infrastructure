#!/usr/bin/env bats
# handoff-fire argv launch — a fired pane's command is its ARGV, never keystrokes (item 2f074ef14947).
#
# WHY THIS SUITE EXISTS. On 2026-08-07 a `--follow` fire raised the new pane into the operator's focus
# WHILE the script was typing the launch line at its prompt. One in-flight keystroke concatenated onto
# the spell-correction disarm line: `unsetopt correct correct_all 2>/dev/null || true` arrived as
# `truem`, zsh asked `correct 'truem' to 'true' [nyae]?`, the answer 'e' left a shell parked at
# `execute:` in an unrelated project. The same session produced three task-less panes, and cc-classify
# calls a booted-but-briefless pane `active`, so cc-reaper never reaps them and they persist.
#
# The subject under test is NOT "does the typed text arrive intact". That question has no good answer:
# the echo-verify READS the line back and then sends CR as a separate act, so a keystroke landing
# between the read and the CR is verified-then-corrupted. Verification samples; the Enter acts. The
# subject is that the command rides in on the LAUNCH — argv+env, one atomic act, before the pane draws
# a row — so there is no prompt to collide with and no interval in which anything can race it.
#
# The tests that MATTER here are the pairs. In particular the interactive-shell branch is stated
# alongside its negative control: handoff's launchers are zsh FUNCTIONS from the operator's
# interactive rc, so the SAME command that resolves under `$SHELL -l -i -c` must be shown to DIE under
# the `eval` path the runner uses for Claude Code. Without that pair, a test of the branch would pass
# just as well if the branch did nothing.
#
# Every assertion is `[ ]` or `… || false` — `[[ ]]` and `(( ))` are errexit-EXEMPT in bats and are
# silently DEAD anywhere but a body's last line.

setup() {
  # Fixturing $HOME is NOT enough: these three seams resolve OUTSIDE it — two to absolute /tmp
  # defaults, one to a BARE NAME the subject then executes off the operator's live PATH. An absent
  # path is the right fixture, because each sensor fails open on one.
  export CC_FIRE_CAPACITY_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-lock-"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  K="$REPO/bin/it2-kitty"
  RUNNER="$REPO/bin/cc-pane-runner"
  export CC_TERM_KITTY_TO="unix:$BATS_TEST_TMPDIR/sock"
  export CC_TERM_KITTY="$BATS_TEST_TMPDIR/fake-kitty"
  export CC_PANE_CMD_DIR="$BATS_TEST_TMPDIR/cmd"
  export CC_PANE_RUNNER_BIN="$RUNNER"
  # …and the four the SUBJECT ITSELF puts on a pane. This suite goes red exactly when it is run from
  # inside a pane THIS FEATURE created — the shape a feature's own suite can least afford (item
  # 4c5eddc16c2d, measured 2026-08-07). `--env CC_PANE_CMD_INTERACTIVE=1` is set on the launch, so it
  # is inherited by every descendant of a fired pane, including bats; the tests below unset
  # CC_PANE_CMD_DIR but never this, so `cc-pane-runner` took the `$SHELL -l -i -c` branch in the two
  # cases that exist to prove it does NOT. Both failures then read as a genuine trunk red — one of
  # them the negative CONTROL "the SAME launcher DIES under the eval path", i.e. the assertion whose
  # whole job is to show that branch is not decoration. Green with these four unset, red with
  # CC_PANE_CMD_INTERACTIVE alone restored, identically on a pristine `git archive origin/main` tree.
  #
  # Pinned in setup, not per-test: a per-test unset leaves every other test in the file pointed at
  # live state, which is rule 1's argument in scripts/test-hermeticity-lint.sh verbatim. That lint
  # cannot catch this class today — its seam table only recognises a `${VAR:-default}` whose default
  # NAMES a repo-shipped tool, and this one defaults to `0`.
  #
  # That pin makes the SUITE hermetic; it does not make the leak stop existing. Under item
  # 22a170cc62aa bin/cc-pane-runner gained the other half — it CONSUMES both variables at delivery,
  # so the command it runs (and every descendant of it) can no longer inherit a spent record at all.
  # "env mode CONSUMES its delivery record" below is that half's control.
  unset CC_PANE_CMD CC_PANE_CMD_INTERACTIVE CC_PANE_CMD_WAIT_S CC_PANE_RUNNER
  KLOG="$BATS_TEST_TMPDIR/kitty.log"
  fake_kitty
}

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

# A hermetic stand-in for the operator's interactive rc: a launcher that exists ONLY as a zsh function
# defined in .zshrc. ZDOTDIR redirects zsh's rc lookup, so this never reads the real ~/.zshrc and the
# suite's verdict does not depend on whose box it runs on.
fixture_rc() {
  local d="$BATS_TEST_TMPDIR/zdot"; mkdir -p "$d"
  printf 'hfprobe_launcher(){ printf "FN-RESOLVED:%%s\\n" "$1"; }\n' > "$d/.zshrc"
  printf '%s' "$d"
}

# ── bin/cc-pane-runner: the ENV delivery mode ────────────────────────────────────────────────────

@test "CC_PANE_CMD runs immediately — no CMD_DIR, no pane id, nothing to poll for" {
  # Env mode must not require the two variables the FILE mode keys on: demanding them would make a
  # perfectly deliverable command fall back to a bare shell over state it never reads.
  run env -u CC_PANE_CMD_DIR -u KITTY_WINDOW_ID \
      CC_PANE_CMD="echo ran > $BATS_TEST_TMPDIR/ran.txt" SHELL="/bin/echo" "$RUNNER"
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/ran.txt")" = "ran" ]
  # …and it still ends as a SHELL, never an exit — a pane that vanishes takes its diagnostic with it.
  printf '%s\n' "$output" | grep -q -- '-l -i' || false
}

@test "env mode CONSUMES its delivery record — the command inherits NEITHER half" {
  # The pair to the `rm -f "$_cmdfile" "$_armed"` the FILE path does, and the half that was missing.
  # `kitty @ launch --env` puts these in the PANE's environment, so without a consume they outlive
  # the delivery by the whole life of the pane and are inherited by every descendant of the command.
  # Measured 2026-08-07 inside a pane scripts/handoff-fire.sh had fired: the agent session still
  # carried the launch line that started it, so `it2-kitty session split` read that spent value as
  # its own caller's intent (it2-kitty:626), forwarded `--env CC_PANE_CMD=<the PARENT's own handoff
  # command>` into the new pane and left it UNARMED — a child re-running its parent's launch while
  # the command actually meant for it was typed at a pane with no prompt.
  #
  # INTERACTIVE=0, not unset: it selects the same eval branch (so this pins consumption and nothing
  # else) while still being SET, which is what keeps the second assertion from passing vacuously.
  cat > "$BATS_TEST_TMPDIR/showenv" <<'SH'
#!/bin/bash
printf 'SAW_CMD=[%s]\nSAW_INT=[%s]\n' "${CC_PANE_CMD:-}" "${CC_PANE_CMD_INTERACTIVE:-}"
SH
  chmod +x "$BATS_TEST_TMPDIR/showenv"
  run env -u CC_PANE_CMD_DIR -u KITTY_WINDOW_ID \
      CC_PANE_CMD="$BATS_TEST_TMPDIR/showenv" CC_PANE_CMD_INTERACTIVE=0 SHELL="/bin/echo" "$RUNNER"
  [ "$status" -eq 0 ]
  # It must have RUN (else both greps below pass on output the command never produced).
  printf '%s\n' "$output" | grep -q 'SAW_CMD=' || false
  printf '%s\n' "$output" | grep -qx 'SAW_CMD=\[\]' || false
  printf '%s\n' "$output" | grep -qx 'SAW_INT=\[\]' || false
}

@test "the env-mode command is ECHOED first, so a watching operator and get-text see the same line" {
  run env -u CC_PANE_CMD_DIR CC_PANE_CMD="true" SHELL="/bin/echo" "$RUNNER"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qx 'true' || false
}

@test "an EMPTY CC_PANE_CMD is not env mode — it falls through to the file path's own diagnostic" {
  # The pairing that keeps `[ -n ]` honest: were the branch keyed on "is the variable set", an empty
  # value would run nothing and silently become a bare shell with no explanation at all.
  run env -u CC_PANE_CMD_DIR CC_PANE_CMD="" SHELL="/bin/echo" "$RUNNER"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'CC_PANE_CMD_DIR is unset' || false
}

# ── the interactive-shell branch, stated with its negative control ───────────────────────────────

@test "CC_PANE_CMD_INTERACTIVE=1 runs the command under \$SHELL -l -i -c" {
  # /bin/echo stands in for the login shell, so its own argv is the proof of which form was used.
  run env -u CC_PANE_CMD_DIR CC_PANE_CMD="whatever" CC_PANE_CMD_INTERACTIVE=1 SHELL="/bin/echo" "$RUNNER"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q -- '-l -i -c whatever' || false
}

# ── THE TWO TESTS BELOW MUST CLOSE STDIN, AND IT IS NOT HYGIENE (backlog 5a07814271ed) ──────────
# These are the only two tests in this file that hand the runner a REAL shell (`/bin/zsh`); every
# other one uses `/bin/echo`, which prints its argv and exits. That difference is load-bearing,
# because cc-pane-runner:199 ends `_launch` with `_fallback ""`, which at :69 does
#
#     exec "${SHELL:-/bin/zsh}" -l -i          ← by design: the pane BECOMES an ordinary shell
#
# In production that is exactly right — the pane's stdin is a terminal and the operator gets a
# prompt back. Under bats it is a trap: the exec'd interactive login zsh INHERITS the test runner's
# stdin, and if that fd never reaches EOF the shell sits at a prompt forever. `/bin/echo -l -i`
# cannot wedge whatever stdin does, which is why the other seventeen tests never showed this.
#
# MEASURED 2026-08-24 on an unmodified tree, both arms back-to-back at 1-min load 16.9 (NOT the
# ~28 the backlog row suspected — load is held CONSTANT across the partition and does not
# discriminate):
#   stdin held open by a live writer → rc 124, bats emitted `1..2` and then ZERO results
#   stdin </dev/null                  → rc 0, `ok 1` + `ok 2`, ONE SECOND
# and directly against bin/cc-pane-runner at load 12-13, the same split, both arms.
#
# The consequence is far worse than a slow suite. A wedged run inside a belt sweep holds the run
# long enough for bats' own tmpdir to be reclaimed underneath it; the run then dies with
# `test_list_file.txt: No such file or directory` and `Executed 1328 instead of expected 2789`,
# i.e. HALF the corpus silently unexecuted, presented as three ordinary `not ok` lines. Removing
# either redirect below re-arms that.
@test "CONTROL: an interactive-rc-only launcher RESOLVES under -l -i -c" {
  # This is the whole reason the branch exists. handoff's $CMD names `claude4` / `nocorrect claude4 …`,
  # which on this box is a zsh FUNCTION from the interactive rc — not a binary on PATH.
  local zd; zd="$(fixture_rc)"
  run env -u CC_PANE_CMD_DIR HOME="$zd" ZDOTDIR="$zd" \
      CC_PANE_CMD="hfprobe_launcher hello" CC_PANE_CMD_INTERACTIVE=1 SHELL="/bin/zsh" "$RUNNER" </dev/null
  printf '%s\n' "$output" | grep -q 'FN-RESOLVED:hello' || false
}

@test "CONTROL: the SAME launcher DIES under the eval path — so the branch is not decoration" {
  # The negative half. Without CC_PANE_CMD_INTERACTIVE the runner evals in ITS OWN shell (bash), where
  # a zsh interactive-rc function does not exist. This is what would have happened had handoff simply
  # flipped the existing arming flag: the pane prints the command and dies on `command not found` —
  # strictly WORSE than typing it. A test of the positive branch alone could not tell the difference.
  # `</dev/null` for the reason stated above the previous test: this arm sets SHELL=/bin/zsh too, so
  # it reaches the SAME `exec "$SHELL" -l -i`. The backlog row named only the test above; measured
  # here, this one wedges identically (rc 124 vs rc 0 on the stdin split, at the same load).
  local zd; zd="$(fixture_rc)"
  run env -u CC_PANE_CMD_DIR HOME="$zd" ZDOTDIR="$zd" \
      CC_PANE_CMD="hfprobe_launcher hello" SHELL="/bin/zsh" "$RUNNER" </dev/null
  ! printf '%s\n' "$output" | grep -q 'FN-RESOLVED' || false
  printf '%s\n' "$output" | grep -qi 'not found' || false
}

# ── bin/it2-kitty: pre-delivery on the split, and the arming it must NOT do ──────────────────────

@test "a pre-delivered CC_PANE_CMD rides the launch as --env, and the pane is NOT armed" {
  run env CC_PANE_CMD='cd /x && nocorrect claude4 "$(cat /tmp/b.md)"' CC_PANE_CMD_INTERACTIVE=1 \
      "$K" session split -s 7
  [ "$status" -eq 0 ]
  grep -q -- '--env CC_PANE_CMD=cd /x && nocorrect claude4' "$KLOG" || false
  grep -q -- '--env CC_PANE_CMD_INTERACTIVE=1' "$KLOG" || false
  grep -q -- 'exec "$CC_PANE_RUNNER"' "$KLOG" || false
  # No `.armed`: nothing further will be delivered to this pane, and a stale marker would swallow the
  # next legitimate run/send into a file nobody reads.
  [ ! -f "$CC_PANE_CMD_DIR/42.armed" ]
}

@test "PAIR: without CC_PANE_CMD the split still ARMS — the file transport is untouched" {
  run env -u CC_PANE_CMD "$K" session split -s 7
  [ "$status" -eq 0 ]
  [ -f "$CC_PANE_CMD_DIR/42.armed" ]
  ! grep -q -- '--env CC_PANE_CMD=' "$KLOG" || false
}

@test "a missing runner REFUSES pre-delivery loudly instead of launching a broken argv" {
  # Fail-loud, not fail-silent: a pane whose argv names a file that is not there dies instantly and
  # takes the diagnostic with it.
  run env CC_PANE_CMD="true" CC_PANE_RUNNER_BIN="$BATS_TEST_TMPDIR/nope" "$K" session split -s 7
  printf '%s\n' "$output" | grep -q 'cannot be delivered as argv' || false
  ! grep -q -- '--env CC_PANE_CMD=' "$KLOG" || false
}

# ── scripts/handoff-fire.sh wiring ───────────────────────────────────────────────────────────────
# Source-level, because every one of these surfaces CREATES a real tab/window and cannot execute in
# CI. The durable checkable guarantee is that each creating site carries the argv flags at all.

@test "EVERY kitty pane-creating surface pre-delivers \$CMD — none is left typing" {
  # Per-SITE, not "the file mentions HF_ARGV somewhere": a new surface added without the flags would
  # silently reintroduce the 2026-08-07 race on exactly one path. kt launch appears at these three
  # sites; the fourth (split) delegates to it2-kitty and pre-delivers through its environment.
  local n
  n="$(grep -c 'kt launch .*HF_ARGV\[@\]' "$HF")"
  [ "$n" -eq 3 ] || { echo "expected 3 argv-carrying kt launch sites, found $n"; false; }
  # …and no kt launch site is left WITHOUT them.
  local bare
  bare="$(grep -n 'kt launch ' "$HF" | grep -vc 'HF_ARGV\[@\]' || true)"
  [ "$bare" -eq 0 ] || { echo "$bare kt launch site(s) still type:"; grep -n 'kt launch ' "$HF" | grep -v 'HF_ARGV\[@\]'; false; }
  # The split surface hands the command over through the shim's environment instead.
  sed -n '/^it2_split() {/,/^}/p' "$HF" | grep -q 'export CC_PANE_CMD="\$CMD"' || false
}

@test "the array is expanded in the guarded \${HF_ARGV[@]+…} form at every site" {
  # Under `set -euo pipefail` on bash 3.2 (this box) a bare "${HF_ARGV[@]}" on an EMPTY array is a
  # fatal `unbound variable`, and the suites that exercise these functions sed-extract them one at a
  # time, so the array is frequently not merely empty but UNSET. An unguarded expansion would abort
  # the fire outright on exactly the path that is supposed to degrade quietly to typing.
  # DELETE-THEN-MATCH, not a denylist of bad spellings. The unguarded form `"${HF_ARGV[@]}"` is a
  # SUBSTRING of the guarded one `${HF_ARGV[@]+"${HF_ARGV[@]}"}`, so grepping for the bad form matches
  # the good form too and the assertion can never pass — it failed on first run for exactly that
  # reason. Removing every guarded expansion first and then looking for ANY survivor cannot be fooled
  # by a spelling this test did not think of.
  local residue
  residue="$(grep -n 'kt launch ' "$HF" | sed 's/\${HF_ARGV\[@\]+"\${HF_ARGV\[@\]}"}//g' | grep -c 'HF_ARGV\[@\]' || true)"
  [ "$residue" -eq 0 ] || { echo "$residue unguarded HF_ARGV expansion(s) on a kt launch line"; false; }
  # …and the guarded form is actually PRESENT on all three — a file with no expansions at all would
  # otherwise satisfy the check above vacuously. Counted on the launch lines only: the helper's own
  # doc comment quotes the same form, and counting the whole file would pin a comment.
  local n; n="$(grep 'kt launch ' "$HF" | grep -c '\${HF_ARGV\[@\]+"\${HF_ARGV\[@\]}"}')"
  [ "$n" -eq 3 ] || { echo "expected 3 guarded expansions on kt launch lines, found $n"; false; }
}

@test "it2_land does NOT type when the command was pre-delivered" {
  local land; land="$(sed -n '/^it2_land() {/,/^}/p' "$HF")"
  [ -n "$land" ]
  grep -q 'HF_ARGV_ACTIVE:-0' <<<"$land" || false
  # …and the typed transport is still REACHABLE — this is a branch, not a deletion. iTerm2 and any
  # box where the runner cannot be resolved still land the command exactly as they did before.
  grep -q 'it2_type_verified' <<<"$land" || false
}

@test "hf_argv_launch is DEFINED before the top-level call that uses it" {
  # A function called from top-level code must appear textually first — bash reads the file in order,
  # and a definition further down has simply not happened yet. Caught in development: the helper sat
  # next to the surfaces it serves (~line 5100) while the call sits with the other post-\$CMD setup
  # (~line 4565), which is `command not found` and, under `set -e`, an aborted fire.
  local def call
  def="$(grep -n '^hf_argv_launch() {' "$HF" | head -1 | cut -d: -f1)"
  call="$(grep -n '^hf_argv_launch$' "$HF" | head -1 | cut -d: -f1)"
  [ -n "$def" ] && [ -n "$call" ] || false
  [ "$def" -lt "$call" ] || { echo "definition at $def is AFTER the call at $call"; false; }
}

@test "an unresolvable runner degrades to TYPING, never to a broken pane" {
  # Behavioural, on the extracted helper: the whole fail-open contract in one assertion.
  local fn; fn="$(sed -n '/^hf_argv_launch() {/,/^}/p' "$HF")"
  run env bash -euo pipefail -c "
    in_kitty(){ return 0; }
    CMD='cd /x && claude4'
    CC_RUNNER_BIN='$BATS_TEST_TMPDIR/definitely-not-here'
    $fn
    hf_argv_launch
    echo \"active=\${HF_ARGV_ACTIVE}\"
  "
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qx 'active=0' || false
}

@test "FIRE_ARGV_LAUNCH=0 restores the typed launch verbatim" {
  local fn; fn="$(sed -n '/^hf_argv_launch() {/,/^}/p' "$HF")"
  run env bash -euo pipefail -c "
    in_kitty(){ return 0; }
    CMD='cd /x && claude4'
    CC_RUNNER_BIN='$RUNNER'
    FIRE_ARGV_LAUNCH=0
    $fn
    hf_argv_launch
    echo \"active=\${HF_ARGV_ACTIVE}\"
  "
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qx 'active=0' || false
}

@test "on kitty with a real runner it ACTIVATES — the positive half of the two guards above" {
  local fn; fn="$(sed -n '/^hf_argv_launch() {/,/^}/p' "$HF")"
  run env bash -euo pipefail -c "
    in_kitty(){ return 0; }
    CMD='cd /x && nocorrect claude4 \"\$(cat /tmp/b.md)\"'
    CC_RUNNER_BIN='$RUNNER'
    $fn
    hf_argv_launch
    echo \"active=\${HF_ARGV_ACTIVE}\"
    printf '%s\n' \"\${HF_ARGV[@]}\"
  "
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qx 'active=1' || false
  printf '%s\n' "$output" | grep -q 'CC_PANE_CMD_INTERACTIVE=1' || false
  # The command must survive verbatim — this is the value kitty carries into the pane's environment.
  printf '%s\n' "$output" | grep -qF 'CC_PANE_CMD=cd /x && nocorrect claude4 "$(cat /tmp/b.md)"' || false
}

@test "iTerm2 does NOT take the argv path — that branch is untouched" {
  local fn; fn="$(sed -n '/^hf_argv_launch() {/,/^}/p' "$HF")"
  run env bash -euo pipefail -c "
    in_kitty(){ return 1; }
    CMD='cd /x && claude4'
    CC_RUNNER_BIN='$RUNNER'
    $fn
    hf_argv_launch
    echo \"active=\${HF_ARGV_ACTIVE}\"
  "
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qx 'active=0' || false
}

@test "the RECYCLE path still types — it re-uses a pane, so there is no launch to carry argv" {
  # Named so the gap is a decision on the record rather than an oversight. recycle_fire re-uses the
  # CURRENT pane; nothing is launched, so the argv transport cannot apply to it. It is also the one
  # surface where the operator is not being raced by a NEW pane appearing under their hands.
  sed -n '/^recycle_fire() {/,/^}/p' "$HF" | grep -q 'it2_type_verified' || false
}
