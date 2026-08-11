#!/usr/bin/env bats
# hooks/session-start.sh — the MCP connectivity probe: WHICH binary it asks, and whether its answer
# distinguishes "asked and got zero" from "could not ask".  (backlog aac347ddc003)
#
# WHAT IS UNDER TEST, and why the obvious diagnosis was wrong. The item was filed as "`command -v
# claude` is always false in a hook, so CONNECTED_COUNT is permanently 0". Measured against
# ~/.claude/logs/sessions.log on 2026-08-11 that premise is REFUTED: 7,022 of 8,636 session blocks
# logged an MCP Status line, so the gate resolved. It resolved to the WRONG BINARY —
# ~/Library/pnpm/claude, the stock pnpm install at 2.0.5, while the session firing the hook is
# 2.1.220. Same minute, side by side: the stale binary enumerated 2 servers, the running one 6 (the
# 4 claude.ai session-connected servers were invisible to the sensor entirely). So the live defect
# is a track mismatch producing a CONFIDENT WRONG NUMBER, not an inert probe — memory
# version-identity-is-the-running-process-not-the-launcher. The remaining ~19% of sessions took the
# other half of the defect: probe unavailable/failed, count left at 0, and the emitted context said
# the same thing it says for a real zero.
#
# PROOF DISCIPLINE (this repo's, applied verbatim):
#   · $HOME is fixtured into $BATS_TEST_TMPDIR — the hook mkdir -p's ~/.claude/logs and appends to
#     sessions.log; an unfixtured run would write the operator's real state.
#   · PATH is stubs + system dirs only. No real `claude` is ever executed, and the PATH `claude`
#     stub is deliberately DIFFERENT from the resolver's binary — that difference IS the defect.
#   · The terminal is pinned (unset KITTY_WINDOW_ID / IT2_WRAPPER_NO_KITTY=1): this repo's recurring
#     latent-unhermetic class, and session-start.sh sits on the terminal-aware hook path.
#   · Non-final `[ ]` / `[[ ]]` are errexit-EXEMPT under bats and therefore DEAD; every assertion
#     carries `|| false`.
#   · Every ABSENCE assertion is paired with a POSITIVE CONTROL sharing its fixture: (b) pairs
#     "UNKNOWN" against a real zero, (c) pairs the two stripped vars against an inherited third, (d)
#     pairs the timeout against the same stub not hanging, (f) pairs the PPID hit against a miss.
#   · Test (a-control) replays the REAL pre-fix artifact from git at a PINNED SHA, never a mutant
#     of this file — memory control-must-replay-the-real-artifact. It is the only test that can
#     tell the two trees apart, and it is why (a) is not a vacuous pass. It named `origin/main`
#     until 2026-08-11, which made it self-defeating: the fix landed on main and the control began
#     replaying the FIXED hook, so it went red permanently for a reason unrelated to any diff
#     running it. A control keyed on a moving ref expires the moment its own subject lands.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  HOOK="${SS_HOOK:-$REPO/hooks/session-start.sh}"
  TMP="$BATS_TEST_TMPDIR"
  GIT_BIN="$(command -v git 2>/dev/null || true)"   # resolved BEFORE PATH is narrowed
  TIMEOUT_REAL="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || true)"

  export HOME="$TMP/home"
  mkdir -p "$HOME/.claude/logs" "$HOME/.claude/bin"

  # Terminal pinning — see header.
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1

  # Every knob the hook reads comes from the test, never the ambient session.
  unset CLAUDE_CODE_EFFORT_LEVEL CC_CLAUDE_BIN
  export CC_MCP_PROBE_ATTEMPTS=1 CC_MCP_PROBE_TIMEOUT=5 CC_MCP_PROBE_BUDGET=10

  STUB="$TMP/bin"; mkdir -p "$STUB"
  export PATH="$STUB:/usr/bin:/bin:/usr/sbin:/sbin"
  # `timeout` lives outside the system dirs on this box; symlink it in so the bounded branch is the
  # one under test by default, and test (d-b) removes it to exercise the unbounded fallback.
  [ -n "$TIMEOUT_REAL" ] && ln -sf "$TIMEOUT_REAL" "$STUB/timeout"

  # Pane identity PRESENT in the hook's own env — the phantom-SessionEnd guard has to strip it.
  export CC_PANE_ID=PANE-REAL ITERM_SESSION_ID=w0t0p9:ABCDEF
  export CLAUDE_CONFIG_DIR="$TMP/cfg"     # inheritance positive control for (c)

  CHILD_ENV="$TMP/child-env"
}

