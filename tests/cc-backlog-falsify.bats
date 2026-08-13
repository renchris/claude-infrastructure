#!/usr/bin/env bats
# cc-backlog `falsify <id> --probe` — attaching a re-run check to an item that ALREADY EXISTS.
#
# THE DEFECT THIS VERB CLOSES. `add --falsifier` can only ever attach a probe to a row it is
# CREATING: cmd_add resolves the id, hits `has_id`, and returns rc 0 with the id BEFORE it writes
# anything (the idempotency contract cc-discover depends on). So `add --falsifier` aimed at an
# existing row is a silent, successful no-op — which is why a7bf7068 could teach the four generators
# to emit probes going forward and still leave the ~450 rows already in the store permanently
# uncoverable. Measured on the live ledger 2026-08-11 before this verb: 461 open, 6 with a probe.
#
# THE CONTROL IS THE FIRST TEST, and it is not decoration: it replays the REAL pre-fix artifact
# (`add --falsifier` on a known id) and asserts it still stores nothing. Without it, a `falsify`
# that silently delegated to `add` would pass every other assertion in this file
# (memory: control-must-replay-the-real-artifact).
#
# THE EXIT-0 SCREEN is asserted in BOTH directions — refused without --force, stored with it — for
# the reason the guard exists at all: exit 0 is the RETRACTING direction, so a screen that could only
# ever accept, or could only ever refuse, would be indistinguishable from no screen
# (memory: guard-proxy-fails-in-both-directions).

setup() {
  # Project labels in this suite are FIXTURES, not projects — and `cc-backlog add` now WARNS on an
  # explicit --project outside the dispatch set (df2b6a40a5dc), which bats folds into $output. Off
  # here because dispatchability is not this suite's subject; tests/cc-backlog-project-dispatch.bats
  # owns it, unfixtured, in both directions.
  export CC_BACKLOG_PROJECT_WARN=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CB="$REPO/bin/cc-backlog"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/dispatch-kick"
  # The screen runs the probe with cwd = the git toplevel, which under bats is this repo. Every
  # probe below is therefore written against $BATS_TEST_TMPDIR by ABSOLUTE path, so no assertion
  # here is a function of the repo's own working tree.
  MISSING="$BATS_TEST_TMPDIR/not-there"
  PRESENT="$BATS_TEST_TMPDIR/present"; : > "$PRESENT"
  ID=$(bash "$CB" add --project P --title "a live defect" --source s1)
}

fals_of() { bash "$CB" list --all --json | jq -r --arg i "$1" '.[]|select(.id==$i)|.falsifier // ""'; }
status_of() { bash "$CB" list --all --json | jq -r --arg i "$1" '.[]|select(.id==$i)|.status'; }

# ── THE CONTROL: the pre-fix path, replayed ──────────────────────────────────────────────────────

@test "CONTROL — add --falsifier on an EXISTING id stores nothing and still exits 0" {
  run bash "$CB" add --project P --title "a live defect" --source s1 --falsifier "test -e $MISSING"
  [ "$status" -eq 0 ]
  [ "$output" = "$ID" ]                      # same id: the event key resolved, as designed
  [ "$(fals_of "$ID")" = "" ]                # …and the probe went nowhere. This is the whole defect.
}

# ── the write path ───────────────────────────────────────────────────────────────────────────────

@test "falsify attaches a probe to an existing row" {
  run bash "$CB" falsify "$ID" --probe "test -e $MISSING"
  [ "$status" -eq 0 ]
  [ "$(fals_of "$ID")" = "test -e $MISSING" ]
}

@test "falsify does NOT disturb status — the fold carries it through" {
  bash "$CB" block "$ID" --needs "an operator step"
  [ "$(status_of "$ID")" = "blocked" ]
  bash "$CB" falsify "$ID" --probe "test -e $MISSING"
  # The new event must land in every fold's CARRY-FORWARD arm, never in a status branch: a member
  # that lands in someone's `*)` arm is the recurring defect this record shape was chosen to avoid.
  [ "$(status_of "$ID")" = "blocked" ]
}

@test "last write wins — re-falsifying CORRECTS the probe rather than appending history" {
  bash "$CB" falsify "$ID" --probe "test -e $MISSING"
  bash "$CB" falsify "$ID" --probe "test -d $MISSING"
  [ "$(fals_of "$ID")" = "test -d $MISSING" ]
}

