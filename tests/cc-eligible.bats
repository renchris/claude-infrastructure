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

@test "EXTERNAL DEPLOY: a provider CLI the VM does not install is refused under its OWN token" {
  # Regression for backlog `96c57c1c4a6c`, the item that exposed the class: a vector.toml filter
  # that drops a serving app's logs, whose directory "has NEVER been deployed" and needs a one-time
  # `flyctl apps create`. The artifact is ordinary repo text and the repo is the item's own, so no
  # list above fires — measured on the real title, which returned `eligible / (nothing fired)`.
  # The separate token matters for the same reason branch-banking's does: a reader handed
  # `ineligible-box` goes looking for a keychain on this disk, not for a Fly credential.
  local id; id="$(add fly "fly-log-shipper-iad ships NOTHING for a serving reso-iad; needs a one-time 'flyctl apps create'")"
  run "$CE" check "$id"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=ineligible-external-deploy"* ]] || { echo "$output"; false; }
  [[ "$output" == *"flyctl"* ]] || { echo "named the class but not the spelling: $output"; false; }
}

@test "EXTERNAL DEPLOY: the provider's artifacts count, not just its CLI" {
  local id; id="$(add fly "carry the app in fly.toml the way the sin shipper does, then fly deploy it")"
  run "$CE" check "$id"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=ineligible-external-deploy"* ]] || { echo "$output"; false; }
}

@test "EXTERNAL DEPLOY lookalike: 'flying'/'superfly' are not Fly — boundaries hold both ways" {
  # The paired control. Bare `\bfly\b` was tested and rejected for exactly this: it takes the
  # ordinary English word with it, and every refusal assertion above would still pass.
  local id; id="$(add ctl "stop the log lines flying past; the superfly parser and fly.iowa stay as they are")"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=eligible"* ]] || { echo "$output"; false; }
}

@test "EXTERNAL DEPLOY: the ABSTRACT credential spelling is deliberately NOT the class" {
  # The width guard, pinned as a test because it is the failure this file's header names: over the
  # repo's own corpus `credentials?` matches 506 lines and `secrets?` 133, so classifying on them
  # would refuse a large slice of ordinary repo work. Ordinary work that merely SAYS "credentials"
  # must stay claimable off-box; only the named provider refuses.
  local id; id="$(add ctl "document how the resolver caches credentials and rotates the secret in the README")"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=eligible"* ]] || { echo "$output"; false; }
}

@test "BACKLOG POOL: the live pool is this box — the item that WAS misrouted here" {
  # Regression for backlog `37b112d8950d`, verbatim, and the strongest kind of case this suite can
  # carry: the off-box session this item was dispatched to is the one that wrote the spelling. Its
  # real title returned `eligible / (nothing fired)`, and in the VM `cc-backlog freshness` answers
  # `never validated: 0 of 0 live rows` — the 457 rows and the probes' repos are on the other disk.
  local id; id="$(add pool "L1: run the falsifier sweep across all 457 unvalidated live backlog rows, then close-falsified. cc-backlog freshness reads 'never validated: 457 of 501'.")"
  run "$CE" check "$id"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=ineligible-box"* ]] || { echo "$output"; false; }
  [[ "$output" == *"backlog-pool"* || "$output" == *"backlog-sweep"* ]] || { echo "named the class but not the spelling: $output"; false; }
}

@test "BACKLOG POOL: the whole-pool VERB refuses even with no population word" {
  local id; id="$(add pool "run cc-premise sweep --record --close-falsified over every live row lacking a probe")"
  run "$CE" check "$id"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"backlog-sweep"* ]] || { echo "named the class but not the spelling: $output"; false; }
}

@test "BACKLOG POOL: the store FILE is the class's own name" {
  local id; id="$(add pool "fold ~/.claude/autonomy/backlog.jsonl and report the malformed lines")"
  run "$CE" check "$id"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
}

@test "BACKLOG POOL lookalike: a dispatch brief's own completion protocol stays eligible" {
  # THE WIDTH GUARD, and the reason the verb list is whole-pool-only. Every brief this lane emits
  # ends with `cc-backlog done <id>`; a bare `cc-backlog` spelling would refuse the entire tap.
  local id; id="$(add ctl "On completion: cc-backlog done 37b112d8950d --evidence '<landed sha>'; if blocked, cc-backlog block --needs '<the step>'")"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=eligible"* ]] || { echo "$output"; false; }
}

@test "BACKLOG POOL lookalike: maintaining the backlog TOOL is ordinary repo work" {
  # Deliberate: bin/cc-backlog and bin/cc-premise are verified against fixtures by this very
  # suite, so editing them is claimable off-box. Only operating on the LIVE pool is not.
  local id; id="$(add ctl "add a --json flag to cc-backlog list and pin it with a fixtured bats test; cc-premise check should fail open when the ledger is malformed")"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=eligible"* ]] || { echo "$output"; false; }
}

@test "BACKLOG POOL lookalike: the plain word 'backlog' and unrelated 'rows' stay eligible" {
  local id; id="$(add ctl "file a backlog row for the retired method, rotate docs/plans/BACKLOG_DRAIN_24_7.md, and backfill the rows the migration adds to the sessions table")"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=eligible"* ]] || { echo "$output"; false; }
}
