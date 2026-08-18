#!/usr/bin/env bats
# "STARTED THEN DIED" was the unowned half of the fired-peer lifecycle.
#
# handoff-fire.sh writes `engagedAt` into the fired-peer lifecycle record (cc-fired/<pane>.json) — the
# instant engagement was PROVEN by an oracle. Measured on this tree: that field had ZERO production
# readers. `grep -rn engagedAt` returned the one writer, two bats cases, and docs; no consumer at all.
#
# What that costs: a fired peer that engaged and then died or stalled without self-closing leaves an
# OPEN record (closedAt null) that nothing ever ages. It is not reaped and not surfaced either —
# cc-classify's own tail (bin/cc-classify:804) drops an idle, unlanded, teamless pane into `owned-wait`,
# which is in NEITHER cc-reaper's REAPABLE_RE (bin/cc-reaper:87) nor its SURFACE_PAGE_RE (:216). So the
# fire ends in silence: no page, no board row, no record aged. Start-ack covers "never started"; this is
# the other half.
#
# These cases are BEHAVIOURAL: they put a record on disk, run one real supervisor sweep (`--once`, every
# write seam inside BATS_TEST_TMPDIR) and read the IDL — the daemon's own durable outcome record (S-4).

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_FIRE_CAPACITY_GATE=off
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SUP="$REPO/scripts/lead-supervisor.sh"
  [ -f "$SUP" ] || skip "lead-supervisor.sh not found"
  command -v jq >/dev/null 2>&1 || skip "jq required"

  export CC_TELEMETRY_DIR="$BATS_TEST_TMPDIR/tel";       mkdir -p "$CC_TELEMETRY_DIR"
  export CC_PERMPEND_DIR="$BATS_TEST_TMPDIR/permpend";   mkdir -p "$CC_PERMPEND_DIR"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/registry";   mkdir -p "$CC_REGISTRY_DIR"
  export CC_SUPERVISOR_PAGEDIR="$BATS_TEST_TMPDIR/pages"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_SUPERVISOR_LOG="$BATS_TEST_TMPDIR/sup.log"
  export CC_PAGE_TO_FILE=/dev/null
  export CC_SUP_OS_CHANNEL=off
  export CC_SUP_SELFCHECK_MIN_PERSIST=99
  export CC_WAIT_CONTRACTS_DIR="$BATS_TEST_TMPDIR/contracts"; mkdir -p "$CC_WAIT_CONTRACTS_DIR"
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/cc-fired";      mkdir -p "$CC_FIRED_DIR"
  PANE="11111111-2222-3333-4444-555555555555"
}

# <engagedAt-or-empty> <closedAt-or-empty> <transcript-age: cold|warm|ancient|none>
# `cold` is 2h — inside the actionable window. `ancient` is 30d, deliberately OUTSIDE the upper
# horizon: a record that old is archaeology whose originator is long gone (47 of 53 live cold records
# were >7d), and paging those on the first sweep would be the composer storm, not the feature.
fired_record() {
  local engaged="$1" closed="$2" tage="$3" tp=""
  if [ "$tage" != none ]; then
    tp="$BATS_TEST_TMPDIR/$PANE.jsonl"; : > "$tp"
    [ "$tage" = cold ]    && touch -t "$(date -v-2H  +%Y%m%d%H%M 2>/dev/null || date -d '2 hours ago' +%Y%m%d%H%M)" "$tp"
    [ "$tage" = ancient ] && touch -t "$(date -v-30d +%Y%m%d%H%M 2>/dev/null || date -d '30 days ago' +%Y%m%d%H%M)" "$tp"
  fi
  jq -n --arg pane "$PANE" --arg cwd "$BATS_TEST_TMPDIR/wt" --arg by "ORIGIN-PANE" \
        --arg engaged "$engaged" --arg closed "$closed" --arg tp "$tp" \
    '{paneUUID:$pane, cwd:$cwd, firedBy:$by, firedAt:"2026-08-18T00:00:00Z", selfRetire:true,
      schema:2, originClass:"fired-peer", originator:$by, notifyBack:null,
      firedStartedAt:"2026-08-18T00:00:00Z",
      engagedAt:(if $engaged == "" then null else $engaged end),
      engageProof:"marker", transcript:(if $tp == "" then null else $tp end),
      marker:"FIRE-TEST", engageLatencyS:29,
      closedAt:(if $closed == "" then null else $closed end), succession:null}' \
    > "$CC_FIRED_DIR/$PANE.json"
}

dark_records() { [ -f "$CC_IDL" ] && jq -rs '[.[] | select(.kind=="fired_peer_dark")] | length' "$CC_IDL" || echo 0; }

@test "a peer that ENGAGED and then went dark is a supervisor finding, not silence" {
  fired_record "2026-08-18T00:00:29Z" "" cold
  run bash "$SUP" --once
  [ "$status" -eq 0 ]
  [ "$(dark_records)" -ge 1 ]
  run jq -rs '[.[] | select(.kind=="fired_peer_dark")] | last | .pane' "$CC_IDL"
  [ "$output" = "$PANE" ]
  # …and it counts in the sweep's own heartbeat: a sweep that found a stranded peer must not record
  # an all-clear (S-4).
  run jq -rs '[.[] | select(.kind=="heartbeat")] | last | .findings' "$CC_IDL"
  [ "$output" -ge 1 ]
}

@test "the dark peer is recorded ONCE, not once per 30-second sweep" {
  fired_record "2026-08-18T00:00:29Z" "" cold
  bash "$SUP" --once >/dev/null 2>&1
  bash "$SUP" --once >/dev/null 2>&1
  [ "$(dark_records)" = 1 ]
}

@test "CONTROL (green pre- and post-fix): a warm transcript is never called dark" {
  fired_record "2026-08-18T00:00:29Z" "" warm
  bash "$SUP" --once >/dev/null 2>&1
  [ "$(dark_records)" = 0 ]
}

@test "CONTROL (green pre- and post-fix): a self-closed peer is spent, never paged" {
  # closedAt set = the peer completed its own close. Cold is then NORMAL — the pane is gone because it
  # retired. Paging this would invert the rung and page every healthy completed fire on the box.
  fired_record "2026-08-18T00:00:29Z" "2026-08-18T01:00:00Z" cold
  bash "$SUP" --once >/dev/null 2>&1
  [ "$(dark_records)" = 0 ]
}

@test "a record past the upper horizon is archaeology, not a page" {
  # The activation cost of this rung is measured, not assumed: 47 of 53 live open+engaged records are
  # >7 days cold. Without the upper horizon the first sweep after landing would page all of them at
  # once — the 2026-07-19 composer storm this file's own comments forbid.
  fired_record "2026-08-18T00:00:29Z" "" ancient
  bash "$SUP" --once >/dev/null 2>&1
  [ "$(dark_records)" = 0 ]
}

@test "CONTROL (green pre- and post-fix): a NEVER-ENGAGED record is start-ack's, not this rung's" {
  # engagedAt null = the peer never proved engagement. That is the "never started" class, already owned
  # on both live surfaces. Claiming it here would double-own it and re-page what start-ack pages.
  fired_record "" "" cold
  bash "$SUP" --once >/dev/null 2>&1
  [ "$(dark_records)" = 0 ]
}
