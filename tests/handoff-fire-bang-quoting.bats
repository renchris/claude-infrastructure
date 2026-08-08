#!/usr/bin/env bats
# Regression guard: a `!` in --extra silently refuses the WHOLE typed launch line.
#
# THE HAZARD: handoff-fire composes its launch line in BASH and TYPES it into the operator's
# interactive ZSH, where BANG_HIST is on by default and `!word` at the prompt is an event
# reference. A bare `!` therefore refuses the entire line before any of it runs — no cd, no
# launcher, no session. Both zsh shapes report SUCCESS upstream: an unmatched event refuses the
# line outright, a MATCHING one trips oh-my-zsh's HIST_VERIFY (lib/history.zsh, set by omz and
# invisible from ~/.zshrc), which reloads the expanded line into the buffer and waits for a second
# Enter that never comes. it2_type_verified sees neither — it echo-verifies the buffer BEFORE the
# CR and returns right after sending it, so its success predicate is blind to every PARSE-time
# hazard by construction.
#
# WHAT IS ACTUALLY EXPOSED — measured 2026-07-30, not assumed. Only $EXTRA. Every path in the typed
# line goes through `printf %q`, and BASH's %q escapes `!` unconditionally; $EXTRA is raw shell text
# that is deliberately word-split, so it cannot be quoted without changing its meaning, and it is
# the one token that reaches zsh unquoted. It fails closed instead.
#
# THE TRAP THAT MAKES THIS EASY TO GET BACKWARDS, and the reason it is pinned here: `printf %q` is a
# SHELL BUILTIN and the two shells disagree about `!` — zsh's leaves it BARE, bash's ESCAPES it.
# Measuring it at an interactive zsh prompt (or through any tool whose shell is zsh) reports a bug
# in bash's quoting that bash does not have, and indicts all six typed path shapes for a defect only
# $EXTRA has. The first two tests pin BOTH shells' behaviour so that conflation cannot return.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export HISTFILE="$BATS_TEST_TMPDIR/hist"; : > "$HISTFILE"
  # The --dry-run fires below reach real machine state that a fixtured $HOME does NOT redirect:
  # capacity_gate() reads live loadavg and refuses above 2.0/core (this box lives above it, so the
  # suite would go red by LOAD, not by its subject), and three seams resolve outside $HOME — two
  # absolute /tmp defaults and one BARE NAME the subject then EXECUTES off the operator's PATH.
  # Absent paths are the right fixture: these sensors fail open on one.
  export CC_FIRE_CAPACITY_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  printf 'a brief\n' > "$BATS_TEST_TMPDIR/brief.txt"
  BANGDIR="$BATS_TEST_TMPDIR/wt-hello!world"; mkdir -p "$BANGDIR"
  # A fixtured $HOME has no it2 shim, and the script reads REAL_IT2 out of it with an anchored sed
  # under `set -e` — so without this stub a --dry-run dies at rc 1 having printed NOTHING, which
  # reads exactly like the refusal the --extra tests below assert. Stub it rather than borrowing the
  # live $HOME: a suite that runs against the operator's real shim encodes who ran it.
  mkdir -p "$HOME/.claude/bin"
  printf '#!/usr/bin/env bash\nREAL_IT2="/usr/bin/true"\nexec /usr/bin/true "$@"\n' > "$HOME/.claude/bin/it2"
  chmod +x "$HOME/.claude/bin/it2"
}

# Type one composed line into a real interactive zsh (-i for BANG_HIST, -f for no rc = hermetic)
# and report whether it actually RAN. The subject is what zsh's LEXER does with the bytes we type,
# so these assertions are behavioural: no source-shape proxy can stand in for them.
zsh_runs() { # $1=line → stdout: the shell's own output; rc 0 iff the sentinel executed
  local out
  out="$(printf '%s\n' "$1" | zsh -i -f 2>&1)"
  printf '%s' "$out"
  printf '%s' "$out" | grep -q 'LANDED-OK'
}

@test "the two shells' printf %q disagree about '!' — bash escapes it, zsh does not" {
  # Pins the trap itself. If bash ever stopped escaping, every %q'd path in the typed line would
  # become exposed and the guard below would be covering one of several holes instead of the only
  # one — so this is the premise the rest of the suite rests on, asserted rather than assumed.
  command -v zsh >/dev/null || skip "no zsh on this box"
  [ "$(bash -c 'printf %q "a!b"')" = 'a\!b' ] \
    || { echo "bash's printf %q no longer escapes '!' — the %q'd paths are now exposed too"; false; }
  [ "$(zsh -c 'printf %q "a!b"')" = 'a!b' ] \
    || { echo "zsh's printf %q now escapes '!' — the measurement trap this suite documents is gone"; false; }
}

@test "a '!' path survives the real typed line, because bash's %q escaped it" {
  # The six typed shapes are NOT the hazard. Composed the way the script composes them — in bash —
  # a bang path runs. This is the test that keeps a future 'fix' from rewriting all six shapes for
  # a defect they do not have.
  command -v zsh >/dev/null || skip "no zsh on this box"
  local q; q="$(bash -c 'printf %q "$1"' _ "$BANGDIR")"
  run zsh_runs "cd $q && echo LANDED-OK"
  [ "$status" -eq 0 ] || { echo "a %q'd bang path was refused: $output"; false; }
}

