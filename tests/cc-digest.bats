#!/usr/bin/env bats
# cc-digest — the batched morning-review surface (P15 §3.4, T-P15-6). ONE markdown digest of
# {what landed · open backlog · decisions (open + class-B defaults fired last 24h) · page stats ·
# the D9 inert-check alarms} to stdout + ~/.claude/autonomy/digests/<date>.md. Never an interrupt.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DIGEST="$REPO/bin/cc-digest"
  export CC_LAND_LOG="$BATS_TEST_TMPDIR/land.log"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
  export CC_PAGES_DIR="$BATS_TEST_TMPDIR/pages"
  export CC_SWEEP_SEEN_DIR="$BATS_TEST_TMPDIR/seen"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_DIGESTS_DIR="$BATS_TEST_TMPDIR/digests"
  export CC_DIGEST_DATE="2026-07-18"
  export CC_BACKLOG_BIN="$REPO/bin/cc-backlog"
  export CC_DECIDE_BIN="$REPO/bin/cc-decide"
  mkdir -p "$CC_DECISIONS_DIR" "$CC_PAGES_DIR" "$CC_SWEEP_SEEN_DIR"
}
# stub push-send / cc-announce: log argv (so we can assert the summary counts) + exit a baked rc.
mkpush() { local p="$BATS_TEST_TMPDIR/push-send.sh"; cat > "$p" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$BATS_TEST_TMPDIR/push-args"
exit $1
EOF
chmod +x "$p"; echo "$p"; }
mkann() { local p="$BATS_TEST_TMPDIR/cc-announce"; cat > "$p" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$BATS_TEST_TMPDIR/ann-args"
exit $1
EOF
chmod +x "$p"; echo "$p"; }

@test "emits every section header even with empty inputs" {
  run bash "$DIGEST"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "# Desk digest"
  echo "$output" | grep -q "## Landed"
  echo "$output" | grep -q "## Backlog"
  echo "$output" | grep -q "## Decisions"
  echo "$output" | grep -q "## Pages"
  echo "$output" | grep -qi "## Inert-check alarms"
}

@test "writes the digest to CC_DIGESTS_DIR/<date>.md" {
  run bash "$DIGEST"
  [ "$status" -eq 0 ]
  [ -f "$CC_DIGESTS_DIR/2026-07-18.md" ]
  grep -q "# Desk digest" "$CC_DIGESTS_DIR/2026-07-18.md"
}

@test "Landed section shows the land.log tail" {
  printf '{"landed":"abc1234","repo":"reso"}\n{"landed":"def5678","repo":"infra"}\n' > "$CC_LAND_LOG"
  run bash "$DIGEST"
  echo "$output" | grep -q "abc1234"
  echo "$output" | grep -q "def5678"
}

@test "Backlog section lists open items" {
  bash "$CC_BACKLOG_BIN" add --project /r --title "wire the reset poller" --source p8 >/dev/null
  run bash "$DIGEST"
  echo "$output" | grep -q "wire the reset poller"
}

@test "Decisions: open packets and class-B defaults fired in the last 24h both appear" {
  bash "$CC_DECIDE_BIN" open --class B --what "an open pending fork" \
    --default "park + continue" --deadline "2099-01-01T00:00:00Z" >/dev/null
  # a class-B whose default already fired (expired-actioned) with a fresh resolved ts
  idf=$(bash "$CC_DECIDE_BIN" open --class B --what "a fired fork" \
        --default "continue cross-account" --deadline "2000-01-01T00:00:00Z")
  CC_NOW="2000-01-02T00:00:00Z" bash "$CC_DECIDE_BIN" expire-sweep >/dev/null
  # re-stamp resolved to now so the 24h window includes it (expire-sweep used CC_NOW in the past)
  tmp=$(mktemp); jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '.resolved=$ts' \
    "$CC_DECISIONS_DIR/$idf.json" > "$tmp" && mv "$tmp" "$CC_DECISIONS_DIR/$idf.json"
  run bash "$DIGEST"
  echo "$output" | grep -q "an open pending fork"
  echo "$output" | grep -q "a fired fork"
}

@test "Pages section reports total + surfaced counts" {
  echo 1784370726 > "$CC_PAGES_DIR/p1.page"
  echo 1784370727 > "$CC_PAGES_DIR/p2.page"
  # mark p1 surfaced by writing its .seen marker the way autonomy-sweep keys it
  key=$(printf '%s' "$CC_PAGES_DIR/p1.page" | shasum -a 256 | cut -c1-32)
  : > "$CC_SWEEP_SEEN_DIR/$key"
  run bash "$DIGEST"
  echo "$output" | grep -qiE "pages?.*2|2.*pages?"
}

