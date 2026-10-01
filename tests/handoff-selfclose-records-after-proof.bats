#!/usr/bin/env bats
# Pane-lifecycle fixes 2026-10-01, item 3 (docs/plans/pane-lifecycle-fixes-2026-10-01.md; evidence
# docs/research/selfclose-failures-2026-10-01.md M10).
#
# closedAt (record_close_succession) and the originator's custody return were written BEFORE the arm
# loop, which can still abort with /exit never typed. Pane 32: closedAt 02:25:07Z and custody
# `w1-land-truth` returned at 02:23:24Z, while the pane stayed open. Both now run only after the pane
# is proven. The custody return also used to run above the --dry-run exit, so a dry run discharged it.
#
# The pane probe is the watcher's `$HOME/.claude/bin/it2 session list --json`, so a fake HOME with a
# stub it2 decides the proof: a failing stub is a deaf terminal (proof rc 3), a listing that names the
# pane is a proven pane.

setup() {
  command -v jq >/dev/null || skip "jq required"
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
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
  export CC_SELFCLOSE_NOANSWER_ARMS=1          # give up at once on a deaf terminal
  export CC_CLOSE_LEDGER_GUARD=0               # the ledger refusal is a different gate
  STUB="$BATS_TEST_TMPDIR/cp-stub.sh"; printf '#!/bin/bash\nexit 0\n' > "$STUB"; chmod +x "$STUB"
  export CC_COMPLETION_PUSH_BIN="$STUB"
  WORK="$BATS_TEST_TMPDIR/work"; mkdir -p "$WORK"; WORK="$(cd "$WORK" && pwd -P)"
  PANE="fake:RRRR-0001"
  MARKER="HANDOFF-ENGAGE-7777-1790880000-1"
  jq -n --arg p "$PANE" --arg c "$WORK" --arg m "$MARKER" \
    '{paneUUID:$p, cwd:$c, firedBy:"ORIGIN-PANE-77", firedAt:"2026-10-01T00:00:00Z", selfRetire:true,
      schema:2, originClass:"fired-peer", originator:"ORIGIN-PANE-77", marker:$m, closedAt:null, succession:null}' \
    > "$CC_FIRED_DIR/$PANE.json"
  "$REPO/bin/cc-custody" open --cwd "$BATS_TEST_TMPDIR" --target "$PANE" --marker "$MARKER" --slug rec-test
  [ "$(open_custody)" = 1 ] || { echo "fixture: custody row did not open"; return 1; }
}

open_custody() { "$REPO/bin/cc-custody" count --open --cwd "$BATS_TEST_TMPDIR"; }
closed_at() { jq -r '.closedAt // "null"' "$CC_FIRED_DIR/$PANE.json"; }
it2_stub() { printf '#!/bin/bash\n%s\n' "$1" > "$HOME/.claude/bin/it2"; chmod +x "$HOME/.claude/bin/it2"; }
selfclose() { ( cd "$WORK" && timeout 90 bash "$HF" self-close --terminal --session-id "$PANE" "$@" 2>&1 ); }

@test "deaf terminal: the close aborts, and closedAt + custody are NOT written" {
  it2_stub 'echo "deaf (test stub)" >&2; exit 1'
  run selfclose
  [ "$status" -ne 0 ] || { echo "expected an abort"; echo "$output"; false; }
  [[ "$output" == *"never answered the pane probe"* ]] || { echo "$output"; false; }
  [ "$(closed_at)" = null ] || { echo "closedAt written for a close that did not happen: $(closed_at)"; false; }
  [ "$(open_custody)" = 1 ] || { echo "custody discharged for a close that did not happen"; false; }
}

@test "proven pane: closedAt + custody ARE written (before /exit is typed)" {
  it2_stub 'case "$*" in *"session list"*) printf "[{\"id\":\"fake:RRRR-0001\"}]\n" ;; esac; exit 0'
  run selfclose
  [ "$(closed_at)" != null ] || { echo "closedAt missing after a proven arm"; echo "$output"; false; }
  [ "$(open_custody)" = 0 ] || { echo "custody still open after a proven arm"; echo "$output"; false; }
}

@test "--dry-run writes neither closedAt nor the custody return" {
  it2_stub 'exit 1'
  run selfclose --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(open_custody)" = 1 ] || { echo "a DRY RUN discharged the originator's custody"; false; }
  [ "$(closed_at)" = null ] || false
  [[ "$output" == *"written only after the pane proof"* ]] || { echo "$output"; false; }
}
