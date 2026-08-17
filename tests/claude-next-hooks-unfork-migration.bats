#!/usr/bin/env bats
# claude-next-hooks-unfork-migration.bats — migrations/0013, converting ~/.claude-next/hooks from a
# forked real directory into a symlink to ~/.claude/hooks (backlog 11da376d60e3).
#
# WHY THIS SUITE EXISTS. 0013 is a c10 migration: STAGED and handed to the operator to run, against
# the BUSIEST account's config dir, and its central act is replacing a directory. An operator step
# handed over untested is prescribed-remedy-worse-than-the-bug, so every assertion here EXECUTES the
# real script against a throwaway $HOME. Nothing in this file touches ~/.claude-next.
#
# THE LOAD-BEARING ONE IS THE VACUITY TRAP. The fork holds only symlinks INTO the canonical dir, and
# `cmp` follows symlinks — so a bare "every shared file is byte-identical" sweep compares a link
# against the file it points at and passes by construction, whatever the tree holds. `divergent
# symlink` below plants exactly that shape (a dst link to a DIFFERENT file) and pins that the
# migration still refuses; without it, the losslessness assertion would be a tautology wearing a
# pass.
#
# THE CONTROL THAT CAN FAIL is the live-pane pair: one ps stub reporting a claude session under the
# TARGET config dir (must refuse) and one reporting a session under a DIFFERENT config dir (must
# convert). A gate that refused on either would pass the first arm and fail the second, so "refuses
# under a live pane" cannot be satisfied by an always-refusing gate.
#
# BATS ERREXIT DISCIPLINE: a non-final `[[ ]]`, `(( ))`, `!` or `A && B` is errexit-EXEMPT and
# therefore a DEAD assertion. Every such assertion carries `|| false`; a final `[ ]` is live.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  MIG="$REPO/migrations/0013-claude-next-hooks-unfork.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  SRC="$HOME/.claude/hooks"; DSTC="$HOME/.claude-next"; DST="$DSTC/hooks"
  mkdir -p "$SRC/lib" "$DST/lib"
  printf 'canonical a\n' > "$SRC/a.sh"
  printf 'canonical b\n' > "$SRC/b.sh"          # forward gap: in the canonical dir only. Expected.
  printf 'canonical l\n' > "$SRC/lib/l.sh"
  # the fork's real shape, reduced: every entry a symlink into the canonical dir, recursively.
  ln -s "$SRC/a.sh" "$DST/a.sh"
  ln -s "$SRC/lib/l.sh" "$DST/lib/l.sh"
  export CC_SRC_CONFIG="$HOME/.claude" CC_DST_CONFIG="$DSTC"
  # default stub: one real claude session, but under ANOTHER account's config dir → 0 in-scope panes.
  ps_stub "$HOME/.claude-secondary"
}

ps_stub() { # <config-dir-to-report> … ; writes a ps replacement that emits one claude line per arg
  STUB="$BATS_TEST_TMPDIR/ps-stub.sh"
  { printf '#!/bin/bash\n'
    printf 'printf %%s\\\\n "/bin/bash -c something"\n'          # a non-claude line, always present
    for d in "$@"; do
      # argv first, environment appended after it — the real `ps -E` shape.
      printf 'printf %%s\\\\n "/Users/x/.claude/local/claude --model opus TERM=xterm CLAUDE_CONFIG_DIR=%s"\n' "$d"
    done
  } > "$STUB"
  chmod +x "$STUB"
  export CC_UNFORK_PS="$STUB"
}

@test "0013 declares its class, its operator step, the command to paste, and a verifier" {
  grep -q '^# migration-class: c10$' "$MIG" || false
  grep -q '^# migration-step: ' "$MIG" || false
  grep -q '^# migration-run: ' "$MIG" || false
  grep -q '^# migration-verify: ' "$MIG" || false
  grep -q '^# migration-conflict: ' "$MIG" || false
}

@test "0013's verifier is config-dir-invariant (a CC_CLAUDE_DIR spelling would manufacture a permanent partial)" {
  # registration-state.sh re-runs each verifier once per config dir with CC_CLAUDE_DIR re-aimed, and
  # this effect is a fact about ONE dir. Reject the per-dir spelling outright.
  run grep '^# migration-verify: ' "$MIG"
  printf '%s' "$output" | grep -q 'claude-next' || false
  printf '%s' "$output" | grep -qv 'CC_CLAUDE_DIR' || false
}

@test "0013 converts the clean case losslessly, backs the fork up, and prints the restore command" {
  run bash "$MIG"
  [ "$status" -eq 0 ]
  [ -L "$DST" ]
  [ "$(readlink "$DST")" = "$SRC" ]
  # the canonical files the fork was MISSING are now reachable through the target — the whole point.
  [ -f "$DST/b.sh" ]
  [ "$(cat "$DST/lib/l.sh")" = "canonical l" ]
  # reversible: the fork was moved, not deleted, and its entries survive in the backup.
  bak="$(echo "$DSTC"/hooks.premirror-bak.*)"
  [ -L "$bak/a.sh" ]
  printf '%s' "$output" | grep -q 'restore with: rm -f' || false
  printf '%s' "$output" | grep -q 'losslessness re-verified: 3 entries' || false
}