# ── D9 inert-check monitor (RED-proven) ────────────────────────────────────────
# Every seed carries .ts, as every real IDL record does — the recency horizon reads it.
@test "D9: a hook 12/12 BLIND-abstained (100%, N>=10) raises an ALARM line" {
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  for i in $(seq 1 12); do
    printf '{"hook":"stale-guard","disposition":"abstained","reason":"no-assistant-text","ts":"%s"}\n' "$now" >> "$CC_IDL"
  done
  run bash "$DIGEST"
  echo "$output" | grep -qi "ALARM"
  echo "$output" | grep -q "stale-guard"
  echo "$output" | grep -q "12/12"
}

@test "D9: a hook that sometimes fires does NOT alarm" {
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  for i in $(seq 1 10); do printf '{"hook":"healthy-guard","disposition":"abstained","ts":"%s"}\n' "$now" >> "$CC_IDL"; done
  printf '{"hook":"healthy-guard","disposition":"fired","ts":"%s"}\n' "$now" >> "$CC_IDL"
  printf '{"hook":"healthy-guard","disposition":"fired","ts":"%s"}\n' "$now" >> "$CC_IDL"
  run bash "$DIGEST"
  ! echo "$output" | grep -q "healthy-guard"
}

@test "D9: a hook with fewer than 10 evals does NOT alarm (below the window)" {
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  for i in $(seq 1 5); do printf '{"hook":"quiet-guard","disposition":"abstained","ts":"%s"}\n' "$now" >> "$CC_IDL"; done
  run bash "$DIGEST"
  ! echo "$output" | grep -q "quiet-guard"
}

@test "D9: a healthy 'no alarms' line appears when nothing is inert" {
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"hook":"g","disposition":"fired","ts":"%s"}\n' "$now" >> "$CC_IDL"
  run bash "$DIGEST"
  echo "$output" | grep -qiE "no inert|none|no alarm|healthy"
}

# The bug this fixes (e7d326caa6a7): a record-flood night (page/sweep churn) crowds a naive global
# tail so a rarely-firing HEALTHY hook that DID fire that night is flagged inert. The fire is buried
# FIRST, then 6000 flood records (> the 5000 tail) push it out of a global tail, leaving only
# abstentions in view. The fix greps to hook-eval records first and exonerates any fire in-horizon.
@test "D9: record-flood does NOT false-flag a rare hook that fired in-horizon (regression: e7d326caa6a7)" {
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  fired="$(date -u -v-2H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '-2 hours' +%Y-%m-%dT%H:%M:%SZ)"
  {   # one open, not 6000 — grouped redirection keeps the gate fast
    printf '{"hook":"rare-guard","disposition":"fired","ts":"%s"}\n' "$fired"
    for i in $(seq 1 6000); do printf '{"actor":"pager","kind":"page","ts":"%s"}\n' "$now"; done
    for i in $(seq 1 12); do printf '{"hook":"rare-guard","disposition":"abstained","reason":"no-transcript-path","ts":"%s"}\n' "$now"; done
    for i in $(seq 1 12); do printf '{"hook":"dead-guard","disposition":"abstained","reason":"no-transcript-path","ts":"%s"}\n' "$now"; done
  } >> "$CC_IDL"
  run bash "$DIGEST"
  [ "$status" -eq 0 ]
  # the false positive being fixed: rare-guard fired in-horizon → NOT flagged
  ! echo "$output" | grep -q "rare-guard"
  # the check still works despite the flood: dead-guard never fired → still flagged
  echo "$output" | grep -q "dead-guard"
}

# reason-aware (blind-check law §3i, 117bf1aea7b7): a correctly-quiet CONDITIONAL hook abstains 100%
# for DORMANT reasons (condition-not-met: no-tell / not-armed) — it still sees reality, so it is NOT
# inert and must NOT alarm. Without reason discrimination this healthy advisory paged every night.
@test "D9: a 100%-DORMANT hook (condition-not-met reasons) does NOT alarm (reason-aware)" {
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  for i in $(seq 1 8); do printf '{"hook":"quiet-cond","disposition":"abstained","reason":"no-tell","ts":"%s"}\n' "$now" >> "$CC_IDL"; done
  for i in $(seq 1 4); do printf '{"hook":"quiet-cond","disposition":"abstained","reason":"not-armed","ts":"%s"}\n' "$now" >> "$CC_IDL"; done
  run bash "$DIGEST"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "ALARM"
  ! echo "$output" | grep -q "quiet-cond"
}

