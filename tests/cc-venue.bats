#!/usr/bin/env bats
# cc-venue — the PRODUCER. What decides that an item runs off-box.
#
# WHAT THIS SUITE IS ACTUALLY GUARDING, and it is not "the routing is correct" — correctness of a
# routing decision is not a property a test can hold, because the spelling list it rests on is a
# list of observed spellings and never the class. The properties worth pinning are the ones whose
# failure is SILENT and EXPENSIVE, i.e. the ones that produce a cloud label that should not exist:
#
#   · THE PRODUCER FAILS CLOSED WHERE THE GATE FAILS OPEN. cc-eligible exits 0 on every state it
#     cannot read, on purpose. If this file inherited that, an unreadable ledger or an unmeasurable
#     horizon would route work to a VM on the strength of having failed to look. Each uncertified
#     state gets its own case, and each is paired with the certified control that must still route
#     cloud — otherwise "it refused" is indistinguishable from "it refuses everything".
#   · THE GUARD IS KEYED ON THE EFFECT. A shallow measuring clone cannot certify reach, so it
#     cannot mint a cloud label — which is what makes "a cloud VM must never decide its own
#     admission" mechanical rather than remembered. Pinned by running the SAME item against a full
#     clone and a shallow one and requiring the LABEL to differ.
#   · IT WRITES THROUGH `cc-backlog venue` AND NOWHERE ELSE, so the closed set, the done-refusal and
#     the idempotence have exactly one implementation (memory: make-the-actuator-the-arbiter).
#   · DRY BY DEFAULT. A `run` with no --apply must leave the ledger byte-identical.
#
# Assertions use the explicit `|| { …; false; }` form: a non-final `[[ ]]` is errexit-EXEMPT under
# bats and would be a DEAD assertion that can never fail.
#
# RED-PROOF (re-runnable): bin/cc-venue does not exist on origin/main, so every case here fails
# with "no such file" against it.

setup() {
  # Project labels in this suite are FIXTURES, not projects — and `cc-backlog add` now WARNS on an
  # explicit --project outside the dispatch set (df2b6a40a5dc), which bats folds into $output. Off
  # here because dispatchability is not this suite's subject; tests/cc-backlog-project-dispatch.bats
  # owns it, unfixtured, in both directions.
  export CC_BACKLOG_PROJECT_WARN=off
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CV="$REPO/bin/cc-venue"
  CB="$REPO/bin/cc-backlog"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_DISPATCH_BIN="$BATS_TEST_TMPDIR/absent-dispatch"
  export CC_BACKLOG_ELIGIBLE_GATE=off      # this suite drives the PRODUCER, not the claim gate
  export CC_ELIGIBLE_HISTORY_DEPTH=3
  # Pinned because the test-hermeticity ratchet flags any suite whose TEXT names handoff-fire,
  # and this one does — inside a FIXTURE TITLE, as the specification of an item the classifier
  # must refuse. Nothing here fires anything. The pin is a no-op for this suite and it is the
  # sanctioned fix, so it is taken rather than argued with; the detector reading a quoted
  # string as an invocation is filed separately.
  export CC_FIRE_CAPACITY_GATE=off
  # cc-premise executes stored falsifier probes and reads a repo of its own; question 3 has its own
  # cases below, driven by a stub. Off by default so the other cases pin one thing each.
  export CC_VENUE_PREMISE=off
  G="$HOME/Development/probe"
}

mkrepo() {
  mkdir -p "$G"
  git -C "${G:?repo path required}" init -q -b main
  # THE ARGUMENT IS ASSERTED, not the chain. `git -C ""` is a documented NO-OP rather than an
  # error, so an empty $G would drop this identity into whatever repo the process is standing in —
  # and ~100 linked worktrees here share ONE .git/config, so a single such line re-authors every
  # session on the box. A `&&`/`||` guard does not rescue it either: `cd ""` exits 0.
  git -C "${G:?repo path required}" config user.email t@e.com
  git -C "${G:?repo path required}" config user.name t
  local i
  for i in 1 2 3 4 5 6; do
    echo "$i" > "$G/f$i"; git -C "$G" add "f$i"; git -C "$G" commit -qm "c$i"
  done
  git -C "$G" update-ref refs/remotes/origin/main "$(git -C "$G" rev-parse main)"
  OLD="$(git -C "$G" rev-list main | tail -1)"
}

