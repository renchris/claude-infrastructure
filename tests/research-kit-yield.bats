#!/usr/bin/env bats
# research-kit-yield — method v1.2, REPORT.md §12.1: stages 3 (contact) and 5 (the build-to-learn
# skeleton) end on YIELD, not on the stage clock. K consecutive quiet probes end the stage, unless
# measured finds per day x the intake escape cost is above 1; the hard ceilings stay.
#
# Covers lib/yield_stop.py (the one rule), `cc-research yield show|find`, the `budget end` refusal
# and gate row 18. Every case plants ONE probe history into the known-good program
# (tests/fixtures/research-kit/build_good.py, lite profile: K = 3, window 6 probes, stage 3 ceiling
# 3 days) and asserts the verdict. Times are hours before the suite's fixed CC_NOW.

setup_file() {
  export HOME="$BATS_FILE_TMPDIR/home"
  mkdir -p "$HOME"
  export W="$BATS_FILE_TMPDIR/w"
  export CC_RESEARCH_HOME="$W/home" CC_RESEARCH_REGISTRY="$W/home/programs.json"
  CC_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "$CC_NOW" > "$BATS_FILE_TMPDIR/now"
  export CC_NOW CC_RESEARCH_VAULT_KEY="test-key"
  export CC_DECISIONS_DIR="$W/decisions" CC_IDL="$W/idl.jsonl"
  mkdir -p "$W"
  "$BATS_TEST_DIRNAME/fixtures/research-kit/build_good.py" "$W" > "$BATS_FILE_TMPDIR/records-path"
  cp -Rp "$W" "$BATS_FILE_TMPDIR/golden"
}

setup() {
  export HOME="$BATS_FILE_TMPDIR/home"
  mkdir -p "$HOME"
  unset CC_BATS_ACTIVE CC_RESEARCH_RECORDS
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  G="$REPO/scripts/research-kit/gate.sh"
  R="$REPO/bin/cc-research"
  export W="$BATS_FILE_TMPDIR/w"
  export CC_RESEARCH_HOME="$W/home" CC_RESEARCH_REGISTRY="$W/home/programs.json"
  CC_NOW="$(cat "$BATS_FILE_TMPDIR/now")"
  export CC_NOW CC_RESEARCH_VAULT_KEY="test-key"
  export CC_DECISIONS_DIR="$W/decisions" CC_IDL="$W/idl.jsonl"
  export CC_RESEARCH_ROUTER="$W/router.sh"
  export CC_RESEARCH_CALIBRATION="$W/calibration.jsonl"
  rsync -a --delete "$BATS_FILE_TMPDIR/golden/" "$W/"
  REC="$(cat "$BATS_FILE_TMPDIR/records-path")"
  jedit frame.json "d['method_version']='1.2'; d['escape_cost_days']=3"
}

jedit() {
  /usr/bin/python3 -c "import json; p='$REC/$1'; d=json.load(open(p)); $2; json.dump(d, open(p, 'w'))"
}
rowstat() {
  "$G" run --program demo --consent-sealed-read --json 2>/dev/null | /usr/bin/python3 -c "import json,sys; print([r['status'] for r in json.load(sys.stdin) if r['num'] == $1][0])"
}
rowtext() {
  "$G" run --program demo --consent-sealed-read --json 2>/dev/null | /usr/bin/python3 -c "import json,sys; print('\n'.join([r for r in json.load(sys.stdin) if r['num'] == $1][0]['evidence']))"
}
field() { /usr/bin/python3 -c "import json,sys; print(json.load(sys.stdin)['$1'])"; }

# plant "<stage>:<started h ago>:<ended h ago|->:<probe>,<probe>…" …
# Replaces probes.jsonl, yield.jsonl and the stage windows. A probe is a letter and its age in
# hours: q quiet (passed, could fail) · f failed, unexplained · u passed but could not fail ·
# n passed and tied to a hole by yield.jsonl (a named find).
plant() {
  /usr/bin/python3 - "$REC" "$CC_NOW" "$@" <<'PY'
import calendar, json, sys, time
rec, now = sys.argv[1], calendar.timegm(time.strptime(sys.argv[2], "%Y-%m-%dT%H:%M:%SZ"))
iso = lambda h: time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now - float(h) * 3600))
probes, finds, n = [], [], 0
budget = json.load(open(f"{rec}/budget.json"))
for spec in sys.argv[3:]:
    stage, start, end, items = spec.split(":")
    budget["stages"][stage] = {"started": iso(start), "ended": None if end == "-" else iso(end)}
    for it in filter(None, items.split(",")):
        n += 1
        kind, age = it[0], it[1:]
        nc = {"ran": True, "reported_refutation": True}
        if kind == "u":
            nc = {"ran": False, "reason_if_not_run": None}
        probes.append({"id": f"Y-{n}", "kind": "spike", "env": {"id": "agent-shell"}, "closes": [],
                       "exit": 1 if kind == "f" else 0, "n": 1, "negative_control": nc,
                       "at": iso(age)})
        if kind == "n":
            finds.append({"probe": f"Y-{n}", "ref": "H-planted", "ref_kind": "hole",
                          "stage": int(stage), "at": iso(age)})
