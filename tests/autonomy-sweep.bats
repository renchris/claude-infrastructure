#!/usr/bin/env bats
# autonomy-sweep.sh — the ONE pull-based consumer of the write-only escalation dirs (a18 SO-5).
# Drains pages/ + cc-announce-alarms/ + completion-push/(push-failed) + decisions/(open+expiring),
# dedupes via per-record .seen markers, and: (a) cc-notifies the desk ROLE once when anything NEW
# exists, (b) runs cc-decide expire-sweep and appends each fired class-B default as a cc-backlog
# item (never acts inline), (c) writes one {fired|abstained} IDL record.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SWEEP="$REPO/scripts/autonomy-sweep.sh"
  export CC_PAGES_DIR="$BATS_TEST_TMPDIR/pages"
  export CC_ANNOUNCE_ALARM_DIR="$BATS_TEST_TMPDIR/alarms"
  export CC_COMPLETION_RECORDS_DIR="$BATS_TEST_TMPDIR/completion"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_SWEEP_SEEN_DIR="$BATS_TEST_TMPDIR/seen"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_DECIDE_BIN="$REPO/bin/cc-decide"
  export CC_BACKLOG_BIN="$REPO/bin/cc-backlog"
  # ⚠️ EVERY dir the sweep can DELETE from must be redirected here. The sweep age-reaps six event
  # dirs; any one left unexported falls back to its $HOME default and the suite becomes a reaper
  # against LIVE state. (It did: an unexported CC_TEARDOWN_RECORDS_DIR let a test run delete 6 real
  # ~/.claude/cc-teardown records, 2026-07-25. A destructive default is the harness's bug.)
  export CC_COMMS_ALARM_DIR="$BATS_TEST_TMPDIR/comms-alarms"
  export CC_PUSH_RECORDS_DIR="$BATS_TEST_TMPDIR/push-records"
  export CC_TEARDOWN_RECORDS_DIR="$BATS_TEST_TMPDIR/cc-teardown"
  export CC_INBOX_GUARD_STATE_DIR="$BATS_TEST_TMPDIR/inbox-guard"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mailbox"
  mkdir -p "$CC_PAGES_DIR" "$CC_ANNOUNCE_ALARM_DIR" "$CC_COMPLETION_RECORDS_DIR" \
           "$CC_DECISIONS_DIR" "$CC_ROLES_DIR" "$CC_COMMS_ALARM_DIR" "$CC_PUSH_RECORDS_DIR" \
           "$CC_TEARDOWN_RECORDS_DIR" "$CC_INBOX_GUARD_STATE_DIR" "$CC_MAILBOX_DIR"
  # stub cc-notify: log every call to <stub>.log, exit 0.
  export CC_NOTIFY_BIN="$BATS_TEST_TMPDIR/stub-notify"
  cat > "$CC_NOTIFY_BIN" <<'SH'
#!/bin/bash
echo "$@" >> "$0.log"
SH
  chmod +x "$CC_NOTIFY_BIN"
  echo "desk-pane-uuid-current" > "$CC_ROLES_DIR/desk"
}
notify_count() { [ -f "$CC_NOTIFY_BIN.log" ] && wc -l < "$CC_NOTIFY_BIN.log" | tr -d ' ' || echo 0; }

# ── nothing-new → abstain, no notify ───────────────────────────────────────────
@test "nothing new → abstain, zero notifies" {
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(notify_count)" -eq 0 ]
  grep -q '"disposition":"abstained"' "$CC_IDL"
}

# ── new alarm → exactly one notify, once (dedup on the second run) ──────────────
@test "a new alarm → one notify to the desk role; a second run (nothing new) abstains" {
  echo '{"kind":"alarm","detail":"never-stuck gate red"}' > "$CC_ANNOUNCE_ALARM_DIR/a1.json"
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(notify_count)" -eq 1 ]
  grep -q 'desk-pane-uuid-current' "$CC_NOTIFY_BIN.log"   # resolved the desk role at send-time
  grep -q '"disposition":"fired"' "$CC_IDL"
  # second run: the alarm is now .seen → nothing new → abstain, still exactly ONE notify total
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(notify_count)" -eq 1 ]
}

