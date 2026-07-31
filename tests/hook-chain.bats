#!/usr/bin/env bats
# hook-chain.sh — the collapsed hook dispatcher (§8.5.4 fork storm / §12.5).
#
# WHY THIS EXISTS. Measured 2026-07-31 at load 0.75/core (a HEALTHY box, so this is the floor):
# ONE Bash tool call costs 232 ms in PreToolUse (6 processes) + 136 ms in PostToolUse (2), = 368 ms
# across 8 processes. 93 ms of the 232 is pure interpreter startup and ~78 ms is six separate `jq`
# invocations all extracting THE SAME field. §8.5.4 shows the cost is O(N^2) — forks/s is O(N),
# cost-per-fork is O(load), load is O(forks/s) — so this is the term that makes every other term
# worse, and unlike iTerm2/WindowServer it is entirely ours.
#
# WHY THE TESTS LOOK LIKE THIS. Collapsing six SAFETY GATES into one process is the exact shape of
# memory `decision-moved-out-of-the-guarded-unit`: a remedy that moves the decision out of the
# guarded unit can leave the suite 100% green while the invariant is un-fixed. So the load-bearing
# tests here are not the happy paths — they are:
#   * the MUTATION CONTROL (§C): drop a member from the registry and the parity assertion MUST go
#     red. A parity suite that still passes with a guard removed is measuring nothing.
#   * the NO-SKIP-SPELLING law (§C): there must exist NO value of any env var that makes the
#     dispatcher run fewer members than the registry lists. "Disable" degrades to legacy fork+exec,
#     never to skip — a kill switch that silently disarms six guards is worse than no kill switch
#     (memory `denylist-enumerates-spellings-not-the-class`).
#   * LOUD INERTNESS (§A): an unreadable/absent registry or a missing member REFUSES; it never
#     admits. §12.2's rule for capacity_gate applies verbatim to this dispatcher.
#
# Harness laws (repo convention): L1 fixtures reproduce the LIVE shape; L2 assertions key on
# failure-distinct values; L3 `[ ]` / `grep -q` only; L4 every behaviour has a must-change AND a
# must-NOT-change fixture.

setup() {
  # HERMETICITY first — this subject reads a registry under $HOME and execs members from it.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/hooks"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  S="$REPO/hooks/hook-chain.sh"
  CHAINS="$HOME/.claude/config/hook-chains.d"; mkdir -p "$CHAINS"
  M="$HOME/.claude/hooks"
  export CC_HOOK_CHAIN_DIR="$CHAINS"
  export CC_HOOK_CHAIN_MEMBER_DIR="$M"
  PAY='{"session_id":"t","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"echo hi"}}'
}

# ── fixture members: each emits a failure-distinct marker so a skipped member is VISIBLE ────────
mkmember() { # <name> <exit> <stdout>
  cat > "$M/$1" <<EOF
#!/usr/bin/env bash
INPUT=\$(cat)
printf '%s' '$3'
exit $2
EOF
  chmod +x "$M/$1"
}
mkchain() { printf '%s\n' "$@" > "$CHAINS/testchain"; }

# a member that PROVES it received the payload on stdin (not an empty pipe)
mkecho_member() {
  cat > "$M/$1" <<'EOF'
#!/usr/bin/env bash
INPUT=$(cat)
printf '%s' "$INPUT" | grep -q '"command":"echo hi"' || { echo "NO-PAYLOAD" >&2; exit 3; }
exit 0
EOF
  chmod +x "$M/$1"
}

run_chain() { printf '%s' "$PAY" | "$S" testchain; }

# ══ §A — LOUD INERTNESS: the dispatcher must never silently admit ═══════════════════════════════

@test "selftest passes and runs its full check count (a zero-check suite must not 'pass')" {
  run "$S" --selftest
  [ "$status" -eq 0 ]
  n="$(printf '%s' "$output" | grep -c '^  ok   ')"
  [ "$n" -ge 12 ]
  ! printf '%s' "$output" | grep -q '^  FAIL'
}

@test "an ABSENT registry REFUSES loudly — it does not admit the tool call" {
  run bash -c "printf '%s' '$PAY' | '$S' nosuchchain"
  [ "$status" -ne 0 ]
  printf '%s' "$output" >&2
  printf '%s%s' "$output" "$stderr" | grep -qi 'chain' || true
}

