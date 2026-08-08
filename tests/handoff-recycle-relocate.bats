#!/usr/bin/env bats
# handoff-fire.sh --recycle + --worktree/--cwd: the RELOCATING recycle (2026-08-08).
#
# WHY THIS EXISTS. `--recycle` refused --worktree/--cwd outright ("same pane = same dir"), which made
# ♻️ Recycle structurally unreachable for the commonest long-horizon succession: wave N finishes,
# wave N+1 needs a FRESH worktree off origin/main. The close protocol then routed that to 📤 Handoff
# — a NEW pane — purely because recycle could not express it, leaving the predecessor as an idle
# orphan that an ORIGIN session is (deliberately) forbidden from self-closing. Measured on
# TENANT_PROVISIONING_100P wave 5: pane 427 fired the wave lead, ran `self-close --successor 756`,
# was correctly refused, and idled from 05:39 onward holding nothing.
#
# Exercised through --dry-run with an explicit --launcher (no iTerm2, no account ranking, no spawn).
# --dry-run prints the composed command and executes nothing, so the assertions below are about the
# COMMAND the pane would be given — which is exactly the thing that was wrong before.

setup() {
  # M11 pins — see fire-autonomy.bats. The capacity gate sits upstream of everything and turns this
  # suite red under load; it is not what these tests are about.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  # $REPO must be resolved BEFORE $HOME is fixtured — it is derived from the test file's own path,
  # not from $HOME, but reading it first keeps the ordering obvious to the next editor.
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  # HERMETICITY (test-hermeticity-lint.sh rules 5a/5b). Fixturing $HOME alone is NOT enough: an
  # ABSOLUTE /tmp default is not redirected by it, and a BARE tool name is executed off the
  # operator's live PATH. An ABSENT path is the right fixture for all three — these sensors fail
  # open, so the fire proceeds without ever touching the operator's real sweep stamp, heal locks,
  # or deployed claude-accounts binary.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  # The it2 shim is NOT optional under a fixtured $HOME. handoff-fire.sh runs `set -euo pipefail`
  # (:197), and it resolves PYTHON_BIN by sed-ing the shim's own `PYTHON_BIN=` line — so a MISSING
  # shim fails the pipeline under `pipefail` and the script exits 1 with the sed error swallowed by
  # its own `2>/dev/null`. That is a silent, message-free abort long before anything this file
  # asserts on. Seed a minimal shim: only the one line the resolver parses is load-bearing, and
  # nothing here ever executes it (every test is --dry-run).
  mkdir -p "$HOME/.claude/bin"
  printf '#!/bin/sh\nPYTHON_BIN="/usr/bin/python3"\nexit 0\n' > "$HOME/.claude/bin/it2"
  chmod +x "$HOME/.claude/bin/it2"
  PF="$BATS_TEST_TMPDIR/prompt.md"
  printf 'WAVE N+1 BRIEF\n' > "$PF"
  export TMPDIR="$BATS_TEST_TMPDIR"
  SID_ENV="w1t0p0:AAAAAAAA-0000-0000-0000-0000000000C1"
}

@test "--recycle --cwd DIR: relaunch cd's into the NEW dir, not \$PWD" {
  target="$BATS_TEST_TMPDIR/elsewhere"; mkdir -p "$target"
  run env ITERM_SESSION_ID="$SID_ENV" \
    bash "$HF" --prompt-file "$PF" --launcher claude-test --recycle --cwd "$target" --dry-run
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "cd $target"
  # the whole point: it must NOT compose the same-dir recycle command
  ! printf '%s\n' "$output" | grep -qF "cd $PWD &&" || false
}

@test "--recycle --worktree NAME: relaunch cd's into the worktree, and stays a RECYCLE (same pane)" {
  run env ITERM_SESSION_ID="$SID_ENV" \
    bash "$HF" --prompt-file "$PF" --launcher claude-test --recycle \
    --worktree relocate-probe --repo "$REPO" --dry-run
  [ "$status" -eq 0 ]
  ! printf '%s\n' "$output" | grep -q 'excludes --worktree' || false
  # the command cd's into the resolved worktree...
  printf '%s\n' "$output" | grep -qE 'command: +cd .*/\.worktrees/relocate-probe'
  # ...and this is still the recycle EXECUTION path: one pane, exit-then-relaunch. If this ever
  # reports a split/tab/window the change has silently become an ordinary fire, which would spawn a
  # second pane and re-create the orphan the relocating recycle exists to remove.
  printf '%s\n' "$output" | grep -q 'surface: *(recycle'
}

@test "--recycle still refuses SURFACE flags (there is no second surface to place)" {
  run env ITERM_SESSION_ID="$SID_ENV" \
    bash "$HF" --prompt-file "$PF" --launcher claude-test --recycle --window --dry-run
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -q 'excludes surface flags'
}

@test "--recycle refuses --worktree AND --cwd together (one destination, not two)" {
  target="$BATS_TEST_TMPDIR/elsewhere2"; mkdir -p "$target"
  run env ITERM_SESSION_ID="$SID_ENV" \
    bash "$HF" --prompt-file "$PF" --launcher claude-test --recycle \
    --worktree relocate-probe --cwd "$target" --dry-run
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -q 'mutually exclusive'
}

# A same-dir recycle must be BYTE-IDENTICAL to its pre-change behavior — this change is a widening,
# and the 90% case is the one that must not move. (The `cd $PWD` form is what the old code emitted
# for a non-worktree cwd; the linked-worktree fallback chain has its own test file.)
@test "plain --recycle (no dir flags) is unchanged: cd \$PWD, no relocation" {
  run env ITERM_SESSION_ID="$SID_ENV" \
    bash "$HF" --prompt-file "$PF" --launcher claude-test --recycle --dry-run
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "cd $PWD"
}

# CLAUDE_ISOLATION_SKIP=1 exists to stop a repo-ROOT relaunch auto-routing into a fresh worktree out
# from under the continuation. A relocating recycle is already landing IN an explicit dir, where the
# launcher launches in place — so forcing it would make the relocating recycle diverge from the
# ordinary --worktree fire it is supposed to reuse wholesale.
@test "relocating recycle does NOT force CLAUDE_ISOLATION_SKIP (same-dir recycle still does)" {
  target="$BATS_TEST_TMPDIR/elsewhere3"; mkdir -p "$target"
  run env ITERM_SESSION_ID="$SID_ENV" \
    bash "$HF" --prompt-file "$PF" --launcher claude-test --recycle --cwd "$target" --dry-run
  [ "$status" -eq 0 ]
  ! printf '%s\n' "$output" | grep -q 'CLAUDE_ISOLATION_SKIP' || false

  run env ITERM_SESSION_ID="$SID_ENV" \
    bash "$HF" --prompt-file "$PF" --launcher claude-test --recycle --dry-run
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'CLAUDE_ISOLATION_SKIP'
}