# ── a new page surfaces ────────────────────────────────────────────────────────
@test "a new page triggers one notify" {
  echo "1784370726" > "$CC_PAGES_DIR/$(uuidgen 2>/dev/null || echo p1).page"
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(notify_count)" -eq 1 ]
}

# ── completion-push: only push-failed records surface, not verified ────────────
@test "completion-push: a push-failed record surfaces; a verified one does not" {
  echo '{"kind":"completion-push","verdict":"verified","event":"ok"}'   > "$CC_COMPLETION_RECORDS_DIR/good.json"
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(notify_count)" -eq 0 ]                     # verified-only ⇒ nothing stuck ⇒ no notify
  grep -q '"disposition":"abstained"' "$CC_IDL"
  echo '{"kind":"completion-push","verdict":"push-failed(cc-announce rc=5)","event":"terminal"}' > "$CC_COMPLETION_RECORDS_DIR/bad.json"
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(notify_count)" -eq 1 ]                     # the push-failed one wakes the desk
}

# ── fired class-B default → a backlog item is appended (never acted inline) ────
@test "a past-deadline class-B default fires → cc-backlog item appended, packet expired-actioned" {
  id=$(bash "$CC_DECIDE_BIN" open --class B --what "which account to continue on" \
        --default "continue cross-account on next2" --deadline "2000-01-01T00:00:00Z")
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  # the sweep is the default-ACTUATOR: it appends a backlog item rather than acting inline
  run bash "$CC_BACKLOG_BIN" list --open
  echo "$output" | grep -q "continue cross-account on next2"
  # and the packet transitioned (expire-sweep) — never deleted
  [ "$(jq -r '.status' "$CC_DECISIONS_DIR/$id.json")" = "expired-actioned" ]
  grep -q '"disposition":"fired"' "$CC_IDL"
}

# ── an open decision packet is surfaced in the summary (once) ──────────────────
@test "an open (future-deadline) class-B packet surfaces once, then is deduped" {
  bash "$CC_DECIDE_BIN" open --class B --what "a pending fork" \
    --default "park + continue" --deadline "2099-01-01T00:00:00Z" >/dev/null
  run bash "$SWEEP"
  [ "$(notify_count)" -eq 1 ]
  run bash "$SWEEP"
  [ "$(notify_count)" -eq 1 ]      # deduped on the second run
}

# ── missing desk role → do NOT mark seen (retry next sweep), fail loud in IDL ──
@test "no desk role → notify is not delivered and the record is NOT marked seen (retry)" {
  rm -f "$CC_ROLES_DIR/desk"
  echo '{"kind":"alarm"}' > "$CC_ANNOUNCE_ALARM_DIR/a1.json"
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(notify_count)" -eq 0 ]                       # nothing delivered
  grep -q 'no-desk-role\|undelivered' "$CC_IDL"     # loud, not silent
  # restore role: the SAME alarm must still surface (it was never marked seen)
  echo "desk-pane-uuid-current" > "$CC_ROLES_DIR/desk"
  run bash "$SWEEP"
  [ "$(notify_count)" -eq 1 ]
}

# ── launchd/supervisor-callable: runs standalone, exit 0, no args ──────────────
@test "runs standalone with no args and exits 0" {
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
}

# ══ age-reap of the six write-only event dirs (audit 03 §1b/§1c fix 5) ═════════════════════════
# L2: each case asserts the failure-DISTINCT pair — OLD reaped AND YOUNG kept. Asserting only the
# reap would stay green if the horizon collapsed to 0 and ate live records; asserting only the keep
# would stay green if the reaper never ran at all.

mk_old()   { mkdir -p "$(dirname "$1")"; printf 'x\n' > "$1"; touch -t "$(date -v-9d +%Y%m%d%H%M)" "$1"; }
mk_young() { mkdir -p "$(dirname "$1")"; printf 'x\n' > "$1"; }

