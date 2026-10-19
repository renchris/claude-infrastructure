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

# ─── (h) the probe is off the SessionStart critical path (W0.2 stale-while-revalidate) ─────────
# Every test above runs with a FRESH fixtured $HOME, so there is never a cache and they all take
# the inline-probe path — which is why they stay valid unchanged, and also why none of them
# exercises the cache. These do.

@test "(h) a FRESH cache is served without spawning the CLI at all" {
  printf 'a: u - %s Connected\n' '✔' > "$TMP/one.txt"
  mk_claude "$TMP/running-claude" "$TMP/one.txt"; mk_resolver "$TMP/running-claude"
  run_hook                                          # populates the cache
  [ "$status" -eq 0 ] || false
  [ -f "$CLAUDE_CONFIG_DIR/.mcp-probe-cache" ] || false
  rm -f "$CHILD_ENV"                                # the CLI's own footprint
  run_hook                                          # second start
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"MCP: 1 server(s) connected"* ]] || false
  # The load-bearing assertion: the child never ran. This is the whole point of the change.
  [ ! -f "$CHILD_ENV" ] || false
  [[ "$output" == *"[cached "* ]] || false          # and the age is visible, never implied
}

@test "(h-b) POSITIVE CONTROL — with the cache removed, the same fixture DOES spawn the CLI" {
  # Without this, (h)'s absence assertion would also pass if the fixture were simply broken.
  printf 'a: u - %s Connected\n' '✔' > "$TMP/one.txt"
  mk_claude "$TMP/running-claude" "$TMP/one.txt"; mk_resolver "$TMP/running-claude"
  run_hook
  rm -f "$CHILD_ENV" "$CLAUDE_CONFIG_DIR/.mcp-probe-cache"
  run_hook
  [ "$status" -eq 0 ] || false
  [ -f "$CHILD_ENV" ] || false                      # it really can run
  [[ "$output" == *"MCP: 1 server(s) connected"* ]] || false
  [[ "$output" != *"[cached "* ]] || false          # a live answer is not labelled cached
}

@test "(h-c) a cache older than MAX_AGE is NOT served — it degrades to a live probe" {
  printf 'a: u - %s Connected\n' '✔' > "$TMP/one.txt"
  mk_claude "$TMP/running-claude" "$TMP/one.txt"; mk_resolver "$TMP/running-claude"
  run_hook
  # Rewrite the record with an ancient stamp, keeping a DIFFERENT count so we can tell which
  # answer was used.
  printf 'v1\t1\tok\t99\t0\t\n' > "$CLAUDE_CONFIG_DIR/.mcp-probe-cache"
  rm -f "$CHILD_ENV"
  run_hook
  [ "$status" -eq 0 ] || false
  [[ "$output" != *"99 server"* ]] || false         # the ancient answer was refused
  [[ "$output" == *"MCP: 1 server(s) connected"* ]] || false
  [ -f "$CHILD_ENV" ] || false                      # and it probed for real
}

@test "(h-d) a probe that COULD NOT ASK is never cached — the failure does not go sticky" {
  # Caching an UNKNOWN would hide a genuinely broken probe behind the TTL.
  mk_ps "/bin/bash /some/harness"                   # nothing resolvable
  run_hook
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"MCP: UNKNOWN"* ]] || false
  [ ! -f "$CLAUDE_CONFIG_DIR/.mcp-probe-cache" ] || false
}

@test "(h-e) a corrupt or truncated cache record is treated as ABSENT, not as a partial answer" {
  mkdir -p "$CLAUDE_CONFIG_DIR"
  printf 'a: u - %s Connected\n' '✔' > "$TMP/one.txt"
  mk_claude "$TMP/running-claude" "$TMP/one.txt"; mk_resolver "$TMP/running-claude"
  for bad in 'garbage' 'v1	notanumber	ok	1	0	' 'v2	1	ok	1	0	' 'v1	1	unknown	0	0	x'; do
    printf '%s\n' "$bad" > "$CLAUDE_CONFIG_DIR/.mcp-probe-cache"
    rm -f "$CHILD_ENV"
    run_hook
    [ "$status" -eq 0 ] || false
    [[ "$output" == *"MCP: 1 server(s) connected"* ]] || false   # answered from a live probe
    [ -f "$CHILD_ENV" ] || false
  done
}

