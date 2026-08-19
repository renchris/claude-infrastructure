#!/usr/bin/env bats
# cc-eligible — may this work item run OFF-BOX? The predicate behind cc-backlog's `--venue cloud`
# refusal, turning CONCURRENCY_PROGRAM.md §S5's sentence (repo-only ✅ · visual ❌ · about-this-box ❌
# · branch banking ⚠️) into an exit code.
#
# WHAT THIS SUITE IS ACTUALLY GUARDING, and it is not "the keyword list is right". The list
# enumerates SPELLINGS, never the class (memory: denylist-enumerates-spellings-not-the-class), so a
# suite asserting "launchd is refused" proves only that one string is in one array. The properties
# worth pinning are the ones a future edit can silently break:
#
#   · the two failure directions are SEPARATE. Unreadable ⇒ exit 0 (a classifier that refused on "I
#     could not tell" takes the whole cloud tap down with it). Read-and-matched ⇒ exit 3.
#   · the token is on LINE 1 of stdout AND of a `2>&1` capture — the only channel a `head -1`
#     consumer has (memory: claimed-outcome-vs-checked-outcome).
#   · word boundaries hold in BOTH directions. Every refusal arm is paired with a LOOKALIKE that
#     must stay eligible ("success" is not `css`), because a substring list would refuse most of
#     the store and every refusal assertion here would still pass.
#   · the classified SPAN is the item's specification, not everything filed under its id (memory:
#     assertion-span-must-equal-its-subject) — pinned by a control that puts the same word in
#     `evidence` and requires it NOT to fire.
#
# Assertions use the explicit `|| { …; false; }` form: a non-final `[[ ]]` is errexit-EXEMPT under
# bats and would be a DEAD assertion that can never fail.

setup() {
  # Project labels in this suite are FIXTURES, not projects — and `cc-backlog add` now WARNS on an
  # explicit --project outside the dispatch set (df2b6a40a5dc), which bats folds into $output. Off
  # here because dispatchability is not this suite's subject; tests/cc-backlog-project-dispatch.bats
  # owns it, unfixtured, in both directions.
  export CC_BACKLOG_PROJECT_WARN=off
  # Fixture $HOME FIRST (the test-hermeticity ratchet's rule 1): the subject's default store
  # resolves under ~/.claude/autonomy/backlog.jsonl, which is the operator's 5,759 real records.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CE="$REPO/bin/cc-eligible"
  CB="$REPO/bin/cc-backlog"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  # cc-backlog's post-add dispatch kick is backgrounded and irrelevant here; keep it off the box.
  export CC_BACKLOG_DISPATCH_BIN="$BATS_TEST_TMPDIR/absent-dispatch"
}

# add <source> <title> → the item id
add() { "$CB" add --title "$2" --project probe --source "$1"; }

# verdict <id> → line 1 of a `2>&1` capture, which is what every real caller sees
verdict() { "$CE" check "$1" 2>&1 | head -1; }

# ── the three refusal classes, each paired with a control that must stay eligible ───────────────

@test "ABOUT THIS BOX: refused, exit 3, own token" {
  local id; id="$(add box "restart the launchd daemon and reload its plist")"
  run "$CE" check "$id"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=ineligible-box"* ]] || { echo "$output"; false; }
  [[ "$output" == *"launchd"* ]] || { echo "named the class but not the spelling: $output"; false; }
}

@test "VISUAL: refused, exit 3, own token" {
  local id; id="$(add vis "screenshot the banner against the dev server at localhost")"
  run "$CE" check "$id"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=ineligible-visual"* ]] || { echo "$output"; false; }
}

@test "BRANCH BANKING: refused under its OWN token, not folded into box work" {
  # The plan marks this ⚠️ and not ❌, and the distinction is real: the WORK is ordinary repo work
  # and only the CORPUS is local. A reader who gets `ineligible-box` here goes looking for a
  # keychain; the separate token is what stops that.
  local id; id="$(add bank "bank the 2304 commits across 199 unpushed branches")"
  run "$CE" check "$id"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=ineligible-branch-banking"* ]] || { echo "$output"; false; }
}