@test "RED-PROOF: the SAME path unescaped is refused by the same zsh" {
  # The control that gives the test above meaning: strip the escape bash added and the line dies.
  # Without this, "it ran" would be equally consistent with zsh having no history expansion at all.
  command -v zsh >/dev/null || skip "no zsh on this box"
  run zsh_runs "cd $BANGDIR && echo LANDED-OK"
  [ "$status" -ne 0 ] || { echo "a bare '!' survived — this box does not reproduce the hazard at all"; false; }
  printf '%s\n' "$output" | grep -q 'event not found' \
    || { echo "refused, but not by history expansion: $output"; false; }
}

@test "CONTROL: the bare line runs once BANG_HIST is off — the '!' is the cause, not the path" {
  # setopt must be its OWN line: history expansion happens when the line is READ, so a
  # `setopt NO_BANG_HIST; <cmd>` one-liner is expanded before the setopt has run and "fails" for a
  # reason that has nothing to do with the subject.
  command -v zsh >/dev/null || skip "no zsh on this box"
  local out
  out="$(printf '%s\n' 'setopt NO_BANG_HIST' "cd $BANGDIR && echo LANDED-OK" | zsh -i -f 2>&1)"
  printf '%s\n' "$out" | grep -q 'LANDED-OK' \
    || { echo "NO_BANG_HIST did not rescue it — the cause is not history expansion: $out"; false; }
}

@test "%q's \$'…' form leaves the bang bare, and zsh does not expand inside it either" {
  # The one bash %q output form that does NOT escape `!` (emitted for a tab or newline in the
  # path). It is still safe, and this pins WHY — otherwise the next reader finds a bare bang in %q
  # output and reopens a closed question.
  command -v zsh >/dev/null || skip "no zsh on this box"
  local d q; d="$(printf '%s' "$BATS_TEST_TMPDIR/tab	dir!x")"; mkdir -p "$d"
  q="$(bash -c 'printf %q "$1"' _ "$d")"
  [[ "$q" == \$\'* ]] || skip "this bash did not choose the \$'…' form for a tab"
  run zsh_runs "cd $q && echo LANDED-OK"
  [ "$status" -eq 0 ] || { echo "the \$'…' form was refused: $output"; false; }
}

# Drive a real --dry-run fire far enough to compose the typed line. The capacity gate sits BEFORE
# the $EXTRA check and would refuse on a loaded box, turning every assertion below into a pass for
# the wrong reason — setup() pins it off along with the other ambient seams. `--prompt-file` is
# required to get past argument validation at all: without it the script prints usage and exits 1,
# which reads as a refusal and made the first draft of these tests pass vacuously. `--launcher`
# skips account ranking, which cannot work against a fixtured $HOME with no accounts.json.
fire_dry() { # $@ = extra args → the dry-run report
  bash "$HF" --dry-run --launcher claude-next3 \
    --prompt-file "$BATS_TEST_TMPDIR/brief.txt" "$@" 2>&1
}

@test "--extra refuses an unescaped '!' loudly instead of typing a line zsh will drop" {
  run fire_dry --extra '--foo a!b'
  [ "$status" -eq 2 ] || { echo "expected the exit-2 refusal, got $status: $output"; false; }
  printf '%s\n' "$output" | grep -q -- "--extra carries an unescaped" \
    || { echo "refused, but not with the actionable message: $output"; false; }
  ! printf '%s\n' "$output" | grep -q '^command:' \
    || { echo "a command was composed despite the refusal: $output"; false; }
}

@test "RED-PROOF: the value it refuses really would have killed the typed line" {
  # Ties the guard to the hazard rather than to a spelling. Take the line the PRE-guard script would
  # have composed for that same --extra value and type it into a real zsh: it must die.
  command -v zsh >/dev/null || skip "no zsh on this box"
  run zsh_runs "cd $BATS_TEST_TMPDIR && nocorrect echo --foo a!b LANDED-OK"
  [ "$status" -ne 0 ] || { echo "the refused value was actually harmless — the guard over-refuses"; false; }
  printf '%s\n' "$output" | grep -q 'event not found' \
    || { echo "died, but not by history expansion: $output"; false; }
}

@test "--extra accepts a PRE-ESCAPED bang (delete-then-match, not a widened pattern)" {
  # A caller who did the right thing must not be convicted for it — the half a naive
  # `case $EXTRA in *'!'*` guard gets wrong. The `command:` assertion is what makes this
  # non-vacuous: it proves the run reached composition rather than dying somewhere earlier.
  run fire_dry --extra '--permission-mode plan\!x'
  # `! A || {…}`, never `A && {…}`: under errexit the `A && {…}` form is and-absorbed — when A
  # fails the whole list is simply false and the test carries on, so the assertion is unreachable.
  ! printf '%s\n' "$output" | grep -q -- "--extra carries an unescaped" \
    || { echo "pre-escaped '\\!' was refused: $output"; false; }
  printf '%s\n' "$output" | grep -q '^command:.*plan\\!x' \
    || { echo "never reached composition, so the pass proves nothing: $output"; false; }
}

@test "--extra's ordinary values reach the composed line untouched" {
  local v
  for v in '--permission-mode plan' '--resume 3f2a9c1b'; do
    run fire_dry --extra "$v"
    printf '%s\n' "$output" | grep -q "^command:.*$v" \
      || { echo "a real-world --extra value did not survive to the typed line: [$v] $output"; false; }
  done
}
