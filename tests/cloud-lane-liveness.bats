#!/usr/bin/env bats
# cloud-lane-liveness.bats — the cloud FIRE lane's liveness instrument.
#
# The subject reads ONE thing (the remote's `claude/fire-*` heads) and turns it into ONE verdict, so
# every case here drives it through `CC_LANE_REFS_CMD` — the seam that replaces the `ls-remote`
# wholesale. Stubbing `git` itself would only test the stub; replacing the command lets a case drive
# the path that matters most, a sensor that exits non-zero having printed nothing, which is
# byte-identical to a remote holding no fires.
#
# The clock is pinned (`CC_LANE_NOW`) in every case, because a gap is a statement about an interval
# and an unpinned `now` would make the suite a statement about when it was run.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUT="$REPO/scripts/cloud-lane-liveness.sh"
  REFS="$BATS_TEST_TMPDIR/refs"
  export CC_LANE_REFS_CMD="cat '$REFS'"
  export CC_LANE_SELF_BRANCH="main"     # the desk's shape: HEAD is not a fire ref
  export CC_LANE_BASELINE_N=0           # the population control is exercised by its own cases
  export CC_LANE_BASELINE_DATE=20260907
  export CC_LANE_FIRE_CEILING_H=24
  export CC_LANE_WINDOW_DAYS=7
}

# refs <stamp>...   — write a fixture of well-formed fire refs at the given YYYYMMDDTHHMMSSZ stamps
refs() { : >"$REFS"; for s in "$@"; do printf 'claude/fire-%s-1234-1\n' "$s" >>"$REFS"; done; }

# epoch <YYYYMMDDTHHMMSSZ> — the same civil-days arithmetic the subject uses, computed independently
# here so a case can say "now is exactly N hours after that fire" without importing the subject.
epoch() {
  awk -v t="$1" 'BEGIN{
    y=substr(t,1,4)+0; m=substr(t,5,2)+0; d=substr(t,7,2)+0;
    H=substr(t,10,2)+0; M=substr(t,12,2)+0; S=substr(t,14,2)+0;
    yy = y - (m<=2 ? 1 : 0); era = int((yy>=0?yy:yy-399)/400); yoe = yy - era*400;
    doy = int((153*(m + (m>2?-3:9)) + 2)/5) + d - 1;
    doe = yoe*365 + int(yoe/4) - int(yoe/100) + doy;
    printf "%d", (era*146097 + doe - 719468)*86400 + H*3600 + M*60 + S }'
}

@test "a lane that fired an hour ago is LIVE, and --assert agrees" {
  refs 20260910T120000Z 20260911T000000Z
  export CC_LANE_NOW=$(( $(epoch 20260911T000000Z) + 3600 ))
  run bash "$SUT" --assert
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"VERDICT       LIVE"* ]] || false
}

@test "a lane silent past the ceiling is STALLED, and --assert exits 1" {
  refs 20260907T173618Z
  export CC_LANE_NOW=$(( $(epoch 20260907T173618Z) + 31*3600 ))   # W10's 31.14 h gap, still open
  run bash "$SUT" --assert
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"VERDICT       STALLED"* ]] || false
  [[ "$output" == *"silent for 31.00 h"* ]] || false
}

# ── THE CASE THE WHOLE FILE EXISTS FOR ───────────────────────────────────────────────────────────
# Run from a cloud VM the reader's OWN boot-ping branch is the newest fire ref. Without the
# self-exclusion the open gap is the age of the reader's own push — seconds — so the live arm can
# never trip, and firing a session TO DIAGNOSE a stalled lane becomes the act that makes the lane
# read healthy. Same fixture as the STALLED case above plus the reader's own ref, and the verdict
# must not move.
@test "SELF: the reader's own boot-ping ref does not close the gap it was fired to measure" {
  refs 20260907T173618Z 20260909T010000Z
  export CC_LANE_SELF_BRANCH="claude/fire-20260909T010000Z-1234-1"
  export CC_LANE_NOW=$(( $(epoch 20260909T010000Z) + 60 ))        # the reader pushed 60 s ago
  run bash "$SUT" --assert
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"VERDICT       STALLED"* ]] || false
  [[ "$output" == *"self-excluded claude/fire-20260909T010000Z-1234-1"* ]] || false
}

