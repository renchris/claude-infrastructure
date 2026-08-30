#!/usr/bin/env bats
# cc-eligible — THE PARK ARM: a landed park the desk has not yet turned into a `block`.
#
# WHAT IT IS FOR. A cloud VM cannot write the backlog store, so `cc-backlog block <id> --needs "…"`
# answers `unknown id` and writes nothing off-box. `scripts/cloud-park.sh` is the workaround: the VM
# lands `docs/parks/<id>.md` and `scripts/cloud-return.sh` step 8 reads it off the trunk ref and
# calls `block`. That rail has exactly ONE caller — `scripts/autonomy-sweep.sh`, under launchd on
# the operator's box — and backlog `f85fce7c26f5`, the row it was built for, is the row that says
# THAT ARM IS DEAD. Its park landed as `28dab8c4` at 2026-08-29T17:43Z and the wave fired the row
# again 7 h 11 m later. So the park is inert exactly when it is needed, and this arm is the reader
# that is demonstrably alive — the dispatcher had to pass through `claim --venue cloud` to fire at
# all.
#
# WHAT THIS SUITE PINS, which is not "a park is refused" — that would pass against an arm that
# refused everything, and a blanket refusal here kills the cloud tap while looking green:
#
#   · EVERY refusal arm is paired with a control that must stay ELIGIBLE, and the two differ in
#     exactly one fact (the park, its landedness, or the desk record) — never in the item.
#   · TRUNK, NEVER THE WORKING TREE. This gate runs on a live checkout somebody is editing; a park
#     that has not landed must not park. Pinned by committing the file and withholding the ref.
#   · THE RETRACTION RULE BINDS IN BOTH DIRECTIONS. A block/unblock AFTER the park retires the arm
#     (else a landed file is a permanent refusal); one BEFORE it does not (else a row blocked once
#     could never be parked again). `claim` retracts NOTHING — it happens on every dispatch, so an
#     arm that counted it would be retracted by the very fire it exists to prevent.
#   · THE VERDICT LEADS. Refusal order decides the one sentence a `head -1` reader gets, and the
#     park is the only class that says what to RUN rather than "claim it locally".
#   · IT REACHES THE REAL GATE. The last two cases go through `cc-backlog claim --venue cloud`,
#     which is the consumer that actually costs a spawn.
#
# Assertions use the explicit `|| { …; false; }` form: a non-final `[[ ]]` is errexit-EXEMPT under
# bats and would be a DEAD assertion that can never fail.
#
# RED-PROOF, MEASURED rather than asserted (re-runnable: `git archive origin/main | tar -x` into a
# temp dir, drop this file into its tests/, run it there). Pristine trunk has no PARKED verdict and
# no park_assess, and the suite reads **8 red / 5 ok** against it:
#
#   RED   1, 2, 5, 7, 8, 9, 10, 12 — every case whose subject is a refusal that does not exist yet.
#   GREEN 3, 4, 6, 13             — the ELIGIBLE controls, and this is correct: they pin behaviour
#                                   this change had to PRESERVE, and a suite whose controls also
#                                   went red would be crediting itself for the whole file.
#   RED   11                      — the fail-open control, and it is red for the RIGHT half. Its
#                                   `status -eq 0` and `verdict=eligible` assertions PASS on
#                                   pristine; it dies on `park : not-measured`, which is the one
#                                   assertion that distinguishes "the arm ran and abstained" from
#                                   "there is no arm". Without it, fail-open would be pinned by a
#                                   case that passes when the feature is absent.

