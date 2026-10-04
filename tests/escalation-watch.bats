#!/usr/bin/env bats
# escalation-watch.sh — SessionStart: the HEALTH check on the escalation pipeline (D3,
# HANDOFF_FAILURE_DETECTION_V2). Since 2026-10-04 the hook reports only the two conditions under
# which the Stop readout's unseen-record count is wrong while looking fine, as ONE top-level
# systemMessage (the operator's terminal, 0 model tokens). Proves:
#   · a healthy pipeline ⇒ EMPTY stdout, and so does a FULL board over a live sweep: the per-class
#     record block is gone (operator-readout.sh owns the count), with a control beside each absence
#   · sweep-liveness keys on the sweep's OWN `"tool":"autonomy-sweep"` rows — a ledger full of other
#     hooks' `"hook":"…"` rows reads NEVER-RAN, not fresh (idl.jsonl is shared; waiting-recycle alone
#     holds 9733 rows, so "newest ts in the file" could never go stale while a session is open),
#     with a MUTATION control against a mutated copy of the live subject (`ew_mutant`)
#   · the 1 MB tail window and its full-scan fallback agree on a large ledger
#   · an unrunnable scan (perl/Digest::SHA) is REPORTED, alone, and composes with a dead sweep
#   · the channel: top-level systemMessage, never additionalContext
#   · the kill switch silences everything; the hook mutates nothing; --selftest exits 0
#
# Test law: hermetic $HOME in BATS_TEST_TMPDIR · `|| false` on non-final `[[ ]]` · positive control
# beside every absence assertion · the subject mutates NOTHING, and a test asserts that too.
# The record-store seams (CC_HANDOFF_ALARM_DIR and friends) are still exported and still seeded:
# the hook no longer reads them, and the full-board cases are what pin that.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/escalation-watch.sh"

  export HOME="$BATS_TEST_TMPDIR/home"          # hermetic: no default may reach the operator's box
  mkdir -p "$HOME"

  export CC_HANDOFF_ALARM_DIR="$BATS_TEST_TMPDIR/handoff-alarms"
  export CC_ANNOUNCE_ALARM_DIR="$BATS_TEST_TMPDIR/announce"
  export CC_COMPLETION_RECORDS_DIR="$BATS_TEST_TMPDIR/completion"
  export CC_PAGES_DIR="$BATS_TEST_TMPDIR/pages"
  # The WRITER's own seam (handoff-fire composes $CC_MAILBOX_DIR/dead-letter). Exported here for the
  # same reason as the other four: unexported, the hook's default would read the OPERATOR's live
  # dead-letter store and every count in this file would flip by machine.
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mailbox"
  export CC_SWEEP_SEEN_DIR="$BATS_TEST_TMPDIR/seen"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_EXPIRED_LEDGER="$BATS_TEST_TMPDIR/expired-unread.jsonl"
  export CC_ESCALATION_NOW=1786100000            # frozen clock — every age below is derived from it
  mkdir -p "$CC_HANDOFF_ALARM_DIR" "$CC_ANNOUNCE_ALARM_DIR" "$CC_COMPLETION_RECORDS_DIR" \
           "$CC_PAGES_DIR" "$CC_SWEEP_SEEN_DIR" "$CC_MAILBOX_DIR/dead-letter"

  sweep_ran_at 60                                # default: sweep ticked 60s ago ⇒ liveness silent
}

# ── fixtures ─────────────────────────────────────────────────────────────────────────────────────
sweep_ran_at() { # <seconds-ago> — one autonomy-sweep IDL row, in the sweep's own `"tool"` shape
  printf '{"ts":"%s","tool":"autonomy-sweep","disposition":"fired"}\n' \
    "$(date -u -r "$(( CC_ESCALATION_NOW - $1 ))" +%Y-%m-%dT%H:%M:%SZ)" > "$CC_IDL"
}

