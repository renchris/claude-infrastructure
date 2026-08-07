#!/usr/bin/env bats
# escalation-watch.sh — SessionStart: the GUARANTEED READER for the escalation dead-letter stores
# (D3, HANDOFF_FAILURE_DETECTION_V2). Proves:
#   · each of the 5 record classes renders one bounded counted line
#   · ZERO unseen records + a live sweep ⇒ EMPTY stdout (the absence-of-noise contract) — with a
#     positive control beside it, so the assertion cannot pass vacuously
#   · BOTH seen-marker forms suppress: the sweep's real sha256(FULL PATH)|cut -c1-32 key AND
#     `<basename>.seen`. The FROZEN INTERFACE documents only the second and calls it "the existing
#     sweep convention"; autonomy-sweep.sh:89-91 implements only the first. A reader that honoured
#     the doc would re-render every drained record forever, so both are pinned here.
#   · sweep-liveness keys on the sweep's OWN `"tool":"autonomy-sweep"` rows — a ledger full of other
#     hooks' `"hook":"…"` rows reads NEVER-RAN, not fresh (idl.jsonl is shared; waiting-recycle alone
#     holds 9733 rows, so "newest ts in the file" could never go stale while a session is open)
#   · the stale-sweep line renders even at ZERO records (a dead sweep is itself the alarm)
#   · expired-unread counts the last 24h only
#   · the kill switch silences everything; --selftest exits 0
#
# RED-PROOF. hooks/escalation-watch.sh is a NEW file: `git archive HEAD` recovers a tree in which it
# does not exist, so every test here reds trivially there (the runner cannot find the subject). That
# is a real red but a weak one, so the two assertions whose logic could silently invert — the
# empty-board control and the foreign-IDL-row control — additionally carry MUTATION controls that
# red them against a mutated copy of the LIVE subject (`ew_mutant`), which is the strong form.
#
# Test law: hermetic $HOME in BATS_TEST_TMPDIR · `|| false` on non-final `[[ ]]` · positive control
# beside every absence assertion · the subject mutates NOTHING, and a test asserts that too.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/escalation-watch.sh"

  export HOME="$BATS_TEST_TMPDIR/home"          # hermetic: no default may reach the operator's box
  mkdir -p "$HOME"

  export CC_HANDOFF_ALARM_DIR="$BATS_TEST_TMPDIR/handoff-alarms"
  export CC_ANNOUNCE_ALARM_DIR="$BATS_TEST_TMPDIR/announce"
  export CC_COMPLETION_RECORDS_DIR="$BATS_TEST_TMPDIR/completion"
  export CC_PAGES_DIR="$BATS_TEST_TMPDIR/pages"
  export CC_SWEEP_SEEN_DIR="$BATS_TEST_TMPDIR/seen"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_EXPIRED_LEDGER="$BATS_TEST_TMPDIR/expired-unread.jsonl"
  export CC_ESCALATION_NOW=1786100000            # frozen clock — every age below is derived from it
  mkdir -p "$CC_HANDOFF_ALARM_DIR" "$CC_ANNOUNCE_ALARM_DIR" "$CC_COMPLETION_RECORDS_DIR" \
           "$CC_PAGES_DIR" "$CC_SWEEP_SEEN_DIR"

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

ctx() { # run the hook, unwrap additionalContext when jq wrapped it
  run "$HOOK"
  [ "$status" -eq 0 ] || false
  if command -v jq >/dev/null 2>&1 && [ -n "$output" ]; then
    CTX="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null || printf '%s' "$output")"
  else
    CTX="$output"
  fi
}

ew_mutant() { # a copy of the LIVE subject with one line mutated → the strong RED-proof
  local out="$BATS_TEST_TMPDIR/mutant.sh"
  sed "$1" "$HOOK" > "$out"
  bash -n "$out" || false        # a malformed mutant reddens everything, which reads as coverage
  printf '%s' "$out"
}

# ── each class renders ───────────────────────────────────────────────────────────────────────────
@test "handoff-alarm records render as a counted class line with the newest detail" {
  mk_handoff_alarm 1 "pane 1FBFCD05 never closed"
  ctx
  [[ "$CTX" == *"ESCALATIONS (unseen dead-letter records):"* ]] || false
  [[ "$CTX" == *"handoff-alarm: 1"* ]] || false
  [[ "$CTX" == *"pane 1FBFCD05 never closed"* ]] || false
}

@test "announce-alarm and announce-degrade are counted as SEPARATE classes from one store" {
  mk_announce_alarm 1
  mk_announce_degrade 1
  mk_announce_degrade 2
  ctx
  [[ "$CTX" == *"announce-alarm: 1"* ]] || false
  [[ "$CTX" == *"announce-degrade: 2"* ]] || false
}

