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
  mkdir -p "$CC_PAGES_DIR" "$CC_ANNOUNCE_ALARM_DIR" "$CC_COMPLETION_RECORDS_DIR" \
           "$CC_DECISIONS_DIR" "$CC_ROLES_DIR"
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
