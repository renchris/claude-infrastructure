#!/usr/bin/env bats
# lib/pane-custody.sh — the ONE reader of "did this pane's originator collect its work", shared by the
# watchdog's CRASH banner and cc-husk-sweep (docs/research/husk-triage-2026-10-01.md § Gaps, items 2
# and 3: pane 55's lead was killed, its orchestrator abandoned its custody as collected, and both
# surfaces still offered --resume). Every store here is a fixture under $BATS_TEST_TMPDIR.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_CUSTODY_DIR="$BATS_TEST_TMPDIR/custody"; mkdir -p "$CC_CUSTODY_DIR"
  STORE="$CC_CUSTODY_DIR/aaaa.jsonl"
  # 2026-10-01T00:00:00Z — a session start every row below postdates unless it says otherwise
  SINCE=1790812800
}
open_row() { # <file> <ts> <targetPane> <marker> <slug> <originatorPane>
  printf '{"ts":"%s","kind":"open","cwd":"/orig","originatorPane":"%s","targetPane":"%s","marker":"%s","slug":"%s"}\n' "$2" "$6" "$3" "$4" "$5" >> "$1"
}
discharge() { # <file> <kind> <ts> <targetPane> <marker> <slug>
  printf '{"ts":"%s","kind":"%s","cwd":"/orig","targetPane":"%s","marker":"%s","slug":"%s","why":"x"}\n' "$3" "$2" "$4" "$5" "$6" >> "$1"
}
custody() { /bin/bash -c '. "$1/lib/pane-custody.sh"; cc_pane_custody "$2" "$3"' _ "$REPO" "$@"; }

@test "abandon after the open ⇒ collected, naming the slug, the discharge and the originator" {
  open_row "$STORE" 2026-10-01T00:35:50Z 55 M1 w2-reso-review 38
  discharge "$STORE" abandon 2026-10-01T03:59:28Z 55 M1 w2-reso-review
  run custody 55 "$SINCE"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'collected\tw2-reso-review\tabandon\t2026-10-01T03:59:28Z\t38')" ]
}

@test "return ⇒ collected, and the discharge may sit in another originator's file" {
  open_row "$STORE" 2026-10-01T01:00:00Z 55 M2 fire-a 4
  discharge "$CC_CUSTODY_DIR/bbbb.jsonl" return 2026-10-01T02:00:00Z 55 M2 fire-a
  run custody 55 "$SINCE"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'collected\tfire-a\treturn\t2026-10-01T02:00:00Z\t4')" ]
}

@test "no discharge ⇒ open; and a marker-less row discharges by slug+targetPane" {
  open_row "$STORE" 2026-10-01T01:00:00Z 55 M3 fire-b 7
  run custody 55 "$SINCE"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'open\tfire-b\topen\t2026-10-01T01:00:00Z\t7')" ]
  open_row "$STORE" 2026-10-01T01:30:00Z 56 "" fire-c 7
  discharge "$STORE" abandon 2026-10-01T02:00:00Z 56 "" fire-c
  run custody 56 "$SINCE"
  [ "${output%%$'\t'*}" = collected ]
}

@test "no row targets the pane ⇒ rc 1 and no output — absence is never 'collected'" {
  open_row "$STORE" 2026-10-01T01:00:00Z 41 M4 fire-d 4
  discharge "$STORE" return 2026-10-01T02:00:00Z 41 M4 fire-d
  run custody 55 "$SINCE"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "pane-id reuse: a collected row from an EARLIER tenant of the id does not speak for today's session" {
  open_row "$STORE" 2026-09-30T10:00:00Z 55 OLD old-wave 9
  discharge "$STORE" abandon 2026-09-30T12:00:00Z 55 OLD old-wave
  run custody 55 "$SINCE"
  [ "$status" -eq 1 ]
  # and the newest row since the start wins over an older one that was collected
  open_row "$STORE" 2026-10-01T05:00:00Z 55 NEW new-wave 3
  run custody 55 "$SINCE"
  [ "$output" = "$(printf 'open\tnew-wave\topen\t2026-10-01T05:00:00Z\t3')" ]
  # since=0 (an undatable session) takes the weaker, pane-only match: the newest row of any tenant
  run custody 55 0
  [ "${output%%$'\t'*}" = open ]
}

@test "an unreadable store, file or missing dir ⇒ rc 1, never a verdict" {
  open_row "$STORE" 2026-10-01T00:35:50Z 55 M1 w2 38
  discharge "$STORE" abandon 2026-10-01T03:59:28Z 55 M1 w2
  chmod 000 "$STORE"
  run custody 55 "$SINCE"
  chmod 644 "$STORE"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  CC_CUSTODY_DIR="$BATS_TEST_TMPDIR/nope" run custody 55 "$SINCE"
  [ "$status" -eq 1 ]
}

@test "cc_transcript_start_epoch dates a session by its first timestamped record, and 0 when it cannot" {
  tx="$BATS_TEST_TMPDIR/t.jsonl"
  printf '%s\n' '{"type":"last-prompt"}' 'not json' '{"type":"user","timestamp":"2026-10-01T00:35:34.718Z"}' '{"timestamp":"2026-10-01T09:00:00Z"}' > "$tx"
  run /bin/bash -c '. "$1/lib/pane-custody.sh"; cc_transcript_start_epoch "$2"' _ "$REPO" "$tx"
  [ "$output" = 1790814934 ]
  run /bin/bash -c '. "$1/lib/pane-custody.sh"; cc_transcript_start_epoch "$2"' _ "$REPO" "$BATS_TEST_TMPDIR/missing"
  [ "$output" = 0 ]
}
