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
  # The ✅-ledger FREE-WIN arm is OFF by default here so each threshold/size case below stays a
  # function of the axis it names. The fixture repo is clean + landed — RUNG=✅ — so leaving the arm
  # live would make every ≥35% case fire on the LEDGER and silently re-label the size-axis reason:
  # the suite would still look green but would no longer test what its names claim. The arm has its
  # own tests, which enable it explicitly and assert the reason.
  export CC_BOUNDARY_T_FREEWIN=0
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

# ── SIZE AXIS (2026-07-29, K02 — hook header) ──────────────────────────────────────────────────────
# used_pct is the CONTEXT WINDOW's occupancy and compaction resets it; a transcript and a process
# footprint do not reset. Measured live, the largest transcript (22.4 MB) belonged to a session at 61%
# fill — below T=73, so this hook would never have advised it. Every case pins fill BELOW T so the
# legacy trigger cannot be what fires.
mk_tx_size() { # $1=MiB → a transcript file of at least $1 MiB (content irrelevant to the size axis;
               # the pad is STREAMED, never a jq --arg — 1 MiB of argv exceeds ARG_MAX)
  local p="$BATS_TEST_TMPDIR/txbig-${BATS_TEST_NUMBER}.jsonl"
  head -c $(( $1 * 1048576 )) /dev/zero | tr '\0' 'p' > "$p"
  printf '%s' "$p"; }
mk_btel_pid() { # $1=sid $2=used_pct $3=pid
  jq -nc --arg sid "$1" --arg cwd "$WD" --argjson used "$2" --argjson ts "$(date +%s)" --argjson pid "$3" \
    '{ts:$ts,session_id:$sid,cwd:$cwd,config_dir:"/cfg",used_pct:$used,input_tokens:1,pid:$pid}' \
    > "$CC_TELEMETRY_DIR/$1.json"; }
mk_ps_rss() { # $1=rss_kb → `ps` stub (right-aligned, as real ps emits) for a claude-looking comm
  local p="$BATS_TEST_TMPDIR/ps-${BATS_TEST_NUMBER}"
  printf '#!/bin/bash\nprintf "  %%s %%s\\n" "%s" "/usr/local/bin/claude"\n' "$1" > "$p"
  chmod +x "$p"; printf '%s' "$p"; }

