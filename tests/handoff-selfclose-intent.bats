#!/usr/bin/env bats
# Reboot-resume R1 (docs/research/reboot-resume-2026-10-21/REPORT.md item 1): `self-close` writes a
# terminal-intent record, ~/.claude/autonomy/self-close-intent/<sid>, as it starts, and removes it on
# every scripted abort. The restore classifier reads it as verdict RETIRED, so a session that was
# retiring itself when the power went is not relaunched as an idle pane (5d19ef73, 2026-10-21).
#
# Harness: the records-after-proof fixture. The pane probe is the watcher's `$HOME/.claude/bin/it2
# session list --json`, so a stub it2 decides the proof: failing = a deaf terminal (abort), naming
# the pane = a proven pane (the close proceeds and types /exit into a pane that does not exist).

setup() {
  command -v jq >/dev/null || skip "jq required"
  export CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off
  unset KITTY_WINDOW_ID KITTY_LISTEN_ON
  export CC_TERM=iterm2
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/bin"
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/cc-fired";   mkdir -p "$CC_FIRED_DIR"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg";     mkdir -p "$CC_REGISTRY_DIR"
  export CC_CUSTODY_DIR="$BATS_TEST_TMPDIR/custody"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mailbox"
  export CC_COMMS_ALARM_DIR="$BATS_TEST_TMPDIR/comms-alarms"
  export CC_HANDOFF_ALARM_DIR="$BATS_TEST_TMPDIR/handoff-alarms"
  export CC_PANE_CLOSE_QUEUE_DIR="$BATS_TEST_TMPDIR/pane-close-queue"
  export CC_PCQ_LOG="$BATS_TEST_TMPDIR/pane-close-retry.log"
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  export CC_SELFCLOSE_NOANSWER_ARMS=1
  export CC_CLOSE_LEDGER_GUARD=0
  export CLAUDE_CODE_SESSION_ID="aaaaaaaa-1111-2222-3333-444444444444"
  export CC_SELF_CLOSE_INTENT_DIR="$BATS_TEST_TMPDIR/self-close-intent"
  INTENT="$CC_SELF_CLOSE_INTENT_DIR/$CLAUDE_CODE_SESSION_ID"
  STUB="$BATS_TEST_TMPDIR/cp-stub.sh"; printf '#!/bin/bash\nexit 0\n' > "$STUB"; chmod +x "$STUB"
  export CC_COMPLETION_PUSH_BIN="$STUB"
  WORK="$BATS_TEST_TMPDIR/work"; mkdir -p "$WORK"; WORK="$(cd "$WORK" && pwd -P)"
  PANE="fake:RRRR-0001"
  jq -n --arg p "$PANE" --arg c "$WORK" \
    '{paneUUID:$p, cwd:$c, firedBy:"ORIGIN-PANE-77", firedAt:"2026-10-01T00:00:00Z", selfRetire:true,
      schema:2, originClass:"fired-peer", originator:"ORIGIN-PANE-77", marker:"HANDOFF-ENGAGE-7777-1790880000-1",
      closedAt:null, succession:null}' > "$CC_FIRED_DIR/$PANE.json"
}

it2_stub() { printf '#!/bin/bash\n%s\n' "$1" > "$HOME/.claude/bin/it2"; chmod +x "$HOME/.claude/bin/it2"; }
selfclose() { ( cd "$WORK" && timeout 400 bash "$HF" self-close --terminal --session-id "$PANE" "$@" 2>&1 ); }

@test "proven pane: the close proceeds and the terminal-intent record STAYS, naming the mode" {
  it2_stub 'case "$*" in *"session list"*) printf "[{\"id\":\"fake:RRRR-0001\"}]\n" ;; esac; exit 0'
  run selfclose
  [ -f "$INTENT" ] || { echo "no intent record after a close that went ahead"; echo "$output"; false; }
  grep -q 'mode=terminal' "$INTENT" || { cat "$INTENT"; false; }
  grep -q "pane=$PANE" "$INTENT" || { cat "$INTENT"; false; }
  grep -Eq '^ts=[0-9]+ ' "$INTENT" || { cat "$INTENT"; false; }
}

@test "deaf terminal: the close ABORTS and the record is removed (an abort is not a retirement)" {
  it2_stub 'echo "deaf (test stub)" >&2; exit 1'
  run selfclose
  [ "$status" -ne 0 ] || { echo "expected an abort"; echo "$output"; false; }
  [[ "$output" == *"never answered the pane probe"* ]] || { echo "$output"; false; }
  [ ! -e "$INTENT" ] || { echo "intent left behind by an aborted close: $(cat "$INTENT")"; false; }
}

@test "an argument refusal and --dry-run leave no record" {
  it2_stub 'exit 1'
  run selfclose --successor "fake:OTHER-0002"      # --successor with --terminal: exit 2
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [ ! -e "$INTENT" ] || false
  run selfclose --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -e "$INTENT" ] || false
}

@test "a SIGNAL mid-close keeps the record: a shutdown is the death it exists to explain" {
  # The proof stalls (the stub sleeps), so the close is parked in its arm loop when the HUP lands.
  it2_stub 'sleep 20; exit 1'
  ( cd "$WORK" && exec bash "$HF" self-close --terminal --session-id "$PANE" ) >/dev/null 2>&1 &
  pid=$!
  for _ in $(seq 1 100); do [ -f "$INTENT" ] && break; sleep 0.2; done
  [ -f "$INTENT" ] || { kill "$pid" 2>/dev/null; echo "the record was never written"; false; }
  sleep 1
  kill -HUP "$pid" 2>/dev/null || true
  rc=0; wait "$pid" 2>/dev/null || rc=$?
  [ -f "$INTENT" ] || { echo "a signalled close removed the record (rc $rc)"; false; }
}

@test "a --fired-peer or remote close writes no record for the CALLER's session" {
  it2_stub 'exit 1'
  run selfclose --fired-peer "fake:PEER-0003"
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [ ! -e "$INTENT" ] || false
}
