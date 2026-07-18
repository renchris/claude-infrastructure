#!/usr/bin/env bats
# handoff-disposition.sh — un-fakeable mechanical-reason reads.
#
# Every fixture lives in $BATS_TEST_TMPDIR; env overrides (CC_MAILBOX_DIR,
# CC_SESSIONS_BIN, CC_TASKS_DIR) point the script at them. --cwd is pointed at
# a scratch dir so the surrounding worktree's own dirtiness never leaks in.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HD="$REPO/scripts/handoff-disposition.sh"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mailbox"
  export CC_TASKS_DIR="$BATS_TEST_TMPDIR/tasks"
  export CC_SESSIONS_BIN=/nonexistent          # default: no live-peer resolution
  mkdir -p "$CC_MAILBOX_DIR" "$CC_TASKS_DIR"
  CLEAN="$BATS_TEST_TMPDIR/clean"               # a scratch non-repo cwd
  mkdir -p "$CLEAN"
}

# make an executable stub script on PATH / at a path
mkstub() { printf '#!/bin/bash\n%s\n' "$2" > "$1"; chmod +x "$1"; }

@test "1 clean state -> exit 0, all-empty JSON, close-eligible" {
  run bash "$HD" --cwd "$CLEAN" --session UUID-CLEAN
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"dirty":0'
  echo "$output" | grep -q '"mailbox_pending":\[\]'
  echo "$output" | grep -q '"await_ping_running":false'
  echo "$output" | grep -q '"fired_peers_alive":\[\]'
  echo "$output" | grep -q '"open_tasks":null'
  echo "$output" | grep -q 'close-eligible'
}

@test "2 dirty tree -> dirty>0, exit 1" {
  repo="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$repo"; git -C "$repo" init -q; touch "$repo/newfile"
  run bash "$HD" --cwd "$repo" --session UUID-DIRTY
  [ "$status" -eq 1 ]
  dirty=$(echo "$output" | head -n1 | jq '.dirty')
  [ "$dirty" -gt 0 ]
}

@test "3 mailbox pending (2 lines, no cursor) -> mailbox_pending=[uuid], exit 1" {
  printf '2026-01-01 [peer] hi\n2026-01-02 [peer] again\n' > "$CC_MAILBOX_DIR/UUID-MB.md"
  run bash "$HD" --cwd "$CLEAN" --session UUID-MB
  [ "$status" -eq 1 ]
  echo "$output" | head -n1 | jq -e '.mailbox_pending == ["UUID-MB"]'
}

@test "4 mailbox acked then plain -> second run exit 0" {
  printf 'l1\nl2\n' > "$CC_MAILBOX_DIR/UUID-ACK.md"
  # --ack writes the cursor BEFORE computing, so the acked run itself reports empty
  run bash "$HD" --cwd "$CLEAN" --session UUID-ACK --ack
  [ "$status" -eq 0 ]
  echo "$output" | head -n1 | jq -e '.mailbox_pending == []'
  # and a subsequent plain run also sees nothing pending
  run bash "$HD" --cwd "$CLEAN" --session UUID-ACK
  [ "$status" -eq 0 ]
  echo "$output" | head -n1 | jq -e '.mailbox_pending == []'
}

@test "5 cursor older than mail (cursor=1, file 3 lines) -> pending, exit 1" {
  printf 'l1\nl2\nl3\n' > "$CC_MAILBOX_DIR/UUID-OLD.md"
  printf '1\n' > "$CC_MAILBOX_DIR/UUID-OLD.seen"
  run bash "$HD" --cwd "$CLEAN" --session UUID-OLD
  [ "$status" -eq 1 ]
  echo "$output" | head -n1 | jq -e '.mailbox_pending == ["UUID-OLD"]'
}

@test "6 await_ping_running: uuid-scoped pgrep match -> true, exit 1" {
  bindir="$BATS_TEST_TMPDIR/bin"; mkdir -p "$bindir"
  # a watcher for OUR uuid exists: only the scoped pattern matches
  mkstub "$bindir/pgrep" 'case "${2:-}" in *UUID-AP*) exit 0 ;; *) exit 1 ;; esac'
  run env PATH="$bindir:$PATH" bash "$HD" --cwd "$CLEAN" --session UUID-AP
  [ "$status" -eq 1 ]
  echo "$output" | head -n1 | jq -e '.await_ping_running == true'
}