mk_handoff_alarm()    { printf '{"kind":"handoff-alarm","class":"strand-risk","pane":"1FBFCD05","detail":"%s","ts":"x"}\n' "${2:-pane never closed}" > "$CC_HANDOFF_ALARM_DIR/alarm-$1.json"; }
mk_announce_alarm()   { printf '{"kind":"alarm","alarm":"announce-not-verified","detail":"%s"}\n' "${2:-announce NOT verified}" > "$CC_ANNOUNCE_ALARM_DIR/announce-alarm-$1.json"; }
mk_announce_degrade() { printf '{"kind":"alarm","detail":"degraded delivery"}\n' > "$CC_ANNOUNCE_ALARM_DIR/announce-degrade-$1.json"; }
mk_page()             { printf '1786094114\n' > "$CC_PAGES_DIR/p-$1.page"; }
# M3 dead letter — the writer's own shape: the file is NAMED for the closing session's sid and holds
# the raw inbox body (markdown, NOT json), so the detail path here is the non-jq fallback.
mk_deadletter()       { printf '## from desk\n%s\n' "${2:-the seam ruling you asked for}" > "$CC_MAILBOX_DIR/dead-letter/$1.md"; }
# The store's EXISTENCE EVIDENCE — an append-log, deliberately not a record (R4).
mk_deadletter_ran()   { printf '2026-08-13T00:00:00Z terminal-close sid=%s pending=%s\n' "$1" "${2:-2}" >> "$CC_MAILBOX_DIR/dead-letter/.ran"; }
# completion-push records are PRETTY-PRINTED multi-line JSON on disk — the shape the real producer
# writes, and the shape the verdict filter has to survive (fixture-shape parity).
mk_completion() { # <n> <verdict>
  printf '{\n  "kind": "completion-push",\n  "detail": "push %s",\n  "verdict": "%s"\n}\n' "$1" "$2" \
    > "$CC_COMPLETION_RECORDS_DIR/push-$1.json"
}

# the sweep's REAL marker: sha256 of the record's FULL PATH, first 32 chars, no suffix
mark_seen_sweep() { : > "$CC_SWEEP_SEEN_DIR/$(printf '%s' "$1" | shasum -a 256 | cut -c1-32)"; }
# the form the FROZEN INTERFACE documents (and whatever cc-escalations ack may write)
mark_seen_basename() { : > "$CC_SWEEP_SEEN_DIR/$(basename "$1").seen"; }

# Entry count across one or more store dirs, for the mutates-NOTHING assertion. `find`, not
# `ls -A | wc -l` (SC2012): over MULTIPLE dirs `ls` interleaves a header line and a blank per
# directory, so that count was never the number of entries — it only worked because the same
# inflation appeared on both sides of the comparison. `-mindepth 1` excludes the dirs themselves,
# and a missing dir contributes 0 instead of aborting the count.
entry_count() { find "$@" -mindepth 1 2>/dev/null | wc -l | tr -d ' '; }

ctx() { # run the hook, unwrap the systemMessage
  run "$HOOK"
  [ "$status" -eq 0 ] || false
  CTX=""
  [ -z "$output" ] || CTX="$(printf '%s' "$output" | jq -r '.systemMessage')"
}

full_board() { mk_handoff_alarm 1; mk_announce_alarm 1; mk_announce_degrade 1; mk_completion 1 "push-failed(rc=5)"; mk_page 1; mk_deadletter dl-1; }
no_perl() { # a perl that cannot load Digest::SHA, as far as the hook can tell
  printf '#!/bin/bash\nexit 2\n' > "$BATS_TEST_TMPDIR/noperl"; chmod +x "$BATS_TEST_TMPDIR/noperl"
  export CC_ESCALATION_PERL="$BATS_TEST_TMPDIR/noperl"
}

ew_mutant() { # a copy of the LIVE subject with one line mutated → the strong RED-proof
  local out="$BATS_TEST_TMPDIR/mutant.sh"
  sed "$1" "$HOOK" > "$out"
  bash -n "$out" || false        # a malformed mutant reddens everything, which reads as coverage
  printf '%s' "$out"
}

# ── healthy is silent, and records alone no longer speak ─────────────────────────────────────────
@test "an empty board + a live sweep prints NOTHING AT ALL" {
  run "$HOOK"
  [ "$status" -eq 0 ] || false
  [ -z "$output" ]
}

@test "a FULL board over a live sweep is silent too — the per-class block is gone" {
  full_board
  [ "$(entry_count "$CC_HANDOFF_ALARM_DIR" "$CC_ANNOUNCE_ALARM_DIR" "$CC_COMPLETION_RECORDS_DIR" "$CC_PAGES_DIR" "$CC_MAILBOX_DIR/dead-letter")" -eq 6 ]
  run "$HOOK"
  [ "$status" -eq 0 ] || false
  [ -z "$output" ]
}

