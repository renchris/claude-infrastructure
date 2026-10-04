#!/usr/bin/env bats
# research-kit-estimate — scripts/research-kit/estimate.py (REPORT.md §3.8 stop rule, §3.12). The port
# must reproduce the published model's table, and the forecast must read only counted rounds.

setup() {
  unset CC_BATS_ACTIVE
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  E="$REPO/scripts/research-kit/estimate.py"
  export CC_RESEARCH_HOME="$BATS_TEST_TMPDIR/research"
  export CC_RESEARCH_REGISTRY="$CC_RESEARCH_HOME/programs.json"
  export CC_RESEARCH_RECORDS="$BATS_TEST_TMPDIR/records"
  mkdir -p "$CC_RESEARCH_RECORDS/rounds"
}

mat() { # <n> <counted> <quiet> <new_material>
  mkdir -p "$CC_RESEARCH_RECORDS/rounds/$1"
  printf '{"round":"%s","seq":%s,"kind":"certification","counted":%s,"quiet":%s,"new_material":%s,"closed":true,"forecast":%s}\n' \
    "$1" "$1" "$2" "$3" "$4" "$([ "$1" = 1 ] && echo '{"p50":5,"p90":6}' || echo null)" > "$CC_RESEARCH_RECORDS/rounds/$1/matrix.json"
}
stop_of() { /usr/bin/python3 -c "import json,sys; print(json.loads(sys.stdin.read())['stop'])"; }
matx() { # <n> <new_material> <seeds-json>: a counted, non-quiet certification round carrying seed counts
  mkdir -p "$CC_RESEARCH_RECORDS/rounds/$1"
  printf '{"round":"%s","seq":%s,"kind":"certification","counted":true,"quiet":false,"new_material":%s,"closed":true,"forecast":{"p50":5,"p90":6},"seeds":%s}\n' \
    "$1" "$1" "$2" "$3" > "$CC_RESEARCH_RECORDS/rounds/$1/matrix.json"
}
hole() { # <id> <round> <CONFIRMED|REFUTED> <born_in_edit>: one MATERIAL hole event
  printf '{"id":"%s","event":"rate","round":%s,"verification":{"status":"%s"},"materiality":{"level":"MATERIAL"},"seed_match":null,"born_in_edit":%s}\n' \
    "$1" "$2" "$3" "$4" >> "$CC_RESEARCH_RECORDS/holes.jsonl"
}
fld() { /usr/bin/python3 -c "import json,sys; print(json.loads(sys.argv[1])[sys.argv[2]])" "$1" "$2"; }
lt() { /usr/bin/python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) < float(sys.argv[2]) else 1)" "$1" "$2"; }

@test "simulate --published reproduces profile_sim.out exactly (lite base, 10 holes at freeze)" {
  run "$E" simulate --profile lite --n0 10 --published
  [ "$status" -eq 0 ]
  [ "$output" = '{"cap_pct": 21.8, "desk_left": 1.43, "invisible_left": 0.54, "n0": 10, "p_any": 0.83, "profile": "lite", "regime": "base", "reps": 500, "rounds_p50": 5, "rounds_p90": 6, "take_back_pct": 1.2}' ]
}

@test "three quiet counted rounds after a finding round stop a standard program dry" {
  printf '{"profile":"standard"}\n' > "$CC_RESEARCH_RECORDS/frame.json"
  mat 1 true false 4; mat 2 true true 0; mat 3 true true 0; mat 4 true true 0
  [ "$("$E" forecast --program demo | stop_of)" = "dry" ]
}

@test "a program still finding holes keeps running" {
  printf '{"profile":"standard"}\n' > "$CC_RESEARCH_RECORDS/frame.json"
  mat 1 true false 4; mat 2 true true 0; mat 3 true false 1; mat 4 true true 0
  [ "$("$E" forecast --program demo | stop_of)" = "running" ]
}

@test "an uncounted round (dead lane) neither counts as quiet nor breaks the streak" {
  printf '{"profile":"standard"}\n' > "$CC_RESEARCH_RECORDS/frame.json"
  mat 1 true false 4; mat 2 true true 0; mat 3 true true 0; mat 4 false true 0
  [ "$("$E" forecast --program demo | stop_of)" = "running" ]
  mat 5 true true 0
  [ "$("$E" forecast --program demo | stop_of)" = "dry" ]
}

@test "reaching R_max stops at the cap" {
  printf '{"profile":"lite"}\n' > "$CC_RESEARCH_RECORDS/frame.json"
  for i in 1 2 3 4 5 6; do mat "$i" true false 1; done
  [ "$("$E" forecast --program demo | stop_of)" = "cap" ]
}