@test "all six event dirs: records past the horizon are reaped, young ones kept" {
  mk_old   "$CC_PAGES_DIR/old.page";                 mk_young "$CC_PAGES_DIR/new.page"
  mk_old   "$CC_COMMS_ALARM_DIR/old.json";           mk_young "$CC_COMMS_ALARM_DIR/new.json"
  mk_old   "$CC_PUSH_RECORDS_DIR/old.json";          mk_young "$CC_PUSH_RECORDS_DIR/new.json"
  mk_old   "$CC_COMPLETION_RECORDS_DIR/old.json";    mk_young "$CC_COMPLETION_RECORDS_DIR/new.json"
  mk_old   "$CC_TEARDOWN_RECORDS_DIR/old.json";      mk_young "$CC_TEARDOWN_RECORDS_DIR/new.json"

  run bash "$SWEEP"
  [ "$status" -eq 0 ]

  [ ! -f "$CC_PAGES_DIR/old.page" ];              [ -f "$CC_PAGES_DIR/new.page" ]
  [ ! -f "$CC_COMMS_ALARM_DIR/old.json" ];        [ -f "$CC_COMMS_ALARM_DIR/new.json" ]
  [ ! -f "$CC_PUSH_RECORDS_DIR/old.json" ];       [ -f "$CC_PUSH_RECORDS_DIR/new.json" ]
  [ ! -f "$CC_COMPLETION_RECORDS_DIR/old.json" ]; [ -f "$CC_COMPLETION_RECORDS_DIR/new.json" ]
  [ ! -f "$CC_TEARDOWN_RECORDS_DIR/old.json" ];   [ -f "$CC_TEARDOWN_RECORDS_DIR/new.json" ]
}

# ── the durable ledgers are NEVER age-reaped (they are the exclusion, not an oversight) ────────
@test "decisions/ is exempt: an old decision packet survives the reap" {
  mk_old "$CC_DECISIONS_DIR/old.json"
  printf '{"status":"open"}\n' > "$CC_DECISIONS_DIR/old.json"
  touch -t "$(date -v-30d +%Y%m%d%H%M)" "$CC_DECISIONS_DIR/old.json"
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ -f "$CC_DECISIONS_DIR/old.json" ]
}

# ── inbox-guard is DAMPING state: age alone must not clear it (that re-fires the page it damps) ─
@test "an old .escalated marker whose mailbox still exists is KEPT (damping preserved)" {
  mk_old "$CC_INBOX_GUARD_STATE_DIR/PANE-A.escalated"
  printf 'msg\n' > "$CC_MAILBOX_DIR/PANE-A.md"
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ -f "$CC_INBOX_GUARD_STATE_DIR/PANE-A.escalated" ]
}

@test "an old .escalated marker whose mailbox is gone IS reaped (it can damp nothing)" {
  mk_old "$CC_INBOX_GUARD_STATE_DIR/PANE-B.escalated"
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ ! -f "$CC_INBOX_GUARD_STATE_DIR/PANE-B.escalated" ]
}

@test "a YOUNG .escalated marker with no mailbox is still kept (horizon, not lifecycle)" {
  mk_young "$CC_INBOX_GUARD_STATE_DIR/PANE-C.escalated"
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ -f "$CC_INBOX_GUARD_STATE_DIR/PANE-C.escalated" ]
}

# ── the horizon must outlive the reaper-horizon-lint floor (600 s sweep × 10 = 6,000 s) ────────
@test "the event horizon is 7 days — three orders of magnitude above the lint floor" {
  run bash -c "grep -c 'CC_EVENT_TTL_DAYS:-7' '$SWEEP'"
  [ "$status" -eq 0 ]
  run bash "$REPO/scripts/reaper-horizon-lint.sh"
  [ "$status" -eq 0 ]
}

# ══ fired-default triage: subject project + the no-change carve-out (item f32588a73993) ═════════
# The sweep is the class-B default ACTUATOR. Two things it could not previously know, both now
# declared by the PRODUCER on the packet and reported on the fired line:
#   (a) WHICH project the decision is about — this sweep runs from launchd with cwd=/;
#   (b) whether firing the default CHANGES anything — a no-change default ("hold (no change
#       without ruling)", "disclose-only", "park and continue") actuates NOTHING, yet an OPEN
#       backlog item is exactly cc-dispatch's fire predicate, so one could spawn a peer session
#       whose entire assignment was to change nothing. Three such rows are in the live ledger.
# Neither is ever recovered by reading the default's WORDING — that shape-classifier is the thing
# that must not be built (memory: fixture-vs-real-classifier-needs-a-producer).

