#!/usr/bin/env bats
# V2 A2 — the ENGAGEMENT DETECTOR's scan window (SESSION_LIFECYCLE_V2.md §5.3).
#
# Why this suite exists. Row 2's headline DoD is fire→engaged ≤60s p95. Once schema-2 records
# accrued (115 fires), the number read 323s — and decomposing every record against its OWN
# transcript showed the successor was not slow: of a 126s p50, spawn+boot was 26.6s and the model's
# first turn 9.2s, while DETECTION LAG was 89.8s (p95 280.6s). 71% of the metric was the poll
# noticing. Cause: engagement_seen / recycle_engaged content-grep EVERY transcript on every
# iteration (1,888 files / 1.1 GB → 9.3-10.4s per pass warm; recycle_engaged sweeps all five
# CC_PROJECTS_DIRS = 4.6 GB). A marker can only be in a transcript written SINCE the fire, so the
# scan is mtime-scoped.
#
# WHAT IS ASSERTED, AND WHAT DELIBERATELY IS NOT. These tests assert the SCOPE — which files the
# detector will and will not read — never a wall-clock speedup. A timing assertion would be an
# ambient-load coupling on a box whose loadavg ranges 15-41 (map R-1), i.e. exactly the failure the
# capacity-gate pins below exist to prevent; a slow box would turn a correct fix RED. Scope is the
# property; speed is its consequence.
#
# Fixture note: mtimes are set with perl's utime, not `touch -A`/`-t`, so the offsets are exact
# relative seconds with no date-string parsing and no BSD/GNU flag divergence.

setup() {
  # Pinned, never ambient (M11 / MACHINE_CAPACITY_V2 §11.3) — the gate reads live loadavg + memory
  # headroom and exits 9 when the box is busy, which is what turned 16 corpus tests RED (map R-1).
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  hf_bounded() { "$@"; }

  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"

  H="$BATS_TEST_TMPDIR/home"
  mkdir -p "$H/.claude/projects" "$H/.claude/cc-registry" "$H/.claude/bin"
  # Fixtured in setup(), not per-test (test-hermeticity-lint): an unfixtured $HOME would make these
  # detectors grep the OPERATOR's real 1.1 GB transcript corpus — which is also the very cost under
  # test, so the suite would measure the operator's disk instead of its own fixture.
  export HOME="$H"
  PROJ="$H/.claude/projects"
  REG="$H/.claude/cc-registry"
  PANE="FAKEPANE-0000-0000-0000-000000000001"
  OLD_SID="11111111-1111-1111-1111-111111111111"
  NEW_SID="22222222-2222-2222-2222-222222222222"
  export CC_PROJECTS_DIRS="$PROJ"

  eval "$(sed -n '/^assistant_turn_in() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^engagement_seen() {/,/^}/p'   "$HF")"
  eval "$(sed -n '/^cc_sid_for_pane() {/,/^}/p'   "$HF")"
  eval "$(sed -n '/^recycle_engaged() {/,/^}/p'   "$HF")"
}

# A transcript that HAS ingested the marker and HAS run a turn — i.e. genuinely engaged.
engaged_transcript() { # $1=path $2=marker
  printf '%s\n' \
    "{\"type\":\"user\",\"message\":{\"content\":\"brief $2\"}}" \
    '{"type":"assistant","message":{"content":"on it"}}' > "$1"
}
age_minutes() { perl -e 'utime time-($ARGV[1]*60), time-($ARGV[1]*60), $ARGV[0]' "$1" "$2"; }
row() { printf '{"paneUUID":"%s","session_id":"%s"}\n' "$PANE" "$1" > "$REG/$PANE.json"; }

# ── engagement_seen (the fire path) ───────────────────────────────────────────────────────────────

@test "engagement_seen: a FRESH marked transcript is inside the window → engaged" {
  engaged_transcript "$PROJ/$NEW_SID.jsonl" "MK-FRESH"
  run engagement_seen "$PROJ" "MK-FRESH" "$REG" "$PANE"
  [ "$status" -eq 0 ]
}

@test "RED-PROOF engagement_seen: a marked transcript OLDER than the window is not scanned" {
  # The scoping property itself. Unscoped (pristine tree) this file is found and the test FAILS.
  engaged_transcript "$PROJ/$OLD_SID.jsonl" "MK-STALE"
  age_minutes "$PROJ/$OLD_SID.jsonl" 2880   # 2 days — far outside the 240-min default
  run engagement_seen "$PROJ" "MK-STALE" "$REG" "$PANE"
  [ "$status" -eq 1 ]
}