@test "completion-push counts ONLY records whose verdict is not verified" {
  mk_completion 1 "push-failed(cc-announce rc=5)"
  mk_completion 2 "verified"
  mk_completion 3 "degraded(delivered, wake unconfirmed)"
  ctx
  # 2 stuck of 3 present — the positive control is that the class renders at all, so a filter that
  # dropped everything would fail here rather than passing as "nothing stuck".
  [[ "$CTX" == *"completion-push: 2"* ]] || false
  [[ "$CTX" != *"completion-push: 3"* ]] || false
}

@test "pages render, and every class sums into one bounded block (<= 12 lines)" {
  mk_handoff_alarm 1; mk_announce_alarm 1; mk_announce_degrade 1
  mk_completion 1 "push-failed(rc=5)"; mk_page 1; mk_page 2
  ctx
  [[ "$CTX" == *"page: 2"* ]] || false
  [ "$(printf '%s\n' "$CTX" | wc -l | tr -d ' ')" -le 12 ]
}

# ── the absence-of-noise contract, with its controls ─────────────────────────────────────────────
@test "zero unseen records + a live sweep prints NOTHING AT ALL" {
  run "$HOOK"
  [ "$status" -eq 0 ] || false
  [ -z "$output" ]
}

@test "positive control: the SAME empty board speaks the moment one record appears" {
  run "$HOOK"
  [ -z "$output" ] || false          # the absence half
  mk_handoff_alarm 1
  ctx
  [[ "$CTX" == *"handoff-alarm: 1"* ]] || false
}

@test "MUTATION control: the empty-board silence is not vacuous" {
  # Deleting candidates()'s trailing `return 0` lets the last failing `[ -f ]` propagate through
  # pipefail, and a healthy empty board misreports as "the scan DID NOT RUN".
  local m; m="$(ew_mutant '/^  return 0$/d')"
  run bash "$m"
  [ "$status" -eq 0 ] || false
  [ -n "$output" ]                   # the mutant SPEAKS where the subject is silent
  [[ "$output" == *"DID NOT RUN"* ]] || false
}

# ── seen suppression: BOTH marker forms ──────────────────────────────────────────────────────────
@test "the sweep's real sha256-of-full-path marker suppresses a record" {
  mk_handoff_alarm 1
  ctx
  [[ "$CTX" == *"handoff-alarm: 1"* ]] || false      # positive control: it rendered first
  mark_seen_sweep "$CC_HANDOFF_ALARM_DIR/alarm-1.json"
  run "$HOOK"
  [ "$status" -eq 0 ] || false
  [ -z "$output" ]
}

@test "a <basename>.seen marker also suppresses (the ack form the frozen interface documents)" {
  mk_announce_alarm 1
  ctx
  [[ "$CTX" == *"announce-alarm: 1"* ]] || false
  mark_seen_basename "$CC_ANNOUNCE_ALARM_DIR/announce-alarm-1.json"
  run "$HOOK"
  [ "$status" -eq 0 ] || false
  [ -z "$output" ]
}

@test "suppression is per-record: marking one leaves its siblings counted" {
  mk_announce_alarm 1; mk_announce_alarm 2; mk_announce_alarm 3
  mark_seen_sweep "$CC_ANNOUNCE_ALARM_DIR/announce-alarm-2.json"
  ctx
  [[ "$CTX" == *"announce-alarm: 2"* ]] || false
}

# ── sweep liveness — the watcher of the watcher (F7) ─────────────────────────────────────────────
@test "a sweep older than 15 min renders the not-being-drained line" {
  sweep_ran_at 3600
  mk_handoff_alarm 1
  ctx
  [[ "$CTX" == *"autonomy-sweep last ran"* ]] || false
  [[ "$CTX" == *"NOT being drained"* ]] || false
}

@test "the stale-sweep line renders with ZERO records — a dead sweep is itself the alarm" {
  sweep_ran_at 3600
  ctx
  [[ "$CTX" == *"NOT being drained"* ]] || false
  [[ "$CTX" != *"ESCALATIONS"* ]] || false     # and it does NOT invent a record block
}

