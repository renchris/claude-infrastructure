#!/usr/bin/env bats
# memory-store-snapshot.sh — local history for a memory store, kept OUTSIDE the store.
#
# Idea: arXiv 2605.04897 / TrueMemory; independent implementation, no TrueMemory code.
# Design: docs/research/truememory-2026-09-27.md § 3.11.
#
# What these pin, in the order the design argues it: the gitdir is OUTSIDE the store and the store
# is never written; an unchanged tree makes no commit; scratch files are not history; one physical
# store is one history whichever path reached it (worktree/account symlinks, and a store that
# config-mirror moved and replaced with a symlink); the commit is lock-free (a stale index.lock
# cannot block it, concurrent runs cannot lose a commit); a remote is refused; and the two
# callers — the rotor and SessionStart — can never be failed by it.
#
# Every case runs with a temp HOME and a temp history root. Assertions are simple commands only.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SNAP="$REPO/scripts/memory-store-snapshot.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_MEMORY_HISTORY_ROOT="$BATS_TEST_TMPDIR/hist"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  unset CLAUDE_CONFIG_DIR CLAUDE_PROJECT_DIR
  ST="$BATS_TEST_TMPDIR/store"; mkdir -p "$ST"
  printf '# Memory\n- [a](a.md) — hook\n' >"$ST/MEMORY.md"
  printf 'body a\n' >"$ST/a.md"
}

has() { printf '%s' "$1" | grep -qF -- "$2"; }
gitdir() { printf '%s' "$1" | sed -n 's/.*gitdir=\([^ ]*\).*/\1/p'; }
ncommits() { git --git-dir="$1" rev-list --count refs/heads/main; }
one_verdict_line() { # exactly one line, and it is a verdict line
  [ "$(printf '%s\n' "$1" | wc -l | tr -d ' ')" -eq 1 ]
  printf '%s' "$1" | grep -Eq '^verdict=(snapshotted|unchanged|contended|refused|error) store=[^ ]+ sha=[^ ]+ reason=[^ ]+'
}

@test "first snapshot: commits the store into a bare gitdir outside it" {
  run bash "$SNAP" "$ST" first
  [ "$status" -eq 0 ]
  one_verdict_line "$output"
  has "$output" 'verdict=snapshotted'
  G="$(gitdir "$output")"
  # The name is a CONTRACT (memory-fleet-sweep derives it): pwd -P with every `/` → `-`, dots kept.
  [ "$G" = "$CC_MEMORY_HISTORY_ROOT/$(cd "$ST" && pwd -P | tr '/' '-').git" ]
  mkdir -p "$BATS_TEST_TMPDIR/.dot/memory"; : >"$BATS_TEST_TMPDIR/.dot/memory/x.md"
  run bash "$SNAP" "$BATS_TEST_TMPDIR/.dot/memory" dotted
  has "$output" "$(cd "$BATS_TEST_TMPDIR" && pwd -P | tr '/' '-')-.dot-memory.git"
  [ "$(git --git-dir="$G" rev-parse --is-bare-repository)" = true ]
  git --git-dir="$G" show main:a.md | grep -qx 'body a'
  git --git-dir="$G" log -1 --format=%s main | grep -q '^first '
}

@test "unchanged tree makes no commit; a change makes one whose tree carries it" {
  run bash "$SNAP" "$ST" one; G="$(gitdir "$output")"
  run bash "$SNAP" "$ST" two
  has "$output" 'verdict=unchanged'
  [ "$(ncommits "$G")" -eq 1 ]
  printf 'body b\n' >"$ST/b.md"; rm "$ST/a.md"
  run bash "$SNAP" "$ST" three
  has "$output" 'verdict=snapshotted'
  [ "$(ncommits "$G")" -eq 2 ]
  git --git-dir="$G" show main:b.md | grep -qx 'body b'
  if git --git-dir="$G" cat-file -e main:a.md 2>/dev/null; then return 1; fi
  git --git-dir="$G" show main~1:a.md | grep -qx 'body a'    # the pre-image is restorable
}