@test "6b another session's watcher is NOT counted (scoped match) -> false, exit 0" {
  bindir="$BATS_TEST_TMPDIR/bin6b"; mkdir -p "$bindir"
  # a watcher exists (bare pattern would match) but none carries OUR uuid
  mkstub "$bindir/pgrep" 'case "${2:-}" in *UUID-AP2*) exit 1 ;; *) exit 0 ;; esac'
  run env PATH="$bindir:$PATH" bash "$HD" --cwd "$CLEAN" --session UUID-AP2
  [ "$status" -eq 0 ]
  echo "$output" | head -n1 | jq -e '.await_ping_running == false'
}

@test "6c no uuid resolvable -> global pgrep fallback -> true, exit 1" {
  bindir="$BATS_TEST_TMPDIR/bin6c"; mkdir -p "$bindir"
  mkstub "$bindir/pgrep" 'exit 0'
  run env -u ITERM_SESSION_ID PATH="$bindir:$PATH" bash "$HD" --cwd "$CLEAN"
  [ "$status" -eq 1 ]
  echo "$output" | head -n1 | jq -e '.await_ping_running == true'
}

@test "7 fired_peers_alive: stub 3 names, 2 slugs 1 match -> only match, exit 1" {
  stub="$BATS_TEST_TMPDIR/cc-sessions"
  mkstub "$stub" 'printf "ship-hardening\ndisposition-helper\nlead-main\n"'
  export CC_SESSIONS_BIN="$stub"
  run bash "$HD" --cwd "$CLEAN" --session UUID-P ship nomatch
  [ "$status" -eq 1 ]
  echo "$output" | head -n1 | jq -e '.fired_peers_alive == ["ship-hardening"]'
}

@test "8 cc-sessions absent -> [], no crash" {
  export CC_SESSIONS_BIN=/nonexistent
  run bash "$HD" --cwd "$CLEAN" --session UUID-NOSESS ship
  [ "$status" -eq 0 ]
  echo "$output" | head -n1 | jq -e '.fired_peers_alive == []'
}

@test "9 open_tasks from fixture summary (pending 2, in_progress 1) -> 3, exit 1" {
  mkdir -p "$CC_TASKS_DIR/TL1"
  printf '{"pending":2,"in_progress":1,"completed":5}\n' > "$CC_TASKS_DIR/TL1/_summary.json"
  run bash "$HD" --cwd "$CLEAN" --session UUID-T --tasklist TL1
  [ "$status" -eq 1 ]
  echo "$output" | head -n1 | jq -e '.open_tasks == 3'
}

@test "10 --tasklist with missing summary -> null, exit 0" {
  run bash "$HD" --cwd "$CLEAN" --session UUID-T2 --tasklist NOPE
  [ "$status" -eq 0 ]
  echo "$output" | head -n1 | jq -e '.open_tasks == null'
}

@test "11 JSON validity: stdout parses with jq (representative dirty+peers run)" {
  repo="$BATS_TEST_TMPDIR/repo11"; mkdir -p "$repo"; git -C "$repo" init -q; touch "$repo/x"
  stub="$BATS_TEST_TMPDIR/cc-sessions11"
  mkstub "$stub" 'printf "alpha-peer\n"'
  export CC_SESSIONS_BIN="$stub"
  run bash "$HD" --cwd "$repo" --session UUID-J alpha
  echo "$output" | head -n1 | jq -e 'type == "object"'
}

@test "12 usage error (unknown flag) -> exit 2" {
  run bash "$HD" --bogus
  [ "$status" -eq 2 ]
}

# ---- disposition hardening (G-P1-7 fail-closed + word-boundary + a19 §4 completeness) --------

@test "13 cc-sessions present but ERRORS (rc!=0) -> R-REGISTRY-INDETERMINATE, exit 1" {
  stub="$BATS_TEST_TMPDIR/cc-sessions-err"; mkstub "$stub" 'exit 2'
  export CC_SESSIONS_BIN="$stub"
  run bash "$HD" --cwd "$CLEAN" --session UUID-ERR ship
  [ "$status" -eq 1 ]
  echo "$output" | head -n1 | jq -e '.registry_indeterminate == true'
  echo "$output" | grep -q 'R-REGISTRY-INDETERMINATE'
}

