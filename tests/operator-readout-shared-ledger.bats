#!/usr/bin/env bats
# operator-readout-shared-ledger — how operator-readout asks the ledger (Wave 4c,
# docs/plans/LOAD_AND_PROMPT_HOOK_TIMEOUTS.md).
#
# Before: one BUSY-on ask with `--session`, on a memo key of its own — a second full ledger beside the
# one session-continue, boundary-handoff and completion-assert share — and the process-table probe on
# every Stop, for fields read only by the ⏳ notice under an EMPTY block. Now: the render asks the
# shared BUSY-off ledger (no `--session` when the environment already names the session), and the
# notice arm asks for BUSY only when it is reached. A logging stub ledger records every ask; the
# rendering itself is pinned by tests/operator-readout.bats against the real ledger.

setup() {
  export CC_BACKLOG_PROJECT_WARN=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/operator-readout.sh"
  export CC_OPREADOUT_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_ACTIVATION_DIR="$BATS_TEST_TMPDIR/activation"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_BIN="$REPO/bin/cc-backlog"
  export CC_ORB_BLG_CACHE_DIR="$BATS_TEST_TMPDIR/blg-cache"
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
  export CC_RESUME_DEBT_BIN=none
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/lr" LR_RECON_ROOT="$BATS_TEST_TMPDIR/lr/recon"
  export CC_RESEARCH_REGISTRY="$BATS_TEST_TMPDIR/no-research-registry.json"
  mkdir -p "$CC_ACTIVATION_DIR" "$CC_DECISIONS_DIR" "$CC_HANDOFF_ALARM_DIR" \
           "$CC_ANNOUNCE_ALARM_DIR" "$CC_COMPLETION_RECORDS_DIR" "$CC_PAGES_DIR" \
           "$CC_MAILBOX_DIR/dead-letter" "$CC_SWEEP_SEEN_DIR"
  : > "$CC_BACKLOG_FILE"
  unset WRAP_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID CC_OR_SHARED_LEDGER CC_BUSY_NOTICE WRAP_BUSY

  # The stub ledger: one line per ask in $ASKS (WRAP_BUSY and argv), the rung from $STUB_RUNG, and —
  # like the real ledger — real BUSY fields only when BUSY was asked for.
  export ASKS="$BATS_TEST_TMPDIR/asks.log"; : > "$ASKS"
  export WRAP_LEDGER_BIN="$BATS_TEST_TMPDIR/stub-ledger.sh"
  cat > "$WRAP_LEDGER_BIN" <<'STUB'
#!/bin/bash
printf 'busy=%s args=%s\n' "${WRAP_BUSY:-on}" "$*" >> "$ASKS"
case "${1:-}" in --machine) ;; *) printf 'stub\n'; exit 0 ;; esac
printf 'RUNG=%s\nAHEAD=%s\nSHAS=%s\nDIRTY_N=%s\nGATE=green\nREMAINDER=0\nUNLANDED=0\nDOD=present\nSCOPE=met\n' \
  "$STUB_RUNG" "${STUB_AHEAD:-0}" "${STUB_SHAS:-}" "${STUB_DIRTY:-0}"
if [ "${WRAP_BUSY:-on}" = off ]; then
  printf 'BUSY=0\nBUSY_STATE=UNKNOWN\nBUSY_SRC=none\nBUSY_AGE=0\nBUSY_SUSPECT=0\nBUSY_SAMPLE=\nPERMPEND=0\nPERMPEND_AGE=0\n'
else
  printf 'BUSY=0\nBUSY_STATE=IDLE-DEAF\nBUSY_SRC=none\nBUSY_AGE=5\nBUSY_SUSPECT=0\nBUSY_SAMPLE=no-wake-path\nPERMPEND=0\nPERMPEND_AGE=0\n'
fi
STUB
  chmod +x "$WRAP_LEDGER_BIN"
  W="$BATS_TEST_TMPDIR/w"; mkdir -p "$W"
}

