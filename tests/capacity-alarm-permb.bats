#!/usr/bin/env bats
# capacity-alarm-permb.bats — the per-session cost figure (`per_session_mb_est`), backlog ef28f9bb11e6.
#
# THE DEFECT THIS SUITE PINS. `PER_MB` was the frozen constant 636, derived from session tree ROOTS
# only. A session is not its root: teammates, MCP servers and tool children are memory the box holds
# on that session's behalf (measured 616 MB root-only vs 681 MB per whole TREE). PER_MB is the
# DIVISOR of reclaimable headroom in `est_room_sessions`, so undercounting the per-session cost
# OVERSTATES how many more sessions fit — the unsafe direction, and the one direction the code's own
# prose promised this number could never be wrong in.
#
# The properties, in priority order:
#   1. The figure INCLUDES the descendants (a) — proven against the REAL pre-fix artifact replayed
#      from a PINNED sha, not against a mutant of this file, so the control provably fails pre-fix.
#      The pin is a sha and not `origin/main` precisely because the fix landed there; see case (a).
#   2. A corrupt ppid chain under-counts rather than spins (b) — the one shared walk's cycle cap.
#   3. An explicit override still wins (c).
#   4. No live session ⇒ the DOCUMENTED fallback, SAID SO in the row, no divide-by-zero, and the row
#      is still a parseable JSON document (d) — the `"est_room_sessions":?` lesson: a fabricated or
#      unparseable value on the "could not measure" branch poisons the log for every consumer.
#
# `|| false` on every non-final [[ ]]/[ ] chain — errexit-exempt assertions are DEAD.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  ALARM="$REPO/scripts/capacity-alarm.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  export CC_CAP_LOG="$BATS_TEST_TMPDIR/cap.jsonl"
  # Terminal pinned: this repo's recurring latent-unhermetic class (a kitty-aware caller reading the
  # developer's own terminal). Nothing here should be terminal-dependent — pinning is how that stays
  # true rather than being assumed.
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1
  # Every ambient rung pinned NEUTRAL — same reason as capacity-alarm.bats setup(): the verdict is a
  # MAX over rungs that read the live box, so an unpinned rung makes every assertion here a hostage
  # to box weather. The INSTRUMENTS still all run; only the classification floors move.
  export CC_CAP_LOAD_WARN_PER_CORE=9999 CC_CAP_LOAD_ALARM_PER_CORE=9999
  export CC_CAP_WARN_GB=0 CC_CAP_ALARM_GB=0
  export CC_CAP_PRESSURE_WARN=9999 CC_CAP_PRESSURE_ALARM=9999
  export CC_CAP_PROC_WARN_GB=999999
  export CC_CAP_SEG_WARN_PCT=999999 CC_CAP_SEG_ALARM_PCT=999999
  export CC_CAP_COAL_WARN=999999 CC_CAP_COAL_ALARM=999999
  export CC_CAP_SWAP_DELTA_MB=999999
  STUBS="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUBS"
  # A spin in the ppid walk must fail the suite, not hang it. Resolved rather than hardcoded: a
  # hardcoded /opt/homebrew path is a fact about THIS box, and its absence would read as a test
  # failure elsewhere. No timeout(1) ⇒ run bare (the depth cap is still the property under test).
  TIMEOUT=( )
  _t="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || true)"
  [ -n "$_t" ] && TIMEOUT=( "$_t" 60 )
}