@test "BRANCH BANKING: the worktree named as a DIRECTORY, the way the fleet writes one" {
  # Regression for backlog `4abcbbbbc997`, which was dispatched to a cloud VM and could not run
  # there: it names its worktree only as `wt-bsm-gap` and spells no other listed word. The title is
  # the real one, trimmed. Asserting the SPELLING and not just the token is what distinguishes this
  # from the test above — that one already passes on the pre-fix list via `unpushed`.
  local id; id="$(add bank "Retry the BSM land — 7 commits on research/bsm-world-class-gap (wt-bsm-gap), tree clean")"
  run "$CE" check "$id"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=ineligible-branch-banking"* ]] || { echo "$output"; false; }
  [[ "$output" == *"wt-slug"* ]] || { echo "named the class but not the spelling: $output"; false; }
}

@test "CONTROL: a lookalike prefix is NOT a worktree — word boundaries hold leftward" {
  # The paired lookalike every refusal arm in this suite carries. A pattern anchored on a substring
  # rather than a word boundary would refuse these and every assertion above would still pass.
  local id; id="$(add ctl "rewrite the swt-handler and the NEWT-parser; note the wt is unrelated")"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=eligible"* ]] || { echo "$output"; false; }
}

@test "CONTROL: repo-only work is ELIGIBLE, exit 0" {
  # Without this the three arms above are satisfied by a classifier that refuses everything — which
  # kills the cloud tap and reads as a green board (memory: alarm-polarity-and-attention-budget).
  local id; id="$(add repo "audit the eslint rule config across every package")"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=eligible"* ]] || { echo "$output"; false; }
}

@test "CONTROL: word boundaries hold — a LOOKALIKE substring does not refuse" {
  # `success` contains css, `japanese` contains pane, `overhaul` contains haul but not hardware —
  # a substring list would refuse this and every refusal arm above would still be green.
  local id; id="$(add look "measure the success rate of the japanese locale overhaul")"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=eligible"* ]] || { echo "$output"; false; }
}

@test "refusal ORDER: an item naming two classes reports the widest one" {
  # Widest-first is deliberate: an item that says both "launchd" and "render" is box work whose
  # remedy happens to be visible, not design work. The token is one string because the consumer is
  # `head -1`; the ordering is what makes that single string the useful one.
  local id; id="$(add both "render the launchd status banner")"
  run "$CE" check "$id"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=ineligible-box"* ]] || { echo "$output"; false; }
}

# ── the two fail-open directions, kept apart ───────────────────────────────────────────────────

@test "FAIL-OPEN: an unknown id exits 0 and NAMES the uncertainty" {
  # The store must EXIST for this arm to be about the id: with no store at all the honest answer is
  # `unknown-store`, and taking that as a pass would leave "id not found" untested (memory:
  # lookup-miss-is-not-absence — a miss indicts the oracle until you know the oracle answered).
  add present "audit the eslint rule config" >/dev/null
  run "$CE" check ffffffffffff
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=unknown-item"* ]] || { echo "$output"; false; }
}

@test "FAIL-OPEN: an unreadable store exits 0 under a DIFFERENT token" {
  # Separate tokens on purpose: "no such item" is a caller bug and "unreadable store" is an outage.
  # One shared `unknown` would hide the outage inside the typo (memory:
  # sensor-default-off-makes-blindness-the-shipping-path).
  local id; id="$(add gone "restart the launchd daemon")"
  run env CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/no/such/store.jsonl" "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=unknown-store"* ]] || { echo "$output"; false; }
}

@test "FAIL-OPEN: a MALFORMED ledger line is skipped, not fatal" {
  local id; id="$(add mal "audit the eslint rule config")"
  printf 'this is not json\n' >> "$CC_BACKLOG_FILE"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=eligible"* ]] || { echo "$output"; false; }
}

# ── the channel: line 1, in a 2>&1 capture ─────────────────────────────────────────────────────