@test "scratch is not history: lock dir, cited scratch, *.tmp, .MEMORY.md.* temps are excluded" {
  mkdir "$ST/.rotate.lock.d"; : >"$ST/.rotate.lock.d/x"
  : >"$ST/.rotate.cited.AbC123"; : >"$ST/foo.tmp"; : >"$ST/.MEMORY.md.rotate.Q1w2E3"
  mkdir -p "$ST/archive"; : >"$ST/archive/.rotate.cited.zz"; printf 'cold\n' >"$ST/archive/COLD.md"
  run bash "$SNAP" "$ST" scratch; G="$(gitdir "$output")"
  files="$(git --git-dir="$G" ls-tree -r --name-only main)"
  [ "$files" = "$(printf 'MEMORY.md\na.md\narchive/COLD.md')" ]
}

@test "a store reached through a symlink maps to the same gitdir" {
  run bash "$SNAP" "$ST" direct; G1="$(gitdir "$output")"
  ln -s "$ST" "$BATS_TEST_TMPDIR/via-link"
  run bash "$SNAP" "$BATS_TEST_TMPDIR/via-link" linked
  has "$output" 'verdict=unchanged'
  [ "$(gitdir "$output")" = "$G1" ]
  [ "$(find "$CC_MEMORY_HISTORY_ROOT" -maxdepth 1 -name '*.git' | wc -l | tr -d ' ')" -eq 1 ]
}

@test "config-mirror adopt: a store moved and replaced by a symlink keeps ONE history" {
  run bash "$SNAP" "$ST" before-move; G1="$(gitdir "$output")"; first="$(git --git-dir="$G1" rev-parse main)"
  mv "$ST" "$BATS_TEST_TMPDIR/moved"; ln -s "$BATS_TEST_TMPDIR/moved" "$ST"
  printf 'after\n' >>"$ST/a.md"
  # The rotor passes the PHYSICAL path, so adoption must work from that side too.
  run bash "$SNAP" "$BATS_TEST_TMPDIR/moved" after-move
  has "$output" 'verdict=snapshotted'
  G2="$(gitdir "$output")"
  [ "$G2" != "$G1" ]
  [ ! -e "$G1" ]
  [ "$(find "$CC_MEMORY_HISTORY_ROOT" -maxdepth 1 -name '*.git' | wc -l | tr -d ' ')" -eq 1 ]
  [ "$(git --git-dir="$G2" rev-parse main~1)" = "$first" ]
  run bash "$SNAP" "$ST" via-old-path
  has "$output" 'verdict=unchanged'
  [ "$(gitdir "$output")" = "$G2" ]
}

@test "a stale index.lock in the gitdir does not block: the index is a temp file" {
  run bash "$SNAP" "$ST" one; G="$(gitdir "$output")"
  : >"$G/index.lock"; : >"$G/index"
  printf 'more\n' >>"$ST/a.md"
  run bash "$SNAP" "$ST" two
  has "$output" 'verdict=snapshotted'
  [ "$(ncommits "$G")" -eq 2 ]
}

@test "CAS race: concurrent snapshots each print a valid verdict and the ref stays consistent" {
  run bash "$SNAP" "$ST" seed; G="$(gitdir "$output")"
  for i in 1 2 3 4 5 6; do
    printf 'n%s\n' "$i" >"$ST/n$i.md"
    bash "$SNAP" "$ST" "race$i" >"$BATS_TEST_TMPDIR/out.$i" &
  done
  wait
  for i in 1 2 3 4 5 6; do one_verdict_line "$(cat "$BATS_TEST_TMPDIR/out.$i")"; done
  git --git-dir="$G" fsck --no-dangling --no-progress >/dev/null 2>&1
  # Linear history: every commit has at most one parent, and none was lost off the ref.
  [ -z "$(git --git-dir="$G" rev-list --min-parents=2 main)" ]
  snaps="$(cat "$BATS_TEST_TMPDIR"/out.* | grep -c 'verdict=snapshotted')"
  [ "$(ncommits "$G")" -eq $(( snaps + 1 )) ]
  # A quiet follow-up sees the final state already recorded or records it; either way it is whole.
  run bash "$SNAP" "$ST" settle
  [ "$(git --git-dir="$G" ls-tree -r --name-only main | grep -c '^n')" -eq 6 ]
}