dump = lambda rows: "".join(json.dumps(r) + "\n" for r in rows)
open(f"{rec}/probes.jsonl", "w").write(dump(probes))
open(f"{rec}/yield.jsonl", "w").write(dump(finds))
json.dump(budget, open(f"{rec}/budget.json", "w"))
PY
}

@test "K quiet probes in a row stop the stage; K minus one do not" {
  plant "3:40:-:q30,q29,q28"
  run "$R" yield show --program demo --stage 3 --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | field verdict)" = "stop" ]
  [ "$(printf '%s' "$output" | field streak)" = "3" ]
  plant "3:40:-:q30,q29"
  run "$R" yield show --program demo --stage 3 --json
  [ "$status" -eq 1 ]
  [ "$(printf '%s' "$output" | field verdict)" = "continue" ]
}

@test "the escape cost is read: K quiet probes after a recent find keep going while finds per day x escape cost is above 1" {
  # one find 5 h ago, then 3 quiet: 1 find over a 3 h window = 8 per day
  plant "3:40:-:n5,q4,q3,q2"
  run "$R" yield show --program demo --stage 3 --json
  [ "$status" -eq 1 ]
  [ "$(printf '%s' "$output" | field verdict)" = "continue" ]
  [ "$(printf '%s' "$output" | field voi)" = "24.0" ]
  jedit frame.json "d['escape_cost_days']=0.1"
  run "$R" yield show --program demo --stage 3 --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | field verdict)" = "stop" ]
}

@test "a probe that could not fail is not counted as quiet" {
  plant "3:40:-:q30,q29,u28"
  run "$R" yield show --program demo --stage 3 --json
  [ "$status" -eq 1 ]
  [ "$(printf '%s' "$output" | field counted)" = "2" ]
  [ "$(printf '%s' "$output" | field streak)" = "2" ]
}

@test "a failed probe nobody has explained counts as a find and resets the quiet streak" {
  plant "3:40:-:q30,q29,q28,f27"
  run "$R" yield show --program demo --stage 3 --json
  [ "$status" -eq 1 ]
  [ "$(printf '%s' "$output" | field streak)" = "0" ]
  [ "$(printf '%s' "$output" | field finds)" = "1" ]
}

@test "the day ceiling ends the stage even while yield is high" {
  # lite stage 3: 0.75 d budget x 4 = 3 d; this stage has run 80 h and just found something
  plant "3:80:-:f2,f1"
  run "$R" yield show --program demo --stage 3 --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | field verdict)" = "ceiling" ]
  [ "$(printf '%s' "$output" | field ceiling)" = "days" ]
}

@test "the probe ceiling ends the stage at 60 counted probes" {
  spec="$(/usr/bin/python3 -c "print(','.join(f'f{10 - i * 0.1:.1f}' for i in range(60)))")"
  plant "3:12:-:$spec"
  run "$R" yield show --program demo --stage 3 --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | field ceiling)" = "probes" ]
  plant "3:12:-:${spec%,*}"
  run "$R" yield show --program demo --stage 3 --json
  [ "$status" -eq 1 ]
  [ "$(printf '%s' "$output" | field verdict)" = "continue" ]
}

@test "yield show refuses a stage that does not stop on yield, and one that never started" {
  plant "3:40:-:q30"
  run "$R" yield show --program demo --stage 4
  [ "$status" -eq 2 ]
  [[ "$output" == *"does not stop on yield"* ]] || false
  run "$R" yield show --program demo --stage 5
  [ "$status" -eq 2 ]
  [[ "$output" == *"never started"* ]]
}

@test "a missing escape cost refuses the rule instead of reading as zero" {
  plant "3:40:-:q30,q29,q28"
  jedit frame.json "d['escape_cost_days']=None"
  run "$R" yield show --program demo --stage 3
  [ "$status" -eq 2 ]
  [[ "$output" == *"escape_cost_days"* ]]
}

@test "yield find ties a probe to the hole it produced, and the probe then counts as a find" {
  plant "3:40:-:q30,q29,q28"
  hole="$(/usr/bin/python3 -c "import json; print(json.loads(open('$REC/holes.jsonl').readline())['id'])")"
  run "$R" yield find --program demo --probe Y-3 --ref "$hole"
  [ "$status" -eq 0 ]
  [ "$(/usr/bin/python3 -c "import json; print(json.loads(open('$REC/yield.jsonl').readline())['ref_kind'])")" = "hole" ]
  run "$R" yield show --program demo --stage 3 --json
  [ "$status" -eq 1 ]
  [ "$(printf '%s' "$output" | field streak)" = "0" ]
}