@test "a fired NO-CHANGE default is surfaced but NEVER queued as a dispatch candidate" {
  id=$(bash "$CC_DECIDE_BIN" open --class B --what "rearchitect the program?" \
        --default "hold (no change without ruling)" --deadline "2000-01-01T00:00:00Z" \
        --default-effect no-change)
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  # the packet DID fire (the trail is intact — this is not a no-op path)
  [ "$(jq -r '.status' "$CC_DECISIONS_DIR/$id.json")" = "expired-actioned" ]
  # ...and the desk was still woken: surfaced, not swallowed
  [ "$(notify_count)" -eq 1 ]
  grep -q '"fired_nochange":1' "$CC_IDL"
  # ...but NOTHING dispatchable was queued. `list --open` is cc-dispatch's own predicate.
  run bash "$CC_BACKLOG_BIN" list --open
  ! echo "$output" | grep -q "hold (no change without ruling)" || false
  # belt: not merely absent from the OPEN view — never written to the ledger at all
  ! grep -q "hold (no change without ruling)" "$CC_BACKLOG_FILE" 2>/dev/null || false
}

@test "POSITIVE CONTROL: a fired CHANGE default in the same run IS still queued" {
  # Without this, a carve-out that suppressed EVERY fired default would pass the test above.
  bash "$CC_DECIDE_BIN" open --class B --what "no-change one" --default "hold it" \
    --deadline "2000-01-01T00:00:00Z" --default-effect no-change >/dev/null
  bash "$CC_DECIDE_BIN" open --class B --what "change one" --default "land the lossless fix" \
    --deadline "2000-01-01T00:00:00Z" --default-effect change >/dev/null
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  run bash "$CC_BACKLOG_BIN" list --open
  echo "$output" | grep -q "land the lossless fix"
  ! echo "$output" | grep -q "hold it" || false
}

@test "an UNANNOTATED fired default is still queued (fail-open: no silent drop)" {
  # Every legacy producer omits --default-effect. Absent must mean "change", or landing this fix
  # would silently stop draining the class-B queue.
  bash "$CC_DECIDE_BIN" open --class B --what "legacy shape" --default "carry this out" \
    --deadline "2000-01-01T00:00:00Z" >/dev/null
  run bash "$SWEEP"
  run bash "$CC_BACKLOG_BIN" list --open
  echo "$output" | grep -q "carry this out"
}

@test "the item is filed against the packet's DECLARED subject project" {
  bash "$CC_DECIDE_BIN" open --class B --what "whose project?" --default "do the thing" \
    --deadline "2000-01-01T00:00:00Z" --project doc_classifier --default-effect change >/dev/null
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  run jq -r 'select(.source=="autonomy-sweep") | .project' "$CC_BACKLOG_FILE"
  [ "$output" = "doc_classifier" ]
}

@test "no declared project → the host-project fallback, and the default still lands in the title" {
  # The consumer-side half of the TSV collapse control: an unpadded emitter would put the EFFECT in
  # the project slot (filing the item against project "change") and the DEFAULT in the effect slot
  # (so `no-change` would never match and the title would go empty).
  bash "$CC_DECIDE_BIN" open --class B --what "no project" --default "carry this out" \
    --deadline "2000-01-01T00:00:00Z" >/dev/null
  CC_SWEEP_PROJECT=host-proj run bash "$SWEEP"
  [ "$status" -eq 0 ]
  run jq -r 'select(.source=="autonomy-sweep") | .project + "|" + .title' "$CC_BACKLOG_FILE"
  [ "$output" = "host-proj|class-B default fired: carry this out" ]
}

@test "the summary distinguishes queued fires from no-change fires" {
  bash "$CC_DECIDE_BIN" open --class B --what "nc" --default "hold it" \
    --deadline "2000-01-01T00:00:00Z" --default-effect no-change >/dev/null
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  # reporting only the total would read as "1 item queued" on a sweep that queued none
  grep -q "no-change: surfaced, NOT dispatched" "$CC_NOTIFY_BIN.log"
  ! grep -q "fired→backlog" "$CC_NOTIFY_BIN.log" || false
}
