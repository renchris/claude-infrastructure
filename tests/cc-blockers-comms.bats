#!/usr/bin/env bats
# shellcheck shell=bash
#   bats files are bash with @test sugar and shellcheck has no bats mode, so the shell is declared
#   explicitly (SC1008).
# cc-blockers × COMMS — cross-session mail v3 D12 (cc-backlog 02ba4e52389a).
#
# cc-inbox-guard writes `undelivered-escalated` / `enqueue-failed-escalated` rows onto the board and
# nothing rendered them: loud to disk, silent to the operator. These tests pin the READING half:
#   · a still-undelivered escalation renders, with the exact RECOVER command
#   · RELEASE is re-measured from the mailbox cursors, never inferred from the append-only row —
#     a drained box and an archived (vanished) box both clear with no write anywhere
#   · fixture-origin rows, other actors, and rows past the window never render
#   · the kill switch and a malformed board fail OPEN, and take no sibling family down
#
# Assertion style: `[ ]` throughout — a non-final `[[ ]]` / `!` is errexit-EXEMPT under bats and
# therefore a DEAD assertion.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  B="$REPO/bin/cc-blockers"
  D="$BATS_TEST_TMPDIR"
  export HOME="$D/home"; mkdir -p "$HOME/.claude"
  # Every sibling sensor pinned to an ABSENT path: each fails open on a missing one, which is the
  # silence these tests want from everything that is not the comms family.
  export CC_REAPER_IDL="$D/idl.jsonl"
  export CC_POSTLAND_DIR="$D/postland"; mkdir -p "$CC_POSTLAND_DIR/stamps"
  export CC_LAND_LOG="$D/absent-land.log"
  export DEPLOY_REPO="$D/absent-repo"
  export CC_BLOCKERS_ACCOUNTS_BIN="$D/absent-claude-accounts"
  export CC_DISPATCH_LOG="$D/absent-dispatcher.log"
  export CC_PERMPEND_DIR="$D/absent-permission-pending"
  export CC_BEACON_HOOK="$D/absent-hook.sh"
  export CC_BEACON_CONFIG_DIRS="$D/cfg-void"
  export CC_REGISTRY_DIR="$D/registry"
  export CC_TEAM_ROOTS="$D/absent-teams"
  export CC_WATCHDOG_DIR="$D/watchdog"; mkdir -p "$CC_WATCHDOG_DIR"
  export CC_REAP_ALARM_SH="$D/absent-reap-alarm.sh"
  export CC_WTGC_ASSERT_SH="$D/absent-wtgc-assert.sh"
  export CC_MAILBOX_DIR="$D/mbox"; mkdir -p "$CC_MAILBOX_DIR"
  U=11111111-2222-3333-4444-555555555555
  V=66666666-7777-8888-9999-AAAAAAAAAAAA
}

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
ago_iso() { # <seconds ago> — portable: epoch arithmetic through python, no BSD/GNU date flags
  python3 -c "import datetime,sys;print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=int(sys.argv[1]))).strftime('%Y-%m-%dT%H:%M:%SZ'))" "$1"
}
esc() { # <uuid> <kind> [ts] [extra-json] — append a cc-inbox-guard escalation row, as idl_rec writes it
  jq -nc --arg ts "${3:-$(now_iso)}" --arg u "$1" --arg k "$2" --argjson x "${4:-{\}}" \
    '{ts:$ts, actor:"cc-inbox-guard", uuid:$u, kind:$k, reason:"LIVE session, 3 message(s) unconsumed", msg:"hello"} + $x' \
    >> "$CC_REAPER_IDL"
}
box() { # <uuid> <lines> <seen> <acked>
  local i; : > "$CC_MAILBOX_DIR/$1.md"
  for i in $(seq 1 "$2"); do printf '2026-09-23T00:00:0%sZ [peer] m%s\n' "$((i % 10))" "$i" >> "$CC_MAILBOX_DIR/$1.md"; done
  printf '%s\n' "$3" > "$CC_MAILBOX_DIR/$1.seen"
  printf '%s\n' "$4" > "$CC_MAILBOX_DIR/$1.acked"
}
comms() { "$B" --json | jq -c '[.[] | select(.kind=="comms-undelivered")]'; }