@test "0013's second run is a no-op, reported as such" {
  run bash "$MIG"
  [ "$status" -eq 0 ]
  run bash "$MIG"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'already — no-op' || false
  # exactly one backup: a second run must not move anything again
  # shellcheck disable=SC2012  # fixture-controlled names; find(1) would also have to exclude
  # the glob's own literal form on a no-match, which is what makes the count meaningful here
  [ "$(ls -d "$DSTC"/hooks.premirror-bak.* 2>/dev/null | wc -l | tr -d ' ')" -eq 1 ]
}

@test "0013 REFUSES when a shared regular file differs, and names it" {
  rm "$DST/a.sh"; printf 'FORK-ONLY EDIT\n' > "$DST/a.sh"
  run bash "$MIG"
  [ "$status" -eq 1 ]
  [ -d "$DST" ]                                    # untouched: still the real dir
  [ ! -L "$DST" ]
  printf '%s' "$output" | grep -q 'a.sh' || false
  printf '%s' "$output" | grep -q 'bytes differ' || false
}

@test "0013 REFUSES on a divergent SYMLINK — the arm a bare cmp sweep passes vacuously" {
  # cmp follows links, so a link-into-src is a tautology. This one points at a DIFFERENT file, which
  # a name-and-cmp check would still clear if it only ever compared dst-link against src-file.
  printf 'somewhere else entirely\n' > "$HOME/elsewhere.sh"
  rm "$DST/a.sh"; ln -s "$HOME/elsewhere.sh" "$DST/a.sh"
  run bash "$MIG"
  [ "$status" -eq 1 ]
  [ ! -L "$DST" ]
  printf '%s' "$output" | grep -q 'a.sh' || false
  printf '%s' "$output" | grep -q 'bytes differ' || false
}

@test "0013 REFUSES when the reverse gap is NON-empty, and names what would be lost" {
  printf 'only in the fork\n' > "$DST/fork-only.sh"
  run bash "$MIG"
  [ "$status" -eq 1 ]
  [ ! -L "$DST" ]
  printf '%s' "$output" | grep -q 'reverse gap is NOT empty' || false
  printf '%s' "$output" | grep -q 'fork-only.sh' || false
}

@test "0013 REFUSES under a live pane on the TARGET config dir" {
  ps_stub "$DSTC"
  run bash "$MIG"
  [ "$status" -eq 1 ]
  [ ! -L "$DST" ]
  printf '%s' "$output" | grep -q '1 live session' || false
}

@test "0013 CONTROL — a live pane on ANOTHER config dir does not block (the gate discriminates)" {
  # setup()'s stub already reports a claude session under .claude-secondary. If the gate refused on
  # any claude process at all, this arm fails while the arm above still passes — which is what makes
  # "refuses under a live pane" a measurement rather than an always-refusing constant.
  run bash "$MIG"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'live-pane gate: 0 sessions' || false
  [ -L "$DST" ]
}

@test "0013 counts a headless one-shot as NOT a pane, and an argv mention of the dir as NOT a session" {
  STUB="$BATS_TEST_TMPDIR/ps-stub.sh"
  { printf '#!/bin/bash\n'
    # headless: -p among the leading flags, real env pointing at the target
    printf 'printf %%s\\\\n "/Users/x/.claude/local/claude -p hello CLAUDE_CONFIG_DIR=%s"\n' "$DSTC"
    # a session under ANOTHER dir whose PROMPT merely mentions the target: the LAST match wins
    printf 'printf %%s\\\\n "/Users/x/.claude/local/claude fix CLAUDE_CONFIG_DIR=%s now CLAUDE_CONFIG_DIR=%s"\n' \
      "$DSTC" "$HOME/.claude-tertiary"
  } > "$STUB"
  chmod +x "$STUB"
  export CC_UNFORK_PS="$STUB"
  run bash "$MIG"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'live-pane gate: 0 sessions' || false
}

@test "0013 REFUSES on a non-verdict from the live-pane probe (never acts on absence of evidence)" {
  export CC_UNFORK_PS="/usr/bin/false"
  run bash "$MIG"
  [ "$status" -eq 1 ]
  [ ! -L "$DST" ]
  printf '%s' "$output" | grep -q 'probe could not run' || false
}

@test "0013 REFUSES when hooks is already a symlink pointing somewhere ELSE" {
  mkdir -p "$HOME/other-hooks"
  rm -r "$DST"; ln -s "$HOME/other-hooks" "$DST"
  run bash "$MIG"
  [ "$status" -eq 1 ]
  [ "$(readlink "$DST")" = "$HOME/other-hooks" ]
  printf '%s' "$output" | grep -q 'does not overwrite that' || false
}

@test "0013 exits 0 with a note when the target config dir does not exist (not a fabricated failure)" {
  export CC_DST_CONFIG="$HOME/.claude-nonesuch"
  run bash "$MIG"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'not a fleet config' || false
}

@test "0013 REFUSES when the canonical hooks dir is not a real directory" {
  rm -r "$SRC"
  run bash "$MIG"
  [ "$status" -eq 1 ]
  [ -d "$DST" ]
  printf '%s' "$output" | grep -q 'not a real directory' || false
}

@test "0013 converts under a live pane when CC_UNFORK_ALLOW_LIVE=1 is passed explicitly" {
  ps_stub "$DSTC"
  CC_UNFORK_ALLOW_LIVE=1 run bash "$MIG"
  [ "$status" -eq 0 ]
  [ -L "$DST" ]
  printf '%s' "$output" | grep -q 'CC_UNFORK_ALLOW_LIVE=1' || false
}