@test "the verdict token is on LINE 1 even when stderr is merged" {
  # stdout is block-buffered when piped and stderr is not, so without an explicit flush the reasons
  # overtake the token and line 1 becomes a sentence — exactly where `head -1` is looking.
  local id; id="$(add line1 "rebuild the iTerm2 pane registry")"
  run verdict "$id"
  [ "$output" = "verdict=ineligible-box" ] || { echo "line 1 was: $output"; false; }
}

@test "CONTROL: the same channel carries the ELIGIBLE token too" {
  local id; id="$(add line1ok "audit the eslint rule config")"
  run verdict "$id"
  [ "$output" = "verdict=eligible" ] || { echo "line 1 was: $output"; false; }
}

# ── the classified SPAN ────────────────────────────────────────────────────────────────────────

@test "SPAN: dodRef is classified — it is part of the specification" {
  local id; id="$("$CB" add --title "tighten the stale gate" --project probe --source span1 \
                          --dod-ref "hooks/session-continue.sh")"
  run "$CE" check "$id"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=ineligible-box"* ]] || { echo "$output"; false; }
}

@test "SPAN CONTROL: evidence is NOT classified — the span is the spec, not the trail" {
  # The same word that refuses from a title must not refuse from the proof a finished item left.
  # Classifying everything ever filed under an id makes the verdict drift as the item is annotated.
  local id; id="$(add span2 "audit the eslint rule config")"
  "$CB" claim "$id" --by "$(hostname -s)-$$" >/dev/null
  "$CB" "done" "$id" --evidence "landed as a launchd plist change" >/dev/null
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=eligible"* ]] || { echo "$output"; false; }
}

# ── explain / sweep — the other two consumers of the ONE implementation ────────────────────────

@test "explain names the verdict and the spelling, and never blocks" {
  local id; id="$(add exp "restart the launchd daemon")"
  run "$CE" explain "$id"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"ineligible-box"* ]] || { echo "$output"; false; }
  [[ "$output" == *"launchd"* ]] || { echo "$output"; false; }
}

@test "explain on an ELIGIBLE item says what 'eligible' does NOT mean" {
  # The one place the honest weakness of a spelling list has to be stated to its reader.
  local id; id="$(add exp2 "audit the eslint rule config")"
  run "$CE" explain "$id"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"NO SPELLING IN THE LIST FIRED"* ]] || { echo "$output"; false; }
}

@test "sweep censuses the store and PRINTS the eligible bucket" {
  add s1 "restart the launchd daemon" >/dev/null
  add s2 "screenshot the banner" >/dev/null
  local keep; keep="$(add s3 "audit the eslint rule config across packages")"
  run env CC_ELIGIBLE_BACKLOG_BIN="$CB" "$CE" sweep
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"ineligible-box"* ]] || { echo "$output"; false; }
  # The ELIGIBLE bucket is listed in full — it is the bucket where a missed spelling does damage,
  # so the sweep is the instrument for finding the words this file does not know.
  [[ "$output" == *"$keep"* ]] || { echo "eligible item not listed: $output"; false; }
  [[ "$output" == *"spellings that fired"* ]] || { echo "$output"; false; }
}

@test "sweep --json carries the same numbers a reader saw" {
  add j1 "restart the launchd daemon" >/dev/null
  add j2 "audit the eslint rule config" >/dev/null
  run env CC_ELIGIBLE_BACKLOG_BIN="$CB" "$CE" sweep --json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["counts"]["ineligible-box"]==1, d; assert d["counts"]["eligible"]==1, d'
}

@test "FAIL-OPEN: sweep on an unusable fold exits 0, never a false census" {
  local stub="$BATS_TEST_TMPDIR/broken-backlog"
  printf '#!/bin/bash\nexit 1\n' > "$stub"; chmod +x "$stub"
  run env CC_ELIGIBLE_BACKLOG_BIN="$stub" "$CE" sweep
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=unknown-store"* ]] || { echo "$output"; false; }
}

@test "an unknown verb is rc 2, not a silent eligible" {
  run "$CE" frobnicate
  [ "$status" -eq 2 ] || { echo "$output"; false; }
}

