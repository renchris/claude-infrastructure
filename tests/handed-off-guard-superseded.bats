#!/usr/bin/env bats
# hooks/handed-off-session-guard.sh — the SAME-ACCOUNT SUPERSESSION arm (LIMIT_RECOVER_100P).
#
# THE DEFECT (measured 2026-09-09). The reset poller resumed session 52e35019 into a tmux pane while
# pane 616 still held the original process, both on next2. One transcript, two writers. The guard
# could not see it: it keys on the transplant tombstone's account (`handed_off_to`), and a duplicate
# on the SAME account has no transplant and is the same account. A SUPERSEDED tombstone names the live
# copy by PROCESS instead — `superseded_by_pid` — and this hook, which runs as a descendant of the
# claude it guards, compares that against its own ancestry. The live copy is acquitted; every other
# process holding the session id is blocked. A dead successor fails OPEN, exactly like the
# cross-account verdict: nothing is carrying the session, so reviving here is legitimate.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/handed-off-session-guard.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  unset CC_HANDED_OFF_GUARD_DISABLED
  CFG="$BATS_TEST_TMPDIR/cfg-secondary"; export CLAUDE_CONFIG_DIR="$CFG"
  SLUG="-Users-x-Development-thing"; PROJ="$CFG/projects/$SLUG"; mkdir -p "$PROJ"
  # The incident sid, with a ZEROED tail. The full 2026-09-09 uuid is LIVE on this box (a tmux
# `claude --resume <that uuid>` has been running since 00:51Z), and both liveness censuses under
# test — lr-select's `pgrep -f "resume <sid>"` and lr-lib's `ps -axo command=` / `--resume <sid>`
# — read the REAL process table, so the fixture's own registry row stopped being the only voice:
# --locate said DUPLICATE where the case pins RECOVERABLE, and the poller retired the record before
# it could nudge. A fixture may never name an identifier that can exist outside it (memory:
# hermetic-in-stubs-not-in-interpreter). The `52e35019` prefix is kept — it is what the display
# assertions match on, and it is how this suite stays legible against the incident it was written from.
  SID="52e35019-17e8-40f6-a54f-000000000000"
  TX="$PROJ/$SID.jsonl"; : > "$TX"
  TOMB="$PROJ/$SID.HANDOFF.json"
  INPUT="$(printf '{"session_id":"%s","transcript_path":"%s","hook_event_name":"UserPromptSubmit"}' "$SID" "$TX")"
}
mk_superseded() { # $1=successor pid  $2=successor pane
  printf '{"handed_off_to":"%s","superseded_by_pid":%d,"superseded_by_pane":"%s","ts":"2026-09-09T00:00:00Z","reason":"same-account duplicate"}\n' \
    "$CFG" "$1" "${2:-647}" > "$TOMB"
}

@test "no tombstone: an ordinary session is untouched (exit 0, silent)" {
  run bash "$HOOK" <<<"$INPUT"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "THE INCIDENT: the STALE copy (this claude pid is NOT the successor) is BLOCKED, naming the live pane" {
  mk_superseded "$$" 647
  CC_HOG_SELF_PID=4194100 run bash "$HOOK" <<<"$INPUT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"THIS PANE IS A STALE COPY"* ]] || { echo "$output"; false; }
  [[ "$output" == *"pid $$"* ]] || { echo "$output"; false; }
  [[ "$output" == *"pane 647"* ]] || { echo "$output"; false; }
}

@test "the LIVE copy (this claude pid IS the successor) is acquitted — the primary path is not broken" {
  mk_superseded "$$" 647
  CC_HOG_SELF_PID="$$" run bash "$HOOK" <<<"$INPUT"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "CONTROL: the successor is DEAD — fails OPEN, nothing else is carrying the session" {
  mk_superseded 4194101 647
  CC_HOG_SELF_PID=4194100 run bash "$HOOK" <<<"$INPUT"
  [ "$status" -eq 0 ]
}

@test "CONTROL: the account acquittal must NOT rescue a same-account stale copy" {
  # Without the supersession arm the tombstone's handed_off_to == this account would acquit EVERY
  # copy — the exact blindness that let two writers share one transcript.
  mk_superseded "$$" 647
  CC_HOG_SELF_PID=4194100 run bash "$HOOK" <<<"$INPUT"
  [ "$status" -eq 2 ]
}

@test "an unresolvable self identity fails OPEN rather than blocking a session it cannot name" {
  mk_superseded "$$" 647
  # No seam, and the real ancestry of a bats process holds no claude ⇒ _mine stays empty ⇒ exit 0.
  # (Run from inside a Claude session the walk MAY find one; pin via a ps stub so the test is hermetic.)
  STUBD="$BATS_TEST_TMPDIR/stub"; mkdir -p "$STUBD"
  printf '#!/bin/bash\nexit 0\n' > "$STUBD/ps"; chmod +x "$STUBD/ps"
  PATH="$STUBD:$PATH" run bash "$HOOK" <<<"$INPUT"
  [ "$status" -eq 0 ]
}

@test "the cross-account tombstone (no supersession field) still blocks the SOURCE as before" {
  other="$BATS_TEST_TMPDIR/cfg-tertiary"; mkdir -p "$other/projects/$SLUG"
  printf '{"handed_off_to":"%s","target_transcript":"%s/projects/%s/%s.jsonl","ts":"x","lock":"y"}\n' "$other" "$other" "$SLUG" "$SID" > "$TOMB"
  run bash "$HOOK" <<<"$INPUT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"RETIRED SOURCE"* ]] || { echo "$output"; false; }
}