@test "13b cc-sessions rc0 empty output -> genuinely empty, NOT indeterminate, exit 0" {
  stub="$BATS_TEST_TMPDIR/cc-sessions-empty"; mkstub "$stub" 'exit 0'
  export CC_SESSIONS_BIN="$stub"
  run bash "$HD" --cwd "$CLEAN" --session UUID-EMPTY ship
  [ "$status" -eq 0 ]
  echo "$output" | head -n1 | jq -e '.registry_indeterminate == false and .fired_peers_alive == []'
}

@test "13c cc-sessions absent (rc127) stays unavailable -> NOT indeterminate, exit 0" {
  export CC_SESSIONS_BIN=/nonexistent
  run bash "$HD" --cwd "$CLEAN" --session UUID-ABS ship
  [ "$status" -eq 0 ]
  echo "$output" | head -n1 | jq -e '.registry_indeterminate == false'
}

@test "14 word-boundary slug: 'ship' hits 'ship-hardening' NOT 'relationship-tracker'" {
  stub="$BATS_TEST_TMPDIR/cc-sessions-wb"
  mkstub "$stub" 'printf "relationship-tracker\nship-hardening\n"'
  export CC_SESSIONS_BIN="$stub"
  run bash "$HD" --cwd "$CLEAN" --session UUID-WB ship
  [ "$status" -eq 1 ]
  echo "$output" | head -n1 | jq -e '.fired_peers_alive == ["ship-hardening"]'
}

@test "14b word-boundary: a slug that is only a substring -> no match, close-eligible (exit 0)" {
  stub="$BATS_TEST_TMPDIR/cc-sessions-wb2"; mkstub "$stub" 'printf "relationship-tracker\n"'
  export CC_SESSIONS_BIN="$stub"
  run bash "$HD" --cwd "$CLEAN" --session UUID-WB2 ship
  [ "$status" -eq 0 ]
  echo "$output" | head -n1 | jq -e '.fired_peers_alive == []'
}

@test "15 deliverable_missing: --deliverable absent -> exit 1, path listed" {
  run bash "$HD" --cwd "$CLEAN" --session UUID-D --deliverable "$BATS_TEST_TMPDIR/nope.md"
  [ "$status" -eq 1 ]
  echo "$output" | head -n1 | jq -e '.deliverables_missing | index("'"$BATS_TEST_TMPDIR"'/nope.md") != null'
  echo "$output" | grep -q 'deliverables-missing'
}

@test "15b --deliverable present + non-empty -> not missing, exit 0" {
  printf 'content\n' > "$BATS_TEST_TMPDIR/out.md"
  run bash "$HD" --cwd "$CLEAN" --session UUID-D2 --deliverable "$BATS_TEST_TMPDIR/out.md"
  [ "$status" -eq 0 ]
  echo "$output" | head -n1 | jq -e '.deliverables_missing == []'
}

@test "15c --deliverable present but EMPTY (zero-length) -> missing, exit 1" {
  : > "$BATS_TEST_TMPDIR/empty.md"
  run bash "$HD" --cwd "$CLEAN" --session UUID-D3 --deliverable "$BATS_TEST_TMPDIR/empty.md"
  [ "$status" -eq 1 ]
  echo "$output" | head -n1 | jq -e '.deliverables_missing | length == 1'
}

@test "16 --payload DELIVERABLE: extraction -> missing declared path opens (exit 1)" {
  payload="$BATS_TEST_TMPDIR/payload.md"
  printf 'some brief\nDELIVERABLE: %s/report.md\nmore\n' "$BATS_TEST_TMPDIR" > "$payload"
  run bash "$HD" --cwd "$CLEAN" --session UUID-PL --payload "$payload"
  [ "$status" -eq 1 ]
  echo "$output" | head -n1 | jq -e '.deliverables_missing | length == 1'
}

@test "16b --payload DELIVERABLE: present -> close-eligible (exit 0)" {
  printf 'x\n' > "$BATS_TEST_TMPDIR/report.md"
  payload="$BATS_TEST_TMPDIR/payload2.md"
  printf 'DELIVERABLE: %s/report.md\n' "$BATS_TEST_TMPDIR" > "$payload"
  run bash "$HD" --cwd "$CLEAN" --session UUID-PL2 --payload "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | head -n1 | jq -e '.deliverables_missing == []'
}