# mk_claude <path> <payload-file> [rc] — a fake claude CLI. Dumps the env it was given (so the
# phantom-guard test can assert on it) and prints the payload verbatim.
mk_claude() {
  printf '#!/bin/bash\nenv > %q\ncat %q\nexit %s\n' "$CHILD_ENV" "$2" "${3:-0}" > "$1"
  chmod 755 "$1"
}

# mk_hanging_claude <path> — never returns on its own; only a timeout can end it.
mk_hanging_claude() {
  printf '#!/bin/bash\nsleep 30\n' > "$1"
  chmod 755 "$1"
}

# mk_resolver <path> — stand in for bin/cc-claude-bin at the location the hook looks for it.
# Emits the `<path>\t<rung>` shape the real resolver's --explain prints.
mk_resolver() {
  printf '#!/bin/bash\nprintf "%%s\\t%%s\\n" %q "test rung"\n' "$1" > "$HOME/.claude/bin/cc-claude-bin"
  chmod 755 "$HOME/.claude/bin/cc-claude-bin"
}

# mk_ps <command-line> — stub `ps` so the PPID rung sees exactly this parent command line.
mk_ps() {
  printf '#!/bin/bash\nprintf "%%s\\n" %q\n' "$1" > "$STUB/ps"
  chmod 755 "$STUB/ps"
}

# The two fixtures that reproduce the live defect: a stale binary on PATH answering with FEWER
# servers than the binary the running session actually is.
fixture_track_mismatch() {
  printf 'motion: https://mcp.motion.dev (HTTP) - %s Connected\n' '✓' > "$TMP/stale.txt"
  { printf 'claude.ai Gmail: https://g/mcp - %s Connected\n' '✔'
    printf 'claude.ai Drive: https://d/mcp - %s Connected\n' '✔'
    printf 'motion: https://m/mcp - %s Connected\n' '✔'; } > "$TMP/running.txt"
  mk_claude "$STUB/claude" "$TMP/stale.txt"          # what `command -v claude` finds: 1 server
  mk_claude "$TMP/running-claude" "$TMP/running.txt" # what the session actually is: 3 servers
  mk_resolver "$TMP/running-claude"
}

run_hook() { run bash "$HOOK" <<< '{}'; }

# ─── (a) the fix, and the control that proves it is not vacuous ────────────────────────────────

@test "(a) reports the RUNNING session binary's count, not the stale PATH binary's" {
  fixture_track_mismatch
  run_hook
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"MCP: 3 server(s) connected"* ]] || false
  [[ "$output" != *"MCP: 1 server"* ]] || false
}

@test "(a-control) the PRE-FIX artifact answers with the stale PATH binary" {
  # PINNED SHA, NOT `origin/main`. This control replayed origin/main, which MOVES: once the fix
  # landed there (37ef2489c), the control was replaying the POST-fix artifact and went red
  # permanently — reproducing nothing, while looking like a regression in whatever diff happened
  # to run it next. Measured 2026-08-11: red at HEAD with an empty working tree.
  # 54555bed1 is 37ef2489c^ — the last commit whose hook still had the `command -v claude` gate and
  # no _resolve_claude_bin. A control must be keyed on the MECHANISM it replays, not on a ref that
  # advances past it.
  [ -n "$GIT_BIN" ] || skip "git unavailable"
  "$GIT_BIN" -C "$REPO" show 54555bed1:hooks/session-start.sh > "$TMP/pre.sh" 2>/dev/null \
    || skip "pre-fix commit 54555bed1 unavailable (shallow clone?)"
  # The replayed artifact must actually BE pre-fix, or this test passes for the wrong reason.
  ! grep -q '_resolve_claude_bin' "$TMP/pre.sh" || false
  fixture_track_mismatch
  run bash "$TMP/pre.sh" <<< '{}'
  [ "$status" -eq 0 ] || false
  # The defect, pinned: pre-fix asks PATH and reports 1 where the session holds 3.
  [[ "$output" == *"MCP: 1 server(s)"* ]] || false
  [[ "$output" != *"MCP: 3 server"* ]] || false
}

@test "(a-b) degraded rows are not counted as connected" {
  { printf 'a: u - %s Connected\n' '✔'
    printf 'b: u - %s Connected\n' '!'
    printf 'c: u - timed out\n'; } > "$TMP/mixed.txt"
  mk_claude "$TMP/running-claude" "$TMP/mixed.txt"
  mk_resolver "$TMP/running-claude"
  run_hook
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"MCP: 1 server(s) connected (2 degraded)"* ]] || false
  [[ "$output" != *"MCP: 3 server"* ]] || false     # the old bare `grep -c Connected` said 3
}