@test "SELF: the exclusion is exactly one ref — a sibling fired the same minute still counts" {
  refs 20260909T010000Z 20260909T010030Z
  export CC_LANE_SELF_BRANCH="claude/fire-20260909T010030Z-1234-1"
  export CC_LANE_NOW=$(( $(epoch 20260909T010000Z) + 3600 ))
  run bash "$SUT" --json
  [ "$status" -eq 0 ] || false
  [ "$(printf '%s' "$output" | jq -r .verdict)" = "LIVE" ] || false
  [ "$(printf '%s' "$output" | jq -r .last_fire)" = "2026-09-09T01:00:00Z" ] || false
  [ "$(printf '%s' "$output" | jq -r .refs_seen)" = "1" ] || false
}

# ── "cannot look" is never "nothing found" ───────────────────────────────────────────────────────
@test "a sensor that could not run is UNKNOWN at rc 3 — never a stalled lane" {
  cat >"$BATS_TEST_TMPDIR/dead" <<'EOF'
#!/bin/bash
exit 128
EOF
  chmod +x "$BATS_TEST_TMPDIR/dead"
  export CC_LANE_REFS_CMD="bash '$BATS_TEST_TMPDIR/dead'"
  export CC_LANE_NOW=$(epoch 20260911T000000Z)
  run bash "$SUT" --assert
  [ "$status" -eq 3 ] || false
  [[ "$output" == *"VERDICT       UNKNOWN"* ]] || false
  [[ "$output" == *"cannot look"* ]] || false
  [[ "$output" != *STALLED* ]] || false
}

@test "an UNKNOWN reading nulls every number — a consumer must not be handed a zero to sum" {
  cat >"$BATS_TEST_TMPDIR/dead" <<'EOF'
#!/bin/bash
exit 128
EOF
  chmod +x "$BATS_TEST_TMPDIR/dead"
  export CC_LANE_REFS_CMD="bash '$BATS_TEST_TMPDIR/dead'"
  export CC_LANE_NOW=$(epoch 20260911T000000Z)
  run bash "$SUT" --json
  [ "$status" -eq 3 ] || false
  printf '%s' "$output" | jq -e '.verdict=="UNKNOWN"' >/dev/null || false
  printf '%s' "$output" | jq -e '.open_gap_h==null and .rate_per_day==null and .fires_in_window==null and .max_closed_gap_h==null and .refs_seen==null' >/dev/null || false
  # ...and it must be nulled for the SENSOR's reason. Without this the case passes on the
  # no-fire-refs arm too (mutant M2 proved exactly that), so it would credit a cure it never ran.
  printf '%s' "$output" | jq -e '.why | test("cannot look")' >/dev/null || false
}

# ── the population control: nothing deletes a branch, so a SHRINK voids the census ───────────────
@test "a SHRINKING ref population is UNKNOWN — an absent date stops being evidence" {
  refs 20260901T000000Z 20260902T000000Z 20260911T000000Z
  export CC_LANE_BASELINE_N=3          # the pinned floor for refs dated <= 20260907
  export CC_LANE_NOW=$(( $(epoch 20260911T000000Z) + 3600 ))
  run bash "$SUT" --assert
  [ "$status" -eq 3 ] || false
  [[ "$output" == *"a branch was DELETED"* ]] || false
}

@test "a GROWING ref population is the healthy direction and does not trip the control" {
  refs 20260901T000000Z 20260902T000000Z 20260903T000000Z 20260911T000000Z
  export CC_LANE_BASELINE_N=3
  export CC_LANE_NOW=$(( $(epoch 20260911T000000Z) + 3600 ))
  run bash "$SUT" --assert
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"VERDICT       LIVE"* ]] || false
}

@test "a malformed claude/* ref is UNKNOWN — the lane may have been renamed (this plan's §1.1 scar)" {
  refs 20260911T000000Z
  printf 'claude/dispatch-20260911-x\n' >>"$REFS"
  export CC_LANE_NOW=$(( $(epoch 20260911T000000Z) + 3600 ))
  run bash "$SUT" --assert
  [ "$status" -eq 3 ] || false
  [[ "$output" == *"renamed"* ]] || false
}