add() { "$CB" add --title "$1" --project probe --source "${2:-s}"; }
plan_of() { "$CB" list --all --json | jq -r --arg i "$1" 'map(select(.id==$i))|first|.venuePlan // "«absent»"'; }
why_of()  { "$CB" list --all --json | jq -r --arg i "$1" 'map(select(.id==$i))|first|.venueWhy  // "«absent»"'; }
venue_of() { "$CV" assess "$1" --json | jq -r .venue; }

# ── the decision, in both directions ────────────────────────────────────────────────────────────

@test "1 repo-only work under a certified horizon routes CLOUD, and says why" {
  mkrepo
  local id; id="$(add "add a bats case for the tsv-pad helper")"
  run "$CV" assess "$id" --json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  echo "$output" | jq -e '.venue == "cloud"' >/dev/null || { echo "$output"; false; }
  echo "$output" | jq -e '.why | test("^eligible: ")' >/dev/null || { echo "$output"; false; }
  echo "$output" | jq -e '.history.state == "ok"' >/dev/null || { echo "$output"; false; }
}

@test "2 named box state routes LOCAL under the class that fired" {
  mkrepo
  local id; id="$(add "restart the launchd daemon and reload its plist")"
  "$CV" assess "$id" --json | jq -e '.venue == "local"' >/dev/null || false
  "$CV" assess "$id" --json | jq -e '.why | test("^ineligible-box: ")' >/dev/null \
    || { "$CV" assess "$id"; false; }
}

@test "3 a cited sha the shallow clone cannot reach routes LOCAL, with the sha in the why" {
  mkrepo
  local id; id="$(add "regression from ${OLD:0:8} — re-derive the fix")"
  "$CV" assess "$id" --json | jq -e '.why | test("^ineligible-deep-history: ")' >/dev/null \
    || { "$CV" assess "$id"; false; }
  "$CV" assess "$id" --json | jq -e --arg s "${OLD:0:8}" '.why | test($s)' >/dev/null \
    || { "$CV" assess "$id"; false; }
}

@test "4 the off-box lane routes LOCAL — a session this lane made cannot verify a change to it" {
  mkrepo
  local id; id="$(add "off-box payload pushes to an invented branch name — call the cc-cloud preflight")"
  "$CV" assess "$id" --json | jq -e '.why | test("^ineligible-offbox-lane: ")' >/dev/null \
    || { "$CV" assess "$id"; false; }
}

@test "5 the why names EVERY class that fired, not only the one the gate will report" {
  mkrepo
  local id; id="$(add "the off-box lane needs a launchd plist for its sweep")"
  "$CV" assess "$id" --json | jq -e '.why | test("also ineligible-box")' >/dev/null \
    || { "$CV" assess "$id"; false; }
}

# ── FAIL CLOSED: every uncertified state, each against a certified control ──────────────────────

@test "6 THE GUARD: a shallow measuring clone cannot mint a cloud label" {
  mkrepo
  git clone -q --bare "$G" "$BATS_TEST_TMPDIR/origin"
  local id; id="$(add "add a bats case for the tsv-pad helper")"
  [ "$(venue_of "$id")" = cloud ] \
    || { echo "the full-clone control must route cloud, else this case proves nothing"; false; }

  rm -rf "$G"
  git clone -q --depth 2 "file://$BATS_TEST_TMPDIR/origin" "$G"
  [ "$(git -C "$G" rev-parse --is-shallow-repository)" = true ] \
    || skip "clone --depth did not produce a shallow repo here"
  [ "$(venue_of "$id")" = local ] \
    || { echo "a clone that cannot certify reach must not promote"; "$CV" assess "$id"; false; }
  "$CV" assess "$id" --json | jq -e '.why | test("^uncertified-history: shallow")' >/dev/null \
    || { "$CV" assess "$id"; false; }
}

