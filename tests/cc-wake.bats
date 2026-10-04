#!/usr/bin/env bats
# cc-wake.bats — the socket wake for an IDLE peer session (docs/plans/AGENT_PEER_WAKE.md).
#
# WHAT IT GUARDS. cc-wake writes into ANOTHER live session. Every gate below is a reason that write
# would be wrong — the wrong process, a busy one, one blocked on a human, one with nothing to read,
# one woken seconds ago — and each test PLANTS exactly that input and asserts that NO FRAME reached
# the socket. Without its gate each one would send, so each reddens alone under a revert.
#
# HERMETIC. The "session" is a real live process (a background sleep, so ps can read its start time)
# with a fixtured sessions/<pid>.json, presence beat, registry row and inbox, and a REAL unix-socket
# listener (python) that records every byte it receives — so the frame asserted is the frame sent.
# The listener can also play the woken session: on receipt it advances the inbox's acked cursor,
# which is exactly what the woken turn's Stop fold does.
#
# BATS ERREXIT DISCIPLINE: a non-final `[[ ]]`, `!` or `A && B` is errexit-exempt and therefore a DEAD
# assertion. Every such assertion carries `|| false`.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  WAKE="$REPO/bin/cc-wake"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg";      mkdir -p "$CC_REGISTRY_DIR"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox";      mkdir -p "$CC_MAILBOX_DIR"
  export CC_BEAT_DIR="$BATS_TEST_TMPDIR/beats";        mkdir -p "$CC_BEAT_DIR"
  export CC_PERMPEND_DIR="$BATS_TEST_TMPDIR/permpend"; mkdir -p "$CC_PERMPEND_DIR"
  export CC_WAKE_STAMP_DIR="$BATS_TEST_TMPDIR/stamps"
  export CC_WAKE_LOG="$BATS_TEST_TMPDIR/wake.jsonl"
  export CC_WAKE_POLL_S=1
  SDIR="$BATS_TEST_TMPDIR/sessions"; mkdir -p "$SDIR"
  export CC_WAKE_SESSIONS_DIRS="$SDIR"
  unset CC_PANE_ID ITERM_SESSION_ID KITTY_WINDOW_ID CC_WAKE CC_WAKE_FROM

  # A unix socket path must fit in ~104 bytes; bats tmpdirs on macOS do not. Short dir under /tmp.
  SOCKDIR="$(mktemp -d /tmp/ccw.XXXXXX)"
  SOCK="$SOCKDIR/s.sock"
  RECV="$BATS_TEST_TMPDIR/recv"

  sleep 600 & TPID=$!
  PANE="77"; SESS="11111111-aaaa-bbbb-cccc-000000000077"
  START="$(TZ=UTC LC_ALL=C ps -o lstart= -p "$TPID")"
  jq -n --arg p "$PANE" --arg s "$SESS" --argjson pid "$TPID" \
    '{paneUUID:$p,name:"peer-77",session_id:$s,pid:$pid}' > "$CC_REGISTRY_DIR/$PANE.json"
  write_session idle
  jq -n --arg s "$SESS" --argjson pid "$TPID" '{sid:$s,pid:$pid,kind:"stop",t:1}' > "$CC_BEAT_DIR/$SESS.json"
  # Stamped NOW, i.e. after the target process ($TPID) started: W4 does not count a line older than
  # the session (the pre-birth rule), so a fixed past stamp would make every test here a no-mail one.
  NOW="$(date '+%Y-%m-%dT%H:%M:%S%z')"
  printf '%s [tm2-plan-replan-10] SECRET-BODY-ONE\n%s [tm2-plan-replan-10] SECRET-BODY-TWO\n' "$NOW" "$NOW" \
    > "$CC_MAILBOX_DIR/$PANE.md"
  echo 0 > "$CC_MAILBOX_DIR/$PANE.seen"; echo 0 > "$CC_MAILBOX_DIR/$PANE.acked"
}

teardown() {
  [ -n "${SRVPID:-}" ] && kill "$SRVPID" 2>/dev/null || true
  kill "$TPID" 2>/dev/null || true
  rm -rf "$SOCKDIR"
  return 0
}