@test "(h-f) the background refresher writes the cache and emits no stdout" {
  printf 'a: u - %s Connected\n' '✔' > "$TMP/one.txt"
  mk_claude "$TMP/running-claude" "$TMP/one.txt"; mk_resolver "$TMP/running-claude"
  run bash "$HOOK" --refresh-mcp-cache
  [ "$status" -eq 0 ] || false
  [ -z "$output" ] || false                                    # no JSON, no session line
  [ -f "$CLAUDE_CONFIG_DIR/.mcp-probe-cache" ] || false
  grep -q '^v1	' "$CLAUDE_CONFIG_DIR/.mcp-probe-cache" || false
  # and it must NOT have logged a session start (that would inflate the fleet's own session census)
  ! grep -q 'Session started in' "$HOME/.claude/logs/sessions.log" || false
}

# ─── (i) failed refreshes are stamped, backed off and counted ───────────────────────────────────
# docs/research/startup-hooks-2026-10-18/README.md §2 #13. Before this, a failing refresher left no
# trace: every start past the TTL spawned another CLI, and the cache aged silently to MAX_AGE.

FAIL_STAMP() { printf '%s' "$CLAUDE_CONFIG_DIR/.mcp-probe-cache.refresh-fail"; }

@test "(i) a failing refresh writes a stamp; a second failure counts up and keeps the first time" {
  mk_ps "/bin/bash /some/harness"                   # nothing resolvable → the refresh fails
  run bash "$HOOK" --refresh-mcp-cache
  [ "$status" -eq 0 ] || false
  [ -z "$output" ] || false
  [ ! -f "$CLAUDE_CONFIG_DIR/.mcp-probe-cache" ] || false     # the failure is never cached
  IFS=$'\t' read -r v n first last < "$(FAIL_STAMP)"
  [ "$v" = v1 ] && [ "$n" = 1 ] && [ "$first" = "$last" ] || false
  printf 'v1\t1\t1000\t1000\n' > "$(FAIL_STAMP)"
  run bash "$HOOK" --refresh-mcp-cache
  IFS=$'\t' read -r v n first last < "$(FAIL_STAMP)"
  [ "$n" = 2 ] && [ "$first" = 1000 ] && [ "$last" -gt 1000 ] || false
}

@test "(i-b) the back-off suppresses an immediate re-spawn; past the window it spawns again" {
  mk_hanging_claude "$TMP/running-claude"; mk_resolver "$TMP/running-claude"
  mkdir -p "$CLAUDE_CONFIG_DIR"
  local now; now=$(date +%s)
  printf 'v1\t%s\tok\t1\t0\t\n' "$(( now - 400 ))" > "$CLAUDE_CONFIG_DIR/.mcp-probe-cache"  # past TTL
  printf 'v1\t1\t%s\t%s\n' "$(( now - 10 ))" "$(( now - 10 ))" > "$(FAIL_STAMP)"         # wait 600 s
  run_hook
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"MCP: 1 server(s) connected"* ]] || false
  # The spawn takes its lock synchronously and the hanging child holds it, so lock = spawned.
  [ ! -d "$CLAUDE_CONFIG_DIR/.mcp-probe-cache.refresh.lock" ] || false
  # POSITIVE CONTROL — same fixture, last failure outside the 2 × TTL window.
  printf 'v1\t1\t%s\t%s\n' "$(( now - 700 ))" "$(( now - 700 ))" > "$(FAIL_STAMP)"
  run_hook
  [ -d "$CLAUDE_CONFIG_DIR/.mcp-probe-cache.refresh.lock" ] || false
}

