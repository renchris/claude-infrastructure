#!/usr/bin/env bats
# Phase 2 — cc-notify: name/uuid/self resolution, the two-call \r submit recipe,
# the always-on mailbox, and graceful closed-pane degradation.
#
# Isolated via CC_REGISTRY_DIR / CC_MAILBOX_DIR (temp) and IT2_BIN (a stub that
# LOGS each call, rendering a bare CR arg as the token <CR>, and can be forced to
# fail via IT2_STUB_FAIL=1 to simulate a closed/recycled pane).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  NOTIFY="$REPO/bin/cc-notify"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"
  export IT2_LOG="$BATS_TEST_TMPDIR/it2.log"
  mkdir -p "$CC_REGISTRY_DIR"

  STUB="$BATS_TEST_TMPDIR/it2"
  cat > "$STUB" <<'SH'
#!/bin/bash
# `it2 session send -s <uuid> <text>` — log a readable form (CR arg -> <CR>).
out=""
for a in "$@"; do
  if [ "$a" = "$(printf '\r')" ]; then out="$out<CR> "; else out="$out$a "; fi
done
printf '%s\n' "$out" >> "$IT2_LOG"
[ "${IT2_STUB_FAIL:-0}" = 1 ] && exit 1
exit 0
SH
  chmod +x "$STUB"
  export IT2_BIN="$STUB"

  UUID="AAAAAAAA-1111-2222-3333-444444444444"
  # cc-sessions (sibling) must see this pane as live -> stub its it2 list too.
  # cc-notify calls cc-sessions --json, which uses IT2_BIN's `session list`. Our
  # stub only handles `session send`; give cc-sessions its own live-pane view by
  # registering the entry with a LIVE pid ($$) and listing the pane.
  printf '{"paneUUID":"%s","name":"peer","cwd":"/tmp","account":"next","pid":%s,"startedAt":1}' \
    "$UUID" "$$" > "$CC_REGISTRY_DIR/$UUID.json"
}

# cc-notify resolves names via `cc-sessions --json`, whose stale-sweep calls
# `it2 session list`. Our send-stub returns [] for list -> pane looks absent ->
# cc-sessions would sweep "peer". So point cc-sessions at a list-aware stub.
# Simplest: give the stub a `session list` branch echoing the peer UUID.
teardown() { :; }

use_full_stub() {
  cat > "$IT2_BIN" <<SH
#!/bin/bash
if [ "\$1 \$2 \$3" = "session list --json" ]; then
  echo '[{"id":"$UUID"}]'; exit 0
fi
out=""
for a in "\$@"; do
  if [ "\$a" = "\$(printf '\r')" ]; then out="\$out<CR> "; else out="\$out\$a "; fi
done
printf '%s\n' "\$out" >> "$IT2_LOG"
[ "\${IT2_STUB_FAIL:-0}" = 1 ] && exit 1
exit 0
SH
  chmod +x "$IT2_BIN"
}

@test "resolves a friendly NAME to its pane UUID and injects" {
  use_full_stub
  run bash "$NOTIFY" peer "hello world"
  [ "$status" -eq 0 ]
  # two send calls: text then CR, both to the resolved UUID
  [ "$(grep -c 'session send' "$IT2_LOG")" -eq 2 ]
  grep -q "session send -s $UUID hello world" "$IT2_LOG"
  grep -q "session send -s $UUID <CR>" "$IT2_LOG"
}

@test "raw pane UUID passes through (no registry entry needed)" {
  use_full_stub
  RAW="99999999-8888-7777-6666-555555555555"
  run bash "$NOTIFY" "$RAW" "ping"
  [ "$status" -eq 0 ]
  grep -q "session send -s $RAW ping" "$IT2_LOG"
  grep -q "session send -s $RAW <CR>" "$IT2_LOG"
}

@test "the submit uses \\r (CR), never \\n — text call then <CR>, then the verify capture" {
  use_full_stub
  run bash "$NOTIFY" peer "msg"
  [ "$status" -eq 0 ]
  # hardened sequence: send text -> send <CR> -> session capture (verify)
  [ "$(grep -c 'session send' "$IT2_LOG")" -eq 2 ]
  run sed -n '2p' "$IT2_LOG"
  [[ "$output" == *"<CR>"* ]]
  [[ "$output" != *"msg"* ]]   # the CR call carries no text
  grep -q "session capture -s $UUID" "$IT2_LOG"
}

# --- submit-verification hardening (2026-07-13): confirm the effect, never the keystroke ---

# A capture-aware stub: `session capture -s <uuid> -o <file>` copies the Nth fixture
# from $CAPTURE_FIXTURES_DIR/cap.N (N = capture call count) so tests can script the
# composer's state over retries. Missing fixture -> no file (capture unavailable).
use_capture_stub() {
  export CAPTURE_FIXTURES_DIR="$BATS_TEST_TMPDIR/caps"
  mkdir -p "$CAPTURE_FIXTURES_DIR"
  cat > "$IT2_BIN" <<SH
#!/bin/bash
if [ "\$1 \$2 \$3" = "session list --json" ]; then
  echo '[{"id":"$UUID"}]'; exit 0
fi
if [ "\$1 \$2" = "session capture" ]; then
  cnt_f="$BATS_TEST_TMPDIR/capcount"; n=\$(cat "\$cnt_f" 2>/dev/null || echo 0); n=\$((n+1)); echo "\$n" > "\$cnt_f"
  printf 'session capture -s %s (call %s)
' "\$4" "\$n" >> "$IT2_LOG"
  src="$CAPTURE_FIXTURES_DIR/cap.\$n"
  # sticky: past the last scripted fixture, keep serving the highest one
  while [ ! -f "\$src" ] && [ "\$n" -gt 1 ]; do n=\$((n-1)); src="$CAPTURE_FIXTURES_DIR/cap.\$n"; done
  [ -f "\$src" ] || exit 0
  # -o <file> is arg 6 (capture -s <uuid> -o <file>)
  cp "\$src" "\$6"; exit 0
fi
out=""
for a in "\$@"; do
  if [ "\$a" = "\$(printf '\r')" ]; then out="\$out<CR> "; else out="\$out\$a "; fi
done
printf '%s
' "\$out" >> "$IT2_LOG"
exit 0
SH
}

