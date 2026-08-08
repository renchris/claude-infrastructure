#!/usr/bin/env bats
# cc-dispatch — G5: the venue reaches the ledger, and the off-box session gets DECLARED.
#
# WHY THIS EXISTS: `cc-backlog claim --venue local|cloud` was fully built and fully tested with
# ZERO PRODUCERS. cc-dispatch — the only automatic claimer in the fleet — claimed every item with
# a bare `claim <id> --by <sid>` (bin/cc-dispatch:1024-1025), so every item in the ledger read
# `venue: "local"` by the fold's default, including any that was never going to run here. That
# default is not a harmless one: the venue string SELECTS WHICH ORACLES MAY CONVICT the item
# (bin/cc-backlog § VENUE), so an off-box session labelled `local` is judged by oracles that
# structurally cannot see it, and reads as DEAD.
#
# The venue is read off the fire's OWN ARGV — the exact array handed to `$spawn` — rather than
# re-derived from the plan. That is the one source that cannot disagree with what was launched.
#
# AND THE DECLARE (CLOUD_OBSERVABILITY.md §8.1). A cloud session id does not exist until AFTER the
# fire returns it, so "declare before firing" is unsatisfiable. It is therefore scraped from the
# fire's captured output and declared IMMEDIATELY — and every path that fails to declare is LOUD,
# because an undeclared cloud session is both unobservable and reapable: the worst of the two
# possible failures, since nothing will even report it missing.
#
# The helpers are extracted from the shipped bin/cc-dispatch and executed, so this replays the real
# artifact rather than an approximation of it (memory: control-must-replay-the-real-artifact).
# Case 10 is the mutation control proving the structural pin in case 9 can fail.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude"
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  DISPATCH="$REPO/bin/cc-dispatch"
  [ -f "$DISPATCH" ] || skip "bin/cc-dispatch not found at $DISPATCH"
  LIB="$BATS_TEST_TMPDIR/lib.sh"
  {
    sed -n '/^resolve_bin()/,/^}/p'   "$DISPATCH"
    sed -n '/^fire_venue()/,/^}/p'    "$DISPATCH"
    sed -n '/^fire_branch()/,/^}/p'   "$DISPATCH"
    sed -n '/^cloud_declare()/,/^}/p' "$DISPATCH"
  } > "$LIB"
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  # cc-cloud stub — logs the argv it was declared with, and fails on demand ($STUB_DECL_RC).
  cat > "$BIN/cc-cloud" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$BATS_TEST_TMPDIR/declared.log"
exit "\${STUB_DECL_RC:-0}"
EOF
  chmod +x "$BIN/cc-cloud"
  export CC_DISPATCH_CLOUD_BIN="$BIN/cc-cloud"
  CAP="$BATS_TEST_TMPDIR/fire-output.txt"
}

lib() { bash -c ". '$LIB'; $*"; }
declared() { cat "$BATS_TEST_TMPDIR/declared.log" 2>/dev/null; }

# ── the venue is read off the argv that will actually run ─────────────────────────────

@test "1 fire_venue reads cloud off the fire's own argv" {
  run lib 'fire_venue --prompt-file /tmp/p --cloud --cwd /w'
  [ "$status" -eq 0 ]
  [ "$output" = "cloud" ]
}

@test "2 fire_venue defaults to local — the incumbent shape is unchanged" {
  run lib 'fire_venue --prompt-file /tmp/p --cwd /w --account next3'
  [ "$output" = "local" ]
}

@test "3 CONTROL — a near-miss argument is NOT a cloud fire" {
  # Element-exact, never a substring match. `--venue` is a CLOSED SET at the actuator precisely so
  # a mislabel cannot read as a verdict; a producer that matched loosely would hand that actuator a
  # correct-looking string derived from the wrong fire (memory:
  # default-path-hardening-is-blind-to-the-explicit-argument).
  run lib 'fire_venue --prompt-file /tmp/p --extra "--cloudy day"'
  [ "$output" = "local" ]
  run lib 'fire_venue --prompt-file /tmp/p --extra "run with --cloud later"'
  [ "$output" = "local" ]
}

# ── the branch the declare needs ──────────────────────────────────────────────────────

@test "4 fire_branch prefers an explicit --worktree" {
  run lib 'fire_branch --prompt-file /tmp/p --worktree feat/x --cwd /w/other'
  [ "$output" = "feat/x" ]
}

@test "5 fire_branch falls back to the --cwd basename — warm_worktree's own rule" {
  # Not a guess: warm_worktree provisions a --cwd fire's worktree with `br="$(basename "$wt")"`,
  # so the directory name IS the branch on that path. Reading it any other way would invent a
  # second answer to a question the dispatcher already answers one way.
  run lib 'fire_branch --prompt-file /tmp/p --cwd /Users/x/.worktrees/g5-venue'
  [ "$output" = "g5-venue" ]
}