@test "7 no repo for the project ⇒ LOCAL, named — the gate exits 0 on the same state" {
  local id; id="$(add "add a bats case for the tsv-pad helper")"
  [ "$(venue_of "$id")" = local ] || { "$CV" assess "$id"; false; }
  "$CV" assess "$id" --json | jq -e '.why | test("^uncertified-history: no-repo")' >/dev/null \
    || { "$CV" assess "$id"; false; }
  # THE CONTROL that makes this a statement about the PRODUCER: the shared gate, given the very
  # same item, exits 0. The two directions are deliberate and both are load-bearing.
  run "$REPO/bin/cc-eligible" check "$id"
  [ "$status" -eq 0 ] || { echo "the gate must stay fail-open here: $output"; false; }
}

@test "8 a non-clear premise routes LOCAL under premise-<verdict>" {
  mkrepo
  local stub="$BATS_TEST_TMPDIR/premise-stub"
  cat > "$stub" <<'EOF'
#!/bin/bash
echo "verdict=suspect"
exit 0
EOF
  chmod +x "$stub"
  local id; id="$(add "add a bats case for the tsv-pad helper")"
  CC_VENUE_PREMISE=on CC_VENUE_PREMISE_BIN="$stub" run "$CV" assess "$id" --json
  echo "$output" | jq -e '.venue == "local"' >/dev/null || { echo "$output"; false; }
  echo "$output" | jq -e '.why | test("^premise-suspect: ")' >/dev/null || { echo "$output"; false; }
}

@test "9 CONTROL: the same stub saying clear routes CLOUD — the arm is live, not inert" {
  mkrepo
  local stub="$BATS_TEST_TMPDIR/premise-clear"
  cat > "$stub" <<'EOF'
#!/bin/bash
echo "verdict=clear"
exit 0
EOF
  chmod +x "$stub"
  local id; id="$(add "add a bats case for the tsv-pad helper")"
  CC_VENUE_PREMISE=on CC_VENUE_PREMISE_BIN="$stub" run "$CV" assess "$id" --json
  echo "$output" | jq -e '.venue == "cloud"' >/dev/null || { echo "$output"; false; }
}

@test "10 an UNREADABLE premise is an uncertainty, not a green light" {
  mkrepo
  local id; id="$(add "add a bats case for the tsv-pad helper")"
  CC_VENUE_PREMISE=on CC_VENUE_PREMISE_BIN="$BATS_TEST_TMPDIR/absent-premise" run "$CV" assess "$id" --json
  echo "$output" | jq -e '.venue == "local"' >/dev/null || { echo "$output"; false; }
  echo "$output" | jq -e '.why | test("^premise-unreadable")' >/dev/null || { echo "$output"; false; }
}

@test "11 an unreadable LEDGER refuses to route at all — it does not inherit the gate's exit 0" {
  mkrepo
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/nodir/backlog.jsonl"
  mkdir -p "$BATS_TEST_TMPDIR/nodir"; : > "$CC_BACKLOG_FILE"; chmod 000 "$CC_BACKLOG_FILE"
  run "$CV" assess someid --json
  chmod 644 "$CC_BACKLOG_FILE"
  [ "$status" -eq 3 ] \
    || { echo "exit 0 from a producer reads as 'considered everything, routed nothing': $output"; false; }
}

# ── the write path ─────────────────────────────────────────────────────────────────────────────

@test "12 DRY BY DEFAULT: run without --apply leaves the ledger byte-identical" {
  mkrepo
  add "add a bats case for the tsv-pad helper" >/dev/null
  add "restart the launchd daemon" a2 >/dev/null
  # A PURE-BASH read, not a digest. `md5`/`md5sum` are bare names and this corpus runs under
  # launchd's own PATH, where neither resolves — the unattended-path ratchet catches exactly that.
  # `$(<file)` needs no binary, and comparing the CONTENT is a stronger statement than comparing a
  # hash of it anyway.
  local before; before="$(<"$CC_BACKLOG_FILE")"
  run "$CV" run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"DRY RUN"* ]] || { echo "$output"; false; }
  local after; after="$(<"$CC_BACKLOG_FILE")"
  [ "$before" = "$after" ] || { echo "a dry run wrote to the ledger"; false; }
}

