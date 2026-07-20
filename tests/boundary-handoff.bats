#!/usr/bin/env bats
# boundary-handoff.sh — Stop-hook advisory at a committed+green boundary (ALL sessions), now with the
# context-econ signals: forecast-early fire (used ≥ T_MIN ∧ burn-forecast ≤ LEAD_MIN) and
# conversation-aware wording (exchange in flight ⇒ finish + persist first — wording, not suppression).
#
# Coverage: static fire ≥T · below-threshold abstain · forecast-EARLY fire below T · the T_MIN floor ·
# unknown-forecast degrades to static · safety gates unchanged even when early (dirty tree, not-green,
# stale telemetry) · exchange-in-flight wording · B-2 latch + used-delta re-arm · IDL extras.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/boundary-handoff.sh"
  export CC_TELEMETRY_DIR="$BATS_TEST_TMPDIR/tel"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BOUNDARY_LATCH_DIR="$BATS_TEST_TMPDIR/latch"
  export CC_CONTINUE_SENTINEL="$BATS_TEST_TMPDIR/no-such-sentinel"   # compose-guard bypass (not armed)
  mkdir -p "$CC_TELEMETRY_DIR"
  # a committed repo standing in for the session's cwd, marked gate-green at HEAD
  WD="$BATS_TEST_TMPDIR/wd"; mkdir -p "$WD"
  git -C "$WD" init -q
  git -C "$WD" config user.email t@t; git -C "$WD" config user.name t
  echo seed > "$WD/f.txt"; git -C "$WD" add -A; git -C "$WD" commit -qm init
  HEAD="$(git -C "$WD" rev-parse HEAD)"
  printf '%s' "$HEAD" > "$WD/.git/gate-green"
}

mk_btel() { # $1=sid $2=used_pct [$3=ts]
  jq -nc --arg sid "$1" --arg cwd "$WD" --argjson used "$2" --argjson ts "${3:-$(date +%s)}" \
    '{ts:$ts,session_id:$sid,cwd:$cwd,config_dir:"/cfg",used_pct:$used,input_tokens:1}' \
    > "$CC_TELEMETRY_DIR/$1.json"; }
mk_bhist() { # $1=sid $2=from $3=to $4=span_s — burn history ending NOW
  local now; now=$(date +%s)
  printf '%s %s 1\n%s %s 1\n' "$(( now - $4 ))" "$2" "$now" "$3" > "$CC_TELEMETRY_DIR/$1.hist"; }
iso_at() { date -u -r "$1" +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%S.000Z; }
mk_btx() { # $1=human-age-s → transcript path with one interactive turn
  local p="$BATS_TEST_TMPDIR/tx-${BATS_TEST_NUMBER}.jsonl"
  jq -nc --arg t "quick question — status?" --arg ts "$(iso_at $(( $(date +%s) - $1 )))" \
    '{type:"user",isMeta:null,userType:"external",message:{role:"user",content:$t},timestamp:$ts}' > "$p"
  printf '%s' "$p"; }
drive() { printf '{"session_id":"%s","transcript_path":"%s"}' "$1" "${2:-}" | bash "$HOOK"; }
fired() { echo "$1" | grep -q '"decision":"block"'; }

@test "static: 75% ≥ 73 at committed+green → fires the boundary advisory" {
  mk_btel b1 75
  run drive b1
  [ "$status" -eq 0 ]; fired "$output"
  echo "$output" | grep -q "75% ≥ 73%"
}
@test "static: 60% with no burn history → abstains below-threshold (unknown forecast = legacy)" {
  mk_btel b2 60
  run drive b2
  [ "$status" -eq 0 ]; [ -z "$output" ]
  grep -q "below-threshold:60<73" "$CC_IDL"
}
@test "forecast-early: 60% burning fast (≤LEAD_MIN to wall) → fires BELOW the static T with honest wording" {
  mk_btel b3 60
  mk_bhist b3 50 60 300              # +10/300s → burn_x100=200 → forecast (88-60)*100/200 = 14min
  run drive b3
  [ "$status" -eq 0 ]; fired "$output"
  echo "$output" | grep -q "BURNING"
  echo "$output" | grep -q "14min"
}
@test "forecast-early: the T_MIN floor holds — 50% burning fast still abstains" {
  mk_btel b4 50
  mk_bhist b4 40 50 300
  run drive b4
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "safety unchanged when early: dirty tree abstains even with a hot forecast" {
  mk_btel b5 60; mk_bhist b5 50 60 300
  echo dirt >> "$WD/f.txt"
  run drive b5
  [ "$status" -eq 0 ]; [ -z "$output" ]
  grep -q '"reason":"dirty-tree"' "$CC_IDL"
}
@test "safety unchanged: gate-not-green abstains at 75%" {
  printf 'stale-sha' > "$WD/.git/gate-green"
  mk_btel b6 75
  run drive b6
  [ "$status" -eq 0 ]; [ -z "$output" ]
  grep -q "gate-not-green" "$CC_IDL"
}
@test "safety unchanged: stale telemetry abstains" {
  mk_btel b7 75 "$(( $(date +%s) - 100000 ))"
  run drive b7
  [ "$status" -eq 0 ]; [ -z "$output" ]
  grep -q "stale-telemetry" "$CC_IDL"
}
@test "conversation-aware: exchange in flight → advisory STILL fires, wording says finish+persist first" {
  mk_btel b8 75
  run drive b8 "$(mk_btx 30)"
  [ "$status" -eq 0 ]; fired "$output"
  echo "$output" | grep -q "exchange is in flight"
  echo "$output" | grep -q "persist"
}
@test "conversation-aware: an OLD exchange adds no wording" {
  mk_btel b9 75
  export CC_BOUNDARY_CONV_S=100
  run drive b9 "$(mk_btx 2000)"
  [ "$status" -eq 0 ]; fired "$output"
  ! echo "$output" | grep -q "exchange is in flight"
}
@test "B-2 latch: same HEAD re-fires only after +REARM_DELTA fill (early fire stamps the same latch)" {
  mk_btel b10 60; mk_bhist b10 50 60 300
  run drive b10; fired "$output"                  # early fire at 60 stamps latch=60
  mk_btel b10 65; mk_bhist b10 55 65 300
  run drive b10; [ -z "$output" ]                 # +5 < 10 → latched
  grep -q '"reason":"latched:used=65,last=60' "$CC_IDL"
  mk_btel b10 71; mk_bhist b10 61 71 300
  run drive b10; fired "$output"                  # +11 ≥ 10 → re-advises
}
@test "observability: the fire record carries burn_x100/forecast_min/early/conv_age_s" {
  mk_btel b11 75
  run drive b11
  [ "$status" -eq 0 ]; fired "$output"
  tail -1 "$CC_IDL" | jq -e 'select(.reason=="past-boundary") | has("burn_x100") and has("forecast_min") and has("early") and has("conv_age_s")' >/dev/null
}