@test "(i-c) the window doubles per failure and caps at 1 h" {
  mk_hanging_claude "$TMP/running-claude"; mk_resolver "$TMP/running-claude"
  mkdir -p "$CLAUDE_CONFIG_DIR"
  local now; now=$(date +%s)
  printf 'v1\t%s\tok\t1\t0\t\n' "$(( now - 400 ))" > "$CLAUDE_CONFIG_DIR/.mcp-probe-cache"
  printf 'v1\t3\t1\t%s\n' "$(( now - 2000 ))" > "$(FAIL_STAMP)"      # 3 failures → 2400 s
  run_hook
  [ ! -d "$CLAUDE_CONFIG_DIR/.mcp-probe-cache.refresh.lock" ] || false
  printf 'v1\t40\t1\t%s\n' "$(( now - 3700 ))" > "$(FAIL_STAMP)"     # huge count, still ≤ 1 h
  run_hook
  [ -d "$CLAUDE_CONFIG_DIR/.mcp-probe-cache.refresh.lock" ] || false
}

@test "(i-d) the claim carries the failure count and its start time while N > 0" {
  mkdir -p "$CLAUDE_CONFIG_DIR"
  printf 'v1\t%s\tok\t1\t0\t\n' "$(date +%s)" > "$CLAUDE_CONFIG_DIR/.mcp-probe-cache"   # fresh
  printf 'v1\t3\t1700000000\t%s\n' "$(date +%s)" > "$(FAIL_STAMP)"
  run_hook
  [ "$status" -eq 0 ] || false
  local since; since=$(date -r 1700000000 '+%Y-%m-%d %H:%M')
  [[ "$output" == *"MCP: 1 server(s) connected [cached "*"] [3 refresh attempt(s) failed since $since]. agent-browser"* ]] || false
  printf '%s' "$output" | python3 -c 'import json,sys; json.load(sys.stdin)' || false
}

@test "(i-e) a successful refresh clears the stamp" {
  printf 'a: u - %s Connected\n' '✔' > "$TMP/one.txt"
  mk_claude "$TMP/running-claude" "$TMP/one.txt"; mk_resolver "$TMP/running-claude"
  mkdir -p "$CLAUDE_CONFIG_DIR"
  printf 'v1\t5\t1700000000\t1700000000\n' > "$(FAIL_STAMP)"
  run bash "$HOOK" --refresh-mcp-cache
  [ "$status" -eq 0 ] || false
  grep -q '^v1	' "$CLAUDE_CONFIG_DIR/.mcp-probe-cache" || false
  [ ! -f "$(FAIL_STAMP)" ] || false
  run_hook
  [[ "$output" != *"refresh attempt"* ]] || false
}