# ── the lead-audit spellings (2026-08-11): each pinned on the REAL item's phrasing that exposed
# it, each paired with a lookalike that must stay eligible ──────────────────────────────────────

@test "VERSIONED CONFIG DIR: .claude-219/.claude-220 is this box, refused" {
  local id; id="$(add aud "asyncRewake ABSENT from installed .claude-219/.claude-220 binaries tonight — re-verify the field name on current binaries")"
  run "$CE" check "$id"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=ineligible-box"* ]] || { echo "$output"; false; }
  [[ "$output" == *"versioned-config-dir"* || "$output" == *"installed-binaries"* ]] || { echo "named the class but not the spelling: $output"; false; }
}

@test "VERSIONED CONFIG DIR lookalike: .claude-plans and claude-infrastructure are repo words, eligible" {
  local id; id="$(add aud "move the plan into .claude-plans and cite the claude-infrastructure README")"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "INSTALLED BINARIES: a claim about what an installed binary contains is a read of this box" {
  local id; id="$(add aud "the flag is absent because the binaries were installed without it")"
  run "$CE" check "$id"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"installed-binaries"* ]] || { echo "named the class but not the spelling: $output"; false; }
}

@test "INSTALLED BINARIES lookalike: 'binary format' with no install claim stays eligible" {
  local id; id="$(add aud "document the binary format of the journal header")"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "CC BINARY VERSION: adjudicating 2.1.NNN build behavior is this box's installs" {
  local id; id="$(add aud "its claim 2.1.220 IS 3.4x worse per session than 2.1.219 is FALSE — a time-confounded comparison")"
  run "$CE" check "$id"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"cc-binary-version"* ]] || { echo "named the class but not the spelling: $output"; false; }
}

@test "CC BINARY VERSION lookalike: a two-digit patch or a section number stays eligible" {
  local id; id="$(add aud "bump the dep to 2.1.22 and renumber section 2.1.2 of the doc")"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

# ── THE DECLARED-TREE CLASS ────────────────────────────────────────────────────────────────────
# The one class in this file that no spelling can reach. It exists because a cross-repo MASTER row
# can have a perfectly correct span — title, dodRef, condition and source all accurate — and still
# name no project at all, its foreign checkouts living only in the plan BODY that `dodRef` points
# at. Measured on 8f59467c92b0, dispatched to a single-repo cloud VM three times (2026-08-15, -17,
# -19); docs/research/venue-declared-foreign-tree-2026-08-19.md.
#
# What these pin is the SAFETY of the dereference, not that one plan is refused: the arm reads a
# declared frontmatter key and NOTHING else, and every uncertainty it meets must fail OPEN. A
# regression here does not look like a wrong refusal in the census — it looks like the cloud tap
# quietly refusing every item whose plan it merely could not read.

# CALLED BARE, never inside `$( )`. CC_ELIGIBLE_REPO stands in for ~/Development/<project>, and an
# `export` from a command substitution dies with its subshell — which is a live trap here, because
# this arm FAILS OPEN, so losing the variable turns every assertion below into a silent `eligible`
# that looks like a passing control. Two of these tests were written that way first and reported
# `verdict=eligible` for a plan that declares two foreign trees.
fixture_repo() {
  export CC_ELIGIBLE_REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$BATS_TEST_TMPDIR/repo/docs/plans"
}

# plan <name> <frontmatter-lines…> → writes a plan under the fixture repo, echoes its dodRef
plan() {
  local name="$1"; shift
  { echo "---"; printf '%s\n' "$@"; echo "---"; echo; echo "# $name"; echo "body: reso-management-app"; } \
    > "$BATS_TEST_TMPDIR/repo/docs/plans/$name.md"
  echo "docs/plans/$name.md"
}

foreign_item() {
  "$CB" add --title "MASTER: product repos" --project probe --source ft --dod-ref "$1"
}

@test "DECLARED TREE: a plan declaring another checkout refuses, and NAMES the checkouts" {
  fixture_repo
  local id; id="$(foreign_item "$(plan MASTER status:\ open "work-repos: reso-management-app, doc_classifier")")"
  run "$CE" check "$id"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=ineligible-foreign-tree"* ]] || { echo "$output"; false; }
  [[ "$output" == *"reso-management-app"* && "$output" == *"doc_classifier"* ]] \
    || { echo "refused without naming the trees: $output"; false; }
}

@test "DECLARED TREE: the refusal note sends the reader to a session, never to a spelling list" {
  fixture_repo
  local id; id="$(foreign_item "$(plan MASTER status:\ open "work-repos: reso-management-app")")"
  run "$CE" check "$id"
  # REFUSAL_NOTE says "fix bin/cc-eligible's list". There is no list here, and an instruction that
  # cannot be carried out is how a correct refusal gets forced past instead of understood.
  [[ "$output" != *"bin/cc-eligible's list"* ]] || { echo "sent to a list that does not exist: $output"; false; }
  [[ "$output" == *"HOLDS those trees"* ]] || { echo "$output"; false; }
}

@test "DECLARED TREE: a plan declaring only the item's OWN project stays eligible" {
  fixture_repo
  local id; id="$(foreign_item "$(plan MASTER status:\ open "work-repos: probe")")"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "own-tree work must not be refused: $output"; false; }
}

