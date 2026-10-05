#!/usr/bin/env bats
# cc-restore-rebind (W3 P8) — re-binds forwards, roles and exhausted-account sessions after a restore.
# Every actuator is stubbed or pointed at a fixture dir: the roles CLI and lr-fleet are stubs that
# only record their argv, and the mailbox, registry, custody and roles stores live under
# $BATS_TEST_TMPDIR. The subject itself refuses to run under bats unless those seams are set.
# The fixture event dir is tests/fixtures/cc-restore-rebind/: five sessions, four restored (map),
# old pane keys 249 (kitty), an iTerm2 uuid, 4 (reused by a restored window) and 252; next3 is the
# exhausted account.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUBJ="$REPO/bin/cc-restore-rebind"
  FIX="$REPO/tests/fixtures/cc-restore-rebind"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"; mkdir -p "$CC_MAILBOX_DIR"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"; mkdir -p "$CC_ROLES_DIR"
  export CC_CUSTODY_DIR="$BATS_TEST_TMPDIR/custody"
  export CC_COMMS_ALARM_DIR="$BATS_TEST_TMPDIR/comms-alarms"
  export CC_NOTIFY_LAUNCHCTL_BIN="$BATS_TEST_TMPDIR/no-launchctl-here"
  export CC_NOTIFY_PHONE_FALLBACK=0
  export CC_NOTIFY_PUSH_BIN="$BATS_TEST_TMPDIR/no-push-here"
  STUBLOG="$BATS_TEST_TMPDIR/stub.log"; : > "$STUBLOG"

  # roles stub: claim writes the pane as line 1 (what every reader takes), read prints line 1.
  export CC_REBIND_ROLES_BIN="$BATS_TEST_TMPDIR/cc-roles"
  cat > "$CC_REBIND_ROLES_BIN" <<'SH'
#!/bin/bash
echo "cc-roles $*" >> "$STUBLOG"
case "$1" in
  claim) r="$2"; shift 2; p=""
         while [ $# -gt 0 ]; do [ "$1" = --pane ] && p="$2"; shift; done
         printf '%s\n' "$p" > "$CC_ROLES_DIR/$r" ;;
  read)  [ -f "$CC_ROLES_DIR/$2" ] && head -n1 "$CC_ROLES_DIR/$2" ;;