setup() {
  # Project labels in this suite are FIXTURES, not projects — and `cc-backlog add` WARNS on an
  # explicit --project outside the dispatch set, which bats folds into $output.
  export CC_BACKLOG_PROJECT_WARN=off
  # Fixture $HOME FIRST — the subject resolves BOTH its store (~/.claude/autonomy/backlog.jsonl) and
  # its repo ($HOME/Development/<project>) under it, so an unfixtured HOME would classify the
  # operator's real ledger against the operator's real checkouts.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CE="$REPO/bin/cc-eligible"
  CB="$REPO/bin/cc-backlog"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  # `add` ends in dispatch_kick(), whose bin resolution tries `command -v cc-dispatch` BEFORE $HOME —
  # so a fixtured $HOME does NOT close it, and every `add` below would spawn the operator's DEPLOYED
  # dispatcher against this suite's fixtures. Off, and both seams pinned into the tmpdir as well, so
  # nothing here can reach live state even if the switch is flipped back on.
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/.dispatch-kick"
  export CC_BACKLOG_KICK_BIN="$BATS_TEST_TMPDIR/no-such-dispatch"
  # The claim path's liveness oracle resolves under $HOME; an unresolved one abstains and the
  # end-to-end cases would pass vacuously. An empty-but-valid registry answers "not listed".
  printf '#!/bin/bash\necho "[]"\n' > "$BATS_TEST_TMPDIR/nosess"; chmod +x "$BATS_TEST_TMPDIR/nosess"
  export CC_BACKLOG_SESSIONS_BIN="$BATS_TEST_TMPDIR/nosess"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  G="$HOME/Development/probe"
  # A stamp firmly in the past, so a `block` written by the real verb (which stamps `now`) is
  # unambiguously AFTER it and the retraction cases are not racing the clock.
  OLD_STAMP="2026-08-29T17:40:43Z"
}

# mkrepo → a real git repo at $G with one commit on main and origin/main pointing at it.
mkrepo() {
  mkdir -p "$G"
  # THE ARGUMENT IS ASSERTED, not the chain. `git -C ""` is a documented NO-OP rather than an error,
  # so an empty $G would drop this identity into whatever repo the process is standing in.
  git -C "${G:?repo path required}" init -q -b main
  git -C "${G:?repo path required}" config user.email t@e.com
  git -C "${G:?repo path required}" config user.name t
  echo seed > "$G/f1"; git -C "$G" add f1; git -C "$G" commit -qm c1
  sync_trunk
}

# sync_trunk → point origin/main at main. A REAL remote-tracking ref, because the production path
# reads a clone and a branch merely NAMED "origin/main" would exercise a resolution it never takes.
sync_trunk() { git -C "$G" update-ref refs/remotes/origin/main "$(git -C "$G" rev-parse main)"; }

# add <source> <title> → the item id
add() { "$CB" add --title "$2" --project probe --source "$1"; }

# park <id> <stamp> <needs> → commit a park log. Does NOT advance origin/main: landedness is a
# separate fact and every caller that wants it says so.
park() {
  mkdir -p "$G/docs/parks"
  { printf '# park log — cc-backlog %s\n\n' "$1"
    printf 'APPEND ONLY.\n\n'
    printf '## %s\n\n' "$2"
    printf 'branch: claude/fire-fixture-1\n'
    [ -n "${3:-}" ] && printf 'needs: %s\n' "$3"
    printf '\n'
  } > "$G/docs/parks/$1.md"
  git -C "$G" add docs; git -C "$G" commit -qm "park $1"
}

# verdict <id> → line 1 of a `2>&1` capture, which is what every real caller sees
verdict() { "$CE" check "$1" 2>&1 | head -1; }

# ── the arm, and its control ────────────────────────────────────────────────────────────────────

@test "PARKED: a landed park with no desk record refuses, exit 3, own token" {
  mkrepo
  local id; id="$(add park-live "make the widget green")"
  park "$id" "$OLD_STAMP" "bash scripts/cloud-land-arm-diagnose.sh on the operator Mac"
  sync_trunk
  run "$CE" check "$id"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=ineligible-parked"* ]] || { echo "$output"; false; }
}

