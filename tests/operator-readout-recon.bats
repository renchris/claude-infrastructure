#!/usr/bin/env bats
# operator-readout.sh — the LR-RECON line (docs/plans/LIMIT_RECOVER_FLEET_V2_ARCHITECTURE.md §C11).
# The reconciler writes its one counted line to <recon root>/readout.line every pass; the hook only
# relays it. Proves:
#   · recon.on + a non-empty readout.line + a fresh heartbeat ⇒ the line, verbatim, led by ` ⟳`
#   · recon.on absent ⇒ no line (the cutover is the operator's)
#   · a heartbeat older than 180 s ⇒ the stale line INSTEAD of the relayed one
#   · an empty readout.line (nothing open) or a torn heartbeat ⇒ nothing, exit 0
#   · the numbered-step count (NSTEPS) is unchanged by the line
# All state lives under a temp LR_STATE_DIR; the operator's ~/.reso is never read.

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
  export CC_RESUME_DEBT_BIN=none
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/lr"
  RR="$LR_STATE_DIR/recon"; mkdir -p "$RR"
  LINE='lr-recon: 1 cohort open · 0 moving · 0 waiting · 1 held · 0 escalated · bg-held: session abcdef01 (pane 5:7, repo) pages 10:40 (60 min, ship-land)'
  printf '%s' "$LINE" > "$RR/readout.line"          # the daemon writes no trailing newline
  heartbeat $((CC_OPREADOUT_NOW - 5))
  : > "$LR_STATE_DIR/recon.on"
}

heartbeat() { printf '{"pid":4242,"progress_wall":%s.25,"uptime":12.5}\n' "$1" > "$RR/heartbeat"; }

@test "recon.on + readout.line + fresh heartbeat renders the line verbatim" {
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qxF " ⟳ $LINE" || { echo "$output"; false; }
  [ "$(echo "$output" | grep -c 'lr-recon:')" -eq 1 ]
  # NSTEPS invariant: the numbered-step count is what it is with the line absent
  with="$(echo "$output" | grep -cE '^ [0-9]+ (▶|◆|✎)' || true)"
  rm -f "$LR_STATE_DIR/recon.on"
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  [ "$with" = "$(echo "$output" | grep -cE '^ [0-9]+ (▶|◆|✎)' || true)" ]
}

@test "recon.on absent renders no lr-recon line" {
  rm -f "$LR_STATE_DIR/recon.on"
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'OPERATOR' || { echo "$output"; false; }     # the block itself rendered
  ! echo "$output" | grep -q 'lr-recon' || false
}

@test "a heartbeat older than 180 s renders the stale line instead" {
  heartbeat $((CC_OPREADOUT_NOW - 181))
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qxF ' ⚠ lr-recon: reconciler heartbeat stale 3m01s — the reset poller is paging and kickstarting it' \
    || { echo "$output"; false; }
  ! echo "$output" | grep -qF 'bg-held' || false
  heartbeat $((CC_OPREADOUT_NOW - 7500))
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -qF 'heartbeat stale 2h05m —' || { echo "$output"; false; }
  heartbeat $((CC_OPREADOUT_NOW - 180))                 # the boundary is still fresh
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -qxF " ⟳ $LINE" || { echo "$output"; false; }
}

@test "an empty readout.line or a torn heartbeat renders nothing and exits 0" {
  : > "$RR/readout.line"
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'OPERATOR' || { echo "$output"; false; }
  ! echo "$output" | grep -q 'lr-recon' || false
  printf '%s' "$LINE" > "$RR/readout.line"
  printf '{"pid":4242,"progress_wa' > "$RR/heartbeat"
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'lr-recon' || false
  rm -f "$RR/heartbeat"
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'lr-recon' || false
}

@test "a stale heartbeat is shown even when nothing is open (empty readout.line)" {
  : > "$RR/readout.line"
  heartbeat $((CC_OPREADOUT_NOW - 400))
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qxF ' ⚠ lr-recon: reconciler heartbeat stale 6m40s — the reset poller is paging and kickstarting it' \
    || { echo "$output"; false; }
}
