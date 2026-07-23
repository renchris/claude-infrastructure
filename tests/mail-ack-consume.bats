#!/usr/bin/env bats
# mail-ack-consume — proves the ack-on-consume split (drain advances .seen only; .acked is promoted at
# the Stop fold), the dup-not-loss guarantee across a drain→death→succession, and the reaper/watchdog
# deny-append mutex. Exercises the LITERAL lib functions + the real team-orphan-reaper.sh (no copies).
#
# Harness rules (from tests/cc-notify.bats, learned from real escapes):
#   1. Assert the SPECIFIC value, never a loose glob a degraded result also matches.
#   2. Fixture shapes are the producers' LITERAL files (inbox JSON envelope shape; cursor int files).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  REAPER="$REPO/scripts/team-orphan-reaper.sh"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"
  MBOX_DIR="$CC_MAILBOX_DIR"
  mkdir -p "$MBOX_DIR"
  # shellcheck source=../hooks/lib/mailbox-pending.sh
  source "$REPO/hooks/lib/mailbox-pending.sh"
}

# ── (a) mailbox_take ack_now=0 advances .seen only ──────────────────────────────────────────────────
@test "(a) mailbox_take ack_now=0 advances .seen only — .acked is left untouched" {
  local U="AAAAAAAA-0000-0000-0000-000000000001"
  printf 'line one\nline two\n' > "$MBOX_DIR/$U.md"
  run mailbox_take "$U" 0
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'line one'
  printf '%s' "$output" | grep -q 'line two'
  [ "$(cat "$MBOX_DIR/$U.seen")" -eq 2 ]     # emitted cursor advanced to EOF
  [ ! -f "$MBOX_DIR/$U.acked" ]              # consumed cursor NOT written (deferred to the Stop fold)
  [ "$(mailbox_unacked_count "$U")" -eq 2 ]  # the guard still sees 2 unconsumed → no premature clear
}

# ── (b) mailbox_promote_acked folds .acked = .seen ──────────────────────────────────────────────────
@test "(b) mailbox_promote_acked folds .acked up to .seen (the Stop-fold lag-ack)" {
  local U="AAAAAAAA-0000-0000-0000-000000000002"
  printf 'a\nb\nc\n' > "$MBOX_DIR/$U.md"
  mailbox_take "$U" 0 >/dev/null            # seen → 3; acked absent (== 0)
  [ "$(cat "$MBOX_DIR/$U.seen")" -eq 3 ]
  [ "$(mailbox_acked "$U")" -eq 0 ]
  mailbox_promote_acked "$U"
  [ "$(cat "$MBOX_DIR/$U.acked")" -eq 3 ]    # folded up to the emitted cursor
  [ "$(mailbox_unacked_count "$U")" -eq 0 ]  # guard clears only AFTER a turn provably consumed the mail
}

# ── (c) drain → death (no Stop fold) → succession re-delivers (dup, not loss) ────────────────────────
@test "(c) a drain then death before the fold → the successor RE-DELIVERS the unconsumed mail (dup, not loss)" {
  local A="AAAAAAAA-0000-0000-0000-00000000000a" B="BBBBBBBB-0000-0000-0000-00000000000b"
  printf 'urgent page\n' > "$MBOX_DIR/$A.md"
  # A drains at a boundary exactly as the hook now does (ack_now=0): .seen advances, .acked does NOT.
  mailbox_take "$A" 0 >/dev/null
  [ "$(cat "$MBOX_DIR/$A.seen")" -eq 1 ]
  [ "$(mailbox_acked "$A")" -eq 0 ]          # A DIES here — no Stop-fold promote ran → still unconsumed
  # succession: A.forward → B; B adopts A's UNCONSUMED (acked, EOF] tail. Because ack was deferred, that
  # window is non-empty, so the page A was shown but never provably took is re-delivered (a visible dup).
  printf '%s\n' "$B" > "$MBOX_DIR/$A.forward"
  run mailbox_migrate "$A" "$B"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]                        # one line migrated (re-delivered) — NOT swallowed
  grep -q 'urgent page' "$MBOX_DIR/$B.md"    # the unconsumed page reaches the successor
}

@test "(c-discriminator) had the drain ACKED (ack_now=1), the same death would LOSE the mail" {
  # This is the failure the ack-on-consume split removes: acking at drain marks .acked=EOF, so the
  # succession window (acked, EOF] is empty and the dying session's shown-but-unconsumed mail vanishes.
  local A="AAAAAAAA-0000-0000-0000-00000000000c" B="BBBBBBBB-0000-0000-0000-00000000000d"
  printf 'urgent page\n' > "$MBOX_DIR/$A.md"
  mailbox_take "$A" 1 >/dev/null             # OLD behavior: ack at drain → .acked = EOF
  [ "$(mailbox_acked "$A")" -eq 1 ]
  printf '%s\n' "$B" > "$MBOX_DIR/$A.forward"
  run mailbox_migrate "$A" "$B"
  [ "$status" -eq 1 ]                        # nothing to migrate → the page is LOST (proves why we defer)
  [ "$output" -eq 0 ]
  [ ! -f "$MBOX_DIR/$B.md" ]
}

# ── (d) reaper/watchdog deny-append mutex — two concurrent appends BOTH land ─────────────────────────
@test "(d) reaper mutex: two concurrent deny-appends to one inbox BOTH land (no last-mv-wins loss)" {
  # Fake team fixture under a temp HOME so team-orphan-reaper's main() reaches scan_stale_permissions
  # and runs its LITERAL inline mutex against the real inbox JSON shape.
  local FAKEHOME="$BATS_TEST_TMPDIR/home"
  local team="$FAKEHOME/.claude/teams/tm-mutex"
  mkdir -p "$team/inboxes" "$FAKEHOME/.claude/watchdog" "$FAKEHOME/.claude/logs"
  # a LIVE lead pid so the team is scanned (not archived)
  sleep 30 & local livepid=$!
  echo "$livepid" > "$FAKEHOME/.claude/watchdog/lead-sid.pid"
  printf '{"leadSessionId":"lead-sid"}' > "$team/config.json"
  # inbox with TWO stale permission_requests (old timestamp) → each reaper run appends 2 deny envelopes
  jq -nc --arg ts "2020-01-01T00:00:00.000Z" '[
    {from:"m1", text:"{\"type\":\"permission_request\",\"request_id\":\"r1\"}", summary:"req1", timestamp:$ts, read:false},
    {from:"m1", text:"{\"type\":\"permission_request\",\"request_id\":\"r2\"}", summary:"req2", timestamp:$ts, read:false}
  ]' > "$team/inboxes/m1.json"

  # two concurrent reaper subshells against the SAME inbox
  HOME="$FAKEHOME" bash "$REAPER" & local r1=$!
  HOME="$FAKEHOME" bash "$REAPER" & local r2=$!
  wait "$r1"; wait "$r2"
  kill "$livepid" 2>/dev/null || true

  # both serialized appends survive → 4 deny envelopes (2 per run). last-mv-wins would drop one run's
  # pair, leaving 2. the final array must ALSO still be valid JSON (a torn mv would corrupt it).
  jq -e . "$team/inboxes/m1.json" >/dev/null           # not corrupted by a concurrent mv
  local denies
  denies=$(jq '[.[] | select(.from=="reaper")] | length' "$team/inboxes/m1.json")
  [ "$denies" -eq 4 ]
  # and both request_ids are represented in the reaper denies (both envelopes present)
  jq -e '[.[] | select(.from=="reaper") | (.text | fromjson).request_id] | (index("r1") and index("r2"))' \
    "$team/inboxes/m1.json" >/dev/null
}
