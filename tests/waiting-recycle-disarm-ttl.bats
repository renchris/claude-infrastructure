#!/usr/bin/env bats
# waiting-recycle.sh — the DISARM opt-out's time axis (backlog ac914e8982b8).
#
# THE BUG: `clear` writes a durable disarm marker; every reader tested it with a bare `[ -f ]`. No
# age term existed anywhere in the file, and no reader consumed the ISO timestamp `clear` has always
# written into the marker. Measured pre-fix on a fixture: an opt-out backdated 8 DAYS and one written
# 1 SECOND ago produced BYTE-IDENTICAL IDL rows (`"reason":"disarmed"`), the same bare `status` line,
# and both fully suppressed a desk sitting at 90% fill. An 8-day-old opt-out was therefore
# indistinguishable from a hook that is simply broken.
#
# DISCRIMINATOR PAIRS (each KEEP half below is paired with a REMOVE half proven to RED — the REMOVE
# half is the REAL pre-fix artifact from git, not a hand-written mutant: run this same file against a
# tree holding `git show <pre-fix>:hooks/waiting-recycle.sh`):
#   1. TTL      — an EXPIRED opt-out must NOT suppress (and must say so).   REMOVE ⇒ tests 1,2 red.
#   2. WIRE     — age must be visible ON THE WIRE: a stale opt-out and a
#                 fresh one must not be the same record.                    REMOVE ⇒ tests 4,5 red.
# Tests 3 and 6 are the anti-over-fire controls: the TTL must not have deleted the opt-out feature,
# and it must read its own knob rather than a hardcoded number.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_FIRE_CAPACITY_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/waiting-recycle.sh"
  # TEST SEAM: every path the subject touches is redirected here. The operator's LIVE state dir
  # ($CLAUDE_CONFIG_DIR/state/waiting-recycle) is never read and never written by this suite.
  export CC_WR_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CC_WR_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_TELEMETRY_DIR="$BATS_TEST_TMPDIR/tel"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"
  export CC_WR_COORD_DIR="$BATS_TEST_TMPDIR/coord"; export CC_WR_UUID="DESK-UUID-TTL"
  export CC_WR_T_IDLE=55 CC_WR_T_BUSY=75 CC_WR_MAX=3 CC_WR_COOLDOWN_S=600 CC_WR_AGE_MAX=180
  export CC_WR_T_NUDGE=101
  mkdir -p "$CC_TELEMETRY_DIR" "$CC_WR_STATE_DIR" "$CC_WR_COORD_DIR/cc-roles" "$CLAUDE_CONFIG_DIR"
  export CC_WR_NOTIFY="$BATS_TEST_TMPDIR/notify-noop.sh"
  printf '#!/bin/bash\nexit 0\n' > "$CC_WR_NOTIFY"; chmod +x "$CC_WR_NOTIFY"
  DESK="$BATS_TEST_TMPDIR/desk"; mkdir -p "$DESK"
  git -C "$BATS_TEST_TMPDIR/desk" init -q
  echo seed > "$DESK/f.txt"; git -C "$BATS_TEST_TMPDIR/desk" add -A
  git -C "$BATS_TEST_TMPDIR/desk" -c user.email=t@t -c user.name=t commit -qm init
}

mk_tel() { printf '{"session_id":"%s","ts":%s,"used_pct":%s,"cwd":"%s"}' "$1" "$(date +%s)" "$2" "$DESK" > "$CC_TELEMETRY_DIR/$1.json"; }
mk_tx()  { local p="$BATS_TEST_TMPDIR/tx-$1.jsonl"; jq -nc '{type:"assistant",message:{content:[{type:"text",text:"next3 still running; waiting on the rest."}]}}' > "$p"; printf '%s' "$p"; }
drive()  { printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","tool_input":{"command":"echo poll"}}' "$1" "$2" "$DESK" | bash "$HOOK"; }

# The disarm marker's path is taken from the SUBJECT's own key derivation (run `clear`, read what it
# wrote) — never re-derived here. A test that re-implements the key under test can agree with a
# broken subject.
disarm_marker() { ( cd "$DESK" && bash "$HOOK" clear >/dev/null ); ls "$CC_WR_STATE_DIR"/disarm-* ; }
# Backdate a marker's mtime by $2 seconds (BSD `date -r`, then GNU `date -d @`), and its recorded ISO
# timestamp with it, so content and mtime stay consistent the way `clear` writes them.
backdate() {
  local f="$1" at; at=$(( $(date +%s) - $2 ))
  date -u -r "$at" +%Y-%m-%dT%H:%M:%SZ > "$f" 2>/dev/null || date -u -d "@$at" +%Y-%m-%dT%H:%M:%SZ > "$f"
  touch -t "$(date -r "$at" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$at" +%Y%m%d%H%M.%S)" "$f"
}
last_reason() { jq -r 'select(.disposition=="abstained")|.reason' "$CC_WR_IDL" | tail -1; }