@test "PARKED: the refusal NAMES the operator step, verbatim from the park" {
  # The whole value of routing this through the venue gate rather than a spelling: every other
  # refusal in cc-eligible can only say "claim it locally". This one says what to run there, and a
  # reader who has to open a file to find out is a reader who does not.
  mkrepo
  local id; id="$(add park-needs "make the widget green")"
  park "$id" "$OLD_STAMP" "bash scripts/cloud-land-arm-diagnose.sh"
  sync_trunk
  run "$CE" check "$id"
  [[ "$output" == *"bash scripts/cloud-land-arm-diagnose.sh"* ]] \
    || { echo "named the class but not the step: $output"; false; }
}

@test "CONTROL: the SAME item with no park at all stays eligible" {
  # The one assertion that separates "the park arm works" from "the arm refuses everything". Same
  # repo, same title, same store — the park is the only variable.
  mkrepo
  local id; id="$(add park-control "make the widget green")"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=eligible"* ]] || { echo "$output"; false; }
}

@test "TRUNK ONLY: a park committed but NOT on the trunk ref does not park" {
  # cloud-park.sh's own rule — "The park is NOT in effect until this file is on trunk" — and the
  # failure this pins is silent and expensive: this gate runs on a live checkout, so a `[ -f ]`
  # spelling would honour any park a local session happened to have in its tree.
  mkrepo
  # The source label is part of the classified SPAN, so it is chosen to spell nothing: an earlier
  # draft used `park-unlanded` and the BANKING arm fired on `unlanded`, turning a control that must
  # stay eligible into a refusal for a reason with nothing to do with parks.
  local id; id="$(add pk-notrunk "make the widget green")"
  park "$id" "$OLD_STAMP" "run the diagnose"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=eligible"* ]] || { echo "$output"; false; }
}

# ── the retraction rule, in both directions ─────────────────────────────────────────────────────

@test "RETRACTS: a block recorded AFTER the park retires the arm" {
  # Without this the landed file is a permanent refusal — the exact defect cloud-park.sh's `branch:`
  # field exists to prevent on the return side, which this gate cannot use because at claim time
  # there is no branch yet.
  mkrepo
  local id; id="$(add park-retract "make the widget green")"
  park "$id" "$OLD_STAMP" "run the diagnose"
  sync_trunk
  run "$CE" check "$id"
  [ "$status" -eq 3 ] || { echo "not refused before the block: $output"; false; }
  run "$CB" block "$id" --needs "run the diagnose"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "still refused after the desk acted: $output"; false; }
  [[ "$output" == *"verdict=eligible"* ]] || { echo "$output"; false; }
}

