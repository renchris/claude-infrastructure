#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329,SC2317
#   Structurally false under bats: every @test body IS its own subshell, so an `export` inside one
#   is meant to be test-local (SC2030/SC2031), and setup()'s helpers are invoked from those test
#   subshells rather than from file scope (SC2329/SC2317 — shellcheck cannot see that the runner
#   calls setup() before each body, so every helper defined there reads as unreachable).
#
# scripts/lib/cloud-brief.sh — the off-box trailer, and §4.1's BOOT CONTRACT
# (docs/plans/CLOUD_OBSERVABILITY.md §4.1, §8 step 2; backlog 0c8b39b67665).
#
# ── WHAT THIS SUITE IS ACTUALLY DEFENDING ────────────────────────────────────────────────────────
# Not "does a string get emitted". The trailer is the ONLY thing that makes `C1 NOT-STARTED` mean
# anything, and that arm's recover action is "re-fire" — so a trailer that quietly stops carrying
# the boot instruction does not fail loudly, it makes a live cloud session get re-fired on top of.
# The claim under test is therefore an ORDER claim, not a presence claim: the beacon push has to be
# the session's FIRST act, before the work, because a push at the end is the deliverable and says
# nothing about booting.
#
# ── RED CONTROL: THE PRE-FIX TRAILER IS REPLAYED VERBATIM ────────────────────────────────────────
# `old_trailer()` below is the block scripts/handoff-fire.sh carried on trunk before this change,
# copied byte-for-byte. Every case that asserts the contract is present ALSO replays those bytes
# and asserts the same predicate FAILS on them. Without that half, "the trailer mentions a push"
# passes just as well against the trailer that shipped the defect — it mentioned a push too.
#
# DEAD-ASSERTION DISCIPLINE: bats bodies run under `set -eET`, and bash exempts `[[ ]]`, `(( ))`
# and `! cmd` from errexit, so a non-final occurrence of those always passes
# (scripts/bats-assert-liveness.py). POSIX `[ ]` throughout, `|| false` after every non-final
# negation.
#
# NO NETWORK, NO CLOCK, NO REPO: the subject is a pure string composer.

setup() {
  # Fixture $HOME even though the subject is a pure composer: the ratchet is a ratchet precisely
  # because "this one does not read $HOME" is a claim about today's implementation, and the next
  # field added to the trailer is the one that reads a config.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="${CC_BRIEF_SUBJECT_ROOT:-$REPO}/scripts/lib/cloud-brief.sh"
  [ -f "$LIB" ] || skip "scripts/lib/cloud-brief.sh is missing at $LIB"
  # Sourced here, not per-test: bats runs setup() and the body in the SAME shell, so the functions
  # are directly callable and directly `run`-able below.
  # shellcheck source=scripts/lib/cloud-brief.sh
  . "$LIB"

  B="claude/fire-20260826T000000Z-1234-1"

  # The trailer scripts/handoff-fire.sh carried on trunk before backlog 0c8b39b67665, verbatim.
  # It creates the branch and instructs a push — and the push it instructs is the DELIVERABLE.
  old_trailer() {
    cat <<'OLD'
── HOW TO RETURN YOUR WORK (this session runs off-box; read this before you finish) ──
You are running in an Anthropic-managed VM. Nothing on the operator's machine can see your
filesystem, your processes or your terminal, and you cannot run this repo's /ship. Your ONLY
channel back is a git push, and it must go to exactly this branch — CREATE IT FIRST, then push it:

    git switch -c claude/fire-20260826T000000Z-1234-1
    git push -u origin HEAD

That branch name was assigned by the firing side and is already declared as the one thing watched
for your progress — a push anywhere else is invisible and your work will strand. Push whatever you
have before you finish, even if the work is incomplete; an unpushed cloud session leaves no trace
of any kind. A local reconciler (scripts/cloud-reconcile.sh) discovers the branch and lands it.
OLD
  }

  # COMMAND LINES ONLY — the indented block the session pastes, never the prose around it. The
  # trailer says the words "a git push" in its opening sentence, and a predicate that matched prose
  # would read that sentence as the first push and fail an ordering that is in fact correct. What
  # the contract is about is the order of the COMMANDS.
  cmd_lines() { grep -E '^[[:space:]]+git ' ; }

  # THE PREDICATE UNDER TEST, in one place so the red control and the green case cannot drift:
  # "this text instructs an empty commit, and instructs it BEFORE the first push."
  has_boot_contract() { # stdin → rc 0 iff the boot contract is present and ordered
    local t c p
    t="$(cat | cmd_lines)"
    c="$(printf '%s\n' "$t" | grep -n 'git commit .*--allow-empty' | head -1 | cut -d: -f1)"
    p="$(printf '%s\n' "$t" | grep -n 'git push' | head -1 | cut -d: -f1)"
    [ -n "$c" ] || return 1
    [ -n "$p" ] || return 1
    [ "$c" -lt "$p" ]
  }
}

# ── 1: the contract exists at all, with the control that proves the assertion can fail ────────────
@test "1 the trailer instructs an EMPTY COMMIT before any push — and the pre-fix trailer did not" {
  cc_cloud_brief_trailer "$B" | has_boot_contract
  # RED CONTROL — the same predicate over the bytes that shipped the defect.
  ! old_trailer | has_boot_contract || {
    echo "the predicate passes on the PRE-FIX trailer, so it is not measuring the fix"; false; }
}