@test "6 fire_branch names NOTHING rather than guessing" {
  run lib 'fire_branch --prompt-file /tmp/p --account next3'
  [ "$output" = "" ]
}

# ── the declare, and every way it can fail ────────────────────────────────────────────

@test "7 a fired cloud session is declared with the id scraped from the fire output" {
  printf 'Created cloud session: session_01H9ZQ.abc-1 on branch feat/x\n' > "$CAP"
  run lib "cloud_declare item1 '$CAP' feat/x"
  [ "$status" -eq 0 ]
  declared | grep -q 'declare --id session_01H9ZQ.abc-1 --branch feat/x'
}

@test "8 NO session id in the fire output is LOUD — undeclared is unobservable AND reapable" {
  printf 'the fire said nothing useful\n' > "$CAP"
  run lib "cloud_declare item1 '$CAP' feat/x"
  [ "$status" -eq 1 ]
  [[ "$output" == *"UNDECLARED"* ]]
  [ -z "$(declared)" ]
}

@test "9 a FAILING cc-cloud declare is LOUD, never swallowed" {
  # The failure that matters most and is easiest to swallow: the session exists, the fire returned
  # 0, and only the observability of it is gone. Silence here would leave a live off-box session
  # that nothing on this box can see, name, or reap.
  printf 'Created cloud session: session_zz9 on branch feat/y\n' > "$CAP"
  # EXPORTED, and on its own statement. `VAR=x . file` is a temporary assignment for the `.`
  # builtin in non-POSIX bash — reverted the instant `.` returns — so the first draft of this case
  # ran against a stub that exited 0 and reported "declared", i.e. it passed the subject a healthy
  # world and graded it on that. The stub reads the value from its ENVIRONMENT, so it must be
  # exported, not merely set.
  run bash -c ". '$LIB'; export STUB_DECL_RC=2; cloud_declare item1 '$CAP' feat/y"
  [ "$status" -eq 1 ]
  [[ "$output" == *"UNDECLARED"* ]]
  [[ "$output" == *"session_zz9"* ]]
}

@test "10 an unnameable branch REFUSES to declare rather than inventing one" {
  printf 'Created cloud session: session_zz9\n' > "$CAP"
  run lib "cloud_declare item1 '$CAP' ''"
  [ "$status" -eq 1 ]
  [[ "$output" == *"UNDECLARED"* ]]
  [ -z "$(declared)" ]
}

@test "11 an UNRESOLVABLE cc-cloud is LOUD too — and cc-cloud itself is never edited from here" {
  printf 'Created cloud session: session_zz9\n' > "$CAP"
  # The genuinely-unresolvable branch, which needs the override EMPTY: with an override set,
  # resolve_bin returns it unconditionally and the failure arrives one branch later (as a failed
  # exec) — a different path that would have graded this case vacuously. cwd is the tmpdir so
  # resolve_bin's last-resort sibling lookup finds nothing either.
  run bash -c "cd '$BATS_TEST_TMPDIR'; export CC_DISPATCH_CLOUD_BIN='' PATH=/usr/bin:/bin HOME='$HOME'; . '$LIB'; cloud_declare i '$CAP' feat/y"
  [ "$status" -eq 1 ]
  [[ "$output" == *"UNDECLARED"* ]]
  [[ "$output" == *"unresolvable"* ]]
}

# ── the claim wiring (structural pin + its mutation control) ──────────────────────────

@test "12 the claim carries --venue cloud, and NEVER a redundant --venue local" {
  # A structural pin, and labelled as one: the claim happens inside the dispatch loop, which needs
  # a whole planner+backlog+spawn fleet to reach. What it pins is the DECISION, which is the part
  # that could silently regress: cloud claims are labelled, local ones are left alone.
  #
  # `--venue local` is deliberately absent. The fold already defaults a claim with no venue to
  # "local" (bin/cc-backlog:615), so passing it explicitly would add a field to every claim in the
  # fleet and carry exactly zero information — while making a real cloud claim harder to find.
  grep -q -- '--venue cloud' "$DISPATCH"
  ! grep -q -- '--venue local' "$DISPATCH"
  # and it is built as an ARRAY, so the flag cannot be word-split or injected
  grep -q 'claim_args' "$DISPATCH"
}

@test "13 MUTATION CONTROL — case 12's pin can fail" {
  # Without this, case 12 could be passing because its greps cannot go red.
  local mutant="$BATS_TEST_TMPDIR/mutant"
  sed 's/--venue cloud/--venue local/' "$DISPATCH" > "$mutant"
  ! grep -q -- '--venue cloud' "$mutant"
  grep -q -- '--venue local' "$mutant"
}
