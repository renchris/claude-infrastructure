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

@test "simulate reproduces profile_sim.out exactly (lite base, 10 holes at freeze)" {
  run "$E" simulate --profile lite --n0 10
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