@test "RETRACTS: an unblock retires it too — the operator may decide it is moot" {
  mkrepo
  local id; id="$(add park-unblock "make the widget green")"
  park "$id" "$OLD_STAMP" "run the diagnose"
  sync_trunk
  run "$CB" unblock "$id"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "DOES NOT RETRACT: a block recorded BEFORE the park leaves the refusal standing" {
  # The ordering is load-bearing in the other direction: a row that was blocked once and later
  # unblocked and re-dispatched can be parked AGAIN, and an arm keyed on "has a block ever" would
  # be permanently deaf to every park after the first.
  mkrepo
  local id; id="$(add park-order "make the widget green")"
  run "$CB" block "$id" --needs "an older, unrelated step"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # The park's stamp is in the FUTURE relative to that block, which is the real shape: the desk
  # acted, the row came back, and a later dispatch parked it again.
  park "$id" "2099-01-01T00:00:00Z" "the newer step"
  sync_trunk
  run "$CE" check "$id"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=ineligible-parked"* ]] || { echo "$output"; false; }
  [[ "$output" == *"the newer step"* ]] || { echo "read an older entry's step: $output"; false; }
}

@test "A CLAIM RETRACTS NOTHING — it is the event the park exists to prevent" {
  # `claim` is written on every dispatch, so an arm that counted it as the desk acting would be
  # retracted by the very fire the park is trying to stop. Closed event set, asserted.
  mkrepo
  local id; id="$(add park-claim "make the widget green")"
  park "$id" "$OLD_STAMP" "run the diagnose"
  sync_trunk
  run "$CB" claim "$id" --by "localbox-1" --venue local
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run "$CE" check "$id"
  [ "$status" -eq 3 ] || { echo "a local claim retracted the park: $output"; false; }
}

# ── the malformed park, and the ordering ────────────────────────────────────────────────────────

@test "MALFORMED: a park with no needs line refuses under its own description" {
  # cloud-return refuses to settle such a row for the same reason: the worker said "this is not
  # finished" and the only readable half of the statement is the half that says so. Falling through
  # to eligible here would re-open the loop for exactly the case where the statement was garbled.
  mkrepo
  local id; id="$(add park-malformed "make the widget green")"
  park "$id" "$OLD_STAMP" ""
  sync_trunk
  run "$CE" check "$id"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=ineligible-parked"* ]] || { echo "$output"; false; }
  [[ "$output" == *"no readable step"* ]] \
    || { echo "malformed reported as an ordinary park: $output"; false; }
}

@test "ORDER: the park verdict LEADS a spelling class, and why reports both" {
  # Refusal order decides the single token a `head -1` consumer gets. Both classes refuse, so
  # nothing about safety turns on this — what turns on it is whether the reader is told to go find
  # a keychain or told the command to run.
  mkrepo
  local id; id="$(add park-order2 "restart the launchd daemon and re-read its plist")"
  park "$id" "$OLD_STAMP" "run the diagnose"
  sync_trunk
  run bash -c '"$1" check "$2" 2>&1 | head -1' _ "$CE" "$id"
  [[ "$output" == *"verdict=ineligible-parked"* ]] || { echo "$output"; false; }
  run "$CE" why "$id"
  [[ "$output" == *"ineligible-parked"* ]] || { echo "$output"; false; }
  [[ "$output" == *"ineligible-box"* ]] \
    || { echo "the park masked the spelling class in why: $output"; false; }
}

@test "FAILS OPEN: no repo for the project means the arm is silent, not refusing" {
  # This file's founding rule — a claim must never be starved by an instrument outage. There is no
  # $HOME/Development/probe here at all, so the oracle cannot certify and the arm must say nothing.
  local id; id="$(add park-norepo "make the widget green")"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=eligible"* ]] || { echo "$output"; false; }
  run "$CE" why "$id"
  [[ "$output" == *"park    : not-measured"* ]] || { echo "$output"; false; }
}

# ── the consumer that actually costs a spawn ────────────────────────────────────────────────────

@test "THE REAL GATE: claim --venue cloud is refused over a landed park" {
  # cc-eligible is only worth changing if the refusal reaches the claim. This is the path
  # cc-dispatch takes, and rc 4 with the cloud token is what makes the fire a SKIP with zero spawn.
  mkrepo
  local id; id="$(add park-claimgate "make the widget green")"
  park "$id" "$OLD_STAMP" "bash scripts/cloud-land-arm-diagnose.sh"
  sync_trunk
  run "$CB" claim "$id" --by "cloudvm-1" --venue cloud
  [ "$status" -eq 4 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=cloud-ineligible"* ]] || { echo "$output"; false; }
  [[ "$output" == *"ineligible-parked"* ]] \
    || { echo "the class did not ride the claim body: $output"; false; }
  # …and it appended NOTHING: a refused claim must leave the item claimable.
  run "$CB" list --json
  [[ "$output" != *'"status":"claimed"'* ]] || { echo "$output"; false; }
}

@test "CONTROL: that SAME parked item still claims fine with --venue local" {
  # The park says the next step is the OPERATOR's, and the operator is this box — so local is
  # exactly where the row must stay claimable. A gate that broke this would have converted a
  # re-dispatch loop into a stranded row, which is a worse trade than the one it was fixing.
  mkrepo
  local id; id="$(add park-claimlocal "make the widget green")"
  park "$id" "$OLD_STAMP" "bash scripts/cloud-land-arm-diagnose.sh"
  sync_trunk
  run "$CB" claim "$id" --by "localbox-2" --venue local
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"cloud-ineligible"* ]] || { echo "$output"; false; }
}