write_session() { # <status> [procStart] [sessionId]
  jq -n --arg st "$1" --arg ps "${2:-$START}" --arg s "${3:-$SESS}" --arg sock "$SOCK" --argjson pid "$TPID" \
    '{pid:$pid,sessionId:$s,procStart:$ps,status:$st,messagingSocketPath:$sock,version:"2.1.284"}' > "$SDIR/$TPID.json"
}

# start_server [ack] — a listener that records everything it receives into $RECV; with `ack` it then
# advances the inbox cursors to EOF, playing the woken session's drain + Stop fold.
start_server() {
  python3 - "$SOCK" "$RECV" "${1:-}" "$CC_MAILBOX_DIR/$PANE" <<'PY' &
import socket, sys, os
path, out, ack, box = sys.argv[1:5]
d, b = os.path.split(os.path.abspath(path)); os.chdir(d)  # bind the BASENAME: sun_path is 104 bytes
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.bind(b); s.listen(4)
while True:
    c, _ = s.accept(); data = b""
    while True:
        b = c.recv(65536)
        if not b: break
        data += b
    c.close()
    open(out, "ab").write(data)
    if ack == "ack":
        n = sum(1 for _ in open(box + ".md"))
        for suf in (".seen", ".acked"): open(box + suf, "w").write(str(n) + "\n")
PY
  SRVPID=$!
  for _ in $(seq 1 50); do [ -S "$SOCK" ] && return 0; sleep 0.1; done
  return 1
}

no_frame() { [ ! -s "$RECV" ]; }

@test "happy path --no-wait: one fixed frame, pinned to the session, carrying no mail body" {
  start_server
  run "$WAKE" "$PANE" --no-wait --from tester
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=sent"* ]] || false
  sleep 0.3
  line="$(tail -n1 "$RECV")"
  [ "$(printf '%s' "$line" | jq -r .type)" = user ]
  [ "$(printf '%s' "$line" | jq -r .session_id)" = "$SESS" ]
  [ "$(printf '%s' "$line" | jq -r .priority)" = next ]
  [[ "$(printf '%s' "$line" | jq -r .message.content)" == *"2 unread peer message"* ]] || false
  ! grep -q SECRET-BODY "$RECV" || false
}

@test "name and session id resolve the same target" {
  start_server
  run "$WAKE" peer-77 --no-wait --dry-run
  [ "$status" -eq 0 ]
  run "$WAKE" "$SESS" --no-wait --dry-run
  [ "$status" -eq 0 ]
  no_frame
}

@test "W1: an unknown target is refused and nothing is sent" {
  start_server
  run "$WAKE" no-such-pane --no-wait
  [ "$status" -eq 1 ]
  [[ "$output" == *"refused-identity"* ]] || false
  no_frame
}

@test "W1: a dead pid is refused" {
  start_server
  kill "$TPID"; wait "$TPID" 2>/dev/null || true
  run "$WAKE" "$PANE" --no-wait
  [ "$status" -eq 1 ]
  [[ "$output" == *"not alive"* ]] || false
  no_frame
}

@test "W2: a procStart that is not the live pid's start (pid reuse) is refused" {
  start_server
  write_session idle "Mon Jan  1 00:00:00 2024"
  run "$WAKE" "$PANE" --no-wait
  [ "$status" -eq 1 ]
  [[ "$output" == *"pid reuse"* ]] || false
  no_frame
}

@test "W2: a sessions file naming a different session id is refused" {
  start_server
  write_session idle "$START" "99999999-0000-0000-0000-000000000000"
  run "$WAKE" "$PANE" --no-wait
  [ "$status" -eq 1 ]
  [[ "$output" == *"refused-no-socket"* ]] || false
  no_frame
}

@test "W3: vendor status busy is refused" {
  start_server
  write_session busy
  run "$WAKE" "$PANE" --no-wait
  [ "$status" -eq 1 ]
  [[ "$output" == *"refused-busy"* ]] || false
  no_frame
}

@test "W3: a presence beat that is a prompt (turn in flight) is refused even when the vendor says idle" {
  start_server
  jq -n --arg s "$SESS" --argjson pid "$TPID" '{sid:$s,pid:$pid,kind:"prompt",t:1}' > "$CC_BEAT_DIR/$SESS.json"
  run "$WAKE" "$PANE" --no-wait
  [ "$status" -eq 1 ]
  [[ "$output" == *"turn is in flight"* ]] || false
  no_frame
}