@test "13 --apply writes BOTH directions, each with its recorded why" {
  mkrepo
  local c l
  c="$(add "add a bats case for the tsv-pad helper")"
  l="$(add "restart the launchd daemon" a2)"
  run "$CV" run --apply
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(plan_of "$c")" = cloud ] || { echo "cloud item not labelled"; false; }
  [ "$(plan_of "$l")" = local ] || { echo "local item not labelled"; false; }
  # A REFUSAL IS RECORDED, not merely omitted — an unlabelled row and a row refused for a named
  # reason are different facts, and only one of them can be read six weeks later.
  [[ "$(why_of "$l")" == "ineligible-box: "* ]] || { why_of "$l"; false; }
}

@test "14 the write goes through cc-backlog venue — its refusals are the producer's refusals" {
  mkrepo
  local id; id="$(add "add a bats case for the tsv-pad helper")"
  # `done` quoted: it is a reserved word, so shellcheck reads the bare form as a loop terminator.
  "$CB" "done" "$id" --evidence landed >/dev/null 2>&1
  # A done item is rc 4 at the actuator. The producer must not have its own opinion about that, and
  # must not fall back to appending a record itself.
  run "$CV" run --apply
  [ "$(plan_of "$id")" = "«absent»" ] || { echo "a terminal item was labelled anyway"; false; }
}

@test "15 --apply is IDEMPOTENT end to end: a second run appends nothing" {
  mkrepo
  add "add a bats case for the tsv-pad helper" >/dev/null
  add "restart the launchd daemon" a2 >/dev/null
  "$CV" run --apply >/dev/null
  local before; before="$(grep -c '' "$CC_BACKLOG_FILE")"
  "$CV" run --apply >/dev/null
  [ "$(grep -c '' "$CC_BACKLOG_FILE")" -eq "$before" ] \
    || { echo "grew from $before to $(grep -c '' "$CC_BACKLOG_FILE") on an unchanged store"; false; }
}

@test "16 run considers OPEN items only — claimed and blocked work has no dispatch to inform" {
  mkrepo
  local a b
  a="$(add "add a bats case for the tsv-pad helper")"
  b="$(add "another repo-only change to the same helper" a2)"
  "$CB" claim "$b" --by "holder-1" >/dev/null 2>&1
  run "$CV" run --json
  echo "$output" | jq -e --arg i "$a" '[.decisions[].id] | index($i)' >/dev/null || { echo "$output"; false; }
  echo "$output" | jq -e --arg i "$b" '[.decisions[].id] | index($i) | not' >/dev/null || { echo "$output"; false; }
}

@test "17 run --json reports the horizon per repo, so a zero cloud count is diagnosable" {
  mkrepo
  add "add a bats case for the tsv-pad helper" >/dev/null
  run "$CV" run --json
  echo "$output" | jq -e '[.horizons[].state] | index("ok")' >/dev/null || { echo "$output"; false; }
  echo "$output" | jq -e '.counts.cloud >= 1' >/dev/null || { echo "$output"; false; }
}

@test "18 --limit bounds the pass, and an unparseable limit is rc 2 rather than a silent full run" {
  mkrepo
  add "one repo-only change" a1 >/dev/null
  add "two repo-only change" a2 >/dev/null
  add "three repo-only change" a3 >/dev/null
  run "$CV" run --json --limit 2
  echo "$output" | jq -e '.considered == 2' >/dev/null || { echo "$output"; false; }
  run "$CV" run --limit banana
  [ "$status" -eq 2 ] || { echo "$output"; false; }
}

@test "19 the re-run cost gate is STRICTLY WEAKER than the actuator idempotence it shadows" {
  mkrepo
  add "add a bats case for the tsv-pad helper" >/dev/null
  add "restart the launchd daemon" a2 >/dev/null
  "$CV" run --apply >/dev/null
  local before; before="$(grep -c '' "$CC_BACKLOG_FILE")"

  # A cc-backlog that FAILS if it is invoked at all. On an unchanged store the gate must skip every
  # write, so this must not be reached — which is what makes the skip observable rather than merely
  # fast. (Case 15 already pins the end-to-end idempotence; this pins WHERE it is paid for.)
  local tripwire="$BATS_TEST_TMPDIR/cb-tripwire"
  cat > "$tripwire" <<EOF
#!/bin/bash
case "\$1" in
  list) exec "$CB" "\$@" ;;
  *) echo "cc-backlog was invoked to write: \$*" >&2; exit 9 ;;
