#!/usr/bin/env bats
# gitattributes-union-merge — the `merge=union` driver for the always-loaded rules file must
# actually FIRE, and it must fire on REBASE.
#
# WHY THIS TEST EXISTS. `.claude/rules/agent-operating-lessons.md` is appended by every
# session's memory rotor (bin/cc-memory-rotate:502 routes demotion pointers there because that
# file has no 25,000-char cap), in that session's own worktree, and then rebase-landed — so
# every branch collides on the same end-of-file hunk. Measured 2026-09-09: five consecutive
# rebase conflicts on this one file, ending in a DROPPED rotor commit of 26 pointer stubs.
# `.gitattributes` now carries `merge=union` for it.
#
# WHY IT IS SHAPED AS A RED-PROOF. A merge driver that is configured but does not fire is worse
# than none, because it silently restores the conflict everyone believes is fixed — and nothing
# about a passing green arm alone can tell "the driver resolved it" from "these two appends
# never conflicted in the first place". So the control arm (attribute ABSENT, everything else
# byte-identical) must go RED, and it is asserted, not assumed.
#
# Harness laws: L1 the two arms differ in EXACTLY ONE thing — the presence of the
# `.gitattributes` line; L2 both arms are hermetic (GIT_CONFIG_GLOBAL/SYSTEM=/dev/null, rerere
# explicitly off) so the operator's global `rerere.enabled=true` and any global merge driver
# cannot decide the result; L3 the exercise is `git rebase`, not `git merge` — the observed
# failure is a rebase, and that is the half that matters; L4 the green arm asserts NO conflict
# markers as well as rc 0, because a conflicted file still contains both sides' text and would
# pass a naive "both lines present" check.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  TARGET='.claude/rules/agent-operating-lessons.md'
  # Hermetic, and this is load-bearing rather than hygiene: git resolves attributes from
  # `$XDG_CONFIG_HOME/git/attributes` (default `$HOME/.config/git/attributes`) and from
  # core.attributesFile, so an ambient global attributes file could hand the RED control arm the
  # very `merge=union` it must LACK — silently turning the control green and vacuuming the proof.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export XDG_CONFIG_HOME="$HOME/.config"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
  export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
}

# Build a throwaway scratch repo reproducing the real collision: two sessions each appending one
# line to the tail of the rules file, from a common base. $2 = attr | noattr is the ONLY variable.
build_scratch() {
  local r="$1" mode="$2"
  mkdir -p "$r"
  git -C "$r" init -q -b main
  git -C "$r" config rerere.enabled false
  mkdir -p "$r/$(dirname "$TARGET")"
  printf '%s\n' '# Always-loaded project rules' '' >"$r/$TARGET"
  if [ "$mode" = attr ]; then
    printf '%s\n' "$TARGET merge=union" >"$r/.gitattributes"
    git -C "$r" add .gitattributes
  fi
  git -C "$r" add "$TARGET"
  git -C "$r" commit -qm base
  git -C "$r" checkout -q -b sessionA
  printf '%s\n' '- LESSON-FROM-A' >>"$r/$TARGET"
  git -C "$r" commit -qam a
  git -C "$r" checkout -q -b sessionB main
  printf '%s\n' '- LESSON-FROM-B' >>"$r/$TARGET"
  git -C "$r" commit -qam b
}

# THE CONTROL. Without the attribute the rebase MUST fail — if this ever goes green the green arm
# below proves nothing, because the scenario stopped being a conflict at all.
@test "red control: without merge=union the rebase of two divergent appends CONFLICTS" {
  R="$BATS_TEST_TMPDIR/noattr"
  build_scratch "$R" noattr
  run git -C "$R" rebase sessionA
  [ "$status" -ne 0 ]
  grep -q '<<<<<<<' "$R/$TARGET"
  git -C "$R" rebase --abort
}

@test "green: with merge=union the same rebase completes clean and keeps BOTH lines" {
  R="$BATS_TEST_TMPDIR/attr"
  build_scratch "$R" attr
  run git -C "$R" rebase sessionA
  [ "$status" -eq 0 ]
  ! grep -q '<<<<<<<' "$R/$TARGET" || false
  grep -q 'LESSON-FROM-A' "$R/$TARGET"
  grep -q 'LESSON-FROM-B' "$R/$TARGET"
}

# The deliverable itself: the line must be in the real repo AND the pattern must actually MATCH
# the path. `check-attr` is the discriminating check — a typo'd path passes a grep and resolves
# to `unspecified` here, which is the silent-no-op failure this whole file exists to prevent.
@test "the repo's .gitattributes resolves merge=union for the rules file" {
  run git -C "$REPO" check-attr merge -- .claude/rules/agent-operating-lessons.md
  [ "$status" -eq 0 ]
  [[ "$output" == *": merge: union" ]]
}