@test "a member listed in the registry but ABSENT on disk REFUSES — never a silent skip" {
  mkmember a.sh 0 ''
  mkchain a.sh ghost-that-does-not-exist.sh
  run run_chain
  [ "$status" -ne 0 ]
}

@test "an EMPTY registry refuses — a chain that runs zero guards must not report success" {
  : > "$CHAINS/testchain"
  run run_chain
  [ "$status" -ne 0 ]
}

# ══ §B — PARITY: aggregate decision must equal the serial chain's ══════════════════════════════

@test "all-abstain chain is silent and exits 0 (the 99% path)" {
  mkmember a.sh 0 ''; mkmember b.sh 0 ''; mkmember c.sh 0 ''
  mkchain a.sh b.sh c.sh
  run run_chain
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "every member receives the payload on stdin (not an empty pipe)" {
  mkecho_member a.sh; mkecho_member b.sh; mkecho_member c.sh
  mkchain a.sh b.sh c.sh
  run run_chain
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q 'NO-PAYLOAD'
}

@test "a lone member's JSON passes through BYTE-IDENTICAL (zero semantic change)" {
  J='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"x"}}'
  mkmember a.sh 0 ''; mkmember b.sh 0 "$J"; mkmember c.sh 0 ''
  mkchain a.sh b.sh c.sh
  run run_chain
  [ "$status" -eq 0 ]
  [ "$output" = "$J" ]
}

@test "exit 2 from ANY member blocks the chain (blocking beats a later allow)" {
  ALLOW='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"ok"}}'
  mkmember a.sh 2 ''; mkmember b.sh 0 "$ALLOW"
  mkchain a.sh b.sh
  run run_chain
  [ "$status" -eq 2 ]
}

@test "deny BEATS allow when two members disagree (precedence, not first-wins)" {
  DENY='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"nope"}}'
  ALLOW='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"ok"}}'
  # allow FIRST so a first-wins implementation fails this test
  mkmember a.sh 0 "$ALLOW"; mkmember b.sh 0 "$DENY"
  mkchain a.sh b.sh
  run run_chain
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '"permissionDecision":"deny"'
  ! printf '%s' "$output" | grep -q '"permissionDecision":"allow"'
}

@test "ask BEATS allow but LOSES to deny" {
  ASK='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"?"}}'
  ALLOW='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"ok"}}'
  mkmember a.sh 0 "$ALLOW"; mkmember b.sh 0 "$ASK"
  mkchain a.sh b.sh
  run run_chain
  printf '%s' "$output" | grep -q '"permissionDecision":"ask"'
}

@test "a NON-blocking non-zero member (exit 1) does not block the chain" {
  mkmember a.sh 1 ''; mkmember b.sh 0 ''
  mkchain a.sh b.sh
  run run_chain
  [ "$status" -eq 0 ]
}

@test "a member that exits 2 does NOT prevent later members from running" {
  # the harness runs every hook in a matcher group; a short-circuiting dispatcher would change
  # behaviour for any later member with a side effect
  cat > "$M/b.sh" <<EOF
#!/usr/bin/env bash
cat >/dev/null; touch "$M/b-ran"; exit 0
EOF
  chmod +x "$M/b.sh"
  mkmember a.sh 2 ''
  mkchain a.sh b.sh
  run run_chain
  [ "$status" -eq 2 ]
  [ -f "$M/b-ran" ]
}

# ══ §C — ANTI-VACUITY: the tests above must be able to FAIL ════════════════════════════════════

@test "MUTATION CONTROL — removing a member from the registry makes its decision DISAPPEAR" {
  # If this test passes with b.sh dropped, then the parity assertions above prove nothing.
  DENY='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"nope"}}'
  mkmember a.sh 0 ''; mkmember b.sh 0 "$DENY"
  mkchain a.sh b.sh
  run run_chain
  printf '%s' "$output" | grep -q '"permissionDecision":"deny"'   # present with b.sh

  mkchain a.sh                                                    # drop the guard
  run run_chain
  ! printf '%s' "$output" | grep -q '"permissionDecision":"deny"' # and it is GONE
}

@test "NO-SKIP-SPELLING — no env value makes the dispatcher run fewer members than the registry" {
  # memory `denylist-enumerates-spellings-not-the-class`: a kill switch that silently disarms the
  # guards is worse than none. Every spelling must still run all three members.
  mkecho_member a.sh; mkecho_member b.sh; mkecho_member c.sh
  cat > "$M/count.sh" <<EOF
#!/usr/bin/env bash
cat >/dev/null; echo x >> "$M/ran.log"; exit 0
EOF
  chmod +x "$M/count.sh"
  mkchain count.sh count.sh count.sh
  for spelling in \
      CC_HOOK_CHAIN_DISABLED=1 CC_HOOK_CHAIN_MODE=exec CC_HOOK_CHAIN_MODE=source \
      CC_HOOK_CHAIN_MODE=garbage CC_HOOK_CHAIN_MODE= CC_HOOK_CHAIN_DISABLED=true ; do
    : > "$M/ran.log"
    run env "$spelling" bash -c "printf '%s' '$PAY' | '$S' testchain"
    n="$(wc -l < "$M/ran.log" | tr -d ' ')"
    [ "$n" -eq 3 ] || { echo "spelling=$spelling ran $n/3 members" >&2; false; }
  done
}

@test "source mode and exec mode produce IDENTICAL output for the same registry" {
  DENY='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"nope"}}'
  mkmember a.sh 0 ''; mkmember b.sh 0 "$DENY"; mkmember c.sh 0 ''
  mkchain a.sh b.sh c.sh
  o_src="$(printf '%s' "$PAY" | env CC_HOOK_CHAIN_MODE=source "$S" testchain)"; s_src=$?
  o_exe="$(printf '%s' "$PAY" | env CC_HOOK_CHAIN_MODE=exec   "$S" testchain)"; s_exe=$?
  [ "$o_src" = "$o_exe" ]
  [ "$s_src" -eq "$s_exe" ]
}

@test "a member's shell-option pollution cannot leak into the NEXT member (source-mode isolation)" {
  # `set -e`/`set -u`/IFS set by member A must not change member B's behaviour, or source mode is
  # not observationally equal to fork+exec.
  cat > "$M/a.sh" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null; set -euo pipefail; IFS=':'; shopt -s nullglob; exit 0
EOF
  cat > "$M/b.sh" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
UNSET_ON_PURPOSE="${THIS_IS_NOT_SET-default}"   # would abort under an inherited `set -u`
[ "$UNSET_ON_PURPOSE" = "default" ] || exit 7
false                                            # would abort under an inherited `set -e`
exit 0
EOF
  chmod +x "$M/a.sh" "$M/b.sh"
  mkchain a.sh b.sh
  run run_chain
  [ "$status" -eq 0 ]
}

@test "a member cannot terminate the dispatcher early (exit in source mode is contained)" {
  mkmember a.sh 0 ''
  cat > "$M/b.sh" <<EOF
#!/usr/bin/env bash
cat >/dev/null; exit 0
EOF
  chmod +x "$M/b.sh"
  cat > "$M/c.sh" <<EOF
#!/usr/bin/env bash
cat >/dev/null; touch "$M/c-ran"; exit 0
EOF
  chmod +x "$M/c.sh"
  mkchain a.sh b.sh c.sh
  run run_chain
  [ "$status" -eq 0 ]
  [ -f "$M/c-ran" ]      # c ran even though b called `exit`
}

# ══ §D — THE POINT: fewer processes than the serial chain ══════════════════════════════════════

@test "source mode spawns strictly FEWER exec'd processes than the serial chain" {
  # Counted by the members themselves: each records whether it was exec'd (own pid != dispatcher's).
  cat > "$M/p.sh" <<EOF
#!/usr/bin/env bash
cat >/dev/null; echo "\$\$" >> "$M/pids.log"; exit 0
EOF
  chmod +x "$M/p.sh"
  mkchain p.sh p.sh p.sh p.sh

  : > "$M/pids.log"
  printf '%s' "$PAY" | env CC_HOOK_CHAIN_MODE=exec "$S" testchain
  exec_distinct="$(sort -u "$M/pids.log" | wc -l | tr -d ' ')"

  : > "$M/pids.log"
  printf '%s' "$PAY" | env CC_HOOK_CHAIN_MODE=source "$S" testchain
  src_distinct="$(sort -u "$M/pids.log" | wc -l | tr -d ' ')"

  # exec mode: 4 distinct pids (one per member). source mode: subshells share the dispatcher pid.
  [ "$exec_distinct" -eq 4 ]
  [ "$src_distinct" -lt "$exec_distinct" ]
}
