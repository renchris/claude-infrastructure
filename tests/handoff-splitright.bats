#!/usr/bin/env bats
# Regression guard for handoff-fire.sh SPLIT-SURFACE spawn (2026-07-17).
#
# The operator's recurring complaint: handoff fires that were supposed to ⌘D-split the FIRING pane
# kept landing in a SEPARATE window. Root cause: the old osascript as_split could throw AFTER the
# split already happened, the wrapper read that as failure, and fired a SECOND surface via
# spawn_frontmost — into iTerm2's app-frontmost (i.e. some OTHER) window.
#
# The durable invariants this file locks down:
#   1. split surfaces resolve + split via the it2 API and parse its "Created new pane: <id>" line;
#   2. a mis-resolved / dead / missing anchor FAILS LOUD (non-zero) and NEVER calls spawn_frontmost
#      — the only surface allowed to open a fresh window is the deliberate --window.
#
# Functions are extracted from the real script (same technique as fire-autonomy.bats). REAL_IT2 is
# stubbed with a fake it2 whose split of "GOOD" succeeds and any other anchor errors (rc 3, exactly
# like the real CLI); spawn_frontmost / it2_land / as_tab are stubbed to record which path ran.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"

  FAKE_IT2="$BATS_TEST_TMPDIR/it2"
  cat > "$FAKE_IT2" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = session ] && [ "${2:-}" = split ]; then
  id=""; shift 2
  while [ $# -gt 0 ]; do case "$1" in -s) id="${2:-}"; shift 2;; *) shift;; esac; done
  if [ "$id" = GOOD ]; then echo "Created new pane: NEWPANE-123"; exit 0; fi
  echo "Error: Session '$id' not found" >&2; exit 3     # the real it2 rc for a missing anchor
fi
exit 0                                                   # run / focus / anything else: no-op
SH
  chmod +x "$FAKE_IT2"
  REAL_IT2="$FAKE_IT2"

  eval "$(sed -n '/^it2_split() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^spawn() {/,/^}/p' "$HF")"

  FRONTMOST_MARK="$BATS_TEST_TMPDIR/frontmost"; rm -f "$FRONTMOST_MARK"
  LAND_MARK="$BATS_TEST_TMPDIR/land";           rm -f "$LAND_MARK"
  spawn_frontmost() { echo win > "$FRONTMOST_MARK"; echo WINPANE; }   # marker + echoes the new id
  it2_land()        { echo "$1" > "$LAND_MARK"; return 0; }
  as_tab()          { echo NOTFOUND; }                   # per-test override
  CMD="echo test"
}

@test "it2_split: parses the it2 success line into the new session id" {
  run it2_split GOOD vertically
  [ "$status" -eq 0 ]
  [ "$output" = "NEWPANE-123" ]
}

@test "it2_split: returns non-zero and echoes nothing when the anchor is not found" {
  run it2_split DEADBEEF vertically
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "spawn split-right with a live anchor lands via it2 (it2_land), never frontmost" {
  FIRING_SID=GOOD; SURFACE=split-right
  run spawn
  [ "$status" -eq 0 ]
  [ -f "$LAND_MARK" ]
  [ ! -f "$FRONTMOST_MARK" ]
}

@test "spawn split-down with a live anchor also lands via it2, never frontmost" {
  FIRING_SID=GOOD; SURFACE=split-down
  run spawn
  [ "$status" -eq 0 ]
  [ ! -f "$FRONTMOST_MARK" ]
}

@test "REGRESSION: split-right with a DEAD anchor FAILS LOUD — no frontmost window" {
  FIRING_SID=DEADBEEF; SURFACE=split-right
  run spawn
  [ "$status" -ne 0 ]
  [ ! -f "$FRONTMOST_MARK" ]
  [[ "$output" == *"NOT firing into a random window"* ]]
}

@test "REGRESSION: split with NO anchor REFUSES — no frontmost window" {
  FIRING_SID=""; SURFACE=split-right
  run spawn
  [ "$status" -ne 0 ]
  [ ! -f "$FRONTMOST_MARK" ]
  [[ "$output" == *"REFUSING to fire"* ]]
}

@test "spawn --window creates via spawn_frontmost then verified-types via it2_land" {
  FIRING_SID=GOOD; SURFACE=window
  run spawn
  [ "$status" -eq 0 ]
  [ -f "$FRONTMOST_MARK" ]                 # the fresh-window path ran (the one legitimate frontmost caller)
  [ -f "$LAND_MARK" ]                      # …and the command was TYPED via it2_land (it2_type_verified)
  [ "$(cat "$LAND_MARK")" = WINPANE ]      #    with the new window's session id — never osascript write text
}

@test "REGRESSION: --window with an uncreatable window FAILS LOUD — nothing launched" {
  spawn_frontmost() { echo win > "$FRONTMOST_MARK"; }   # created marker but echoes NO id (osascript failed)
  FIRING_SID=GOOD; SURFACE=window
  run spawn
  [ "$status" -ne 0 ]
  [ ! -f "$LAND_MARK" ]                    # never typed into a window that could not be created
  [[ "$output" == *"nothing launched"* ]]
}

@test "spawn tab creates via as_tab then verified-types via it2_land, never frontmost" {
  as_tab() { echo "OK TABPANE"; }
  FIRING_SID=GOOD; SURFACE=tab
  run spawn
  [ "$status" -eq 0 ]
  [ ! -f "$FRONTMOST_MARK" ]
  [ -f "$LAND_MARK" ]                      # typed via it2_land (it2_type_verified), not osascript write text
  [ "$(cat "$LAND_MARK")" = TABPANE ]      #   with the tab's session id
}

@test "REGRESSION: tab with a dead window FAILS LOUD — no frontmost window" {
  as_tab() { echo NOTFOUND; }
  FIRING_SID=GOOD; SURFACE=tab
  run spawn
  [ "$status" -ne 0 ]
  [ ! -f "$FRONTMOST_MARK" ]
  [[ "$output" == *"NOT firing a tab into a random window"* ]]
}