@test "positive control: the SAME full board speaks once the sweep is dead — and names no class" {
  full_board
  sweep_ran_at 3600
  ctx
  [[ "$CTX" == *"autonomy-sweep last ran 1h 0m ago"* ]] || false
  [[ "$CTX" == *"NOT being drained"* ]] || false
  [[ "$CTX" != *"ESCALATIONS (unseen"* ]] || false
  [[ "$CTX" != *"handoff-alarm"* ]] || false
  [[ "$CTX" != *"mail-deadletter"* ]] || false
}

@test "records that expired unread are not reported here either" {
  printf '{"ts":"%s","kind":"expired-unread"}\n' "$(date -u -r "$(( CC_ESCALATION_NOW - 3600 ))" +%Y-%m-%dT%H:%M:%SZ)" > "$CC_EXPIRED_LEDGER"
  run "$HOOK"
  [ "$status" -eq 0 ] || false
  [ -z "$output" ]
}

# ── sweep liveness ───────────────────────────────────────────────────────────────────────────────
@test "the stale-sweep line renders with ZERO records — a dead sweep is itself the alarm" {
  sweep_ran_at 3600
  ctx
  [[ "$CTX" == "ESCALATION PIPELINE: ⚠ autonomy-sweep last ran 1h 0m ago"* ]] || false
  [[ "$CTX" == *"NOT being drained"* ]] || false
}

@test "an absent IDL file reads NEVER-RAN, not fresh" {
  rm -f "$CC_IDL"
  ctx
  [[ "$CTX" == *"has NEVER run"* ]] || false
}

@test "a ledger full of OTHER hooks' rows does NOT fake sweep liveness" {
  # idl.jsonl is SHARED. Hooks write `"hook":"<name>"`; only the sweep writes `"tool":"autonomy-sweep"`.
  # Keying on the newest ts in the file would read this as a live sweep 5 seconds ago.
  printf '{"ts":"%s","hook":"waiting-recycle","disposition":"abstained"}\n' \
    "$(date -u -r "$(( CC_ESCALATION_NOW - 5 ))" +%Y-%m-%dT%H:%M:%SZ)" > "$CC_IDL"
  ctx
  [[ "$CTX" == *"has NEVER run"* ]] || false
}

@test "MUTATION control: the foreign-row assertion is not vacuous" {
  # Widen the row filter to ANY row — i.e. exactly the "newest ts in idl.jsonl" reading — and the
  # same fixture must flip to reporting a healthy sweep.
  printf '{"ts":"%s","hook":"waiting-recycle","disposition":"abstained"}\n' \
    "$(date -u -r "$(( CC_ESCALATION_NOW - 5 ))" +%Y-%m-%dT%H:%M:%SZ)" > "$CC_IDL"
  local m
  # Both reads (the tail window and its full-scan fallback) carry the filter, so the mutant widens
  # every occurrence; a sed that matched nothing would leave the subject alarming and fail below.
  m="$(ew_mutant 's/LC_ALL=C grep -F .\"tool\":\"autonomy-sweep\"./cat/g')"
  run bash "$m"
  [ "$status" -eq 0 ] || false
  [ -z "$output" ]                   # the mutant goes SILENT where the subject alarms
}

# ── the 1 MB tail window over a large ledger (the live one is ~17 MB) ─────────────────────────────
foreign_rows_mb() { # <MB> — append ~<MB> MB of other tools' rows, newer than any sweep row
  awk -v n="$(( $1 * 9000 ))" -v ts="$(date -u -r "$CC_ESCALATION_NOW" +%Y-%m-%dT%H:%M:%SZ)" \
    'BEGIN { for (i = 0; i < n; i++) printf "{\"ts\":\"%s\",\"hook\":\"waiting-recycle\",\"disposition\":\"abstained\",\"pad\":\"%060d\"}\n", ts, i }' \
    >> "$CC_IDL"
}

@test "large ledger: a fresh sweep row inside the tail window keeps liveness silent" {
  foreign_rows_mb 2
  printf '{"ts":"%s","tool":"autonomy-sweep","disposition":"fired"}\n' \
    "$(date -u -r "$(( CC_ESCALATION_NOW - 60 ))" +%Y-%m-%dT%H:%M:%SZ)" >> "$CC_IDL"
  foreign_rows_mb 0; [ "$(wc -c < "$CC_IDL")" -gt 1048576 ] || false
  run "$HOOK"
  [ "$status" -eq 0 ] || false
  [ -z "$output" ]
}