# ─── (b) one value must not mean both "answered zero" and "could not ask" ───────────────────────

@test "(b) unresolvable binary says UNKNOWN, and a real zero says zero — different strings" {
  # b1: nothing to ask. No PATH claude, no resolver, and a parent that is not claude.
  mk_ps "/bin/bash /some/harness"
  run_hook
  [ "$status" -eq 0 ] || false
  local unknown_out="$output"
  [[ "$unknown_out" == *"MCP: UNKNOWN"* ]] || false
  [[ "$unknown_out" == *"NOT a report of zero connected servers"* ]] || false
  [[ "$unknown_out" != *"0 servers connected"* ]] || false

  # b2: same hook, same fixture shape, but the probe RUNS and genuinely finds nothing.
  printf 'No MCP servers configured.\n' > "$TMP/none.txt"
  mk_claude "$TMP/running-claude" "$TMP/none.txt"
  mk_resolver "$TMP/running-claude"
  run_hook
  [ "$status" -eq 0 ] || false
  local zero_out="$output"
  [[ "$zero_out" == *"MCP: 0 servers connected"* ]] || false
  [[ "$zero_out" == *"probe RAN and answered zero"* ]] || false
  [[ "$zero_out" != *"UNKNOWN"* ]] || false

  # the discrimination itself
  [ "$unknown_out" != "$zero_out" ] || false

  # POSITIVE CONTROL: both are still well-formed SessionStart output carrying the other lines,
  # so the difference above is the MCP claim and not one of them having collapsed.
  [[ "$unknown_out" == *'"hookEventName": "SessionStart"'* ]] || false
  [[ "$zero_out"    == *'"hookEventName": "SessionStart"'* ]] || false
  [[ "$unknown_out" == *"agent-browser:"* ]] || false
  [[ "$zero_out"    == *"agent-browser:"* ]] || false
}

@test "(b-b) both states emit ONE parseable JSON object" {
  mk_ps "/bin/bash /some/harness"
  run_hook
  printf '%s' "$output" | python3 -c 'import json,sys; json.load(sys.stdin)' || false

  printf 'a: u - %s Connected\n' '✔' > "$TMP/one.txt"
  mk_claude "$TMP/running-claude" "$TMP/one.txt"; mk_resolver "$TMP/running-claude"
  run_hook
  printf '%s' "$output" | python3 -c 'import json,sys; json.load(sys.stdin)' || false
}

# ─── (c) the phantom-SessionEnd guard still holds ──────────────────────────────────────────────

@test "(c) the probe child is PANELESS — both pane vars absent, an inherited var present" {
  printf 'a: u - %s Connected\n' '✔' > "$TMP/one.txt"
  mk_claude "$TMP/running-claude" "$TMP/one.txt"
  mk_resolver "$TMP/running-claude"
  run_hook
  [ "$status" -eq 0 ] || false
  [ -f "$CHILD_ENV" ] || false                                  # the child really ran
  ! grep -q '^CC_PANE_ID=' "$CHILD_ENV" || false                # ABSENT, not empty
  ! grep -q '^ITERM_SESSION_ID=' "$CHILD_ENV" || false
  # POSITIVE CONTROL: the dump CAN see inherited vars, so the two absences above mean something.
  grep -q '^CLAUDE_CONFIG_DIR=' "$CHILD_ENV" || false
  # and the hook's OWN env still has them (the strip is scoped to the child, not the hook)
  [ -n "$CC_PANE_ID" ] || false
}

@test "(c-b) paneless holds on the no-timeout fallback path too" {
  rm -f "$STUB/timeout"                                          # force the unwrapped branch
  printf 'a: u - %s Connected\n' '✔' > "$TMP/one.txt"
  mk_claude "$TMP/running-claude" "$TMP/one.txt"
  mk_resolver "$TMP/running-claude"
  run_hook
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"MCP: 1 server(s) connected"* ]] || false     # the branch really executed
  ! grep -q '^CC_PANE_ID=' "$CHILD_ENV" || false
  ! grep -q '^ITERM_SESSION_ID=' "$CHILD_ENV" || false
  grep -q '^CLAUDE_CONFIG_DIR=' "$CHILD_ENV" || false
}

# ─── (d) the SessionStart critical path is bounded ─────────────────────────────────────────────