@test "yield find refuses an unknown probe, an unknown ref, and a premise that was not refuted" {
  plant "3:40:-:q30"
  run "$R" yield find --program demo --probe P-nope --ref H-1
  [ "$status" -eq 2 ]
  [[ "$output" == *"no probe P-nope"* ]] || false
  run "$R" yield find --program demo --probe Y-1 --ref NOPE-1
  [ "$status" -eq 2 ]
  [[ "$output" == *"names the record the probe produced"* ]] || false
  prem="$(/usr/bin/python3 -c "import json; print(json.loads(open('$REC/premises.jsonl').readline())['id'])")"
  run "$R" yield find --program demo --probe Y-1 --ref "$prem"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not 'refuted'"* ]] || false
  [ ! -s "$REC/yield.jsonl" ]
}

@test "budget end refuses to end stage 3 while the rule says continue, and names the numbers" {
  plant "3:40:-:q30,q29"
  run "$R" budget end --program demo --stage 3
  [ "$status" -eq 2 ]
  [[ "$output" == *"stage 3 cannot end yet"* ]] || false
  [[ "$output" == *"2 quiet in a row of 3 needed"* ]] || false
  [ "$(/usr/bin/python3 -c "import json; print(json.load(open('$REC/budget.json'))['stages']['3']['ended'])")" = "None" ]
}

@test "budget end ends a quiet stage and records why it stopped" {
  plant "3:40:-:q30,q29,q28"
  run "$R" budget end --program demo --stage 3
  [ "$status" -eq 0 ]
  [ "$(/usr/bin/python3 -c "import json; s=json.load(open('$REC/budget.json'))['stages']['3']; print(s['stop']['reason'], s['stop']['streak'], bool(s['ended']))")" = "quiet 3 True" ]
}

@test "budget end at the ceiling ends the stage with the ceiling as the reason" {
  plant "3:80:-:f2,f1"
  run "$R" budget end --program demo --stage 3
  [ "$status" -eq 0 ]
  [ "$(/usr/bin/python3 -c "import json; s=json.load(open('$REC/budget.json'))['stages']['3']['stop']; print(s['reason'], s['ceiling'])")" = "ceiling days" ]
}

@test "under a 1.1 frame budget end keeps the stage clock: no refusal and no stop record" {
  plant "3:40:-:q30,q29"
  jedit frame.json "d.pop('method_version')"
  run "$R" budget end --program demo --stage 3
  [ "$status" -eq 0 ]
  [ "$(/usr/bin/python3 -c "import json; print('stop' in json.load(open('$REC/budget.json'))['stages']['3'])")" = "False" ]
}

@test "row 18: both stages ended quiet passes" {
  plant "3:40:20:q30,q29,q28" "5:19:1:q10,q9,q8"
  [ "$(rowstat 18)" = "PASS" ]
  [[ "$(rowtext 18)" == *"stage 5: stop: the stage is quiet"* ]]
}

@test "row 18: a stage that has not ended fails" {
  plant "3:40:20:q30,q29,q28" "5:19:-:q10,q9,q8"
  [ "$(rowstat 18)" = "FAIL" ]
  [[ "$(rowtext 18)" == *"stage 5 has not ended"* ]]
}

@test "row 18: a stage ended by hand while the rule said continue fails" {
  plant "3:40:20:q30,q29" "5:19:1:q10,q9,q8"
  [ "$(rowstat 18)" = "FAIL" ]
  [[ "$(rowtext 18)" == *"stage 3 was ended while the yield rule said continue"* ]]
}

@test "row 18: a missing escape cost fails" {
  plant "3:40:20:q30,q29,q28" "5:19:1:q10,q9,q8"
  jedit frame.json "d['escape_cost_days']=None"
  [ "$(rowstat 18)" = "FAIL" ]
  [[ "$(rowtext 18)" == *"escape_cost_days"* ]]
}

@test "row 18: a stage that stopped at the ceiling passes and says so" {
  plant "3:100:20:f22,f21" "5:19:1:q10,q9,q8"
  [ "$(rowstat 18)" = "PASS" ]
  [[ "$(rowtext 18)" == *"stage 3 stopped at the ceiling (days)"* ]]
}

@test "row 18: a frame signed under method 1.1 is not applicable" {
  plant "3:40:-:q30"
  jedit frame.json "d.pop('method_version')"
  [ "$(rowstat 18)" = "PASS" ]
  [[ "$(rowtext 18)" == *"not applicable"* ]]
}
