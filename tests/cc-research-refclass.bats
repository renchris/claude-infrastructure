#!/usr/bin/env bats
# cc-research-refclass — bin/cc-research reference-class record | show | check (REPORT.md §8 item 15,
# §6.3): research time per project type, measured, and the 3x check a program's typical total is
# held to. The committed store is seeded from evidence/internal/greenfield-cases.md:29-36; every
# test below except the seed one writes only to a planted store under $BATS_FILE_TMPDIR.

setup_file() {
  export HOME="$BATS_FILE_TMPDIR/home"
  mkdir -p "$HOME"
}

setup() {
  export HOME="$BATS_FILE_TMPDIR/home"
  mkdir -p "$HOME"
  unset CC_BATS_ACTIVE
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CR="$REPO/bin/cc-research"
  export CC_RESEARCH_HOME="$BATS_TEST_TMPDIR/home-research"
  export CC_RESEARCH_REGISTRY="$CC_RESEARCH_HOME/programs.json"
  export CC_RESEARCH_RECORDS="$BATS_TEST_TMPDIR/records"
  export CC_RESEARCH_REFCLASS="$BATS_TEST_TMPDIR/refclass.jsonl"
  export CC_NOW="2026-10-01T12:00:00Z"
  mkdir -p "$CC_RESEARCH_RECORDS/cert"
}

# plant <project_type or ""> : a finished program — stages 1-6 span 09-21 to 09-25T12 (4.5 days),
# stage 7 still running, certificate v1.
plant() {
  /usr/bin/python3 - "$1" <<'PY'
import json, os, sys
rec = os.environ["CC_RESEARCH_RECORDS"]
frame = {"program": "demo"}
if sys.argv[1]:
    frame["project_type"] = sys.argv[1]
json.dump(frame, open(f"{rec}/frame.json", "w"))
st = {str(i): {"started": f"2026-09-2{i}T00:00:00Z", "ended": f"2026-09-2{i}T12:00:00Z"} for i in range(1, 6)}
st["6"] = {"started": "2026-09-23T00:00:00Z", "ended": "2026-09-24T00:00:00Z"}
st["7"] = {"started": "2026-09-30T00:00:00Z", "ended": None}
json.dump({"stages": st}, open(f"{rec}/budget.json", "w"))
json.dump({"version": 1}, open(f"{rec}/cert/CERT-v1.json", "w"))
PY
}
rows() { if [ -f "$CC_RESEARCH_REFCLASS" ]; then grep -c . "$CC_RESEARCH_REFCLASS"; else echo 0; fi; }
seedtype() { # <type> <research_days>…: append one planted reference row per figure
  local t="$1"; shift
  for d in "$@"; do
    printf '{"case":"c%s","project_type":"%s","research_days":%s,"active_days":null,"source":"test","recorded_at":"x"}\n' \
      "$d" "$t" "$d" >> "$CC_RESEARCH_REFCLASS"
  done
}

@test "record refuses a program whose frame names no project_type" {
  plant ""
  run "$CR" reference-class record --program demo
  [ "$status" -eq 2 ]
  [[ "$output" == *"project_type"* ]]
  [ "$(rows)" -eq 0 ]
}

@test "record appends the research span of stages 1-6 and the certificate version, once" {
  plant tool
  run "$CR" reference-class record --program demo
  [ "$status" -eq 0 ]
  /usr/bin/python3 -c "
import json; r = json.loads(open('$CC_RESEARCH_REFCLASS').read())
assert r['program'] == 'demo' and r['project_type'] == 'tool', r
assert r['research_days'] == 4.5 and r['active_days'] is None, r
assert r['cert_version'] == 1 and r['recorded_at'] == '$CC_NOW', r
assert r['source'].endswith('budget.json'), r"
  run "$CR" reference-class record --program demo
  [ "$status" -eq 0 ]
  [ "$(rows)" -eq 1 ]
  printf '{"version": 2}\n' > "$CC_RESEARCH_RECORDS/cert/CERT-v2.json"
  run "$CR" reference-class record --program demo
  [ "$status" -eq 0 ]
  [ "$(rows)" -eq 2 ]
}

@test "record refuses a program with no certificate" {
  plant tool
  rm "$CC_RESEARCH_RECORDS/cert/CERT-v1.json"
  run "$CR" reference-class record --program demo
  [ "$status" -eq 2 ]
  [[ "$output" == *"no certificate"* ]]
  [ "$(rows)" -eq 0 ]
}

@test "show gives n, median and max research days per type" {
  seedtype tool 1 2 9
  seedtype site 4 6
  run "$CR" reference-class show --type tool
  [ "$status" -eq 0 ]
  [[ "$output" == *"tool"*"n=3"*"median=2"*"max=9"* ]]
  [[ "$output" != *"site"* ]]
  run "$CR" reference-class show --json
  /usr/bin/python3 -c "
import json, sys
d = {t['project_type']: t for t in json.loads(sys.argv[1])['types']}
assert d['site']['n'] == 2 and d['site']['median_days'] == 5 and d['site']['max_days'] == 6, d" "$output"
}

@test "check exits 1 above 3x the type's median and prints both figures" {
  seedtype tool 1 2 9
  run "$CR" reference-class check --type tool --typical-days 6.5
  [ "$status" -eq 1 ]
  [[ "$output" == *"6.5"* ]]
  [[ "$output" == *"median 2"* ]]
}

@test "check exits 0 at or below 3x the median" {
  seedtype tool 1 2 9
  run "$CR" reference-class check --type tool --typical-days 6
  [ "$status" -eq 0 ]
  run "$CR" reference-class check --type tool --typical-days 2 --json
  [ "$status" -eq 0 ]
  /usr/bin/python3 -c "
import json, sys
d = json.loads(sys.argv[1])
assert d['over'] is False and d['median_days'] == 2 and d['limit_days'] == 6, d" "$output"
}

@test "check on a type with no reference rows is uncalibrated and exits 0" {
  seedtype tool 1 2 9
  run "$CR" reference-class check --type robot --typical-days 40
  [ "$status" -eq 0 ]
  [[ "$output" == *"uncalibrated: no reference class for robot"* ]]
}

@test "the committed store carries the measured greenfield cases, each citing its table line" {
  unset CC_RESEARCH_REFCLASS
  run "$CR" reference-class show --type greenfield --json
  [ "$status" -eq 0 ]
  /usr/bin/python3 -c "
import json, sys
t = json.loads(sys.argv[1])['types'][0]
assert t['project_type'] == 'greenfield' and t['n'] == 8 and t['median_days'] == 1.5, t" "$output"
  /usr/bin/python3 -c "
import json
rows = [json.loads(l) for l in open('$REPO/docs/research/research-reference-class.jsonl')]
src = sorted(r['source'] for r in rows)
assert src == ['docs/research/upfront-research-exhaustion-2026-09-30/evidence/internal/greenfield-cases.md:%d' % n for n in range(29, 37)], src"
}
