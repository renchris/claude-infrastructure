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
  # handoff-fire.sh bounds every external iTerm2 call (osascript / it2 CLI / iterm2 python) through
  # hf_bounded — a timeout(1) wrapper — because a wedged iTerm2 API blocks them indefinitely. These
  # suites EXTRACT individual functions instead of sourcing the script, so that helper is not in
  # scope and an extracted function would die with "hf_bounded: command not found". A passthrough
  # keeps the extracted behaviour byte-identical and deterministic; the helper's OWN semantics
  # (bound applied, expiry -> 124, set-but-empty disable seam) are covered by
  # tests/handoff-fire-it2-bound.bats against the real definition.
  hf_bounded() { "$@"; }
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

@test "REGRESSION: split with a NAMED-but-unusable anchor REFUSES — no frontmost window" {
  # ANCHOR_INTENT=1: the caller DID name a pane (via --session-id / \$ITERM_SESSION_ID) and it did not
  # resolve. That is an operator intent we must not betray → fail loud, never resolve a substitute.
  FIRING_SID=""; SURFACE=split-right; ANCHOR_INTENT=1
  run spawn
  [ "$status" -ne 0 ]
  [ ! -f "$FRONTMOST_MARK" ]
  [[ "$output" == *"REFUSING to fire"* ]]
}

@test "REGRESSION: an UNKNOWN anchor intent defaults to the refusal, never to resolution" {
  # Fail-safe direction: if ANCHOR_INTENT is somehow unset, the safe branch is refuse — never
  # "resolve some pane and fire into it".
  FIRING_SID=""; SURFACE=split-right; unset ANCHOR_INTENT
  resolve_headless_anchor() { echo "GOOD 1"; }
  run spawn
  [ "$status" -ne 0 ]
  [ ! -f "$FRONTMOST_MARK" ]
  [[ "$output" == *"REFUSING to fire"* ]]
}

# ---- HEADLESS ANCHOR (2026-07-30) -------------------------------------------------------------
# The regression this locks: between 2026-07-25 and 2026-07-30 every anchor-free caller (launchd
# cc-dispatch via cc-wave-plan, desk-invariant's respawn) hardcoded --window, so each dispatched
# session opened its own iTerm2 WINDOW — 174 of them in a single day. A caller that never named a
# pane has no intent to betray, so it must now resolve a live anchor and ⌘D-split it in place.

@test "HEADLESS: no anchor intent resolves a live pane and SPLITS it — never a new window" {
  FIRING_SID=""; SURFACE=split-right; ANCHOR_INTENT=0
  resolve_headless_anchor() { echo "GOOD 2"; }
  run spawn
  [ "$status" -eq 0 ]
  [ ! -f "$FRONTMOST_MARK" ]               # THE invariant: no fresh window was created
  [ -f "$LAND_MARK" ]
  [ "$(cat "$LAND_MARK")" = NEWPANE-123 ]  # landed in the split of the resolved anchor
  [[ "$output" == *"anchored to live pane GOOD"* ]]
}

@test "HEADLESS: a DENSE anchor tab degrades to a bg-tab in the SAME window, not a new one" {
  FIRING_SID=""; SURFACE=split-right; ANCHOR_INTENT=0
  resolve_headless_anchor() { echo "GOOD 9"; }          # 9 panes ≥ CC_FIRE_MAX_PANES default 6
  it2_bgtab() { echo BGPANE; }
  run spawn
  [ "$status" -eq 0 ]
  [ ! -f "$FRONTMOST_MARK" ]               # sliver-avoidance must NOT become a new window
  [ "$(cat "$LAND_MARK")" = BGPANE ]
  [[ "$output" == *"degrading split-right to a background tab"* ]]
}

@test "HEADLESS: a 4-pane tab still SPLITS — the degrade must not eat the common case" {
  # Calibration guard. The active tab held exactly 4 panes when this was built, so a threshold of 4
  # would have turned nearly every headless fire into a tab and quietly re-lost "same existing tab
  # view" — the thing the operator asked for. The bias is toward splitting.
  FIRING_SID=""; SURFACE=split-right; ANCHOR_INTENT=0
  resolve_headless_anchor() { echo "GOOD 4"; }
  it2_bgtab() { echo BGPANE; }
  run spawn
  [ "$status" -eq 0 ]
  [ ! -f "$FRONTMOST_MARK" ]
  [ "$(cat "$LAND_MARK")" = NEWPANE-123 ]  # the SPLIT ran, not the bg-tab
  [[ "$output" != *"degrading"* ]]
}

@test "HEADLESS: only a totally paneless iTerm2 falls back to a fresh window" {
  FIRING_SID=""; SURFACE=split-right
  # shellcheck disable=SC2034  # read by the spawn() extracted from the real script, not by this file
  ANCHOR_INTENT=0
  resolve_headless_anchor() { return 1; }               # no live session anywhere
  run spawn
  [ "$status" -eq 0 ]
  [ -f "$FRONTMOST_MARK" ]                 # the ONE legitimate window case
  [ "$(cat "$LAND_MARK")" = WINPANE ]
  [[ "$output" == *"no live iTerm2 session to anchor to"* ]]
}

@test "HEADLESS: the kill-switch restores the old behaviour" {
  # CC_FIRE_HEADLESS_ANCHOR=off makes resolve_headless_anchor decline, so a headless fire degrades
  # to the fresh window it used to hardcode — an escape hatch, not the default.
  eval "$(sed -n '/^resolve_headless_anchor() {/,/^}/p' "$HF")"
  # shellcheck disable=SC2034  # read by the extracted resolve_headless_anchor, not by this file
  CC_FIRE_HEADLESS_ANCHOR=off
  run resolve_headless_anchor
  [ "$status" -ne 0 ]
  [ -z "$output" ]
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