@test "RED-PROOF engagement_seen: CC_ENGAGE_SCAN_WINDOW_MIN sets the boundary" {
  engaged_transcript "$PROJ/$NEW_SID.jsonl" "MK-100"
  age_minutes "$PROJ/$NEW_SID.jsonl" 100
  CC_ENGAGE_SCAN_WINDOW_MIN=240 run engagement_seen "$PROJ" "MK-100" "$REG" "$PANE"
  [ "$status" -eq 0 ]   # 100 min old, 240-min window → inside
  CC_ENGAGE_SCAN_WINDOW_MIN=30  run engagement_seen "$PROJ" "MK-100" "$REG" "$PANE"
  [ "$status" -eq 1 ]   # same file, 30-min window → outside
}

@test "R8 kill switch: CC_ENGAGE_SCAN_WINDOW=0 restores the unscoped full-corpus scan" {
  # Green on BOTH trees by design — it asserts the pre-change behaviour is reachable, which is what
  # a kill switch IS. A switch that only works on the new tree would be untestable as a revert path.
  engaged_transcript "$PROJ/$OLD_SID.jsonl" "MK-STALE"
  age_minutes "$PROJ/$OLD_SID.jsonl" 2880
  CC_ENGAGE_SCAN_WINDOW=0 run engagement_seen "$PROJ" "MK-STALE" "$REG" "$PANE"
  [ "$status" -eq 0 ]
}

@test "F2 PRESERVED: a RESUMED successor's pre-existing transcript stays inside the window" {
  # The resume fix (cc-backlog 93a9f880b6fe) depends on the marker landing in the ORIGINAL sid's
  # transcript rather than a new one. Scoping cannot regress that, and this pins WHY: appending the
  # marked prompt is a WRITE, and the write is what refreshes mtime. Born old, ingests now, found.
  printf '%s\n' '{"type":"user","message":{"content":"an old conversation"}}' > "$PROJ/$OLD_SID.jsonl"
  age_minutes "$PROJ/$OLD_SID.jsonl" 5760          # created 4 days ago…
  engaged_transcript "$PROJ/$OLD_SID.jsonl" "MK-RESUMED"   # …then resumed NOW (rewrites → fresh mtime)
  # Called BARE, not via `run`: ENGAGE_PROOF is set by the function and `run` would strand it in a
  # subshell (the idiom tests/handoff-lifecycle-record.bats:118 uses for the same reason).
  engagement_seen "$PROJ" "MK-RESUMED" "$REG" "$PANE"
  [ "$ENGAGE_PROOF" = marker ]
  [ "$ENGAGE_TRANSCRIPT" = "$PROJ/$OLD_SID.jsonl" ]
}

@test "the registry path (b) is unaffected by the marker scan window" {
  # Path (b) resolves a transcript BY NAME from the registry row, so it never content-greps and must
  # keep working for an old transcript. Guards against the scoping leaking into the wrong branch.
  engaged_transcript "$PROJ/$OLD_SID.jsonl" "irrelevant"
  age_minutes "$PROJ/$OLD_SID.jsonl" 2880
  row "$OLD_SID"
  run engagement_seen "$PROJ" "" "$REG" "$PANE"
  [ "$status" -eq 0 ]
}

# ── recycle_engaged (the recycle path — same defect, 5 dirs instead of 1) ─────────────────────────

@test "recycle_engaged: a FRESH marked transcript is inside the window → engaged" {
  row "$OLD_SID"
  engaged_transcript "$PROJ/$NEW_SID.jsonl" "MK-R-FRESH"
  run recycle_engaged "$PANE" "$OLD_SID" "MK-R-FRESH"
  [ "$status" -eq 0 ]
}

@test "RED-PROOF recycle_engaged: a marked transcript OLDER than the window is not scanned" {
  row "$OLD_SID"
  engaged_transcript "$PROJ/$NEW_SID.jsonl" "MK-R-STALE"
  age_minutes "$PROJ/$NEW_SID.jsonl" 2880
  run recycle_engaged "$PANE" "$OLD_SID" "MK-R-STALE"
  [ "$status" -eq 1 ]
}

@test "R8 kill switch: CC_ENGAGE_SCAN_WINDOW=0 restores the unscoped scan on the recycle path too" {
  row "$OLD_SID"
  engaged_transcript "$PROJ/$NEW_SID.jsonl" "MK-R-STALE"
  age_minutes "$PROJ/$NEW_SID.jsonl" 2880
  CC_ENGAGE_SCAN_WINDOW=0 run recycle_engaged "$PANE" "$OLD_SID" "MK-R-STALE"
  [ "$status" -eq 0 ]
}

@test "recycle_engaged: the predecessor-exclusion still holds inside the window" {
  # Scoping must not weaken the false-positive guard the function exists for: the caller of a recycle
  # IS the session being recycled, so its own (fresh, therefore in-window) transcript must never
  # count as proof of the relaunch.
  row "$OLD_SID"
  engaged_transcript "$PROJ/$OLD_SID.jsonl" "MK-LEAK"   # fresh mtime, but it is the PREDECESSOR
  run recycle_engaged "$PANE" "$OLD_SID" "MK-LEAK"
  [ "$status" -eq 1 ]
}
