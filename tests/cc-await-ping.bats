#!/usr/bin/env bats
# Phase 3 — cc-await-ping: the mailbox pull-poller.
# Isolated via CC_MAILBOX_DIR (temp). Short --interval/--timeout keep runs quick.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  AWAIT="$REPO/bin/cc-await-ping"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"
  mkdir -p "$CC_MAILBOX_DIR"
  UUID="AAAAAAAA-1111-2222-3333-444444444444"
  MB="$CC_MAILBOX_DIR/$UUID.md"
}

@test "exits 0 and prints the new line when a ping lands mid-wait" {
  ( sleep 1; printf '2026-07-10T10:00:00+0000 [peer] HANDOFF-PING slug: done\n' >> "$MB" ) &
  writer=$!
  run "$AWAIT" "$UUID" --interval 1 --timeout 10
  wait "$writer" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [[ "$output" == *"HANDOFF-PING slug: done"* ]]
}

@test "prints ONLY new lines (ignores pre-existing mailbox history)" {
  printf '2026-07-10T09:00:00+0000 [old] earlier message\n' > "$MB"   # baseline history
  ( sleep 1; printf '2026-07-10T10:00:00+0000 [peer] fresh ping\n' >> "$MB" ) &
  writer=$!
  run "$AWAIT" "$UUID" --interval 1 --timeout 10
  wait "$writer" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [[ "$output" == *"fresh ping"* ]]
  [[ "$output" != *"earlier message"* ]]
}

@test "times out with exit 2 when no ping arrives" {
  run "$AWAIT" "$UUID" --interval 1 --timeout 2
  [ "$status" -eq 2 ]
}

@test "defaults the uuid to \$ITERM_SESSION_ID's pane" {
  DEF="BBBBBBBB-1111-2222-3333-444444444444"
  ( sleep 1; printf 'ping via default uuid\n' >> "$CC_MAILBOX_DIR/$DEF.md" ) &
  writer=$!
  run env ITERM_SESSION_ID="w5t0p2:$DEF" "$AWAIT" --interval 1 --timeout 10
  wait "$writer" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [[ "$output" == *"ping via default uuid"* ]]
}

@test "exits 3 when no uuid given and no \$ITERM_SESSION_ID" {
  run env -u ITERM_SESSION_ID "$AWAIT" --timeout 1
  [ "$status" -eq 3 ]
}

@test "mailbox created AFTER the poller starts still triggers (baseline 0)" {
  rm -f "$MB"   # file absent at start
  ( sleep 1; printf 'appeared later\n' >> "$MB" ) &
  writer=$!
  run "$AWAIT" "$UUID" --interval 1 --timeout 10
  wait "$writer" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [[ "$output" == *"appeared later"* ]]
}
