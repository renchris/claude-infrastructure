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
@test "D9: a hook that abstained 12/12 (100%, N>=10) raises an ALARM line" {
  for i in $(seq 1 12); do
    printf '{"hook":"stale-guard","disposition":"abstained","reason":"no-tell"}\n' >> "$CC_IDL"
  done
  run bash "$DIGEST"
  echo "$output" | grep -qi "ALARM"
  echo "$output" | grep -q "stale-guard"
  echo "$output" | grep -q "12/12"
}

@test "D9: a hook that sometimes fires does NOT alarm" {
  for i in $(seq 1 10); do printf '{"hook":"healthy-guard","disposition":"abstained"}\n' >> "$CC_IDL"; done
  printf '{"hook":"healthy-guard","disposition":"fired"}\n' >> "$CC_IDL"
  printf '{"hook":"healthy-guard","disposition":"fired"}\n' >> "$CC_IDL"
  run bash "$DIGEST"
  ! echo "$output" | grep -q "healthy-guard"
}

@test "D9: a hook with fewer than 10 evals does NOT alarm (below the window)" {
  for i in $(seq 1 5); do printf '{"hook":"quiet-guard","disposition":"abstained"}\n' >> "$CC_IDL"; done
  run bash "$DIGEST"
  ! echo "$output" | grep -q "quiet-guard"
}

@test "D9: a healthy 'no alarms' line appears when nothing is inert" {
  printf '{"hook":"g","disposition":"fired"}\n' >> "$CC_IDL"
  run bash "$DIGEST"
  echo "$output" | grep -qiE "no inert|none|no alarm|healthy"
}