# ── the fixture ───────────────────────────────────────────────────────────────────────────────────
# ONE session tree, hand-written, and the arithmetic hand-written with it:
#   101  root (claude.exe)            400 MB   ← all the old constant could ever see
#   102  child of 101 (an MCP server) 200 MB
#   103  child of 102 (a tool child)  100 MB   ← two levels down: a one-level fix does not catch it
#   104  child of 101 (a bash)         50 MB
#   401  unrelated, ppid 1            800 MB   ← must NOT be attributed to the session
# ⇒ tree = 750 MB over 1 tree ⇒ 750 MB/session. Root-only would say 400; the frozen constant says 636.
# `mk_ps_stub <extra rows for the 4-column format>` lets a case add rows without restating the tree.
mk_ps_stub() {
  cat > "$STUBS/tree.txt" <<TREE
  101     1 409600 /U/.claude/node_modules/@anthropic-ai/claude-code/bin/claude.exe --agent-id a1
  102   101 204800 node /U/.claude/mcp/server.js
  103   102 102400 /opt/homebrew/bin/rg --json pattern
  104   101  51200 /bin/bash -lc gate
  401     1 819200 /usr/sbin/mDNSResponder
${1:-}
TREE
  # census() reads pid,ppid,args (no rss); rung 6 reads pid,ppid,comm; the top(1) fallback reads
  # pid,rss,comm. Each format is answered separately so a case that changes the tree cannot silently
  # change what a DIFFERENT rung sees.
  cat > "$STUBS/args.txt" <<'ARGS'
  101     1 /U/.claude/node_modules/@anthropic-ai/claude-code/bin/claude.exe --agent-id a1
  102   101 node /U/.claude/mcp/server.js
  103   102 /opt/homebrew/bin/rg --json pattern
  104   101 /bin/bash -lc gate
  401     1 /usr/sbin/mDNSResponder
ARGS
  cat > "$STUBS/comm.txt" <<'COMM'
  101     1 claude.exe
  102   101 node
  401     1 mDNSResponder
COMM
  cat > "$STUBS/rss.txt" <<'RSS'
  401 819200 mDNSResponder
  101 409600 claude.exe
  102 204800 node
RSS
  cat > "$STUBS/ps" <<STUB
#!/bin/bash
case "\$*" in
  *rss=,args=*) cat "$STUBS/tree.txt" ;;
  *ppid=,comm=*) cat "$STUBS/comm.txt" ;;
  *ppid=,args=*) cat "$STUBS/args.txt" ;;
  *)             cat "$STUBS/rss.txt" ;;
esac
STUB
  chmod +x "$STUBS/ps"
}

# The population with NO session in it at all — case (d)'s input.
mk_ps_stub_empty() {
  mk_ps_stub
  cat > "$STUBS/tree.txt" <<'TREE'
  401     1 819200 /usr/sbin/mDNSResponder
  402     1 102400 /Applications/iTerm.app/Contents/MacOS/iTerm2
TREE
  cat > "$STUBS/args.txt" <<'ARGS'
  401     1 /usr/sbin/mDNSResponder
  402     1 /Applications/iTerm.app/Contents/MacOS/iTerm2
ARGS
}

field() { # $1 = json, $2 = key → the raw value, or empty
  printf '%s\n' "$1" | sed -n "s/.*[,{]\"$2\":\([^,}]*\).*/\1/p"
}

run_alarm() { # $1 = script path; rest = extra env assignments
  local script="$1"; shift
  run env PATH="$STUBS:$PATH" CC_CAP_PS="$STUBS/ps" "$@" \
      "${TIMEOUT[@]}" /bin/bash "$script" --json --no-append
}

@test "(a) POSITIVE CONTROL — the per-session figure includes the tree's DESCENDANTS (pre-fix: it cannot)" {
  mk_ps_stub
  # The REAL pre-fix artifact, replayed from git — not a mutant of this test file, and not a
  # hand-edited copy. If this suite ever passes against BOTH versions, the control is vacuous.
  #
  # PINNED SHA, NOT `origin/main` (fixed 2026-08-11, backlog 39c255ca7bab). The pin used to be the
  # moving ref, which is correct for exactly as long as the fix is UNLANDED. The moment 54555bed1
  # landed, `origin/main:scripts/capacity-alarm.sh` became the POST-fix file, so this case began
  # asserting that the fixed script still carries the constant it deleted — a control that
  # invalidates itself by succeeding at its own purpose. It failed loudly (the good direction: the
  # marker grep is what caught it, not a silent 750==750 vacuous pass), but it failed FOREVER.
  # 73f4a4ec1 is 54555bed1^ and is an ancestor of trunk, so this replay is immutable.
  PRE_SHA=73f4a4ec1c31587b40cb5c7216b77e3bd17ac61f
  git -C "$REPO" show "$PRE_SHA:scripts/capacity-alarm.sh" > "$BATS_TEST_TMPDIR/pre.sh"
  [ -s "$BATS_TEST_TMPDIR/pre.sh" ] || false
  grep -q 'CC_CAP_PER_SESSION_MB:-636' "$BATS_TEST_TMPDIR/pre.sh" || false

  run_alarm "$BATS_TEST_TMPDIR/pre.sh"
  pre="$(field "$output" per_session_mb_est)"
  run_alarm "$ALARM"
  post="$(field "$output" per_session_mb_est)"
  src="$(field "$output" per_session_mb_src)"
  echo "pre-fix  per_session_mb_est = $pre  (frozen constant, root-only)"
  echo "post-fix per_session_mb_est = $post  src=$src  (400 root + 200 + 100 + 50 descendants = 750)"

  # Hand-written from the fixture above; never computed with the subject's own arithmetic.
  [ "$post" -eq 750 ] || false
  [ "$src" = '"derived"' ] || false
  # …and the pre-fix artifact provably CANNOT produce it: it is blind to every descendant.
  [ "$pre" -eq 636 ] || false
  [ "$pre" -ne "$post" ] || false
  # the root-only answer is also excluded — a fix that summed only roots would read 400
  [ "$post" -ne 400 ] || false
  printf '%s' "$output" | python3 -c 'import sys,json; json.loads(sys.stdin.read())' || false
}