@test "(i-f) a healthy start's output is byte-identical to the pre-change hook" {
  # Replays the REAL pre-change artifact at a PINNED sha (never a moving ref).
  [ -n "$GIT_BIN" ] || skip "git not resolvable"
  "$GIT_BIN" -C "$REPO" show fda64148a:hooks/session-start.sh > "$TMP/base-hook.sh" || false
  mkdir -p "$CLAUDE_CONFIG_DIR"
  # 150 s old: inside the TTL (no refresh) and stable as "[cached 2m ago]" across both runs.
  printf 'v1\t%s\tok\t2\t1\t\n' "$(( $(date +%s) - 150 ))" > "$CLAUDE_CONFIG_DIR/.mcp-probe-cache"
  export SS_MEMORY_SNAPSHOT=off
  run bash "$TMP/base-hook.sh" <<< '{}'
  local before="$output"
  [[ "$before" == *"MCP: 2 server(s) connected (1 degraded) [cached 2m ago]"* ]] || false
  run bash "$HOOK" <<< '{}'
  [ "$output" = "$before" ] || false
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

# ─── (j) silent when healthy (startup-hooks README §2 #12, A4-R5) ──────────────────────────────
# Every case above runs WITHOUT agent-browser on PATH, which is itself news, so they still see the
# line. These put a stub on PATH: healthy is then silent in the transcript, the claim still lands in
# sessions.log, and each unhealthy state keeps its line.
mk_agent_browser() { printf '#!/bin/bash\nexit 0\n' > "$STUB/agent-browser"; chmod 755 "$STUB/agent-browser"; }
claim_log() { grep -F 'MCP: ' "$HOME/.claude/logs/sessions.log" | tail -1; }

@test "(j) healthy (servers connected, none degraded, agent-browser installed) ⇒ no output; the claim is logged" {
  mk_agent_browser
  printf 'a: u - %s Connected\n' '✔' > "$TMP/one.txt"
  mk_claude "$TMP/running-claude" "$TMP/one.txt"; mk_resolver "$TMP/running-claude"
  run_hook
  [ "$status" -eq 0 ] || false
  [ -z "$output" ] || { echo "healthy start printed: $output" >&2; false; }
  [[ "$(claim_log)" == *"MCP: 1 server(s) connected. agent-browser: installed."* ]] || false
}

@test "(j-b) each unhealthy state keeps its line: degraded, zero, UNKNOWN, failing refresher, no agent-browser" {
  mk_agent_browser
  { printf 'a: u - %s Connected\n' '✔'; printf 'b: u - timed out\n'; } > "$TMP/deg.txt"
  mk_claude "$TMP/running-claude" "$TMP/deg.txt"; mk_resolver "$TMP/running-claude"
  run_hook
  [[ "$output" == *"MCP: 1 server(s) connected (1 degraded)"* ]] || false
  local cache="$CLAUDE_CONFIG_DIR/.mcp-probe-cache"   # each probe caches its answer; the next state must probe
  rm -f "$cache"
  printf 'No MCP servers configured.\n' > "$TMP/none.txt"
  mk_claude "$TMP/running-claude" "$TMP/none.txt"
  run_hook
  [[ "$output" == *"MCP: 0 servers connected"* ]] || false
  rm -f "$cache" "$HOME/.claude/bin/cc-claude-bin"; mk_ps "/bin/bash /some/harness"
  run_hook
  [[ "$output" == *"MCP: UNKNOWN"* ]] || false
  mkdir -p "$CLAUDE_CONFIG_DIR"
  printf 'v1\t%s\tok\t1\t0\t\n' "$(date +%s)" > "$CLAUDE_CONFIG_DIR/.mcp-probe-cache"
  printf 'v1\t2\t1700000000\t%s\n' "$(date +%s)" > "$(FAIL_STAMP)"
  run_hook
  [[ "$output" == *"[2 refresh attempt(s) failed since"* ]] || false
  rm -f "$(FAIL_STAMP)" "$STUB/agent-browser"
  run_hook
  [[ "$output" == *"MCP: 1 server(s) connected [cached "*"agent-browser: not installed."* ]] || false
  printf '%s' "$output" | python3 -c 'import json,sys; json.load(sys.stdin)' || false
}

@test "(j-c) a healthy start with the effort tripwire still prints the tripwire alone" {
  mk_agent_browser
  export CLAUDE_CODE_EFFORT_LEVEL=max
  printf 'a: u - %s Connected\n' '✔' > "$TMP/one.txt"
  mk_claude "$TMP/running-claude" "$TMP/one.txt"; mk_resolver "$TMP/running-claude"
  run_hook
  [[ "$output" == *"CLAUDE_CODE_EFFORT_LEVEL=max"* ]] || false
  [[ "$output" != *"MCP: "* ]] || false
  printf '%s' "$output" | python3 -c 'import json,sys; json.load(sys.stdin)' || false
}
