#!/usr/bin/env bats
# operator-readout.sh — the STRANDED SESSIONS line (docs/plans/CLOSE_RESUME_CUSTODY.md §2 D4).
# A session a mover closed and could not relaunch escalates to ONE `cc-backlog needs` row, which in
# the standing pile is buried inside a collapsed `◆ N blocked backlog` count with its `▶` never
# printed. This line itemises those debts (up to 3) with their command. Proves:
#   · two escalated debts render two `▶ cc-do <id>` rows carrying the sid's first 8 chars
#   · zero debts render no stranded line
#   · an absent or failing tool renders none, and the hook still exits 0
#   · five debts render three rows plus `+2 more`; a row without a backlog id renders `◆ … settle`
#   · the numbered-step count (NSTEPS) is unchanged by the line
# cc-resume-debt is a stub behind CC_RESUME_DEBT_BIN that prints a fixture file.

setup() {
  export CC_FIRE_CAPACITY_GATE=off
  export CC_ADMIT_GATE=off
  unset CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID CC_SESSION_ID
  export CC_BACKLOG_PROJECT_WARN=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/operator-readout.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_OPREADOUT_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_ACTIVATION_DIR="$BATS_TEST_TMPDIR/activation"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_BIN="$REPO/bin/cc-backlog"
  export CC_ORB_BLG_CACHE_DIR="$BATS_TEST_TMPDIR/blg-cache"
  export WRAP_LEDGER_BIN="$REPO/scripts/wrap-ledger.sh"
  export WRAP_TRUNK="origin/main"
  export CC_SHARED_CHECKOUT="$BATS_TEST_TMPDIR/no-such-checkout"
  export CC_OPREADOUT_NOW=1000000
  export CC_OPREADOUT_TTL_S=900
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/.dispatch-kick"
  export CC_BACKLOG_KICK_BIN="$BATS_TEST_TMPDIR/no-such-dispatch"
  export CC_HANDOFF_ALARM_DIR="$BATS_TEST_TMPDIR/handoff-alarms"
  export CC_ANNOUNCE_ALARM_DIR="$BATS_TEST_TMPDIR/announce-alarms"
  export CC_COMPLETION_RECORDS_DIR="$BATS_TEST_TMPDIR/completion-push"
  export CC_PAGES_DIR="$BATS_TEST_TMPDIR/pages"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mailbox"
  export CC_SWEEP_SEEN_DIR="$BATS_TEST_TMPDIR/sweep-seen"
  mkdir -p "$CC_ACTIVATION_DIR" "$CC_DECISIONS_DIR" "$CC_HANDOFF_ALARM_DIR" \
           "$CC_ANNOUNCE_ALARM_DIR" "$CC_COMPLETION_RECORDS_DIR" "$CC_PAGES_DIR" \
           "$CC_MAILBOX_DIR/dead-letter" "$CC_SWEEP_SEEN_DIR"
  : > "$CC_BACKLOG_FILE"
  # One real step, because the block (and so this line) renders only when something is pending.
  printf '#!/bin/bash\necho hi\n' > "$CC_ACTIVATION_DIR/10-plain-activate.sh"
  # the stub: `list --escalated --json` prints the fixture; anything else is an error
  FIX="$BATS_TEST_TMPDIR/escalated.json"; printf '[]\n' > "$FIX"
  export CC_RESUME_DEBT_BIN="$BATS_TEST_TMPDIR/cc-resume-debt"
  cat > "$CC_RESUME_DEBT_BIN" <<EOF
#!/bin/bash
[ "\$*" = "list --escalated --json" ] || exit 2
cat "$FIX"
EOF
  chmod +x "$CC_RESUME_DEBT_BIN"
}

