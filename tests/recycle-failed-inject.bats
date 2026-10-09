#!/usr/bin/env bats
# hooks/recycle-failed-inject.sh — the SessionStart channel for a failed recycle's recovery packet
# (docs/plans/RECYCLE_KEYSTROKELESS_DELIVERY.md §D4). Every case runs the hook under /bin/bash, the
# interpreter the harness hands it (deployment-interpreter lesson), against a fixture packet dir.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  HOOK="$REPO/hooks/recycle-failed-inject.sh"
  SSD="$REPO/hooks/session-start-dispatch.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_RECYCLE_FAILED_DIR="$BATS_TEST_TMPDIR/recycle-failed"; mkdir -p "$CC_RECYCLE_FAILED_DIR"
  unset CC_RECYCLE_ATTACHED_TOKEN
  SID=6defb493-0000-4000-8000-000000000044
  TOK="recycle-recovery:$SID:1791000000"
  PKT="$CC_RECYCLE_FAILED_DIR/$SID.json"
}

mk_packet() { # [extra jq assignment]
  jq -n --arg tok "$TOK" "{failed_at:\"2026-10-09T05:31:00Z\", class:\"relaunch-failed\", pane:\"44\", token:\$tok,
    refire_cmd:\"bash h.sh --recycle --recovery-of \(\$tok)\"} ${1:+| $1}" > "$PKT"
  printf 'Your self-recycle at 05:31 FAILED (relaunch-failed). token %s\nIf none, re-fire with exactly: bash h.sh\n' "$TOK" \
    > "$CC_RECYCLE_FAILED_DIR/$SID.prompt.md"
}
hook() { # runs the hook as SessionStart would, payload on stdin
  run /bin/bash -c 'printf "%s" "$1" | /bin/bash "$2"' _ \
    "{\"session_id\":\"$SID\",\"hook_event_name\":\"SessionStart\",\"source\":\"resume\"}" "$HOOK"
}
ctx() { printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext'; }

@test "an undelivered packet is injected as additionalContext and injected_at is stamped" {
  mk_packet
  hook
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r .hookSpecificOutput.hookEventName)" = SessionStart ]
  [[ "$(ctx)" == *"RECYCLE FAILED"* ]] || { echo "$output"; false; }
  [[ "$(ctx)" == *"$TOK"* ]] || { echo "$output"; false; }      # the prompt text, token included
  [ -n "$(jq -r '.injected_at // empty' "$PKT")" ]
  jq -e '.token and .refire_cmd' "$PKT" >/dev/null            # the rest of the packet survived the rewrite
}

@test "exactly once: a second SessionStart (clear, compact, re-resume) prints nothing" {
  mk_packet
  hook; [ -n "$output" ]
  hook
  [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "$output"; false; }
}

@test "a delivered packet is never injected" {
  mk_packet '.delivered_at = "2026-10-09T05:40:00Z"'
  hook
  [ -z "$output" ] && [ -z "$(jq -r '.injected_at // empty' "$PKT")" ]
}

@test "the same token already attached by reso-resume-one is not injected twice, and not stamped" {
  mk_packet
  CC_RECYCLE_ATTACHED_TOKEN="$TOK" hook
  [ -z "$output" ] || { echo "$output"; false; }
  [ -z "$(jq -r '.injected_at // empty' "$PKT")" ]
  # control: a DIFFERENT attached token (another packet's) does not suppress this one
  CC_RECYCLE_ATTACHED_TOKEN="recycle-recovery:other:1" hook
  [[ "$(ctx)" == *"$TOK"* ]]
}

@test "no packet, no prompt file, a path-shaped sid or a malformed packet: nothing, exit 0" {
  hook; [ "$status" -eq 0 ] && [ -z "$output" ]
  mk_packet; rm -f "$CC_RECYCLE_FAILED_DIR/$SID.prompt.md"
  hook; [ "$status" -eq 0 ] && [ -z "$output" ]
  mk_packet; printf 'not json' > "$PKT"
  hook; [ "$status" -eq 0 ] && [ -z "$output" ]
  run /bin/bash -c 'printf "%s" "{\"session_id\":\"../x\"}" | /bin/bash "$1"' _ "$HOOK"
  [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "through the dispatcher: the shipped child reaches the merged additionalContext" {
  mk_packet
  run /bin/bash -c 'printf "%s" "$1" | CC_SSD_HOOK_DIR="$2" CC_SSD_CHILDREN=recycle-failed-inject.sh CC_SSD_BOUND_S=5 /bin/bash "$3"' _ \
    "{\"session_id\":\"$SID\",\"hook_event_name\":\"SessionStart\"}" "$REPO/hooks" "$SSD"
  [ "$status" -eq 0 ]
  [[ "$(ctx)" == *"$TOK"* ]] || { echo "$output"; false; }
}