@test "a gitdir with a remote is refused and nothing is committed" {
  run bash "$SNAP" "$ST" one; G="$(gitdir "$output")"
  git --git-dir="$G" remote add origin https://example.invalid/x.git
  printf 'more\n' >>"$ST/a.md"
  run bash "$SNAP" "$ST" two
  [ "$status" -eq 0 ]
  one_verdict_line "$output"
  has "$output" 'verdict=refused'
  has "$output" 'reason=has-remote'
  [ "$(ncommits "$G")" -eq 1 ]
}

@test "the store is byte-identical afterwards and gains no .git, lock or temp" {
  mkdir -p "$ST/archive"; printf 'x\n' >"$ST/archive/c.md"
  before="$(cd "$ST" && find . -print0 | sort -z | xargs -0 ls -ld | awk '{print $1, $5, $NF}'; cd "$ST" && find . -type f -print0 | sort -z | xargs -0 shasum)"
  run bash "$SNAP" "$ST" one
  run bash "$SNAP" "$ST" two
  after="$(cd "$ST" && find . -print0 | sort -z | xargs -0 ls -ld | awk '{print $1, $5, $NF}'; cd "$ST" && find . -type f -print0 | sort -z | xargs -0 shasum)"
  [ "$before" = "$after" ]
  [ ! -e "$ST/.git" ]
}

@test "bad input still exits 0 with exactly one verdict line" {
  run bash "$SNAP" "$BATS_TEST_TMPDIR/nope" x
  [ "$status" -eq 0 ]; one_verdict_line "$output"; has "$output" 'verdict=error'
  run bash "$SNAP" --bogus
  [ "$status" -eq 0 ]; one_verdict_line "$output"
}

# ── the rotor: pre-image inside its lock, and never failed by the snapshot ────────────────────
rotor_env() {
  export MEMORY_INDEX_LIMIT=3000 MEMORY_ROTATE_AT=1500 MEMORY_ROTATE_TARGET=1000
  export MEMORY_ROTATE_MIN_KEEP=2 MEMORY_ROTATE_TAIL_GUARD=1 MEMORY_ROTATE_MIN_AGE_DAYS=7
  M="$BATS_TEST_TMPDIR/proj/memory"; mkdir -p "$M"
  printf '# Memory — fixture\n' >"$M/MEMORY.md"
  local i x; x="$(head -c 140 /dev/zero | tr '\0' x)"
  for i in 01 02 03 04 05 06 07 08 09 10; do   # same shape as tests/cc-memory-rotate.bats mkbulk
    printf -- '- [a%s](a%s.md) — %s\n' "$i" "$i" "$x" >>"$M/MEMORY.md"
    printf -- '---\nname: a%s\ndescription: d\nmetadata:\n  type: project\n---\nbody\n' "$i" >"$M/a$i.md"
    touch -t 202601011200 "$M/a$i.md"
  done
}

@test "rotor: the snapshot is the PRE-image of the rotation, taken once" {
  rotor_env
  pre="$(shasum <"$M/MEMORY.md")"
  run "$REPO/bin/cc-memory-rotate" "$M/MEMORY.md"
  [ "$status" -eq 0 ]
  has "$output" 'verdict=rotated'
  if has "$output" 'verdict=snapshotted'; then return 1; fi      # its line never reaches our stdout
  G="$(find "$CC_MEMORY_HISTORY_ROOT" -maxdepth 1 -name '*.git')"
  [ "$(ncommits "$G")" -eq 1 ]
  git --git-dir="$G" log -1 --format=%s main | grep -q '^cc-memory-rotate:rotate '
  [ "$(git --git-dir="$G" show main:MEMORY.md | shasum)" = "$pre" ]
}