@test "a fresh sweep row keeps the liveness line silent (positive control for the above)" {
  sweep_ran_at 60
  mk_handoff_alarm 1
  ctx
  [[ "$CTX" == *"handoff-alarm: 1"* ]] || false
  [[ "$CTX" != *"NOT being drained"* ]] || false
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
  # Widen the row filter to ANY row — i.e. exactly the "newest ts in idl.jsonl" reading the brief
  # specified — and the same fixture must flip to reporting a healthy sweep.
  printf '{"ts":"%s","hook":"waiting-recycle","disposition":"abstained"}\n' \
    "$(date -u -r "$(( CC_ESCALATION_NOW - 5 ))" +%Y-%m-%dT%H:%M:%SZ)" > "$CC_IDL"
  local m; m="$(ew_mutant 's/grep .\"tool\":\"autonomy-sweep\". "\$IDL"/cat "$IDL"/')"
  run bash "$m"
  [ "$status" -eq 0 ] || false
  [ -z "$output" ]                   # the mutant goes SILENT where the subject alarms
}

# ── expired-unread ───────────────────────────────────────────────────────────────────────────────
@test "expired-unread counts rows from the last 24h only" {
  printf '{"ts":"%s","kind":"expired-unread"}\n' "$(date -u -r "$(( CC_ESCALATION_NOW - 3600 ))"   +%Y-%m-%dT%H:%M:%SZ)" >  "$CC_EXPIRED_LEDGER"
  printf '{"ts":"%s","kind":"expired-unread"}\n' "$(date -u -r "$(( CC_ESCALATION_NOW - 7200 ))"   +%Y-%m-%dT%H:%M:%SZ)" >> "$CC_EXPIRED_LEDGER"
  printf '{"ts":"%s","kind":"expired-unread"}\n' "$(date -u -r "$(( CC_ESCALATION_NOW - 200000 ))" +%Y-%m-%dT%H:%M:%SZ)" >> "$CC_EXPIRED_LEDGER"
  ctx
  [[ "$CTX" == *"2 record(s) expired UNREAD in the last 24h"* ]] || false
}

@test "an expired ledger holding only OLD rows stays silent (control)" {
  printf '{"ts":"%s","kind":"expired-unread"}\n' "$(date -u -r "$(( CC_ESCALATION_NOW - 200000 ))" +%Y-%m-%dT%H:%M:%SZ)" > "$CC_EXPIRED_LEDGER"
  run "$HOOK"
  [ "$status" -eq 0 ] || false
  [ -z "$output" ]
}

# ── contract ─────────────────────────────────────────────────────────────────────────────────────
@test "CC_ESCALATION_WATCH=0 silences the hook even with a full board and a dead sweep" {
  mk_handoff_alarm 1; mk_announce_alarm 1; mk_page 1
  sweep_ran_at 99999
  CC_ESCALATION_WATCH=0 run "$HOOK"
  [ "$status" -eq 0 ] || false
  [ -z "$output" ]
}

@test "output is valid SessionStart additionalContext JSON" {
  command -v jq >/dev/null 2>&1 || skip "jq absent"
  mk_handoff_alarm 1
  run "$HOOK"
  [ "$status" -eq 0 ] || false
  printf '%s' "$output" | jq -e '.hookSpecificOutput.hookEventName=="SessionStart"' >/dev/null
  printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | length > 0' >/dev/null
}

@test "the hook mutates NOTHING — no seen marker, no record, no ledger row" {
  mk_handoff_alarm 1; mk_announce_alarm 1; mk_completion 1 "push-failed(rc=5)"; mk_page 1
  local before_seen before_rec before_idl
  before_seen="$(ls -A "$CC_SWEEP_SEEN_DIR" | wc -l)"
  before_rec="$(ls -A "$CC_HANDOFF_ALARM_DIR" "$CC_ANNOUNCE_ALARM_DIR" "$CC_COMPLETION_RECORDS_DIR" "$CC_PAGES_DIR" | wc -l)"
  before_idl="$(wc -l < "$CC_IDL")"
  run "$HOOK"
  [ "$status" -eq 0 ] || false
  [ "$(ls -A "$CC_SWEEP_SEEN_DIR" | wc -l)" -eq "$before_seen" ]
  [ "$(ls -A "$CC_HANDOFF_ALARM_DIR" "$CC_ANNOUNCE_ALARM_DIR" "$CC_COMPLETION_RECORDS_DIR" "$CC_PAGES_DIR" | wc -l)" -eq "$before_rec" ]
  [ "$(wc -l < "$CC_IDL")" -eq "$before_idl" ]
}

@test "an absent store dir is tolerated (fail-open), and the rest still render" {
  rm -rf "$CC_PAGES_DIR"
  mk_handoff_alarm 1
  ctx
  [[ "$CTX" == *"handoff-alarm: 1"* ]] || false
  [[ "$CTX" != *"page:"* ]] || false
}

@test "--selftest exits 0 and reports GREEN" {
  run bash "$HOOK" --selftest
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"0 failed"* ]] || false
  [[ "$output" == *"GREEN"* ]] || false
}