@test "DECLARED TREE: ANY foreign tree refuses — a cloud session gets exactly one repository" {
  fixture_repo
  local id; id="$(foreign_item "$(plan MASTER status:\ open "work-repos: probe, doc_classifier")")"
  run "$CE" check "$id"
  [ "$status" -eq 3 ] || { echo "own + foreign is still uncompletable off-box: $output"; false; }
  [[ "$output" == *"doc_classifier"* ]] || { echo "$output"; false; }
  [[ "$output" != *"named: probe"* ]] || { echo "named the tree it DOES hold: $output"; false; }
}

@test "FAIL-OPEN: a plan with no work-repos key is eligible — the key is opt-in, not a default" {
  fixture_repo
  local id; id="$(foreign_item "$(plan MASTER status:\ open owner:\ desk)")"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "silence must not read as foreign: $output"; false; }
}

@test "FAIL-OPEN: a dodRef pointing at NOTHING is eligible, not refused" {
  fixture_repo
  local id; id="$("$CB" add --title "m" --project probe --source ft --dod-ref "docs/plans/ABSENT.md")"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "unreadable must fail OPEN: $output"; false; }
}

@test "FAIL-OPEN: a plan with no frontmatter at all is eligible" {
  fixture_repo
  printf '# bare\nwork-repos: reso-management-app\n' > "$BATS_TEST_TMPDIR/repo/docs/plans/BARE.md"
  local id; id="$("$CB" add --title "m" --project probe --source ft --dod-ref "docs/plans/BARE.md")"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "a body line is not a declaration: $output"; false; }
}

@test "THE BODY IS NOT READ: prose naming a foreign tree does not refuse — only the declaration does" {
  # The fixture plan's body carries the line `body: reso-management-app` in every case above. If
  # this ever fires, the arm has started reading prose, and the span rule this file guards
  # (memory: assertion-span-must-equal-its-subject) is gone.
  fixture_repo
  local id; id="$(foreign_item "$(plan MASTER status:\ open)")"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "read the body, not the frontmatter: $output"; false; }
}

@test "DECLARED TREE: an ABSOLUTE dodRef written on another box is re-rooted at this checkout" {
  fixture_repo
  local rel; rel="$(plan MASTER status:\ open "work-repos: doc_classifier")"
  local id; id="$("$CB" add --title "m" --project probe --source ft \
                           --dod-ref "/Users/someone/Development/probe/$rel")"
  run "$CE" check "$id"
  [ "$status" -eq 3 ] || { echo "a Mac-absolute dodRef must still resolve here: $output"; false; }
}

@test "DECLARED TREE: a section anchor on the dodRef is not part of the path" {
  fixture_repo
  local id; id="$(foreign_item "$(plan MASTER status:\ open "work-repos: doc_classifier")#3")"
  run "$CE" check "$id"
  [ "$status" -eq 3 ] || { echo "'…md#3' must resolve to '…md': $output"; false; }
}