@test "rotor: a snapshot that fails or prints garbage changes neither verdict nor exit code" {
  rotor_env
  R="$BATS_TEST_TMPDIR/fakerepo"; mkdir -p "$R/bin" "$R/hooks/lib" "$R/scripts"
  cp "$REPO/bin/cc-memory-rotate" "$R/bin/"
  cp "$REPO/hooks/lib/memory-index-measure.sh" "$R/hooks/lib/"
  printf '#!/bin/bash\necho garbage; echo verdict=snapshotted; echo >&2 boom; exit 7\n' >"$R/scripts/memory-store-snapshot.sh"
  ln -s "$R/bin/cc-memory-rotate" "$BATS_TEST_TMPDIR/rotor-link"   # deref path, as live
  run "$BATS_TEST_TMPDIR/rotor-link" "$M/MEMORY.md"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 1 ]
  has "$output" 'verdict=rotated'
  if has "$output" 'garbage'; then return 1; fi
  rm "$R/scripts/memory-store-snapshot.sh"                          # missing entirely
  rotor_env; rm -rf "$M/archive"
  run "$BATS_TEST_TMPDIR/rotor-link" "$M/MEMORY.md"
  [ "$status" -eq 0 ]
  has "$output" 'verdict=rotated'
}

# ── SessionStart: detached trigger, resolved through the hook's dereferenced path ─────────────
wait_for_line() { # file pattern
  local n=0
  while [ "$n" -lt 50 ]; do
    grep -q -- "$2" "$1" 2>/dev/null && return 0
    perl -e 'select(undef,undef,undef,0.2)'; n=$(( n + 1 ))
  done
  return 1
}

@test "session-start through a symlinked hook path snapshots the session's store and logs it" {
  mkdir -p "$HOME/.claude/logs" "$BATS_TEST_TMPDIR/proj2" "$BATS_TEST_TMPDIR/links"
  P="$(cd "$BATS_TEST_TMPDIR/proj2" && pwd -P)"
  S="$HOME/.claude/projects/$(printf '%s' "$P" | tr '/.' '--')/memory"
  mkdir -p "$S"; printf 'x\n' >"$S/MEMORY.md"
  ln -s "$REPO/hooks/session-start.sh" "$BATS_TEST_TMPDIR/links/session-start.sh"
  cd "$BATS_TEST_TMPDIR"
  run bash -c 'printf "{\"cwd\":\"%s\",\"session_id\":\"sid-1\"}" "$1" | SS_MISSION_TIMEOUT_BIN= bash "$2"' _ "$P" "$BATS_TEST_TMPDIR/links/session-start.sh"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null
  L="$HOME/.claude/state/memory-snapshot.log"
  wait_for_line "$L" 'session-start:memory-snapshot verdict=snapshotted'
  has "$(cat "$L")" "store=$(cd "$S" && pwd -P)"
  wait_for_line "$CC_IDL" '"hook":"session-start:memory-snapshot"'
  jq -e 'select(.hook=="session-start:memory-snapshot") | .disposition=="fired" and .sid=="sid-1"' "$CC_IDL" >/dev/null
}

@test "session-start: a project with no store logs a quiet no-store, not a failure" {
  mkdir -p "$HOME/.claude/logs" "$BATS_TEST_TMPDIR/bare"
  cd "$BATS_TEST_TMPDIR"
  run bash -c 'printf "{\"cwd\":\"%s\"}" "$1" | SS_MISSION_TIMEOUT_BIN= bash "$2"' _ "$BATS_TEST_TMPDIR/bare" "$REPO/hooks/session-start.sh"
  [ "$status" -eq 0 ]
  wait_for_line "$HOME/.claude/state/memory-snapshot.log" 'reason=no-store'
  wait_for_line "$CC_IDL" 'no-store'
  jq -e 'select(.hook=="session-start:memory-snapshot") | .disposition=="abstained"' "$CC_IDL" >/dev/null
  [ ! -d "$CC_MEMORY_HISTORY_ROOT" ] || [ -z "$(ls "$CC_MEMORY_HISTORY_ROOT")" ]
}