# ── PAIR 1 — TTL: an opt-out is a decision with a shelf life ───────────────────────────────────────
@test "TTL: an opt-out older than the TTL no longer suppresses — the hook proceeds past the disarm gate" {
  local m; m="$(disarm_marker)"
  ( cd "$DESK" && bash "$HOOK" arm >/dev/null )     # armed AND (re-)disarmed: expiry must reach the armed path
  backdate "$m" $(( 8 * 86400 ))
  mk_tel s1 90
  run drive s1 "$(mk_tx 1)"
  [ "$status" -eq 0 ]
  # POSITIVE assertion (never "the reason merely isn't disarmed" — an earlier guard could satisfy that
  # trivially): the subject must record the expiry as its own event.
  jq -e 'select(.disposition=="gc" and .reason=="disarm-expired")' "$CC_WR_IDL"
  jq -e 'select(.reason=="disarm-expired" and .disarm_age_s >= 604800)' "$CC_WR_IDL"
  [ "$(last_reason)" != "disarmed" ]
  [[ "$(last_reason)" != disarmed:* ]]
}

@test "TTL: the expired marker is CLEARED, so status and the hook cannot disagree about it" {
  local m; m="$(disarm_marker)"
  backdate "$m" $(( 8 * 86400 ))
  mk_tel s2 90
  run drive s2 "$(mk_tx 2)"
  [ "$status" -eq 0 ]
  [ ! -f "$m" ]
  run bash -c "cd '$DESK' && bash '$HOOK' status"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "DISARMED"
}

@test "TTL control: a FRESH opt-out still fully suppresses (the TTL did not delete the feature)" {
  disarm_marker >/dev/null
  mk_tel s3 90
  run drive s3 "$(mk_tx 3)"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ "$(last_reason)" = "disarmed" ]
}

# ── PAIR 2 — WIRE VISIBILITY: two ages must not be one record ─────────────────────────────────────
@test "wire: a STALE (but unexpired) opt-out carries a :stale suffix and its age; a FRESH one does not" {
  local m; m="$(disarm_marker)"
  backdate "$m" $(( 3 * 86400 ))                     # 3d: past DISARM_STALE_S (1d), inside the 7d TTL
  mk_tel s4 90; run drive s4 "$(mk_tx 4)"
  [ "$status" -eq 0 ]; [ -z "$output" ]              # still suppressing — visibility is not a behaviour change
  local stale_row; stale_row="$(tail -1 "$CC_WR_IDL")"
  echo "$stale_row" | jq -e '.reason=="disarmed:stale" and .disarm_age_s >= 259200'
  # …and the token still projects to `disarmed` for scripts/idl-abstain-alarm.sh's split(":")[0].
  [ "$(echo "$stale_row" | jq -r '.reason|split(":")[0]')" = "disarmed" ]

  touch "$m"                                          # same operator intent, one second old
  mk_tel s5 90; run drive s5 "$(mk_tx 5)"
  local fresh_row; fresh_row="$(tail -1 "$CC_WR_IDL")"
  echo "$fresh_row" | jq -e '.reason=="disarmed"'
  # THE DISCRIMINATOR: pre-fix these two rows were byte-identical on .reason.
  [ "$(echo "$stale_row" | jq -r .reason)" != "$(echo "$fresh_row" | jq -r .reason)" ]
}

@test "wire: status names WHEN the opt-out was set, how old it is, and when it stops suppressing" {
  local m; m="$(disarm_marker)"
  backdate "$m" $(( 3 * 86400 ))
  run bash -c "cd '$DESK' && bash '$HOOK' status"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "DISARMED"
  echo "$output" | grep -qE "set: [0-9]{4}-[0-9]{2}-[0-9]{2}T.*\(3d[0-9]+h ago\)"
  echo "$output" | grep -qE "ttl: expires in [0-9]"
  # …and an already-expired one says EXPIRED rather than a countdown into the past.
  backdate "$m" $(( 8 * 86400 ))
  run bash -c "cd '$DESK' && bash '$HOOK' status"
  echo "$output" | grep -q "ttl: EXPIRED"
}

@test "knob control: CC_WR_DISARM_TTL_S=0 disables expiry — an 8-day opt-out still suppresses" {
  local m; m="$(disarm_marker)"
  backdate "$m" $(( 8 * 86400 ))
  mk_tel s6 90
  export CC_WR_DISARM_TTL_S=0
  run drive s6 "$(mk_tx 6)"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ -f "$m" ]                                          # not cleared
  [[ "$(last_reason)" = disarmed* ]]
}