# ── the rate is CONTEXT, the gap is the VERDICT — the design decision, pinned both ways ──────────
@test "RATE-NOT-VERDICT: a busy window with an OPEN stall is STALLED, not healthy" {
  # 20 fires inside the window, then silence. Rate reads high; the lane is not firing now.
  set --
  for h in 00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19; do
    set -- "$@" "20260908T${h}0000Z"
  done
  refs "$@"
  export CC_LANE_NOW=$(( $(epoch 20260908T190000Z) + 30*3600 ))
  run bash "$SUT" --json
  [ "$status" -eq 0 ] || false
  [ "$(printf '%s' "$output" | jq -r .verdict)" = "STALLED" ] || false
  # and the high rate is still REPORTED beside the refusal, not suppressed to justify it
  printf '%s' "$output" | jq -e '.rate_per_day > 2' >/dev/null || false
}

@test "RATE-NOT-VERDICT: a near-silent window with one RECENT fire is LIVE, not stalled" {
  refs 20260911T000000Z
  export CC_LANE_NOW=$(( $(epoch 20260911T000000Z) + 3600 ))
  run bash "$SUT" --json
  [ "$status" -eq 0 ] || false
  [ "$(printf '%s' "$output" | jq -r .verdict)" = "LIVE" ] || false
  printf '%s' "$output" | jq -e '.rate_per_day < 0.2' >/dev/null || false
}

# ── history is reported, never charged ──────────────────────────────────────────────────────────
@test "a CLOSED stall in the window is counted but does not redden a lane that is firing now" {
  # W9's own series: the 58.76 h deadlock, then the lane reopens and keeps firing daily. The daily
  # fires sit at EXACTLY the ceiling, which also pins that the closed arm uses the same strict
  # compare as the open one — a 24.00 h silence is not a stall on either.
  refs 20260904T193754Z 20260907T062332Z 20260907T063702Z \
       20260908T060000Z 20260909T060000Z 20260910T060000Z 20260911T060000Z
  export CC_LANE_NOW=$(( $(epoch 20260911T060000Z) + 3600 ))
  run bash "$SUT" --json
  [ "$status" -eq 0 ] || false
  [ "$(printf '%s' "$output" | jq -r .verdict)" = "LIVE" ] || false
  [ "$(printf '%s' "$output" | jq -r .stalls_in_window)" = "1" ] || false
  [ "$(printf '%s' "$output" | jq -r .max_closed_gap_h)" = "58.76" ] || false
}

@test "the gap arithmetic is exact at the ceiling: 24.00 h is LIVE, one second more is STALLED" {
  refs 20260911T000000Z
  export CC_LANE_NOW=$(( $(epoch 20260911T000000Z) + 86400 ))
  run bash "$SUT" --assert
  [ "$status" -eq 0 ] || false
  export CC_LANE_NOW=$(( $(epoch 20260911T000000Z) + 86401 ))
  run bash "$SUT" --assert
  [ "$status" -eq 1 ] || false
}

@test "a fire stamped in the FUTURE reads as a zero gap, never as a negative one" {
  refs 20260911T000000Z
  export CC_LANE_NOW=$(( $(epoch 20260911T000000Z) - 7200 ))   # clock skew, or a bad stamp
  run bash "$SUT" --json
  [ "$status" -eq 0 ] || false
  [ "$(printf '%s' "$output" | jq -r .open_gap_h)" = "0.00" ] || false
}

@test "--selftest drives every verdict state with no network, no repo and no clock" {
  run env -u CC_LANE_REFS_CMD -u CC_LANE_NOW bash "$SUT" --selftest
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"all states discriminate"* ]] || false
  [[ "$output" != *FAIL* ]] || false
}

@test "an ls-remote-shaped '<sha>\\trefs/heads/<name>' row parses the same as a bare name" {
  printf '%s\trefs/heads/claude/fire-20260911T000000Z-1234-1\n' "$(printf 'a%.0s' $(seq 40))" >"$REFS"
  export CC_LANE_NOW=$(( $(epoch 20260911T000000Z) + 3600 ))
  run bash "$SUT" --json
  [ "$status" -eq 0 ] || false
  [ "$(printf '%s' "$output" | jq -r .last_fire)" = "2026-09-11T00:00:00Z" ] || false
}

@test "an unknown argument is a usage error, not a silent default reading" {
  run bash "$SUT" --nope
  [ "$status" -eq 2 ] || false
}
