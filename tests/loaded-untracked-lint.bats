#!/usr/bin/env bats
# loaded-untracked-lint — the RATCHET that stops a file the HARNESS AUTO-LOADS from living outside git.
#
# THE SCAR (backlog b7e127506fda, 2026-09-08). `.claude/rules/agent-operating-lessons.md` was injected
# into every interactive session in this repo under the harness's own label "project instructions,
# checked into the codebase", while `git ls-tree -r origin/main -- .claude/rules` listed ZERO files and
# `git check-ignore` returned rc 1. It was neither tracked nor ignored: 8,165 bytes of always-loaded
# policy that one `git clean -f -d` would have deleted with no diff and no trace. `.claude/` was
# already a TRACKED directory (CLAUDE.md, settings.json, commands/ship.md) with one unprotected child,
# which is why nobody looked.
#
# Harness laws: L1 the fixtures are real git repos driven through the real script — no stubbing of
# git's own ignore resolution, because git IS the predicate; L2 every assertion is failure-distinct
# (the untracked rules file FAILS and the same file tracked PASSES, so neither "always red" nor
# "always green" survives); L3 `[ ]` / `grep -q` only; L4 the fail-closed path is tested, because a
# lint that reports health when it cannot read its subject is worse than no lint.
#
# HERMETICITY. Every fixture pins BOTH git config layers at a scratch file, so the operator's real
# ~/.gitignore_global (which does contain `.claude/`) cannot decide a verdict here — and neither can
# its absence on an off-box runner. The fixtures then REPLICATE that stack deliberately, because the
# subject's true condition is a global `.claude/` ignore re-admitted by the repo's own `!.claude/`.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LINT="$REPO/scripts/loaded-untracked-lint.sh"
  # Pin the ignore stack: a scratch global that ignores .claude/, and an empty system layer.
  printf '%s\n' '.claude/' > "$BATS_TEST_TMPDIR/global-ignore"
  printf '[core]\n\texcludesFile = %s\n' "$BATS_TEST_TMPDIR/global-ignore" > "$BATS_TEST_TMPDIR/gitconfig"
  : > "$BATS_TEST_TMPDIR/gitconfig-system"
  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig"
  export GIT_CONFIG_SYSTEM="$BATS_TEST_TMPDIR/gitconfig-system"
}

mkrepo() {  # $1 = name -> echoes the repo path. No remote is ever added, so the identity pre-commit
            # hook is inert by its own documented scope; nothing here is ever committed.
  local r="$BATS_TEST_TMPDIR/$1"
  mkdir -p "$r"
  git -C "$r" init -q
  printf '%s\n' '!.claude/' '.claude/settings.local.json' > "$r/.gitignore"
  git -C "$r" add .gitignore
  printf '%s' "$r"
}

# ── fixture (i): the scar itself ────────────────────────────────────────────────────────────────
@test "a loaded-but-untracked file under .claude/rules/ fails the guard" {
  r="$(mkrepo scar)"
  mkdir -p "$r/.claude/rules"
  printf 'always-loaded policy\n' > "$r/.claude/rules/agent-operating-lessons.md"
  run bash "$LINT" "$r"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "RED"
  echo "$output" | grep -q ".claude/rules/agent-operating-lessons.md"
}

@test "the RED names the cure as a runnable git add, not a description of one" {
  r="$(mkrepo cure)"
  mkdir -p "$r/.claude/rules"
  printf 'x\n' > "$r/.claude/rules/lesson.md"
  run bash "$LINT" "$r"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "git add .claude/rules/lesson.md"
}

# ── fixture (ii): the discriminator — tracked, beside an untracked file that IS ignored ──────────
@test "the same rules file TRACKED, beside an untracked-but-ignored file, passes" {
  r="$(mkrepo tracked)"
  mkdir -p "$r/.claude/rules"
  printf 'always-loaded policy\n' > "$r/.claude/rules/agent-operating-lessons.md"
  git -C "$r" add .claude/rules/agent-operating-lessons.md
  printf '{}\n' > "$r/.claude/settings.local.json"
  run bash "$LINT" "$r"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "OK"
}

@test "an untracked file that is ignored is NOT a finding on its own" {
  r="$(mkrepo ignored)"
  mkdir -p "$r/.claude"
  printf '{}\n' > "$r/.claude/settings.local.json"
  run bash "$LINT" "$r"
  [ "$status" -eq 0 ]
}

@test "an untracked file OUTSIDE the loaded scope is not a finding (this is not a whole-repo check)" {
  r="$(mkrepo outside)"
  mkdir -p "$r/notes"
  printf 'scratch\n' > "$r/notes/scratch.md"
  run bash "$LINT" "$r"
  [ "$status" -eq 0 ]
}

@test "the root CLAUDE.md is in the loaded scope too" {
  r="$(mkrepo rootmd)"
  printf '# project rules\n' > "$r/CLAUDE.md"
  run bash "$LINT" "$r"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "CLAUDE.md"
}

# ── L4: fail-closed. An indeterminate run must be LOUD, never a silent 0 ────────────────────────
@test "a non-repo directory exits 2, not 0" {
  mkdir -p "$BATS_TEST_TMPDIR/plain"
  run bash "$LINT" "$BATS_TEST_TMPDIR/plain"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "CANNOT DETERMINE"
}

@test "a SET-BUT-EMPTY scope set exits 2 — a scope-less lint judges nothing" {
  r="$(mkrepo emptyscope)"
  mkdir -p "$r/.claude/rules"
  printf 'x\n' > "$r/.claude/rules/lesson.md"
  CC_LOADED_SCOPES="" run bash "$LINT" "$r"
  [ "$status" -eq 2 ]
}

# ── the lint's own discrimination proof ─────────────────────────────────────────────────────────
@test "--selftest passes and proves both directions" {
  run bash "$LINT" --selftest
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "7/7"
}

# ── ENFORCEMENT LIVES AT THE CHOKEPOINT, and this is the assertion that pins it there ───────────
# A lint that only its own suite invokes is DETECTION, not enforcement (memory:
# enforcement-must-live-at-the-chokepoint). run_gate is the event that IS the act.
@test "run_gate in ship-land.sh invokes the lint" {
  grep -q 'loaded-untracked-lint.sh' "$REPO/scripts/ship-land.sh"
}

@test "the nightly picks it up automatically (name matches *lint*.sh AND supports --selftest)" {
  case "$(basename "$LINT")" in *lint*.sh) ;; *) false ;; esac
  grep -q -- '--selftest' "$LINT"
}

# ── the ratchet: this repo must stay clean, which is the whole point of landing it ──────────────
@test "this repo is clean under its own lint" {
  run env -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_SYSTEM bash "$LINT" "$REPO"
  [ "$status" -eq 0 ]
}
