#!/usr/bin/env bats
# reaper-horizon-lint — the gate had NO test of its own until now (its DUAL, growth-coverage-lint,
# shipped with one). This covers §5, the anchor resolver added by item 74a0896ee989, plus a §1 case
# so the scorer that gate exists for cannot be broken silently by an edit to the declaration block.
#
# WHY §5 NEEDS A TEST MORE THAN THE SCORERS DO. §1-§2b fail loudly when they break: a horizon stops
# being scored and the `ok` line disappears. §5 fails SILENTLY in one specific way — if it cannot
# read its own `@anchor` lines it finds zero anchors, reports nothing, and exits 0. That is a green
# gate over an unread declaration block, which is the exact blind-spot shape §3's header forbids
# ("a detector with a blind spot is the bug it exists to prevent"). Test 7 is the positive control
# for that branch and is the reason $SELF is resolved before the script's `cd ..`.
#
# Harness laws (adopted from tests/growth-coverage-lint.bats): L1 the fixture is a real tree driven
# through a COPY OF THE REAL SCRIPT, never a hand-written approximation — an approximation passes
# vacuously (memory: control-must-replay-the-real-artifact); L2 every assertion is failure-distinct,
# so the same fixture that RED-proves a branch goes green once the defect is undone; L3 `[ ]` /
# `grep -q` only; L4 the silent-blindness path is tested, not just the loud ones.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # Non-$HOME seams. This suite names bin/cc-recover-safeguard (it is one of the four anchored
  # files), and that script resolves two helpers by BARE NAME off PATH — `cc-sessions` and
  # `cc-notify`. Fixturing $HOME does not redirect a bare name, so the test-hermeticity ratchet
  # requires them pinned. Pointed at ABSENT paths deliberately: this suite only ever WRITES a stub
  # at that path and never executes the real script, and both helpers fail open on a missing
  # binary — so if a future edit does reach them, it reaches nothing of the operator's.
  export CC_RECOVER_SESSIONS_BIN="$BATS_TEST_TMPDIR/absent-cc-sessions"
  export CC_RECOVER_NOTIFY_BIN="$BATS_TEST_TMPDIR/absent-cc-notify"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FIX="$BATS_TEST_TMPDIR/fix"
  mkdir -p "$FIX/scripts" "$FIX/hooks" "$FIX/bin"
  # L1: the REAL gate, copied. Its `cd "$(dirname "$0")/.."` then lands in $FIX, so every grep it
  # runs reads the fixture tree and nothing of the live repo.
  LINT="$FIX/scripts/reaper-horizon-lint.sh"
  cp "$REPO/scripts/reaper-horizon-lint.sh" "$LINT"
  # Stubs carrying each anchored symbol AS CODE. Only ANCHORED files need to exist; the rest of
  # $DECLARED is absent by design and the scorers correctly find nothing to bound in it.
  #
  # ⚠️ THIS SET IS COUPLED TO THE GATE'S @anchor BLOCK, and the coupling is invisible from the other
  # side. Adding an `# @anchor <file> <ERE>` to reaper-horizon-lint.sh WITHOUT adding a stub here
  # makes §5 report "names a file that no longer exists", which reds THREE tests in this suite
  # (baseline, the L2 control, and the L4 relative-path control) — a correct anchor red-proved by a
  # harness gap rather than by its subject. That is exactly what happened when scripts/cc-gc.sh was
  # anchored on 2026-08-12 (backlog 6cab0ab3cb2f): all four of its anchors resolved against the live
  # tree, the gate's own output said so, and the suite failed anyway, because THE FIXTURE IS NOT THE
  # TREE. If you anchor a new file, stub it below in the same commit.
  printf '%s\n' 'find "$D" \( -name "*.pending" \) -mtime +7 -delete' 'rm -f "$PENDING"' \
    > "$FIX/hooks/dispatch-assert.sh"
  printf '%s\n' 'STALE_MARKER_MAX_AGE_S="${DESK_INVARIANT_MARKER_MAX_AGE_S:-604800}"' \
    'sweep_stale_markers() { rm -f "$f"; }' > "$FIX/scripts/desk-invariant.sh"
  printf '%s\n' 'REWORDED="$(mktemp)"' 'rm -f "$REWORDED"' > "$FIX/bin/cc-recover-safeguard"
  printf '%s\n' 'gc_teardown_marker() { :; }' 'rm -f "$W/$sid.daemon"' \
    > "$FIX/hooks/lead-crash-watchdog.sh"
  # cc-gc's four anchors: the 30 d strand horizon, the archive-instead-of-delete site that makes
  # unacked mail evidence rather than litter, the identity-pinned watchdog age, and the dry-run
  # default that keeps a scheduled run harmless without --apply.
  printf '%s\n' 'MBX_STRAND_DAYS="${CC_GC_MBX_STRAND_DAYS:-30}"' \
    'WD_AGE_S="${CC_GC_WATCHDOG_AGE_S:-172800}"' \
    'APPLY=0' \
    'mv -f "$MBX_DIR/$key.md" "$MBX_DIR/archive/$key.md"' \
    'rm -f "$WD_DIR/$sid.pid"' > "$FIX/scripts/cc-gc.sh"
}