@test "an escalated box that STILL holds unacked mail renders the COMMS section with its recover command" {
  box "$U" 5 2 2
  esc "$U" undelivered-escalated
  run "$B"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^COMMS — 1 inbox'
  echo "$output" | grep -qF "cc-thread $U"
  echo "$output" | grep -qF "$U"
  [ "$(comms | jq -r '.[0].state')" = UNDELIVERED ]
  [ "$(comms | jq -r '.[0].unacked')" = 3 ]
}

@test "RELEASE: the owner drained the box ⇒ the row clears with no write to the board" {
  box "$U" 5 5 5
  esc "$U" undelivered-escalated
  [ "$(comms | jq 'length')" -eq 0 ]
  run "$B"
  echo "$output" | grep -q 'no safeguard-blocked sessions surfaced'
}

@test "RELEASE: cc-gc archived the box (file gone) ⇒ the row clears" {
  esc "$U" undelivered-escalated
  [ ! -e "$CC_MAILBOX_DIR/$U.md" ]
  [ "$(comms | jq 'length')" -eq 0 ]
}

@test "cursor clamps mirror mailbox-pending.sh: .seen past EOF re-delivers ⇒ everything is unacked" {
  box "$U" 4 99 99
  esc "$U" undelivered-escalated
  [ "$(comms | jq -r '.[0].unacked')" = 4 ]
}

@test "RED ARM: the release really is a re-measure — the SAME row renders or not with only the box changed" {
  esc "$U" undelivered-escalated
  box "$U" 3 3 3; [ "$(comms | jq 'length')" -eq 0 ]
  printf '2026-09-23T00:00:09Z [peer] late\n' >> "$CC_MAILBOX_DIR/$U.md"
  [ "$(comms | jq 'length')" -eq 1 ]
}

@test "latest row per box, not one row per escalation" {
  box "$U" 6 1 1
  esc "$U" undelivered-escalated "$(ago_iso 7200)"
  esc "$U" undelivered-escalated "$(ago_iso 60)"
  [ "$(comms | jq 'length')" -eq 1 ]
  [ "$(comms | jq -r '.[0].detail')" = "5 unacked now; escalated 0h ago" ]
}

@test "enqueue-failed renders ENQUEUE-FAIL within the window, with no box to re-measure" {
  esc "$V" enqueue-failed-escalated
  [ "$(comms | jq -r '.[0].state')" = ENQUEUE-FAIL ]
  [ "$(comms | jq -r '.[0].reason')" = hello ]
}

@test "the window bounds both kinds (older than CC_BLOCKERS_COMMS_H ⇒ silent)" {
  box "$U" 5 0 0
  esc "$U" undelivered-escalated "$(ago_iso 90000)"
  esc "$V" enqueue-failed-escalated "$(ago_iso 90000)"
  [ "$(comms | jq 'length')" -eq 0 ]
  CC_BLOCKERS_COMMS_H=48
  export CC_BLOCKERS_COMMS_H
  [ "$(comms | jq 'length')" -eq 2 ]
}

@test "kill switch CC_BLOCKERS_COMMS_H=0 ⇒ no comms rows" {
  box "$U" 5 0 0
  esc "$U" undelivered-escalated
  export CC_BLOCKERS_COMMS_H=0
  [ "$(comms | jq 'length')" -eq 0 ]
}

@test "fixture-origin rows and other actors never render" {
  box "$U" 5 0 0
  esc "$U" undelivered-escalated "" '{"test_origin":"bats:x.bats"}'
  esc "$U" undelivered-escalated "" '{"actor":"someone-else"}'
  [ "$(comms | jq 'length')" -eq 0 ]
}

@test "an unsafe key never reaches the filesystem or the JSON map" {
  esc "../etc/passwd" undelivered-escalated
  esc 'a"b' undelivered-escalated
  run "$B" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '[.[] | select(.kind=="comms-undelivered")] | length')" -eq 0 ]
}

@test "a malformed board line is skipped, not fatal — and the valid row still renders" {
  box "$U" 5 0 0
  printf 'not json\n{"half":\n' >> "$CC_REAPER_IDL"
  esc "$U" undelivered-escalated
  [ "$(comms | jq 'length')" -eq 1 ]
}

@test "DETAIL stays ASCII (the renderer pads by bytes) even when the reason is not" {
  box "$U" 2 0 0
  esc "$U" undelivered-escalated "" '{"reason":"LIVE — 2 message(s) ⚠"}'
  [ "$(comms | jq -r '.[0].detail')" = "2 unacked now; escalated 0h ago" ]
  [ "$(comms | jq -r '.[0].reason')" = "LIVE  2 message(s) " ]
}