esac
exit 0
SH
  export CC_REBIND_LRFLEET="$BATS_TEST_TMPDIR/lr-fleet.sh"
  printf '#!/bin/bash\necho "lr-fleet $*" >> "$STUBLOG"\nexit 0\n' > "$CC_REBIND_LRFLEET"
  chmod +x "$CC_REBIND_ROLES_BIN" "$CC_REBIND_LRFLEET"
  export STUBLOG

  # a fresh copy of the fixture event dir per test (the subject writes rebind.log into it)
  EV="$BATS_TEST_TMPDIR/events/1791200000"; mkdir -p "$EV"
  cp "$FIX"/event/* "$EV"/
  : > "$EV.done"
  ACCTS="$FIX/accounts.json"
  # registry rows for the restored windows, with a LIVE pid (this test process) so roles can claim
  for f in "$FIX"/registry/*.json; do
    jq -c --argjson p "$$" '.pid = $p' "$f" > "$CC_REGISTRY_DIR/$(basename "$f")"
  done
  S1=11111111-aaaa-4aaa-8aaa-000000000001
  S2=11111111-aaaa-4aaa-8aaa-000000000002
  S3=11111111-aaaa-4aaa-8aaa-000000000003
  S4=11111111-aaaa-4aaa-8aaa-000000000004
  S5=11111111-aaaa-4aaa-8aaa-000000000005
  IT=ABCDEF01-2222-3333-4444-555555555555
}

rebind() { "$SUBJ" "$EV" --accounts-json "$ACCTS" "$@"; }

@test "dry-run lists forwards, role claims and lr-fleet handoffs, and writes nothing" {
  run rebind --dry-run
  [ "$status" -eq 1 ]   # PARTIAL: the reused key 4 is refused
  [[ "$output" == *"DRY forward old=249 → sid=$S1 new_pane=3 state=write"* ]] || false
  [[ "$output" == *"DRY forward old=$IT → sid=$S2 new_pane=4 state=write"* ]] || false
  [[ "$output" == *"DRY forward-refused old=4 sid=$S3 new_pane=7 reason=old-key-reused"* ]] || false
  [[ "$output" == *"DRY role-claim role=desk sid=$S1 pane=3 pid=$$"* ]] || false
  [[ "$output" == *"DRY role-claim role=docs-lead sid=$S2 pane=4"* ]] || false
  [[ "$output" == *"DRY role-skip role=drain-lead sid=$S4 reason=not-restored"* ]] || false
  [[ "$output" == *"DRY lrfleet-handoff sid=$S1 acct=next3 verdict=INTERRUPTED"* ]] || false
  [[ "$output" == *"DRY lrfleet-handoff sid=$S5 acct=next3 verdict=WAKE-LOST"* ]] || false
  [[ "$output" == *"verdict=PARTIAL forwards=3 roles=2 handoffs=2 skipped=2 deferred=0 refused=1 failed=0 dry=1"* ]] || false
  [ ! -e "$EV/rebind.log" ]
  [ -z "$(ls "$CC_MAILBOX_DIR")" ]
  ! grep -q -e '^cc-roles claim' -e '^lr-fleet ' "$STUBLOG"
}

@test "real run: forwards written (lib writer for a uuid key, local for a kitty key), roles claimed, exhausted rows handed off" {
  run rebind
  [ "$status" -eq 1 ]
  [ "$(cat "$CC_MAILBOX_DIR/249.forward")" = "$S1" ]
  [ "$(cat "$CC_MAILBOX_DIR/$IT.forward")" = "$S2" ]
  [ "$(cat "$CC_MAILBOX_DIR/252.forward")" = "$S5" ]
  [ ! -e "$CC_MAILBOX_DIR/4.forward" ]
  [[ "$output" == *"forward old=249 → sid=$S1 new_pane=3 writer=local migrated=0"* ]] || false
  [[ "$output" == *"forward old=$IT → sid=$S2 new_pane=4 writer=lib migrated=0"* ]] || false
  grep -qxF "cc-roles claim desk --pane 3 --pid $$ --force" "$STUBLOG"
  grep -qxF "cc-roles claim docs-lead --pane 4 --pid $$ --force" "$STUBLOG"
  ! grep -q 'claim drain-lead' "$STUBLOG" || false
  # only the restored, exhausted, INTERRUPTED/WAKE-LOST rows: S1 and S5 (S2 is on a healthy account,
  # S3 is IDLE, S4 was not restored)
  [ "$(grep -c '^lr-fleet ' "$STUBLOG")" -eq 2 ]
  grep -qxF "lr-fleet --one $S1 --target auto --detach" "$STUBLOG"
  grep -qxF "lr-fleet --one $S5 --target auto --detach" "$STUBLOG"
  # every act is in the log
  grep -q " forward old=249 → sid=$S1" "$EV/rebind.log"
  grep -q " role-claim role=desk sid=$S1 pane=3" "$EV/rebind.log"
  grep -q " lrfleet-handoff sid=$S5 acct=next3" "$EV/rebind.log"
  grep -q " forward-refused old=4 " "$EV/rebind.log"
}

@test "idempotent: a second run re-writes nothing, re-claims nothing and hands nobody off twice" {
  "$SUBJ" "$EV" --accounts-json "$ACCTS" >/dev/null || true
  : > "$STUBLOG"
  run rebind
  [[ "$output" == *"forward old=249 → sid=$S1 new_pane=3 writer=held migrated=0"* ]] || false
  [[ "$output" == *"role-held role=desk pane=3"* ]] || false
  [[ "$output" == *"lrfleet-held sid=$S1"* ]] || false
  [[ "$output" == *"handoffs=0"* ]] || false
  ! grep -q -e '^cc-roles claim' -e '^lr-fleet ' "$STUBLOG"
}

@test "mail already stranded in the old box is migrated to the session box, once" {
  printf '%s\n' "2026-10-04T10:00:00+0000 [peer] early ping" > "$CC_MAILBOX_DIR/249.md"
  run rebind
  [[ "$output" == *"forward old=249 → sid=$S1 new_pane=3 writer=local migrated=1"* ]] || false
  grep -q 'early ping' "$CC_MAILBOX_DIR/$S1.md"
  run rebind
  [[ "$output" == *"forward old=249 → sid=$S1 new_pane=3 writer=held migrated=0"* ]] || false
  [ "$(grep -c 'early ping' "$CC_MAILBOX_DIR/$S1.md")" -eq 1 ]
}

@test "a forward is refused when the old pane key's registry row now names another session" {
  printf '{"paneUUID":"252","session_id":"%s","pid":%s}\n' "$S2" "$$" > "$CC_REGISTRY_DIR/252.json"
  run rebind
  [[ "$output" == *"forward-refused old=252 sid=$S5 reason=pane-reoccupied"* ]] || false
  [ ! -e "$CC_MAILBOX_DIR/252.forward" ]
}

@test "a role whose restored session has no live pid yet is deferred, not claimed with a dead pid" {
  jq -c '.pid = 0' "$FIX/registry/3.json" > "$CC_REGISTRY_DIR/3.json"
  run rebind
  [[ "$output" == *"role-deferred role=desk sid=$S1 new_pane=3 reason=no-live-pid"* ]] || false
  ! grep -q 'claim desk' "$STUBLOG"
}

@test "accounts wait for the event's .done marker, and an unreadable accounts read hands nobody off" {
  rm -f "$EV.done"
  run rebind
  [[ "$output" == *"lrfleet-deferred reason=event-not-done"* ]] || false
  ! grep -q '^lr-fleet ' "$STUBLOG" || false
  : > "$EV.done"
  printf 'not json\n' > "$BATS_TEST_TMPDIR/bad.json"
  run "$SUBJ" "$EV" --accounts-json "$BATS_TEST_TMPDIR/bad.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"lrfleet-deferred reason=accounts-unreadable"* ]] || false
  ! grep -q '^lr-fleet ' "$STUBLOG"
}

@test "under bats the subject refuses to run with a live seam unset" {
  run env -u CC_REBIND_LRFLEET "$SUBJ" "$EV" --accounts-json "$ACCTS"
  [ "$status" -eq 3 ]
  [[ "$output" == *"CC_REBIND_LRFLEET must be set"* ]] || false
  ! grep -q '^lr-fleet ' "$STUBLOG"
}

@test "runs under /bin/bash 3.2 (the launchd interpreter) with the same result" {
  run /bin/bash "$SUBJ" "$EV" --accounts-json "$ACCTS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"verdict=PARTIAL forwards=3 roles=2 handoffs=2 skipped=2 deferred=0 refused=1 failed=0 dry=0"* ]] || false
  [ "$(cat "$CC_MAILBOX_DIR/249.forward")" = "$S1" ]
}

# ── END TO END: a forwarded DONE discharges the originator's open custody row ───────────────────────
# The originator (S1) fired a peer with --notify-back naming its OLD pane, 249. Kitty restarted and S1
# came back in window 3. The peer then pings 249. Without the rebind the ping lands in 249.md, which
# S1's drain never reads, and custody stays open (the control). With it, cc-notify follows
# 249.forward to S1's session box and S1's drain discharges the row.
custody_ping() { # sends the peer's final ping to the OLD pane key, then runs S1's drain in window 3
  local orig="$BATS_TEST_TMPDIR/originator"; mkdir -p "$orig"
  "$REPO/bin/cc-custody" open --cwd "$orig" --target 9 --marker M-P8-1 --slug p8-wave --notify-back 249
  [ "$("$REPO/bin/cc-custody" count --open --cwd "$orig")" = 1 ]
  "$REPO/bin/cc-notify" --mailbox-only --no-wake 249 "HANDOFF-PING p8-wave: DONE — landed abc1234" >/dev/null 2>&1 || true
  printf '{"cwd":"%s","session_id":"%s"}' "$orig" "$S1" \
    | CC_PANE_ID=3 ITERM_SESSION_ID='' "$REPO/hooks/mailbox-drain.sh" prompt >/dev/null 2>&1 || true
  "$REPO/bin/cc-custody" count --open --cwd "$orig"
}

@test "custody CONTROL: without the rebind, a DONE sent to the old pane key leaves custody open" {
  run custody_ping
  [ "${lines[${#lines[@]}-1]}" = 1 ]
  grep -q 'HANDOFF-PING p8-wave: DONE' "$CC_MAILBOX_DIR/249.md"
}

@test "custody: after the rebind, a DONE sent to the old pane key is forwarded and discharges the open row" {
  "$SUBJ" "$EV" --accounts-json "$ACCTS" >/dev/null || true
  run custody_ping
  [ "${lines[${#lines[@]}-1]}" = 0 ]
  grep -q 'HANDOFF-PING p8-wave: DONE' "$CC_MAILBOX_DIR/$S1.md"
}