@test "no counted round, or no profile, is a refusal and never a forecast" {
  printf '{"profile":"lite"}\n' > "$CC_RESEARCH_RECORDS/frame.json"
  run "$E" forecast --program demo
  [ "$status" -eq 2 ]
  printf '{}\n' > "$CC_RESEARCH_RECORDS/frame.json"
  mat 1 true false 2
  run "$E" forecast --program demo
  [ "$status" -eq 2 ]
}

@test "found is deflated by the program's own false-material share, and the bound does not rise" {
  printf '{"profile":"standard"}\n' > "$CC_RESEARCH_RECORDS/frame.json"
  matx 1 4 '{"original":{"s_eff":10,"k_left":3},"shadow":{"s_eff":0,"k_left":0}}'
  run "$E" forecast --program demo
  [ "$status" -eq 0 ]
  [ "$(fld "$output" false_material_source)" = "calibration" ]
  lt "$(fld "$output" found)" "$(fld "$output" found_raw)"
  for i in 1 2 3 4; do hole "H-$i" 1 CONFIRMED false; done
  run "$E" forecast --program demo
  [ "$status" -eq 0 ]
  a="$output"
  [ "$(fld "$a" false_material_source)" = "program" ]
  [ "$(fld "$a" found)" = "4.0" ]
  for i in 5 6 7 8; do hole "H-$i" 1 REFUTED false; done
  run "$E" forecast --program demo
  [ "$status" -eq 0 ]
  b="$output"
  [ "$(fld "$b" found_raw)" = "4" ]
  [ "$(fld "$b" false_material_share)" = "0.5" ]
  [ "$(fld "$b" found)" = "2.0" ]
  lt "$(fld "$b" desk_n95)" "$(( $(fld "$a" desk_n95) + 1 ))"
}

@test "the shadow stratum draws from its own found count, not from zero" {
  printf '{"profile":"standard"}\n' > "$CC_RESEARCH_RECORDS/frame.json"
  matx 1 4 '{"original":{"s_eff":10,"k_left":3},"shadow":{"s_eff":4,"k_left":1}}'
  for i in 1 2 3 4; do hole "H-$i" 1 CONFIRMED false; done
  run "$E" forecast --program demo
  [ "$status" -eq 0 ]
  a="$output"
  [ "$(fld "$a" found_shadow)" = "0" ]
  hole H-1 1 CONFIRMED true; hole H-2 1 CONFIRMED true
  run "$E" forecast --program demo
  [ "$status" -eq 0 ]
  b="$output"
  [ "$(fld "$b" found_shadow)" = "2" ]
  lt "$(fld "$a" desk_shadow_mean)" "$(fld "$b" desk_shadow_mean)"
}

@test "the invisible bound uses the measured u_hi and rises over the old assumed 0.2" {
  printf '{"profile":"standard"}\n' > "$CC_RESEARCH_RECORDS/frame.json"
  matx 1 40 '{"original":{"s_eff":10,"k_left":3},"shadow":{"s_eff":0,"k_left":0}}'
  run "$E" forecast --program demo
  [ "$status" -eq 0 ]
  out="$output"
  # control: the pre-fix U_HI, pinned here so the comparison never follows the constant
  ctrl="$(/usr/bin/python3 -c "import sys; sys.path[:0]=[sys.argv[1], sys.argv[1]+'/lib']; import estimate; u=0.2; print(estimate.poisson_q95(float(sys.argv[2])*u/(1-u)))" "$REPO/scripts/research-kit" "$(fld "$out" n_hat)")"
  lt "$ctrl" "$(fld "$out" invisible_bound95)"
  [[ "$(fld "$out" measured)" == *"u_hi"* ]]
  [[ "$(fld "$out" assumed)" != *"0.2 (share assumed)"* ]]
}

@test "calibration prints coverage, bound sharpness and rank skill over a replay file" {
  f="$BATS_TEST_TMPDIR/cal.jsonl"
  printf '%s\n' \
    '{"plan":"a","forecast_point":2,"forecast_95":10,"realized_desk_missed":5}' \
    '{"plan":"b","forecast_point":4,"forecast_95":20,"realized_desk_missed":25}' \
    '{"plan":"c","forecast_point":6,"forecast_95":30,"realized_desk_missed":0}' \
    '{"plan":"d","forecast_point":8,"forecast_95":40,"realized_desk_missed":30}' > "$f"
  run "$E" calibration --file "$f"
  [ "$status" -eq 0 ]
  [ "$(fld "$output" rows)" = "4" ]
  [ "$(fld "$output" coverage)" = "0.75" ]
  [ "$(fld "$output" sharpness_median)" = "1.333" ]
  [ "$(fld "$output" realized_zero)" = "1" ]
  [ "$(fld "$output" spearman)" = "0.4" ]
}