stranded_pane() { printf 'transcript noise\n\u276f %s and more of it typed here\n' "$1"; }
clear_pane()    { printf '%s (queued above)\n\u276f Press up to edit queued messages\n' "$1"; }

@test "verify: clean submit on first capture -> exit 0, VERIFIED, no extra CR" {
  use_capture_stub
  printf 'countermand text (queued above)
\342\235\257 Press up to edit queued messages
' > "$CAPTURE_FIXTURES_DIR/cap.1"
  run bash "$NOTIFY" peer "countermand text"
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERIFIED"* ]]
  [ "$(grep -c '<CR>' "$IT2_LOG")" -eq 1 ]
}

@test "verify: stranded once -> one CR retry -> VERIFIED exit 0" {
  use_capture_stub
  printf 'noise
\342\235\257 countermand text still sitting here
' > "$CAPTURE_FIXTURES_DIR/cap.1"
  printf 'countermand text (queued above)
\342\235\257 Press up to edit queued messages
' > "$CAPTURE_FIXTURES_DIR/cap.2"
  run bash "$NOTIFY" peer "countermand text"
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERIFIED"* ]]
  [ "$(grep -c '<CR>' "$IT2_LOG")" -eq 2 ]   # initial + 1 retry
}

@test "verify: stranded forever -> exit 4, STRANDED reported, mailbox still holds it" {
  use_capture_stub
  printf 'noise
\342\235\257 countermand text still sitting here
' > "$CAPTURE_FIXTURES_DIR/cap.1"
  run bash "$NOTIFY" peer "countermand text"
  [ "$status" -eq 4 ]
  [[ "$output" == *"STRANDED"* ]]
  [ "$(grep -c '<CR>' "$IT2_LOG")" -eq 3 ]   # initial + 2 retries
  grep -q "countermand text" "$CC_MAILBOX_DIR/$UUID.md"
}

@test "verify: capture unavailable -> graceful UNVERIFIED, exit 0" {
  use_capture_stub   # no fixtures written -> capture produces no file
  run bash "$NOTIFY" peer "some message"
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNVERIFIED"* ]]
}

@test "ALWAYS writes the mailbox on success (composer + mailbox)" {
  use_full_stub
  run bash "$NOTIFY" --from tester peer "recorded too"
  [ "$status" -eq 0 ]
  [ -f "$CC_MAILBOX_DIR/$UUID.md" ]
  grep -q "\[tester\] recorded too" "$CC_MAILBOX_DIR/$UUID.md"
}

@test "closed/recycled pane -> mailbox-only, exit 0, stderr note (no hard fail)" {
  use_full_stub
  export IT2_STUB_FAIL=1
  run bash "$NOTIFY" peer "into the void"
  [ "$status" -eq 0 ]
  [ -f "$CC_MAILBOX_DIR/$UUID.md" ]
  grep -q "into the void" "$CC_MAILBOX_DIR/$UUID.md"
  [[ "$output" == *"mailbox only"* ]]
}

@test "--mailbox-only records but skips injection (it2 send never called)" {
  use_full_stub
  run bash "$NOTIFY" --mailbox-only peer "silent"
  [ "$status" -eq 0 ]
  [ -f "$CC_MAILBOX_DIR/$UUID.md" ]
  grep -q "silent" "$CC_MAILBOX_DIR/$UUID.md"
  [ ! -f "$IT2_LOG" ] || [ "$(grep -c 'session send' "$IT2_LOG")" -eq 0 ]
}

@test "--self prints own pane UUID and exits (no message)" {
  run env ITERM_SESSION_ID="w9t0p0:FEEDFACE-0000-0000-0000-000000000000" bash "$NOTIFY" --self
  [ "$status" -eq 0 ]
  [ "$output" = "FEEDFACE-0000-0000-0000-000000000000" ]
}

@test "--self <msg> injects into own pane" {
  use_full_stub
  run env ITERM_SESSION_ID="w9t0p0:$UUID" bash "$NOTIFY" --self "note to self"
  [ "$status" -eq 0 ]
  grep -q "session send -s $UUID note to self" "$IT2_LOG"
}

@test "unresolvable target -> exit 3, no mailbox (unknown UUID)" {
  use_full_stub
  run bash "$NOTIFY" no-such-session "hi"
  [ "$status" -eq 3 ]
  [ ! -d "$CC_MAILBOX_DIR" ] || [ -z "$(ls -A "$CC_MAILBOX_DIR" 2>/dev/null)" ]
}

@test "missing message (non-self target) -> usage error exit 2" {
  use_full_stub
  run bash "$NOTIFY" peer
  [ "$status" -eq 2 ]
}

@test "--from attribution appears in the mailbox line" {
  use_full_stub
  run bash "$NOTIFY" --from originator-session peer "with attribution"
  [ "$status" -eq 0 ]
  grep -q "\[originator-session\] with attribution" "$CC_MAILBOX_DIR/$UUID.md"
}