@test "(d) a hung probe is cut by the per-attempt timeout and reported as UNKNOWN" {
  [ -x "$STUB/timeout" ] || skip "no timeout binary on this box"
  export CC_MCP_PROBE_TIMEOUT=1 CC_MCP_PROBE_BUDGET=3
  mk_hanging_claude "$TMP/running-claude"
  mk_resolver "$TMP/running-claude"
  local t0 t1
  t0=$SECONDS
  run_hook
  t1=$SECONDS
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"MCP: UNKNOWN"* ]] || false
  [[ "$output" == *"timed out"* ]] || false
  [ $(( t1 - t0 )) -le 8 ] || false          # bounded: the old loop had no ceiling at all
}

@test "(d-b) POSITIVE CONTROL — the same fixture without the hang answers normally" {
  export CC_MCP_PROBE_TIMEOUT=1 CC_MCP_PROBE_BUDGET=3
  printf 'a: u - %s Connected\n' '✔' > "$TMP/one.txt"
  mk_claude "$TMP/running-claude" "$TMP/one.txt"
  mk_resolver "$TMP/running-claude"
  run_hook
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"MCP: 1 server(s) connected"* ]] || false
  [[ "$output" != *"UNKNOWN"* ]] || false
}

@test "(d-c) the DEFAULT bound accommodates a probe slower than the measured median" {
  # The regression this pins: the first bound written here was 5 s, and a live run showed a healthy
  # probe exceeding it under load — a too-tight bound reports a FALSE "could not ask". No exact
  # number is asserted (that would tripwire its own future retune); the claim is only that a probe
  # taking materially longer than the ~2.6 s median still ANSWERS on the shipped defaults.
  unset CC_MCP_PROBE_TIMEOUT CC_MCP_PROBE_BUDGET CC_MCP_PROBE_ATTEMPTS
  [ -x "$STUB/timeout" ] || skip "no timeout binary on this box"
  printf 'a: u - %s Connected\n' '✔' > "$TMP/one.txt"
  printf '#!/bin/bash\nsleep 4\ncat %q\n' "$TMP/one.txt" > "$TMP/running-claude"
  chmod 755 "$TMP/running-claude"
  mk_resolver "$TMP/running-claude"
  run_hook
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"MCP: 1 server(s) connected"* ]] || false
  [[ "$output" != *"UNKNOWN"* ]] || false
}

# ─── (f) the PPID rung — the running process, not a name ───────────────────────────────────────

@test "(f) resolves the parent claude process when no resolver exists" {
  printf 'a: u - %s Connected\n' '✔' > "$TMP/one.txt"
  mk_claude "$TMP/ppid-claude" "$TMP/one.txt"
  mv "$TMP/ppid-claude" "$TMP/claude"                # basename must read as claude
  chmod 755 "$TMP/claude"
  mk_ps "$TMP/claude --model x"                      # a claude parent, with args
  rm -f "$HOME/.claude/bin/cc-claude-bin"            # no rung 2
  run_hook
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"MCP: 1 server(s) connected"* ]] || false
}

@test "(f-b) POSITIVE CONTROL — a non-claude parent does NOT resolve" {
  mk_ps "/usr/bin/login -pf chrisren"
  rm -f "$HOME/.claude/bin/cc-claude-bin"
  run_hook
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"MCP: UNKNOWN"* ]] || false
  [[ "$output" == *"no claude binary resolved"* ]] || false
}

# ─── (g) the hook's other duties are untouched ─────────────────────────────────────────────────

@test "(g) the effort-env tripwire still rides the same single JSON object" {
  export CLAUDE_CODE_EFFORT_LEVEL=max
  printf 'a: u - %s Connected\n' '✔' > "$TMP/one.txt"
  mk_claude "$TMP/running-claude" "$TMP/one.txt"; mk_resolver "$TMP/running-claude"
  run_hook
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"CLAUDE_CODE_EFFORT_LEVEL=max"* ]] || false
  [[ "$output" == *"MCP: 1 server(s) connected"* ]] || false
  printf '%s' "$output" | python3 -c 'import json,sys; json.load(sys.stdin)' || false
}

@test "(g-b) the session line and the resolved-binary rung are logged" {
  printf 'a: u - %s Connected\n' '✔' > "$TMP/one.txt"
  mk_claude "$TMP/running-claude" "$TMP/one.txt"; mk_resolver "$TMP/running-claude"
  run_hook
  grep -q 'Session started in' "$HOME/.claude/logs/sessions.log" || false
  grep -q 'MCP probe binary: .*test rung' "$HOME/.claude/logs/sessions.log" || false
}