@test "(b) a CYCLIC ppid chain under-counts rather than spins — the shared walk's depth cap" {
  # 601→602→601 is a chain no walk can terminate on by reaching pid 1. The cap must drop those two
  # processes (under-count, never over) and leave the real tree's answer untouched. `timeout` in
  # run_alarm is what turns a spin into a RED rather than a hung suite.
  mk_ps_stub "  601   602 999999 /some/looping/proc
  602   601 999999 /some/other/looping/proc"
  run_alarm "$ALARM"
  [ "$status" -ne 124 ] || { echo "TIMED OUT — the ppid walk spun on the cycle"; false; }
  got="$(field "$output" per_session_mb_est)"
  echo "per_session_mb_est with a cyclic pair present = $got (want 750: the cycle contributes nothing)"
  # 999999 KB × 2 ≈ 1953 MB — if either cyclic proc were attributed, this could not still read 750.
  [ "$got" -eq 750 ] || false
  printf '%s' "$output" | python3 -c 'import sys,json; json.loads(sys.stdin.read())' || false
}

@test "(c) CC_CAP_PER_SESSION_MB wins over the live derivation, and the row says so" {
  mk_ps_stub
  run_alarm "$ALARM" CC_CAP_PER_SESSION_MB=1234
  got="$(field "$output" per_session_mb_est)"
  src="$(field "$output" per_session_mb_src)"
  [ "$got" -eq 1234 ] || false
  [ "$src" = '"override"' ] || false
  # the derivation is genuinely overridden, not merely absent — same fixture derives 750 without it
  [ "$got" -ne 750 ] || false
  printf '%s' "$output" | python3 -c 'import sys,json; json.loads(sys.stdin.read())' || false
}

@test "(d) 0 sessions ⇒ the DOCUMENTED fallback, labelled, and the row still PARSES (no divide-by-zero)" {
  mk_ps_stub_empty
  run_alarm "$ALARM"
  [ "$status" -ne 124 ] || false
  got="$(field "$output" per_session_mb_est)"
  src="$(field "$output" per_session_mb_src)"
  room="$(field "$output" est_room_sessions)"
  echo "0 sessions → per_session_mb_est=$got src=$src est_room_sessions=$room"
  [ "$got" -eq 636 ] || false
  # LABELLED, not silent: a consumer must be able to tell a measured figure from a remembered one.
  [ "$src" = '"fallback"' ] || false
  # no fabricated `?`, and the whole document parses — the est_room_sessions incident, in reverse
  ! [[ "$output" =~ est_room_sessions\":\? ]] || false
  ! [[ "$output" =~ per_session_mb_est\":\? ]] || false
  printf '%s' "$output" | python3 -c 'import sys,json; json.loads(sys.stdin.read())' || false
}

@test "(e) the human line names the SOURCE of the figure, in every state" {
  mk_ps_stub
  run env PATH="$STUBS:$PATH" CC_CAP_PS="$STUBS/ps" \
      "${TIMEOUT[@]}" /bin/bash "$ALARM" --no-append
  [[ "$output" =~ "750 MB/session · derived" ]] || false
  mk_ps_stub_empty
  run env PATH="$STUBS:$PATH" CC_CAP_PS="$STUBS/ps" \
      "${TIMEOUT[@]}" /bin/bash "$ALARM" --no-append
  # the fallback must ANNOUNCE itself in the operator-facing line, not just in the row
  [[ "$output" =~ "636 MB/session · fallback" ]] || false
  [[ "$output" =~ "ROOT-ONLY" ]] || false
}

@test "(f) ONE ppid walk in the file — rung 6 and the cost derivation share it" {
  # The brief's structural requirement, executable: a second copy of the walk is a second place for
  # the cycle cap to drift, and drift there is unobservable until a corrupt chain arrives.
  n="$(grep -c 'while (q' "$ALARM")"
  [ "$n" -eq 1 ] || { echo "expected exactly 1 ppid-walk loop, found $n"; false; }
  # and both callers actually go through it
  [ "$(grep -c 'tree_root(' "$ALARM")" -ge 3 ] || false
}