# ── push wiring (T-P15-6 delivery) ─────────────────────────────────────────────────────────────
@test "push: delivers a quiet phone summary + a desk wake carrying the section counts (exit 0)" {
  printf '{"landed":"abc1234"}\n{"landed":"def5678"}\n' > "$CC_LAND_LOG"
  bash "$CC_BACKLOG_BIN" add --project /r --title "open one" --source x >/dev/null
  echo 1784370726 > "$CC_PAGES_DIR/p1.page"
  CC_PUSH_SEND_BIN="$(mkpush 0)" CC_ANNOUNCE_BIN="$(mkann 0)" run bash "$DIGEST" push
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'phone push delivered'
  echo "$output" | grep -q 'desk-role wake delivered'
  grep -q '2 landed' "$BATS_TEST_TMPDIR/push-args"
  grep -q '1 backlog' "$BATS_TEST_TMPDIR/push-args"
  grep -q '1 page(s) pending' "$BATS_TEST_TMPDIR/push-args"
  grep -q 'priority -1' "$BATS_TEST_TMPDIR/push-args"   # quiet / never-an-interrupt
}

@test "push: the summary's inert count is DERIVED from the digest's ALARM lines (single source of truth)" {
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  for i in $(seq 1 12); do printf '{"hook":"stale-guard","disposition":"abstained","reason":"no-assistant-text","ts":"%s"}\n' "$now" >> "$CC_IDL"; done
  CC_PUSH_SEND_BIN="$(mkpush 0)" CC_ANNOUNCE_BIN="$(mkann 0)" run bash "$DIGEST" push
  [ "$status" -eq 0 ]
  n="$(echo "$output" | grep -c '^ALARM:')"; [ "$n" -eq 1 ]   # emit produced exactly one ALARM…
  grep -q '1 inert alarm(s)' "$BATS_TEST_TMPDIR/push-args"     # …and the summary reports the SAME count
}

@test "push: phone INERT (push-send exit 3) is a NOTE, not a failure → exit 0" {
  CC_PUSH_SEND_BIN="$(mkpush 3)" CC_ANNOUNCE_BIN="$(mkann 0)" run bash "$DIGEST" push
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'INERT'
}

@test "push: desk-role wake FAILS → exit 5 (never silent)" {
  CC_PUSH_SEND_BIN="$(mkpush 0)" CC_ANNOUNCE_BIN="$(mkann 5)" run bash "$DIGEST" push
  [ "$status" -eq 5 ]
  echo "$output" | grep -q 'desk-role wake NOT verified'
}

@test "push: phone send FAILS (creds present) → exit 5 (never silent)" {
  CC_PUSH_SEND_BIN="$(mkpush 5)" CC_ANNOUNCE_BIN="$(mkann 0)" run bash "$DIGEST" push
  [ "$status" -eq 5 ]
  echo "$output" | grep -q 'phone push FAILED'
}

@test "push --no-phone skips the phone leg (a failing phone leg can't fail the run)" {
  CC_PUSH_SEND_BIN="$(mkpush 5)" CC_ANNOUNCE_BIN="$(mkann 0)" run bash "$DIGEST" push --no-phone
  [ "$status" -eq 0 ]
  [ ! -f "$BATS_TEST_TMPDIR/push-args" ]
}

@test "push --no-desk skips the desk leg" {
  CC_PUSH_SEND_BIN="$(mkpush 0)" CC_ANNOUNCE_BIN="$(mkann 5)" run bash "$DIGEST" push --no-desk
  [ "$status" -eq 0 ]
  [ ! -f "$BATS_TEST_TMPDIR/ann-args" ]
}

@test "bare cc-digest (no subcommand) does NOT deliver — default path unchanged (exit 0)" {
  CC_PUSH_SEND_BIN="$(mkpush 5)" CC_ANNOUNCE_BIN="$(mkann 5)" run bash "$DIGEST"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'phone push'
  ! echo "$output" | grep -q 'desk-role wake'
  [ ! -f "$BATS_TEST_TMPDIR/push-args" ]
}

@test "unknown subcommand → usage error (exit 2)" {
  run bash "$DIGEST" bogus
  [ "$status" -eq 2 ]
}