stop() { # $1 = session id in the Stop payload
  printf '{"session_id":"%s","cwd":"%s"}' "$1" "$W" | "$HOOK"
}

@test "a non-empty block: ONE ledger ask, BUSY-off, and no BUSY probe" {
  export STUB_RUNG="📦" STUB_AHEAD=1 STUB_SHAS=abc1234
  run stop "t-$BATS_TEST_NUMBER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"📦"* ]] || { echo "$output"; false; }
  [ "$(wc -l < "$ASKS" | tr -d ' ')" -eq 1 ] || { cat "$ASKS"; false; }
  grep -q '^busy=off args=--machine' "$ASKS"
}

@test "an empty block reaches the ⏳ arm, which asks for BUSY itself and renders it" {
  export STUB_RUNG="🔧" STUB_DIRTY=1
  run stop "t-$BATS_TEST_NUMBER"
  [ "$status" -eq 0 ]
  # The notice renders the BUSY ask's IDLE-DEAF — the BUSY-off ask said UNKNOWN, which renders nothing.
  [[ "$output" == *"no wake path armed"* ]] || { echo "$output"; cat "$ASKS"; false; }
  [ "$(wc -l < "$ASKS" | tr -d ' ')" -eq 2 ] || { cat "$ASKS"; false; }
  [ "$(sed -n 1p "$ASKS")" = "busy=off args=--machine --session t-$BATS_TEST_NUMBER" ]
  [ "$(sed -n 2p "$ASKS")" = "busy=on args=--machine --session t-$BATS_TEST_NUMBER" ]
}

@test "CC_BUSY_NOTICE=0: the empty-block path makes no BUSY ask" {
  export STUB_RUNG="🔧" STUB_DIRTY=1 CC_BUSY_NOTICE=0
  run stop "t-$BATS_TEST_NUMBER"
  [ "$status" -eq 0 ]
  [[ "$output" != *"⏳"* ]]
  [ "$(wc -l < "$ASKS" | tr -d ' ')" -eq 1 ] || { cat "$ASKS"; false; }
}

@test "the session flag is dropped when the environment already names the session, kept otherwise" {
  export STUB_RUNG="📦" STUB_AHEAD=1 STUB_SHAS=abc1234
  # A fresh state dir per Stop: the hook damps a repeat of the same block for the same session.
  CC_OPREADOUT_STATE_DIR="$BATS_TEST_TMPDIR/s1" CLAUDE_CODE_SESSION_ID="t-same" run stop "t-same"
  [ "$(cat "$ASKS")" = "busy=off args=--machine" ] || { cat "$ASKS"; false; }
  : > "$ASKS"
  CC_OPREADOUT_STATE_DIR="$BATS_TEST_TMPDIR/s2" CLAUDE_CODE_SESSION_ID="t-other" run stop "t-same"
  [ "$(cat "$ASKS")" = "busy=off args=--machine --session t-same" ] || { cat "$ASKS"; false; }
  : > "$ASKS"
  CC_OPREADOUT_STATE_DIR="$BATS_TEST_TMPDIR/s3" CC_OR_SHARED_LEDGER=off CLAUDE_CODE_SESSION_ID="t-same" \
    run stop "t-same"
  [ "$(cat "$ASKS")" = "busy=off args=--machine --session t-same" ] || { cat "$ASKS"; false; }
}

@test "with the flag dropped, the ⏳ arm's BUSY ask repeats the same argument shape" {
  export STUB_RUNG="🔧" STUB_DIRTY=1
  CLAUDE_CODE_SESSION_ID="t-same" run stop "t-same"
  [[ "$output" == *"no wake path armed"* ]] || { echo "$output"; false; }
  [ "$(sed -n 1p "$ASKS")" = "busy=off args=--machine" ]
  [ "$(sed -n 2p "$ASKS")" = "busy=on args=--machine" ]
}