@test "the stored probe is what cc-premise reads — the raw record carries the field" {
  bash "$CB" falsify "$ID" --probe "test -e $MISSING"
  # cc-premise folds `if r.get(falsifier)` over RAW records, not over list --json. Assert the raw
  # line too, so a regression that satisfied only the projection cannot pass.
  n=$(jq -rs --arg i "$ID" '[.[]|select(.id==$i and (.falsifier//"")!="")]|length' "$CC_BACKLOG_FILE")
  [ "$n" -eq 1 ]
}

# ── THE EXIT-0 SCREEN, both directions ───────────────────────────────────────────────────────────

@test "a probe that exits 0 RIGHT NOW is REFUSED and stores nothing" {
  run bash "$CB" falsify "$ID" --probe "test -e $PRESENT"
  [ "$status" -eq 5 ]
  [ "$(fals_of "$ID")" = "" ]
  printf '%s' "$output" | grep -q "REFUSED"
  # The refusal must name the CLOSE, not just complain: an item whose probe already passes is
  # finished work, and `done --evidence` is the write that says so.
  printf '%s' "$output" | grep -q "cc-backlog done $ID"
}

@test "--force stores an exit-0 probe deliberately" {
  run bash "$CB" falsify "$ID" --probe "test -e $PRESENT" --force
  [ "$status" -eq 0 ]
  [ "$(fals_of "$ID")" = "test -e $PRESENT" ]
}

@test "--no-run stores without screening" {
  run bash "$CB" falsify "$ID" --probe "test -e $PRESENT" --no-run
  [ "$status" -eq 0 ]
  [ "$(fals_of "$ID")" = "test -e $PRESENT" ]
}

# ── --clear, and the reason it cannot be an omitted key ──────────────────────────────────────────
#
# A probe can be wrong with NO correct replacement available: `eef88daa030a`'s item is "the deploy
# converger refuses every land, no green tree descends from live HEAD", its probe asked only whether
# one commit had reached the checkout, and the mechanism-true alternative (`deploy-live --dry-run`)
# has two success states. So the honest end state is NO probe, and something has to be able to
# express that.

@test "--clear retires a stored probe" {
  bash "$CB" falsify "$ID" --probe "test -e $MISSING"
  run bash "$CB" falsify "$ID" --clear
  [ "$status" -eq 0 ]
  [ "$(fals_of "$ID")" = "" ]
  printf '%s' "$output" | grep -q "CLEARED"
  # The refusal message must SAY what it deleted — a clear with no record of the old probe makes an
  # accidental clear unrecoverable from the operator's screen.
  printf '%s' "$output" | grep -q "test -e $MISSING"
}

@test "BOTH readers agree the probe is gone — not just list --json" {
  bash "$CB" falsify "$ID" --probe "test -e $MISSING"
  bash "$CB" falsify "$ID" --clear
  # This is the assertion the whole flag turns on. cc-backlog's fold clears on "" because jq's `//`
  # treats only null and false as falsy; cc-premise folded on TRUTHINESS and so would have SKIPPED
  # the clearing record and gone on running the deleted probe — invisibly, since `list --json` shows
  # none. A divergence in exactly that direction is the worst available outcome.
  [ "$(fals_of "$ID")" = "" ]
  # Asked through cc-premise ITSELF rather than by re-implementing its fold here: a second copy of
  # the rule is exactly how the two readers drifted apart in the first place.
  out=$(CC_BACKLOG_FILE="$CC_BACKLOG_FILE" python3 "$REPO/bin/cc-premise" check "$ID" 2>&1)
  [ "$(printf '%s' "$out" | grep -c 'FALSIFIER PASSED')" -eq 0 ]
  [ "$(printf '%s' "$out" | grep -c 'Falsifier re-run just now')" -eq 0 ]
}

@test "--clear on an item with no probe is a no-op that still succeeds" {
  run bash "$CB" falsify "$ID" --clear
  [ "$status" -eq 0 ]
  [ "$(fals_of "$ID")" = "" ]
}

@test "--clear and --probe together are refused" {
  run bash "$CB" falsify "$ID" --clear --probe "test -e $MISSING"
  [ "$status" -eq 2 ]
  [ "$(fals_of "$ID")" = "" ]
}

