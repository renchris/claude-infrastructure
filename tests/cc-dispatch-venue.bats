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
# Case 13 is the mutation control proving the structural pin in case 12 can fail.
#
# RED-PROOF (MEASURED 2026-08-08, re-runnable): replayed against `git show origin/main:bin/cc-dispatch`
# in a scratch tree with this file copied in unchanged — 13 of 13 RED, because the sed extractions
# in setup() find none of fire_venue / fire_branch / cloud_declare there and every case runs
# against an empty library. That is a weaker red than the sibling suite's (it proves the helpers
# are new, not that each assertion binds); what proves the assertions bind is case 13's mutation
# control plus the analyzer pass — `scripts/bats-assert-liveness.py` reports 0 dead assertions for
# this file, after it caught 6 of them here that were being evaluated and silently discarded.

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
# code_of <file> — $CODE is <file> with whole-line comments removed, so a structural scan cannot
# match the subject's own documentation. Written to a FILE rather than piped, so no case depends
# on whether pipefail happens to be set (memory: pipefail-inverts-early-exit-probe).
code_of() { CODE="$BATS_TEST_TMPDIR/code.txt"; grep -v '^[[:space:]]*#' "$1" > "$CODE"; }

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
  [[ "$output" == *"UNDECLARED"* ]] || false
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
  [[ "$output" == *"UNDECLARED"* ]] || false
  [[ "$output" == *"session_zz9"* ]]
}

@test "10 an unnameable branch REFUSES to declare rather than inventing one" {
  printf 'Created cloud session: session_zz9\n' > "$CAP"
  run lib "cloud_declare item1 '$CAP' ''"
  [ "$status" -eq 1 ]
  [[ "$output" == *"UNDECLARED"* ]] || false
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
  [[ "$output" == *"UNDECLARED"* ]] || false
  [[ "$output" == *"unresolvable"* ]]
}

# ── the claim wiring (structural pin + its mutation control) ──────────────────────────

@test "12 the claim carries --venue cloud, and NEVER a redundant --venue local" {
  # A structural pin, and labelled as one: the claim happens inside the dispatch loop, which needs
  # a whole planner+backlog+spawn fleet to reach. What it pins is the DECISION, which is the part
  # that could silently regress: cloud claims are labelled, local ones are left alone.
  #
  # The absent half is `--venue local`. The fold already defaults a claim with no venue to the
  # local one (bin/cc-backlog:615), so passing it explicitly would add a field to every claim in
  # the fleet, carry exactly zero information, and make a real cloud claim harder to find.
  #
  # COMMENTS ARE STRIPPED FIRST, and the first draft of this case is why: the dispatcher's own
  # comment EXPLAINS why the local label is omitted, so a scan of the raw file matched its own
  # documentation and convicted a correct tree. Same failure the sibling capacity-gate lint records
  # against itself ("this function's own prose says `return 0`") — a scan whose subject is code
  # must not read prose.
  code_of "$DISPATCH"
  grep -q -- '--venue cloud' "$CODE"
  ! grep -q -- '--venue local' "$CODE" || false
  # and it is built as an ARRAY, so the flag cannot be word-split or injected
  grep -q 'claim_args' "$CODE"
}

@test "13 MUTATION CONTROL — case 12's pin can fail" {
  # Without this, case 12 could be passing because its greps cannot go red.
  code_of "$DISPATCH"
  local mutant="$BATS_TEST_TMPDIR/mutant"
  sed 's/--venue cloud/--venue local/' "$CODE" > "$mutant"
  ! grep -q -- '--venue cloud' "$mutant" || false
  grep -q -- '--venue local' "$mutant"
}

# ── G5-P: THE PRODUCER'S DECISION REACHES THE ARGV (W1, 2026-08-11) ────────────────────────────
#
# Cases 1-13 above proved the venue is read off the fire's own argv. That was true and inert: no
# caller ever put `--cloud` into an argv, which is the "ZERO PRODUCERS" the dispatcher documents
# about itself. bin/cc-venue now writes `venuePlan` onto open rows, and these cases pin the seam
# where the plan becomes an argument — including the two ways that seam could be wrong in a way
# nothing downstream would notice.

