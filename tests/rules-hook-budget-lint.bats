#!/usr/bin/env bats
# rules-hook-budget-lint.sh — the always-loaded rules file must stay a HOOK tier.
#
# Each case is red-proved: the fixture it uses fails on a lint mutated to drop that arm. The
# NON-VERDICT arm matters most — a lint whose anchor stops matching must say so rather than
# report a clean file, because a silent 0 here is a permanently un-gated always-loaded surface.

setup() {
  # Hermetic: the lint reads only the file it is given, but a suite that leaves $HOME ambient
  # can never PROVE that — and two concurrent runs would share the operator's live ~/.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  LINT="$REPO/scripts/rules-hook-budget-lint.sh"
  TMP="$BATS_TEST_TMPDIR"
}

@test "selftest passes and exercises all four arms" {
  run "$LINT" --selftest
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"PASS (4 arms)"* ]] || false
}

@test "a well-formed hook is clean" {
  printf '# r\n\n- [Ok](../../docs/lessons/a.md) — a hook that states its rule.\n' > "$TMP/f.md"
  run "$LINT" --file "$TMP/f.md"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"clean"* ]] || false
}

@test "a bodyless bullet is REFUSED and its line is named" {
  printf '# r\n\n- [Ok](../../docs/lessons/a.md) — fine.\n- [Bad](.) — pasted whole.\n' > "$TMP/f.md"
  run "$LINT" --file "$TMP/f.md"
  [ "$status" -eq 1 ] || false
  [[ "$output" == *":4: BODYLESS"* ]] || false
}

@test "an over-budget bullet is REFUSED and its size is named" {
  { printf '# r\n\n- [Fat](../../docs/lessons/b.md) — '
    awk 'BEGIN{for(i=0;i<500;i++)printf "x"}'; printf '\n'; } > "$TMP/f.md"
  run "$LINT" --file "$TMP/f.md"
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"OVER BUDGET"* ]] || false
}

@test "a file the anchor cannot parse is a NON-VERDICT, never a pass" {
  printf '# r\n\nprose only, no bullets\n' > "$TMP/f.md"
  run "$LINT" --file "$TMP/f.md"
  [ "$status" -eq 2 ] || false
  [[ "$output" == *"NON-VERDICT"* ]] || false
}

@test "a missing file is a NON-VERDICT, never a pass" {
  run "$LINT" --file "$TMP/does-not-exist.md"
  [ "$status" -eq 2 ] || false
}

@test "prose bullets and the header are not judged as lessons" {
  printf '# r\n\nsome header prose that is very long %s\n\n- [Ok](../../docs/lessons/a.md) — fine.\n' \
    "$(awk 'BEGIN{for(i=0;i<600;i++)printf "y"}')" > "$TMP/f.md"
  run "$LINT" --file "$TMP/f.md"
  [ "$status" -eq 0 ] || false
}

# The live file must remain PARSEABLE, not globally clean. Asserting cleanliness here would
# contradict the own-scope design one screen down: the gate blocks only on lines a land ADDS, so a
# pre-existing bodyless bullet is legitimate and persistent by construction. That assertion was
# tried and it went red the moment a sibling landed an untiered lesson onto trunk while this branch
# was gating — a content event in someone else's diff, surfacing as a failure in this suite. What
# genuinely must never happen is the anchor drifting off the file's bullet shape, because a lint
# that parses 0 bullets would silently un-gate an always-loaded surface while reporting success.
# rc 2 is the only forbidden answer; 0 and 1 are both real verdicts.
@test "the live rules file still PARSES — rc 2 would mean the anchor has drifted" {
  run "$LINT" --file "$REPO/.claude/rules/agent-operating-lessons.md"
  [ "$status" -ne 2 ] || false
  [[ "$output" != *"NON-VERDICT"* ]] || false
  [[ "$output" == *"bullet(s)"* ]] || false
}

# -- own-scope: block on what THIS land added, report the rest ------------------------------------
# Fixture is a real two-commit repo: the BASE already carries a sibling bodyless bullet, HEAD adds
# one of our own. Without --own-range both are blocking; with it, only ours is. This is the case the
# lint's first live run got wrong, so it is pinned. Identity is passed transiently (git -c ...) so
# it can never persist into a shared .git/config.
_own_fixture() {  # -> echoes the repo dir
  local d="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$d/.claude/rules"
  git -C "$BATS_TEST_TMPDIR/repo" init -q
  printf '# r\n\n- [Sib](.) - a sibling bullet already on the base.\n' > "$d/.claude/rules/x.md"
  git -C "$BATS_TEST_TMPDIR/repo" add -A
  git -C "$BATS_TEST_TMPDIR/repo" -c user.email=t@t -c user.name=t commit -qm base
  printf '# r\n\n- [Sib](.) - a sibling bullet already on the base.\n- [Mine](.) - added by this land.\n' > "$d/.claude/rules/x.md"
  git -C "$BATS_TEST_TMPDIR/repo" add -A
  git -C "$BATS_TEST_TMPDIR/repo" -c user.email=t@t -c user.name=t commit -qm head
  echo "$d"
}

@test "without --own-range both the sibling and our bullet block" {
  d="$(_own_fixture)"
  run "$LINT" --file "$d/.claude/rules/x.md"
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"bodyless=2"* ]] || false
}

@test "with --own-range only OUR added line blocks; the sibling is advisory" {
  d="$(_own_fixture)"
  cd "$d"
  run "$LINT" --file ".claude/rules/x.md" --own-range "HEAD~1..HEAD"
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"bodyless=1"* ]] || false
  [[ "$output" == *"advisory: "* ]] || false
}

@test "a land that adds NOTHING to the file is not convicted for the sibling bullet" {
  d="$(_own_fixture)"
  cd "$d"
  run "$LINT" --file ".claude/rules/x.md" --own-range "HEAD..HEAD"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"advisory"* ]] || false
}

@test "an unreadable range is a NON-VERDICT, never an all-advisory pass" {
  printf '# r\n\n- [Bad](.) - x.\n' > "$TMP/f.md"
  cd "$TMP"
  run "$LINT" --file "f.md" --own-range "no-such-ref..HEAD"
  [ "$status" -eq 2 ] || false
  [[ "$output" == *"NON-VERDICT"* ]] || false
}

# -- duplicate link targets: one rule resident twice -----------------------------------------------
# Found live, twice over: a rebase re-introduced three already-tiered lessons, and one pair predated
# the land. Always blocking (never own-scoped) because a duplicate is a property of the PAIR.
@test "two bullets linking one body are REFUSED" {
  printf '# r\n\n- [A](../../docs/lessons/x.md) - one.\n- [B](../../docs/lessons/x.md) - two.\n' > "$TMP/f.md"
  run "$LINT" --file "$TMP/f.md"
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"DUPLICATE"* ]] || false
}

@test "distinct bodies are not flagged as duplicates" {
  printf '# r\n\n- [A](../../docs/lessons/x.md) - one.\n- [B](../../docs/lessons/y.md) - two.\n' > "$TMP/f.md"
  run "$LINT" --file "$TMP/f.md"
  [ "$status" -eq 0 ] || false
}