# ── refusals ─────────────────────────────────────────────────────────────────────────────────────

@test "unknown id is refused (rc 3), not silently created" {
  run bash "$CB" falsify deadbeef0000 --probe "test -e $MISSING"
  [ "$status" -eq 3 ]
  [ "$(bash "$CB" list --all --json | jq 'length')" -eq 1 ]
}

@test "a DONE item is refused (rc 4) — a probe there can never fire" {
  # `done` quoted: unquoted it reads as the shell keyword to shellcheck (SC1010), not as this
  # tool's verb — the parser has no idea "$CB" takes a subcommand.
  bash "$CB" "done" "$ID" --evidence "landed as abc123"
  run bash "$CB" falsify "$ID" --probe "test -e $MISSING"
  [ "$status" -eq 4 ]
  [ "$(fals_of "$ID")" = "" ]
  # …and the refusal must not have moved the item. This used to be justified by cc-value folding
  # `status: $r.event` over raw records, so a falsify record after a done made a closed item read
  # as un-closed; that fold was fixed 2026-08-13 and carries status through now. The assertion
  # stays, on the stronger and reader-independent reason: a REFUSED operation appends nothing, so
  # there is no record here for any fold to see.
  [ "$(status_of "$ID")" = "done" ]
}

@test "a missing --probe is a usage error that explains the one-success-state rule" {
  run bash "$CB" falsify "$ID"
  [ "$status" -eq 2 ]
  printf '%s' "$output" | grep -q "ONE success state"
  [ "$(fals_of "$ID")" = "" ]
}

@test "an unknown argument is refused rather than absorbed" {
  run bash "$CB" falsify "$ID" --probe "test -e $MISSING" --wat
  [ "$status" -eq 2 ]
  [ "$(fals_of "$ID")" = "" ]
}

# ── the bound ────────────────────────────────────────────────────────────────────────────────────

# ── the claim-time refusal must say WHICH signal refuted it ──────────────────────────────────────
#
# cc-dispatch's IDL row is built from `claim_excerpt` — head -1, 200 chars — so a discriminator that
# is not on line 1 does not exist to any reader of the ledger. Before `signal=`, all 74 refusal rows
# read identically and "was any of these a re-run?" could only be answered by re-running cc-premise
# by hand. BOTH directions are asserted: a probe-driven refusal and a prose-driven one must produce
# DIFFERENT tokens, or the field carries no bits (memory: guard-proxy-fails-in-both-directions).

@test "a claim refused by a RE-RUN records signal=falsified on line 1" {
  bash "$CB" falsify "$ID" --probe "test -e $PRESENT" --force   # exits 0 ⇒ the probe retracts
  run bash "$CB" claim "$ID" --by sess-x
  [ "$status" -eq 4 ]
  printf '%s' "$output" | head -1 | grep -q "verdict=premise-refuted signal=falsified"
}

@test "a claim refused by filing-time PROSE records a different signal" {
  # An item whose own TITLE declares it redundant — the OLD declared-obsolescence path, no probe.
  # cc-premise's self-duplicate arm reads the item's own words, which is precisely the filing-time
  # prose this token has to be distinguishable from.
  dup=$(bash "$CB" add --project P --source s2 --title "DUPLICATE of $ID — that item is canonical")
  run bash "$CB" claim "$dup" --by sess-x
  [ "$status" -eq 4 ]
  line1="$(printf '%s' "$output" | head -1)"
  printf '%s' "$line1" | grep -q "verdict=premise-refuted signal="
  # The whole point: NOT falsified. A prose declaration is not a measurement.
  [ "$(printf '%s' "$line1" | grep -c 'signal=falsified')" -eq 0 ]
}

@test "a probe that outruns the bound is STORED with a warning, never refused" {
  # "I could not ask" must never read as "the answer was no" — the same fail-open run_falsifier
  # applies at claim time. rc 124 is the bound expiring, which is not a verdict.
  CC_PREMISE_FALSIFIER_TIMEOUT=1 run bash "$CB" falsify "$ID" --probe "sleep 5"
  [ "$status" -eq 0 ]
  [ "$(fals_of "$ID")" = "sleep 5" ]
  printf '%s' "$output" | grep -q "WARNING"
}