@test "large ledger: a stale sweep row BEFORE the tail window is still found (full-scan fallback)" {
  sweep_ran_at 7200                  # 2h ago, then >1 MB of newer foreign rows buries it
  foreign_rows_mb 2
  ctx
  [[ "$CTX" == *"autonomy-sweep last ran 2h 0m ago"* ]] || false
  [[ "$CTX" != *"NEVER run"* ]] || false
}

# ── the scan-health line ─────────────────────────────────────────────────────────────────────────
@test "an unrunnable scan is REPORTED, alone, over a live sweep" {
  # The Stop readout's counter prints 0 when perl is missing; this line is what says that 0 is a
  # board nobody read. The healthy-silent case above is its control: same fixture, real perl.
  no_perl
  ctx
  [[ "$CTX" == "ESCALATION PIPELINE: ⚠ escalation record scan DID NOT RUN"* ]] || false
  [[ "$CTX" == *"ABSENT, not zero"* ]] || false
  [[ "$CTX" != *"autonomy-sweep"* ]] || false
}

@test "an unrunnable scan and a dead sweep compose into ONE message, one line each" {
  no_perl
  sweep_ran_at 3600
  run "$HOOK"
  [ "$status" -eq 0 ] || false
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 1 ]
  [ "$(printf '%s' "$output" | jq -r '.systemMessage' | wc -l | tr -d ' ')" -eq 2 ]
  printf '%s' "$output" | jq -e '.systemMessage | test("scan DID NOT RUN") and test("NOT being drained")' >/dev/null
}

# ── channel, kill switch, purity ─────────────────────────────────────────────────────────────────
@test "the emit is a top-level systemMessage — never additionalContext" {
  # additionalContext is model context the TUI hides; hookSpecificOutput.systemMessage is silently
  # ignored. Only the top-level key renders for the operator.
  sweep_ran_at 3600
  run "$HOOK"
  [ "$status" -eq 0 ] || false
  printf '%s' "$output" | jq -e '(.systemMessage | length > 0) and (has("hookSpecificOutput") | not)' >/dev/null
}

@test "CC_ESCALATION_WATCH=0 silences the hook even with a full board and a dead sweep" {
  full_board
  sweep_ran_at 99999
  CC_ESCALATION_WATCH=0 run "$HOOK"
  [ "$status" -eq 0 ] || false
  [ -z "$output" ]
}

@test "the hook mutates NOTHING — no seen marker, no record, no ledger row" {
  mk_handoff_alarm 1; mk_announce_alarm 1; mk_completion 1 "push-failed(rc=5)"; mk_page 1; mk_deadletter dl-1
  local before_seen before_rec before_idl
  before_seen="$(entry_count "$CC_SWEEP_SEEN_DIR")"
  before_rec="$(entry_count "$CC_HANDOFF_ALARM_DIR" "$CC_ANNOUNCE_ALARM_DIR" "$CC_COMPLETION_RECORDS_DIR" "$CC_PAGES_DIR" "$CC_MAILBOX_DIR/dead-letter")"
  before_idl="$(wc -l < "$CC_IDL")"
  run "$HOOK"
  [ "$status" -eq 0 ] || false
  # A positive control on the counter itself: the fixtures above created records, so a counter
  # that always returned 0 would satisfy every equality here without measuring anything.
  [ "$before_rec" -gt 0 ]
  [ "$(entry_count "$CC_SWEEP_SEEN_DIR")" -eq "$before_seen" ]
  [ "$(entry_count "$CC_HANDOFF_ALARM_DIR" "$CC_ANNOUNCE_ALARM_DIR" "$CC_COMPLETION_RECORDS_DIR" "$CC_PAGES_DIR" "$CC_MAILBOX_DIR/dead-letter")" -eq "$before_rec" ]
  [ "$(wc -l < "$CC_IDL")" -eq "$before_idl" ]
}

@test "--selftest exits 0 and reports GREEN" {
  run bash "$HOOK" --selftest
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"0 failed"* ]] || false
  [[ "$output" == *"GREEN"* ]] || false
}
