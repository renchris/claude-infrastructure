#!/usr/bin/env bats
# SHIP FLOOR (CLOSE_INTEGRITY W2b) — hooks/session-continue.sh must not let a session idle silently
# on committed-but-unlanded (📦) or landed-not-live (🚀) work IT wrote.
#
# WHY: the mechanical arm deliberately refused 📦 ("the ship policy's business, not a loop") and the
# 2026-08-10 recon convicted that refusal as the load-bearing leak — the ship policy had no
# actuator, 58% of stops assert nothing, so silent 📦 idles passed every rail (62 content-stranded
# commits across 21 abandoned-wave branches). The floor is the bounded actuator. This suite pins
# the fire, BOTH bounds (one-shot per HEAD-sha; CC_SHIP_FLOOR_MAX per session), the attribution
# abstain (#105: never nudge on a sibling's commits), the 🚀 arm, the kill-switch, and the seam.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/session-continue.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/bin"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$CLAUDE_CONFIG_DIR"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"; mkdir -p "$CC_MAILBOX_DIR"
  export CONTINUE_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export ITERM_SESSION_ID="w0t0p0:BBBBBBBB-1111-2222-3333-444444444444"
  # Isolate the floor under test: the mechanical arm and the wake floor have their own suites.
  export CC_MECH_CONTINUE=0 CC_WAKE_FLOOR=0
  # THE SUITE MUST NOT BE A FUNCTION OF WHO RUNS IT (review 2026-08-10 #2, the completion-assert:26
  # lesson verbatim): the assignee oracle reads the RUNNING process's ancestry, so an agent-spawned
  # runner is itself "an assignee" and the floor abstains — 4/10 cases red purely by runner. The
  # missing-file override yields the stub ("not an assignee"), which is these fixtures' truth.
  export AGENT_IDENTITY_LIB="$BATS_TEST_TMPDIR/no-such-agent-identity.sh"
  # A REAL repo so HEAD moves when the one-shot-per-sha bound needs it to.
  CWD="$BATS_TEST_TMPDIR/wt"; mkdir -p "$CWD"
  ( cd "$CWD" && git init -q \
    && git -c user.email=t@e.com -c user.name=t commit -q --allow-empty -m c1 ) >/dev/null 2>&1
  # Ledger stub — the floor CONSUMES wrap-ledger's verdict, so the suite drives it by env.
  WRAP_STUB="$BATS_TEST_TMPDIR/wrap-stub"
  printf '%s\n' '#!/usr/bin/env bash' \
    'printf "RUNG=%s\n" "${STUB_RUNG:-📦}"' \
    'printf "TRUNK=origin/main\nAHEAD=3\nSHAS=abc1234 def5678\nDIRTY=0\nUNLANDED=1\n"' > "$WRAP_STUB"
  chmod +x "$WRAP_STUB"
  export WRAP_LEDGER_BIN="$WRAP_STUB"
  # Attribution stub — rc driven by env; the real intersection has its own suite.
  SW_STUB="$BATS_TEST_TMPDIR/sw-stub.sh"
  printf '%s\n' 'session_writes_paths() { return "${SW_WRITES_RC:-0}"; }' \
                'session_writes_paths_turn() { return "${SW_WRITES_RC:-0}"; }' \
                'session_wrote_here_this_turn() { return "${SW_WRITES_RC:-0}"; }' \
                'session_dirty_mine() { return 1; }' \
                'session_unlanded_mine() { return "${SW_UNLANDED_RC:-0}"; }' > "$SW_STUB"
  export SESSION_WRITES_LIB="$SW_STUB"
}

actuate() { printf '{"cwd":"%s","session_id":"%s","transcript_path":"%s"}' "$CWD" "${1:-sidA}" "${2:-}" | bash "$HOOK" 2>/dev/null; }
blocked() { printf '%s' "$1" | grep -q '"decision":"block"'; }
tx() {
  local p="$BATS_TEST_TMPDIR/tx-$BATS_TEST_NUMBER.jsonl"
  jq -nc --arg t "$1" '{type:"user",message:{content:[{type:"text",text:$t}]}}' > "$p"
  printf '%s' "$p"
}

@test "📦 + own unlanded work ⇒ BLOCKS naming the ship policy, and logs arm=ship-floor" {
  run actuate sidA
  blocked "$output"
  printf '%s' "$output" | jq -r .reason | grep -q 'SHIP FLOOR'
  printf '%s' "$output" | jq -r .reason | grep -q '/ship'
  grep -q '"reason":"ship-floor"' "$CONTINUE_IDL"
}

@test "one shot per HEAD-sha: the same idle again is SILENT; a new commit re-arms" {
  run actuate sidA; blocked "$output"
  run actuate sidA
  if blocked "$output"; then echo "re-blocked on the same sha" >&2; false; fi
  ( cd "$CWD" && git -c user.email=t@e.com -c user.name=t commit -q --allow-empty -m c2 ) >/dev/null 2>&1
  run actuate sidA
  blocked "$output"
}

@test "per-session budget (2): the third distinct sha does NOT block; a successor sid starts fresh" {
  run actuate sidA; blocked "$output"
  ( cd "$CWD" && git -c user.email=t@e.com -c user.name=t commit -q --allow-empty -m c2 ) >/dev/null 2>&1
  run actuate sidA; blocked "$output"
  ( cd "$CWD" && git -c user.email=t@e.com -c user.name=t commit -q --allow-empty -m c3 ) >/dev/null 2>&1
  run actuate sidA
  if blocked "$output"; then echo "third fire exceeded CC_SHIP_FLOOR_MAX" >&2; false; fi
  run actuate sidB
  blocked "$output"
}

@test "#105 direction: unlanded commits NOT mine ⇒ silent (never nudge on a sibling's work)" {
  export SW_UNLANDED_RC=1
  run actuate sidA
  if blocked "$output"; then false; fi
}

@test "attribution cannot-tell ⇒ silent (a floor never blocks on its own ignorance)" {
  export SW_UNLANDED_RC=2
  run actuate sidA
  if blocked "$output"; then false; fi
}

@test "🚀 + write evidence ⇒ BLOCKS naming the converger (deploy-live.sh)" {
  export STUB_RUNG="🚀"
  run actuate sidA
  blocked "$output"
  printf '%s' "$output" | jq -r .reason | grep -q 'deploy-live.sh'
}

@test "🚀 with NO write evidence ⇒ silent (a repo-wide converger outage must not nudge every session)" {
  export STUB_RUNG="🚀" SW_WRITES_RC=1
  run actuate sidA
  if blocked "$output"; then false; fi
}

@test "operator kill-switch wins: '…and stop' in the last user message ⇒ silent" {
  t="$(tx 'commit what you have and stop')"
  run actuate sidA "$t"
  if blocked "$output"; then false; fi
}

@test "SEAM: CC_SHIP_FLOOR=0 disables the floor outright" {
  CC_SHIP_FLOOR=0 run actuate sidA
  if blocked "$output"; then false; fi
}

@test "✅ rung ⇒ silent (the floor owns 📦/🚀 only)" {
  export STUB_RUNG="✅"
  run actuate sidA
  if blocked "$output"; then false; fi
}