esac
EOF
  chmod +x "$tripwire"
  CC_VENUE_BACKLOG_BIN="$tripwire" run "$CV" run --apply --json
  [ "$status" -eq 0 ] || { echo "the gate did not skip: $output"; false; }
  echo "$output" | jq -e '.counts.unchanged >= 2' >/dev/null || { echo "$output"; false; }
  [ "$(grep -c '' "$CC_BACKLOG_FILE")" -eq "$before" ] || { echo "the store grew"; false; }
}

@test "20 CONTROL: a CHANGED decision still reaches the actuator — the gate is not a mute button" {
  mkrepo
  local id; id="$(add "add a bats case for the tsv-pad helper")"
  "$CV" run --apply >/dev/null
  [ "$(plan_of "$id")" = cloud ] || { echo "setup failed"; false; }
  # Hand-write a DIFFERENT decision, so the fold no longer matches what the producer will compute.
  "$CB" venue "$id" --venue local --why "stale: hand-written" >/dev/null
  run "$CV" run --apply --json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(plan_of "$id")" = cloud ] \
    || { echo "the gate suppressed a write the actuator would have taken"; false; }
}

@test "21 label routes ONE item, including a row run skips — same decide(), same actuator" {
  mkrepo
  local id; id="$(add "open a pull request against the upstream repo")"
  "$CB" block "$id" --needs "an operator has to own this" >/dev/null 2>&1
  # `run` is open-only and must stay so: routing exists to inform a dispatch, and blocked work
  # reaches none. Pinned here rather than assumed, because `label` only earns its place if the
  # default it works around is real.
  run "$CV" run --json
  echo "$output" | jq -e --arg i "$id" '[.decisions[].id] | index($i) | not' >/dev/null \
    || { echo "run should skip blocked work: $output"; false; }

  run "$CV" label "$id"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(plan_of "$id")" = local ] || { plan_of "$id"; false; }
  [[ "$(why_of "$id")" == "ineligible-github: "* ]] || { why_of "$id"; false; }
  # …and the why is BYTE-IDENTICAL to what assess computed: one producer, not two.
  [ "$(why_of "$id")" = "$("$CV" assess "$id" --json | jq -r .why)" ] \
    || { echo "label and assess disagree — that is a second producer"; false; }
}

@test "22 label on an unknown id is rc 3, not a silent no-op" {
  mkrepo
  run "$CV" label nosuchid0000
  [ "$status" -eq 3 ] || { echo "$output"; false; }
}

# ── QUESTION 1b: IS THE ITEM'S OWN SPECIFICATION ON TRUNK? ──────────────────────────────────────
# The arm added 2026-08-24. What it guards is the same silent-and-expensive failure the header
# names, on the one citation no arm resolved: a `dodRef` naming a plan that exists only in the
# DISPATCHING box's working tree. Every case below is paired with a control that must still route
# cloud, because "it refused" is worthless unless the same shape is shown to be promotable.

land_plan() {  # land_plan <repo-relative path> — commit it and move origin/main onto it
  mkdir -p "$G/$(dirname "$1")"
  echo "# plan" > "$G/$1"
  git -C "$G" add "$1"
  git -C "$G" commit -qm "plan $1"
  git -C "$G" update-ref refs/remotes/origin/main "$(git -C "$G" rev-parse main)"
}

add_dod() { "$CB" add --title "$1" --project probe --source "${3:-s}" --dod-ref "$2"; }

@test "23 a dodRef on no commit routes LOCAL — the VM would arrive unable to read its own spec" {
  mkrepo
  # NOT landed: the file is written into the working tree exactly as the filing box holds it, which
  # is the whole condition. `git ls-tree origin/main` has never heard of it.
  mkdir -p "$G/docs/plans"; echo "# open" > "$G/docs/plans/TRIAGE_B.md"
  local id; id="$(add_dod "triage the open remainder" "docs/plans/TRIAGE_B.md")"
  [ "$(venue_of "$id")" = local ] || { "$CV" assess "$id"; false; }
  "$CV" assess "$id" --json | jq -e '.why | test("^ineligible-dod-offtrunk: ")' >/dev/null \
    || { "$CV" assess "$id"; false; }
  # The why must NAME the path, or a reader cannot act on the refusal.
  "$CV" assess "$id" --json | jq -e '.why | test("docs/plans/TRIAGE_B.md")' >/dev/null \
    || { "$CV" assess "$id"; false; }
}

