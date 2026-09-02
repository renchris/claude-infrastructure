#!/usr/bin/env bats
# session-continue.sh mechanical_arm — THE PEER EXEMPTION (2026-09-02).
#
# Both sibling floors stand down for a peer: ship_floor :865-869, wake_floor :587-608. The
# mechanical arm checked NEITHER, so ONE hook gave THREE different answers about the same class of
# session — a confirmed Agent-Teams assignee with its own dirty files was exempt from the ship
# floor, exempt from the wake floor, and blocked here.
#
# Why that is the wrong actor rather than a wrong fact: the dirty tree is REAL (the ledger is
# right), but an assignee's close is the LEAD's harvest. Blocking it makes the assignee keep taking
# turns over dirt it cannot discharge — the merge is not its to do. Who-vs-when, session-writes.sh
# :13-22.
#
# Semantics under test are ship_floor's — rc 0 (confirmed) OR rc 2 (cannot tell) both exempt — NOT
# wake_floor's, which also exempts argv-only. The three floors are not interchangeable.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/session-continue.sh"
  # HERMETIC: the hook's lib-resolution chain and its teardown/mailbox readers all fall back to
  # $HOME/.claude/…, so an unfixtured suite reads — and can write — the operator's live tree. Both
  # libs this arm actually needs are pinned by env below, so those fallbacks are never the resolver
  # here; fixturing HOME removes the ambient path without changing what is under test.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"
  export CLAUDE_CONTINUE_FILE="$BATS_TEST_TMPDIR/cont"
  export CONTINUE_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CONTINUE_LOG="$BATS_TEST_TMPDIR/cont.log"
  export ITERM_SESSION_ID="w0t0p0:CCCCCCCC-1111-2222-3333-444444444444"
  # Isolate the arm under test — the other two floors have their own suites.
  export CC_SHIP_FLOOR=0 CC_WAKE_FLOOR=0
  CWD="$BATS_TEST_TMPDIR/wt"; mkdir -p "$CWD"
  ( cd "$CWD" && git init -q \
    && git -c user.email=t@e.com -c user.name=t commit -q --allow-empty -m c1 ) >/dev/null 2>&1
  # Ledger stub: 🔧 over a dirty tree is exactly the state the mechanical arm exists to act on.
  WRAP_STUB="$BATS_TEST_TMPDIR/wrap-stub"
  printf '%s\n' '#!/usr/bin/env bash' \
    'printf "RUNG=🔧\nDIRTY=1\nUNLANDED=0\nREMAINDER=0\nTRUNK=origin/main\nAHEAD=0\n"' > "$WRAP_STUB"
  chmod +x "$WRAP_STUB"; export WRAP_LEDGER_BIN="$WRAP_STUB"
  # Attribution stub: the dirt IS this session's, so ONLY the peer exemption can stop the block.
  SW_STUB="$BATS_TEST_TMPDIR/sw-stub.sh"
  printf '%s\n' 'session_dirty_mine() { printf "a.txt\n"; return 0; }' \
                'session_writes_paths() { return 0; }' \
                'session_writes_paths_turn() { return 0; }' \
                'session_wrote_here_this_turn() { return 0; }' \
                'session_unlanded_mine() { return 1; }' > "$SW_STUB"
  export SESSION_WRITES_LIB="$SW_STUB"
}

# Assignee oracle driven by env, so one fixture covers confirmed / cannot-tell / refuted.
ai_stub() { # $1 = rc for agent_team_member_confirms; empty argv id ⇒ "not an assignee"
  local p="$BATS_TEST_TMPDIR/ai-stub.sh"
  printf '%s\n' "agent_assignee_argv() { [ -n \"\${AI_ID:-}\" ] && printf '%s' \"\$AI_ID\" && return 0; return 1; }" \
                "agent_team_member_confirms() { return \${AI_CONFIRM:-$1}; }" > "$p"
  export AGENT_IDENTITY_LIB="$p"
}
actuate() { printf '{"cwd":"%s","session_id":"%s"}' "$CWD" "${1:-sidM}" | bash "$HOOK" 2>/dev/null; }
blocked() { printf '%s' "$1" | grep -q '"decision":"block"'; }

@test "CONTROL: not an assignee ⇒ the mechanical arm still BLOCKS (fixture reaches the arm)" {
  ai_stub 1; unset AI_ID
  run actuate sid-ctl
  [ "$status" -eq 0 ]; blocked "$output"
}

@test "a CONFIRMED assignee (rc 0) with its own dirty files ⇒ EXEMPT" {
  ai_stub 0; export AI_ID="member-x"
  run actuate sid-c0
  [ "$status" -eq 0 ]; ! blocked "$output"
  /usr/bin/grep -q 'mechanical-assignee' "$CONTINUE_IDL"
}

@test "CANNOT-TELL (rc 2) is exempt too — ship_floor's semantics, never nudge on ignorance" {
  ai_stub 2; export AI_ID="member-y"
  run actuate sid-c2
  [ "$status" -eq 0 ]; ! blocked "$output"
  /usr/bin/grep -q 'mechanical-assignee' "$CONTINUE_IDL"
}

@test "REFUTED (rc 1) is NOT exempt — the exemption is not a blanket off-switch" {
  ai_stub 1; export AI_ID="member-z"
  run actuate sid-c1
  [ "$status" -eq 0 ]; blocked "$output"
}