# ── the baseline every red below is measured against ───────────────────────────────────────────
@test "baseline: every anchor resolves and the gate is clean" {
  run bash "$LINT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "clean"
  echo "$output" | grep -q "anchor /gc_teardown_marker/ resolves"
}

# ── §5: the rot this item measured ─────────────────────────────────────────────────────────────
@test "a RENAMED symbol fails the gate — the justification now describes code that is gone" {
  printf '%s\n' 'reap_teardown_marker() { :; }' 'rm -f "$W/$sid.daemon"' \
    > "$FIX/hooks/lead-crash-watchdog.sh"
  run bash "$LINT"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "NO LONGER RESOLVES IN CODE"
  echo "$output" | grep -q "lead-crash-watchdog"
}

@test "L2 control: restoring that symbol clears the gate again" {
  printf '%s\n' 'reap_teardown_marker() { :; }' > "$FIX/hooks/lead-crash-watchdog.sh"
  run bash "$LINT"
  [ "$status" -eq 1 ]
  printf '%s\n' 'gc_teardown_marker() { :; }' 'rm -f "$W/$sid.daemon"' \
    > "$FIX/hooks/lead-crash-watchdog.sh"
  run bash "$LINT"
  [ "$status" -eq 0 ]
}

@test "an anchor satisfied ONLY by a comment is still RED" {
  # The sharpest case. §3 once convicted two files whose only tie to an evidence artifact was a
  # comment; an anchor that a comment could satisfy would re-open that hole from the other side —
  # prose about the code would stand in for the code. A check must observe the thing it guards.
  printf '%s\n' '# gc_teardown_marker lives here in prose only' 'rm -f "$W/$sid.daemon"' \
    > "$FIX/hooks/lead-crash-watchdog.sh"
  run bash "$LINT"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "NO LONGER RESOLVES IN CODE"
}

@test "an anchored file that no longer exists fails the gate" {
  rm -f "$FIX/bin/cc-recover-safeguard"
  run bash "$LINT"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "no longer exists"
}

@test "a malformed anchor fails rather than being skipped" {
  # An unparseable anchor must never be silently dropped: a dropped anchor is an unchecked
  # justification wearing a green gate's clothes.
  sed -i.bak 's|^# @anchor bin/cc-recover-safeguard REWORDED$|# @anchor bin/cc-recover-safeguard|' "$LINT"
  run bash "$LINT"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "malformed @anchor"
}

@test "an anchor naming a file absent from DECLARED fails the gate" {
  sed -i.bak 's|^# @anchor bin/cc-recover-safeguard REWORDED$|&\
# @anchor bin/not-declared REWORDED|' "$LINT"
  run bash "$LINT"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "absent from"
}

# ── L4: the branch that fails SILENTLY ─────────────────────────────────────────────────────────
@test "L4 positive control: §5 still runs when invoked by a RELATIVE path from scripts/" {
  # The script cd's to its parent on line 2 of its body. A relative \$0 ("./reaper-horizon-lint.sh")
  # stops resolving after that cd, so reading the anchors from \$0 would yield NOTHING and the gate
  # would report clean having checked no declaration at all. \$SELF is resolved before the cd; this
  # asserts anchors were actually READ, never merely that the exit code was 0.
  run bash -c "cd '$FIX/scripts' && bash ./reaper-horizon-lint.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "anchor /gc_teardown_marker/ resolves"
}

# ── §1: the horizon scorer the gate exists for ─────────────────────────────────────────────────
@test "a horizon under the floor still fails — the declaration block did not break the scorer" {
  printf '%s\n' 'find "$D" -mmin +5 -delete' > "$FIX/hooks/dispatch-assert.sh"
  run bash "$LINT"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "300s"
  echo "$output" | grep -q "supervisor would MISS this evidence"
}