@test "24 CONTROL: the same item with its plan ON trunk routes CLOUD — the arm is scoped, not blanket" {
  mkrepo
  land_plan "docs/plans/TRIAGE_A.md"
  local id; id="$(add_dod "triage the open remainder" "docs/plans/TRIAGE_A.md")"
  [ "$(venue_of "$id")" = cloud ] || { "$CV" assess "$id"; false; }
  "$CV" assess "$id" --json | jq -e '.why | test("DoD on trunk at docs/plans/TRIAGE_A.md")' >/dev/null \
    || { "$CV" assess "$id"; false; }
}

@test "25 an ABSOLUTE dodRef resolves by suffix — a filing-box mount prefix is not absence" {
  mkrepo
  land_plan "docs/plans/TRIAGE_A.md"
  # The spelling cc-dispatch's own `[ -f "$sdod" ]` gate reads, and the spelling the live store
  # carries. Resolved as a repo-root path it is absent; that reading would refuse every such row.
  local id; id="$(add_dod "triage" "/Users/someone/Development/probe/docs/plans/TRIAGE_A.md")"
  [ "$(venue_of "$id")" = cloud ] || { "$CV" assess "$id"; false; }
}

@test "26 an absolute dodRef whose suffix is on NO commit is still refused, and named" {
  mkrepo
  local id; id="$(add_dod "triage" "/Users/someone/Development/probe/docs/plans/TRIAGE_B.md")"
  [ "$(venue_of "$id")" = local ] || { "$CV" assess "$id"; false; }
  "$CV" assess "$id" --json | jq -e '.why | test("^ineligible-dod-offtrunk: ")' >/dev/null \
    || { "$CV" assess "$id"; false; }
}

@test "27 a row with NO dodRef is untouched — the arm convicts only what it can read" {
  mkrepo
  local id; id="$(add "add a bats case for the tsv-pad helper")"
  [ "$(venue_of "$id")" = cloud ] || { "$CV" assess "$id"; false; }
}

@test "28 a dodRef that is not a path claim is untouched — decision:<id> is not a missing file" {
  mkrepo
  local id; id="$(add_dod "ratify the open decisions" "decision:5f0ab12c9d34")"
  [ "$(venue_of "$id")" = cloud ] || { "$CV" assess "$id"; false; }
}

@test "29 the arm runs BEFORE the premise probe — no falsifier is spent on work that cannot go" {
  mkrepo
  mkdir -p "$G/docs/plans"; echo "# open" > "$G/docs/plans/TRIAGE_B.md"
  local stub="$BATS_TEST_TMPDIR/premise-marker"
  cat > "$stub" <<EOF
#!/bin/bash
touch "$BATS_TEST_TMPDIR/premise-ran"
echo "verdict=clear"
exit 0
EOF
  chmod +x "$stub"

  local off; off="$(add_dod "triage the open remainder" "docs/plans/TRIAGE_B.md")"
  CC_VENUE_PREMISE=on CC_VENUE_PREMISE_BIN="$stub" "$CV" assess "$off" >/dev/null
  [ ! -e "$BATS_TEST_TMPDIR/premise-ran" ] \
    || { echo "the premise probe ran on an item already refused for its DoD"; false; }

  # THE CONTROL that makes the line above a statement about ORDER rather than about a dead stub.
  land_plan "docs/plans/TRIAGE_A.md"
  local on; on="$(add_dod "triage the open remainder" "docs/plans/TRIAGE_A.md" a2)"
  CC_VENUE_PREMISE=on CC_VENUE_PREMISE_BIN="$stub" "$CV" assess "$on" >/dev/null
  [ -e "$BATS_TEST_TMPDIR/premise-ran" ] \
    || { echo "the stub never runs at all — case 29 proves nothing"; false; }
}
