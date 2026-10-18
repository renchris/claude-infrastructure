#!/usr/bin/env bats
# hooks/session-start.sh — the mission-board freshness gate
# (docs/research/startup-hooks-2026-10-18/README.md §2 #18). `cc-mission render` (python3 + ~8 git
# calls) used to run on every start; it now runs only when the board's rendered date is not today,
# or a row file / the row repo's origin/main ref is newer than both the board and the last attempt,
# and at most once per 10 min.
#
# HERMETIC: $HOME is $BATS_TEST_TMPDIR/home; `cc-mission` is a stub that only appends its argv to a
# call log; the MCP probe is served from a fresh fixture cache so no CLI runs; the memory snapshot is
# off. Every absence (0 calls) is paired with a positive control on the same fixture.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  HOOK="$REPO/hooks/session-start.sh"
  TMP="$BATS_TEST_TMPDIR"
  export HOME="$TMP/home"
  mkdir -p "$HOME/.claude/logs" "$HOME/.claude/bin" "$HOME/.claude/rules" \
           "$HOME/.claude/autonomy/customer/rows"
  unset KITTY_WINDOW_ID CLAUDE_CODE_EFFORT_LEVEL CC_CLAUDE_BIN
  export IT2_WRAPPER_NO_KITTY=1 SS_MEMORY_SNAPSHOT=off
  export CLAUDE_CONFIG_DIR="$TMP/cfg"; mkdir -p "$CLAUDE_CONFIG_DIR"
  STUB="$TMP/bin"; mkdir -p "$STUB"
  export PATH="$STUB:/usr/bin:/bin:/usr/sbin:/sbin"

  # A fresh MCP cache: the probe is served, never spawned.
  printf 'v1\t%s\tok\t1\t0\t\n' "$(date +%s)" > "$CLAUDE_CONFIG_DIR/.mcp-probe-cache"

  # The 20 s bound, reduced to a pass-through so the stub's call is observable.
  printf '#!/bin/bash\nshift\nexec "$@"\n' > "$STUB/tmo"; chmod 755 "$STUB/tmo"
  export SS_MISSION_TIMEOUT_BIN="$STUB/tmo"

  CALLS="$TMP/mission-calls"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> %q\n' "$CALLS" > "$HOME/.claude/bin/cc-mission"
  chmod 755 "$HOME/.claude/bin/cc-mission"

  BOARD="$HOME/.claude/rules/00-mission-board.md"
  ROWS="$HOME/.claude/autonomy/customer/rows"
  STAMP="$HOME/.claude/state/mission-render.stamp"
  TODAY="$(date +%Y-%m-%d)"

  # A row repo with an origin/main ref, everything dated in the past, the board newest.
  RREPO="$TMP/repo"
  mkdir -p "$RREPO/.git/refs/remotes/origin"
  printf '0000000000000000000000000000000000000000\n' > "$RREPO/.git/refs/remotes/origin/main"
  printf '{\n  "id": "a.b",\n  "repo": "%s",\n  "state": "lead"\n}\n' "$RREPO" > "$ROWS/a.b.json"
  touch -t 202001010000 "$RREPO/.git/refs/remotes/origin/main" "$ROWS/a.b.json" "$ROWS"
  mk_board "$TODAY"
}

# mk_board <date> — the line shape cc-mission's board_text emits, dated <date>, mtime 2021.
mk_board() {
  printf '# Mission board\n\n- row\n<sub>rendered %s, one session behind</sub>\n' "$1" > "$BOARD"
  touch -t 202101010000 "$BOARD"
}

calls() { if [ -f "$CALLS" ]; then wc -l < "$CALLS" | tr -d ' '; else echo 0; fi; }

run_hook() {
  run bash "$HOOK" <<< '{}'
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"MCP: 1 server(s) connected"* ]] || false
}

@test "a fresh board (today's date, inputs older) is NOT re-rendered" {
  run_hook
  [ "$(calls)" -eq 0 ] || false
}

@test "POSITIVE CONTROL — the same fixture with a stale rendered date renders once" {
  mk_board 2020-01-01
  run_hook
  [ "$(calls)" -eq 1 ] || false
  [ "$(cat "$CALLS")" = render ] || false
  [ -f "$STAMP" ] || false
}

@test "a missing board renders" {
  rm -f "$BOARD"
  run_hook
  [ "$(calls)" -eq 1 ] || false
}

@test "a row file newer than the board renders; a second start within 10 min does not" {
  touch "$ROWS/a.b.json"
  run_hook
  [ "$(calls)" -eq 1 ] || false
  run_hook
  [ "$(calls)" -eq 1 ] || false
}

@test "a new row (rows dir newer) renders" {
  printf '{\n  "id": "c.d"\n}\n' > "$ROWS/c.d.json"
  touch -t 202001010000 "$ROWS/c.d.json"; touch "$ROWS"
  run_hook
  [ "$(calls)" -eq 1 ] || false
}

@test "the row repo's origin/main moving renders" {
  touch "$RREPO/.git/refs/remotes/origin/main"
  run_hook
  [ "$(calls)" -eq 1 ] || false
}

@test "origin/main is read from a linked worktree's COMMON git dir" {
  mkdir -p "$TMP/common/refs/remotes/origin" "$TMP/common/worktrees/wt" "$TMP/wt"
  printf 'x\n' > "$TMP/common/refs/remotes/origin/main"
  printf '../..\n' > "$TMP/common/worktrees/wt/commondir"
  printf 'gitdir: %s\n' "$TMP/common/worktrees/wt" > "$TMP/wt/.git"
  printf '{\n  "id": "a.b",\n  "repo": "%s"\n}\n' "$TMP/wt" > "$ROWS/a.b.json"
  touch -t 202001010000 "$ROWS/a.b.json" "$ROWS" "$TMP/common/refs/remotes/origin/main"
  run_hook
  [ "$(calls)" -eq 0 ] || false                 # common ref older: nothing to do
  touch "$TMP/common/refs/remotes/origin/main"
  run_hook
  [ "$(calls)" -eq 1 ] || false
}

@test "an input older than the last attempt does not re-render an unchanged board" {
  # An unchanged render leaves the board's mtime old; the stamp is what stops the repeat.
  touch "$ROWS/a.b.json"
  mkdir -p "${STAMP%/*}"; printf '1\n' > "$STAMP"   # stamp content ancient, mtime now
  run_hook
  [ "$(calls)" -eq 0 ] || false
}

@test "a stale date is throttled to once per 10 min, then renders again" {
  mk_board 2020-01-01
  run_hook
  run_hook
  [ "$(calls)" -eq 1 ] || false                 # second start inside the window
  printf '%s\n' "$(( $(date +%s) - 601 ))" > "$STAMP"
  run_hook
  [ "$(calls)" -eq 2 ] || false                 # window passed
}

@test "no bound resolvable still skips the render (unchanged contract)" {
  mk_board 2020-01-01
  SS_MISSION_TIMEOUT_BIN='' run_hook
  [ "$(calls)" -eq 0 ] || false
}