# ── 2: FIRST act, not last. The ordering is the whole contract ────────────────────────────────────
@test "2 switch, then the empty commit, then the push — and all three precede the closing push" {
  local out sw ci p1 plast
  out="$(cc_cloud_brief_trailer "$B" | cmd_lines)"
  sw="$(printf '%s\n' "$out"    | grep -n "git switch -c $B" | head -1 | cut -d: -f1)"
  ci="$(printf '%s\n' "$out"    | grep -n 'git commit .*--allow-empty' | head -1 | cut -d: -f1)"
  p1="$(printf '%s\n' "$out"    | grep -n 'git push' | head -1 | cut -d: -f1)"
  plast="$(cc_cloud_brief_trailer "$B" | grep -c 'push')"
  [ -n "$sw" ]
  [ -n "$ci" ]
  [ -n "$p1" ]
  [ "$sw" -lt "$ci" ] || { echo "the branch must exist before the beacon is committed to it"; false; }
  [ "$ci" -lt "$p1" ] || { echo "the beacon commit must precede the push that publishes it"; false; }
  # The end-of-work push is still instructed — the beacon REPLACES nothing, it precedes.
  [ "$plast" -ge 2 ] || { echo "the trailer dropped the end-of-work push instruction"; false; }
}

# ── 3: the beacon is re-run-safe, which is what makes it executable on the API lane ───────────────
# scripts/cloud-create-api.py sets `reuse_outcome_branches: true` and names the branch AT CREATE,
# so the VM can legitimately already be on it. A bare `git switch -c` aborts there and the session
# proceeds with no beacon at all — the exact silence the contract removes.
@test "3 the switch has a fallback for a branch that already exists — the API lane's normal case" {
  cc_cloud_brief_trailer "$B" | grep -q "git switch -c $B 2>/dev/null || git switch $B"
  # RED CONTROL: the pre-fix trailer had the bare form, which fails on that lane.
  ! old_trailer | grep -q '|| git switch' || {
    echo "the pre-fix trailer already had the fallback — this case measures nothing"; false; }
}

# ── 4: the branch is NAMED, everywhere it is used ─────────────────────────────────────────────────
@test "4 every git line names the declared branch — a trailer that names none instructs nothing" {
  local out other
  out="$(cc_cloud_brief_trailer "$B")"
  [ "$(printf '%s\n' "$out" | grep -o -- "$B" | wc -l)" -ge 4 ]
  # Every git line that selects a branch selects THIS one: the ref the VM may push is exactly one,
  # and a second name in the trailer is a push the firing side is not watching.
  other="$(printf '%s\n' "$out" | grep -E 'git (switch|checkout)' | grep -cv -- "$B" || true)"
  [ "$other" -eq 0 ] || { echo "a git branch line names a branch other than the declared one"; false; }
}

# ── 5: a trailer with no branch is a REFUSAL, never a trailer with a hole in it ───────────────────
@test "5 an empty or whitespace branch REFUSES — a push to nowhere is worse than no instruction" {
  run cc_cloud_brief_trailer ""
  [ "$status" -eq 2 ]
  [[ "$output" == *REQUIRED* ]] || false
  run cc_cloud_brief_trailer "has space"
  [ "$status" -eq 2 ]
  # POSITIVE CONTROL on the same door: a real branch still composes.
  run cc_cloud_brief_trailer "$B"
  [ "$status" -eq 0 ]
}

# ── 6: the payload is the brief VERBATIM plus the trailer ─────────────────────────────────────────
# The operator's brief is the deliverable's instructions; a composer that reflowed, truncated or
# re-ordered it would change the work, not just its return path.
@test "6 the payload preserves the brief byte-for-byte and appends the trailer after it" {
  local brief out bpos tpos
  brief="$(printf 'line one\n\n  indented two\nUNIQUEMARK-9f3a\n')"
  out="$(cc_cloud_brief_payload "$B" "$brief")"
  printf '%s\n' "$out" | grep -q 'UNIQUEMARK-9f3a'
  printf '%s\n' "$out" | grep -q '  indented two'
  bpos="$(printf '%s\n' "$out" | grep -n 'UNIQUEMARK-9f3a' | head -1 | cut -d: -f1)"
  tpos="$(printf '%s\n' "$out" | grep -n 'HOW TO RETURN YOUR WORK' | head -1 | cut -d: -f1)"
  [ -n "$tpos" ]
  [ "$bpos" -lt "$tpos" ] || { echo "the trailer must come AFTER the brief, not replace it"; false; }
  # And the failure propagates: a payload cannot be composed for a branch the trailer refuses.
  run cc_cloud_brief_payload "" "$brief"
  [ "$status" -eq 2 ]
}

# ── 7: the recognisable marker both fire paths and this suite key on ──────────────────────────────
@test "7 the trailer carries CC_CLOUD_BEACON_MARK, so a silent drop is a red test not a quiet loss" {
  [ -n "$CC_CLOUD_BEACON_MARK" ]
  cc_cloud_brief_trailer "$B" | grep -q "$CC_CLOUD_BEACON_MARK"
  ! old_trailer | grep -q "$CC_CLOUD_BEACON_MARK" || false
}