@test "14 the plan MUTATES THE ARGV rather than setting the venue directly" {
  # The load-bearing property of the whole G5 design: `fire_venue` reads the array that will
  # ACTUALLY RUN. If the seam assigned `venue=cloud` itself, the label would be derived from the
  # PLAN instead of from the fire, and a plan that failed to become an argument would produce a
  # claim asserting a venue nothing was launched into — the mislabel-that-reads-as-a-verdict this
  # suite exists to prevent. So: the injection appends to fire_args, and `venue` is still assigned
  # from fire_venue AFTER it.
  code_of "$DISPATCH"
  grep -q 'fire_args+=(--cloud)' "$CODE" \
    || { echo "the plan never reaches the argv"; false; }
  grep -q 'venue="$(fire_venue "${fire_args\[@\]}")"' "$CODE" \
    || { echo "the venue is no longer derived from the argv that will run"; false; }
  # …and the ORDER holds: the injection is above the read, else it lands too late to be seen.
  local inj rd
  inj="$(grep -n 'fire_args+=(--cloud)' "$CODE" | head -1 | cut -d: -f1)"
  rd="$(grep -n 'venue="$(fire_venue' "$CODE" | head -1 | cut -d: -f1)"
  [ "$inj" -lt "$rd" ] || { echo "injection at $inj is AFTER the read at $rd"; false; }
}

@test "15 the duplicate check is fire_venue itself, never a substring test over the argv" {
  # `--venue` is a closed set at the actuator precisely so a loose match cannot hand it a
  # well-formed string derived from the wrong fire (case 3). A `case " ${fire_args[*]} " in
  # *" --cloud "*)` guard here would re-introduce exactly that substring matching one line above
  # the function that refuses it.
  code_of "$DISPATCH"
  ! grep -q 'fire_args\[\*\]' "$CODE" \
    || { echo "an argv SUBSTRING test appeared beside the element-exact reader"; false; }
  grep -q '\[ "$(fire_venue "${fire_args\[@\]}")" = cloud \] || fire_args+=(--cloud)' "$CODE" \
    || { echo "the duplicate check must reuse the one element-exact reader"; false; }
}

@test "16 the BOX OPT-IN outranks the plan, and an unhonoured plan is journalled" {
  # handoff-fire ships --cloud default-off and exits 2 unless CC_FIRE_CLOUD=on, because an off-box
  # fire spends an ACCOUNT's rate limit rather than this box's cores. Injecting regardless would
  # turn every cloud-labelled item on a box without the opt-in into a FIRE FAILURE — a producer
  # that strands exactly the work it routed. The item must fire locally instead, and the IDL must
  # say so: a plan silently dropped is indistinguishable from a plan never made.
  code_of "$DISPATCH"
  grep -q 'CC_FIRE_CLOUD:-off' "$CODE" \
    || { echo "the seam does not consult the same opt-in the actuator enforces"; false; }
  grep -q 'PLANNED but not honoured' "$CODE" \
    || { echo "an unhonoured plan leaves no record"; false; }
}

@test "17 MUTATION CONTROL — cases 14-16 can fail" {
  # Without this they could all be passing because their greps cannot go red.
  code_of "$DISPATCH"
  local mutant="$BATS_TEST_TMPDIR/mutant-p"
  sed -e 's/fire_args+=(--cloud)/fire_args+=(--local)/' \
      -e 's/CC_FIRE_CLOUD:-off/CC_FIRE_ALWAYS:-on/' "$CODE" > "$mutant"
  ! grep -q 'fire_args+=(--cloud)' "$mutant" || false
  ! grep -q 'CC_FIRE_CLOUD:-off' "$mutant" || false
}