@test "W3: a missing presence beat is refused (unknown is not idle)" {
  start_server
  rm "$CC_BEAT_DIR/$SESS.json"
  run "$WAKE" "$PANE" --no-wait
  [ "$status" -eq 1 ]
  no_frame
}

@test "W3: a pending permission prompt is refused" {
  start_server
  echo '{"ts":1,"tool_name":"Bash"}' > "$CC_PERMPEND_DIR/$SESS.json"
  run "$WAKE" "$PANE" --no-wait
  [ "$status" -eq 1 ]
  [[ "$output" == *"permission prompt"* ]] || false
  no_frame
}

@test "W4: an inbox with nothing unacked is refused" {
  start_server
  echo 2 > "$CC_MAILBOX_DIR/$PANE.seen"; echo 2 > "$CC_MAILBOX_DIR/$PANE.acked"
  run "$WAKE" "$PANE" --no-wait
  [ "$status" -eq 1 ]
  [[ "$output" == *"refused-no-mail"* ]] || false
  no_frame
}

@test "W4: unacked mail older than the session itself is not a reason to wake (2026-10-04)" {
  # A reused kitty window number or an adoption can put a line written before this session existed
  # into its keys; its boundary drain delivers that line, and waking for it is the incident's false
  # "peer mail arrived". The [forwarded:] outer stamp is the migration time, so the INNER one counts.
  # RED-proof: pre-fix W4 counts both lines and sends a frame.
  start_server
  printf '%s [forwarded:b6b0ac64] 2026-09-11T13:47:12-0500 [claude] post-land RED\n2026-09-11T10:35:38-0500 [peer] raw old line\n' \
    "$NOW" > "$CC_MAILBOX_DIR/$PANE.md"
  run "$WAKE" "$PANE" --no-wait
  [ "$status" -eq 1 ]
  [[ "$output" == *"refused-no-mail"* ]] || false
  no_frame
}

@test "W5: a second wake inside the minimum gap is refused" {
  start_server
  run "$WAKE" "$PANE" --no-wait
  [ "$status" -eq 0 ]
  sleep 0.3; : > "$RECV"
  run "$WAKE" "$PANE" --no-wait
  [ "$status" -eq 1 ]
  [[ "$output" == *"refused-rate"* ]] || false
  no_frame
}

@test "verify by effect: exit 0 only once the receipt reads READ" {
  start_server ack
  run "$WAKE" "$PANE" --wait 10
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=read"* ]] || false
}

@test "sent but never read: exit 3, never success" {
  start_server
  run "$WAKE" "$PANE" --wait 1
  [ "$status" -eq 3 ]
  [[ "$output" == *"sent-unread"* ]] || false
  [[ "$output" == *"=unread"* ]] || false
}

@test "a stale socket with no listener is a transport failure (exit 4)" {
  python3 -c 'import os,socket,sys; d,b=os.path.split(os.path.abspath(sys.argv[1])); os.chdir(d); s=socket.socket(socket.AF_UNIX); s.bind(b); s.close()' "$SOCK"
  run "$WAKE" "$PANE" --no-wait
  [ "$status" -eq 4 ]
  [[ "$output" == *"transport-failed"* ]] || false
}

@test "auth: a matching key file sends the auth line first; the token never appears in our output" {
  start_server
  jq -n --arg ps "$START" '{peerToken:"TOKEN-abc123",procStart:$ps,pidDomain:"darwin"}' > "$SDIR/$TPID.deadbeef.key"
  run "$WAKE" "$PANE" --no-wait
  [ "$status" -eq 0 ]
  sleep 0.3
  [ "$(head -n1 "$RECV" | jq -r .type)" = auth ]
  [ "$(head -n1 "$RECV" | jq -r .token)" = TOKEN-abc123 ]
  [[ "$output" != *TOKEN-abc123* ]] || false
}

@test "kill switch CC_WAKE=off sends nothing" {
  start_server
  CC_WAKE=off run "$WAKE" "$PANE" --no-wait
  [ "$status" -eq 1 ]
  no_frame
}

@test "every attempt is logged, refused ones included" {
  start_server
  run "$WAKE" no-such-pane --no-wait
  [ "$(jq -r .verdict "$CC_WAKE_LOG" | tail -n1)" = refused-identity ]
}