debt() { # <backlog_id|""> <sid> <cwd> <account> → one JSON object
  jq -cn --arg b "$1" --arg s "$2" --arg c "$3" --arg a "$4" \
    '{sid:$s, cwd:$c, account:$a, state:"escalated"} + (if $b == "" then {} else {backlog_id:$b} end)'
}
fixture() { jq -s . > "$FIX"; }   # stdin: JSON objects → the fixture array
hookrun() { # $1=cwd → hook mode with stdin JSON (tests/operator-readout.bats's helper)
  printf '{"session_id":"t-%s","cwd":"%s"}' "$BATS_TEST_NUMBER" "${1:-}" | "$HOOK"
}

@test "two escalated debts render two ▶ cc-do rows carrying the sid's first 8 chars" {
  { debt bl0000000001 11111111-aaaa-4000-8000-000000000001 /Users/x/Development/reso next3
    debt bl0000000002 22222222-bbbb-4000-8000-000000000002 /Users/x/Development/infra next; } | fixture
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx ' ⚠ 2 stranded session(s) — closed by a mover, relaunch failed:' || { echo "$output"; false; }
  echo "$output" | grep -qxF '   ▶ cc-do bl0000000001   [11111111 · reso · next3]' || { echo "$output"; false; }
  echo "$output" | grep -qxF '   ▶ cc-do bl0000000002   [22222222 · infra · next]' || false
  [ "$(echo "$output" | grep -c '▶ cc-do bl')" -eq 2 ]
  # NSTEPS invariant: the numbered-step count is what it is with the line absent
  with="$(echo "$output" | grep -cE '^ [0-9]+ (▶|◆|✎)' || true)"
  CC_RESUME_DEBT_BIN=none run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  ! echo "$output" | grep -q 'stranded' || false
  [ "$with" = "$(echo "$output" | grep -cE '^ [0-9]+ (▶|◆|✎)' || true)" ]
}

@test "zero escalated debts render NO stranded line" {
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'OPERATOR' || { echo "$output"; false; }     # the block itself rendered
  ! echo "$output" | grep -q 'stranded' || false
}

@test "an absent or failing tool renders nothing, and the Stop hook still exits 0" {
  export CC_RESUME_DEBT_BIN="$BATS_TEST_TMPDIR/no-such-cc-resume-debt"
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'stranded' || false
  # failing: non-zero exit with JSON-shaped junk on stdout — never half-rendered
  export CC_RESUME_DEBT_BIN="$BATS_TEST_TMPDIR/failing-rd"
  printf '#!/bin/bash\necho "[{\\"sid\\":\\"x\\"}]"\necho boom >&2\nexit 1\n' > "$CC_RESUME_DEBT_BIN"; chmod +x "$CC_RESUME_DEBT_BIN"
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'stranded\|boom' || false
  # hook mode, same failing tool: exit 0 and no stranded text in the systemMessage
  run hookrun "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'stranded\|boom' || false
}

@test "five debts render three rows plus '+2 more'; a row without a backlog id renders ◆ settle" {
  { debt ""           33333333-0000-4000-8000-000000000001 /w/alpha next
    debt bl0000000002 33333333-0000-4000-8000-000000000002 /w/beta  next2
    debt bl0000000003 33333333-0000-4000-8000-000000000003 /w/gamma next3
    debt bl0000000004 33333333-0000-4000-8000-000000000004 /w/delta next4
    debt bl0000000005 33333333-0000-4000-8000-000000000005 /w/eps   next; } | fixture
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q ' ⚠ 5 stranded session(s)' || { echo "$output"; false; }
  echo "$output" | grep -qxF '   ◆ cc-resume-debt settle --sid 33333333-0000-4000-8000-000000000001   [33333333 · alpha · next]' \
    || { echo "$output"; false; }
  [ "$(echo "$output" | grep -cE '^   (▶ cc-do|◆ cc-resume-debt settle) ')" -eq 3 ]
  echo "$output" | grep -qxF '   … +2 more — cc-resume-debt list --escalated' || false
  ! echo "$output" | grep -q 'bl0000000004' || false
}