@test "size: an OVERSIZE transcript fires at 40% — below T=73, where fill alone is silent" {
  export CC_BOUNDARY_SIZE_MB=1
  mk_btel s1 40
  run drive s1 "$(mk_tx_size 1)"
  [ "$status" -eq 0 ]; fired "$output"
  echo "$output" | grep -q "TRANSCRIPT is 1MB"
  echo "$output" | grep -q "only 40% context"
  echo "$output" | grep -q "only a NEW SESSION resets"
  tail -1 "$CC_IDL" | jq -e 'select(.reason=="past-boundary") | .axis=="size" and .over_size==true' >/dev/null
  # the control: same 40% fill, small transcript → silent
  rm -rf "$CC_BOUNDARY_LATCH_DIR"
  mk_btel s2 40
  run drive s2
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "size: high RSS fires the advisory here (no auto-exec in this hook) and names the RSS axis" {
  export CC_CE_PS="$(mk_ps_rss 1600000)"
  mk_btel_pid s3 40 4242
  run drive s3
  [ "$status" -eq 0 ]; fired "$output"
  echo "$output" | grep -q "PROCESS is at 1562MB RSS"
  tail -1 "$CC_IDL" | jq -e 'select(.reason=="past-boundary") | .over_rss==true and .axis=="size"' >/dev/null
}
@test "size: B-2 THIRD re-arm dimension — a size fire re-arms on transcript GROWTH, not only on fill" {
  # Without it: a size fire at flat fill on an unchanged HEAD satisfies neither the HEAD nor the
  # used_pct re-arm, so the latch goes silent FOREVER — B-2's own failure mode on a monotonic axis
  # where "the condition clears on its own" is never true.
  export CC_BOUNDARY_SIZE_MB=1 CC_BOUNDARY_SIZE_REARM_MB=2
  mk_btel s4 40
  run drive s4 "$(mk_tx_size 1)"; fired "$output"          # fires; latch records used=40 tx=1
  run drive s4 "$(mk_tx_size 1)"                            # same fill, same size → latched
  [ "$status" -eq 0 ]; [ -z "$output" ]
  grep -q 'last_tx=1MB,need=+2MB' "$CC_IDL"
  run drive s4 "$(mk_tx_size 3)"                            # +2 MB growth → re-arms at FLAT fill
  [ "$status" -eq 0 ]; fired "$output"
}
@test "size: a LEGACY one-field latch (pre-size, 'used' only) still parses — no flag day" {
  export CC_BOUNDARY_SIZE_MB=1
  mk_btel s5 75
  run drive s5; fired "$output"
  # rewrite the latch in the OLD single-value format the shipped hook wrote
  latch="$(ls "$CC_BOUNDARY_LATCH_DIR"/* | head -1)"; printf '75' > "$latch"
  mk_btel s5 78
  run drive s5                                              # +3 < 10 and no size growth → latched
  [ "$status" -eq 0 ]; [ -z "$output" ]
  grep -q 'latched:used=78,last=75' "$CC_IDL"
  mk_btel s5 88
  run drive s5; fired "$output"                             # +13 ≥ 10 → fill re-arm still works
}
@test "size: the axis never bypasses the safety gates — dirty tree / not-green still abstain" {
  export CC_BOUNDARY_SIZE_MB=1
  echo dirt > "$WD/dirty.txt"
  mk_btel s6 40
  run drive s6 "$(mk_tx_size 1)"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  grep -q '"reason":"dirty-tree"' "$CC_IDL"
  git -C "$WD" checkout -- . 2>/dev/null; rm -f "$WD/dirty.txt"
  printf 'not-the-head' > "$WD/.git/gate-green"
  run drive s6 "$(mk_tx_size 1)"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  grep -q '"reason":"gate-not-green-at-head"' "$CC_IDL"
}
@test "size: both bars at 0 disable the axis, and the abstain still RECORDS what it measured" {
  export CC_BOUNDARY_SIZE_MB=0 CC_BOUNDARY_RSS_MB=0
  mk_btel s7 40
  run drive s7 "$(mk_tx_size 1)"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  # silence alone is also what a hook with no size axis produces — assert it was EVALUATED-and-disabled
  tail -1 "$CC_IDL" | jq -e 'select(.disposition=="abstained")
      | .size_mb_t==0 and .rss_mb_t==0 and .tx_mb>=1' >/dev/null
}

# ── ✅-LEDGER FREE-WIN ARM ────────────────────────────────────────────────────────────────────────
# CLAUDE.md § Context Stewardship: "Idle at ≥~35% fill is a FREE WIN: recycle now." Nothing
# implemented it. waiting-recycle.sh owns T_IDLE=35 but runs on PostToolUse:Bash — an idle pane
# issues no Bash, so the hook with the right threshold never executes in the state it exists for.
# This hook runs at Stop, the moment a session is about to go quiet, but its threshold was 73: on the
# session the operator watched sit idle it abstained below-threshold:41<73, 42<73, 43<73. The arm
# fires here only when the LEDGER says ✅ — clean · landed · no DoD remainder · no filed operator
# step — which is the mechanical form of "everything of value is already on disk".
@test "free-win: 43% with a ✅ ledger → FIRES (the idle case that abstained 41/42/43 < 73)" {
  export CC_BOUNDARY_T_FREEWIN=35
  mk_btel fw1 43
  run drive fw1
  [ "$status" -eq 0 ]; fired "$output"
}
@test "free-win: 34% is below the floor → still abstains (the floor is real)" {
  export CC_BOUNDARY_T_FREEWIN=35
  mk_btel fw2 34
  run drive fw2
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
# The guard that makes this safe: work in hand must never be cut. A dirty tree yields RUNG=🔧, so
# the arm stays silent even well above the floor.
@test "free-win: 43% but a DIRTY tree (RUNG=🔧) → SILENT, never cuts work in hand" {
  export CC_BOUNDARY_T_FREEWIN=35
  echo uncommitted > "$WD/dirty.txt"
  mk_btel fw3 43
  run drive fw3
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "free-win: the arm is off by default at 0 → legacy below-threshold behaviour preserved" {
  export CC_BOUNDARY_T_FREEWIN=0
  mk_btel fw4 43
  run drive fw4
  [ "$status" -eq 0 ]; [ -z "$output" ]
  grep -q 'below-threshold:43<73' "$CC_IDL"
}
