#!/usr/bin/env bats
# research-kit-built-e2e — method v1.2, REPORT.md §11: Stage 9 end to end. The instruments
# (`cc-research built mutate|contact`), the built gate (`gate.sh built-run`, rows 20-25), the built
# certificate and the render were built as separate pieces over one record contract (RECORDS.md
# "Stage 9 records"). This suite proves the contract by execution: records WRITTEN by the real
# verbs are the ones the real rows READ, and a defect the verbs record turns its row FAIL.
#
# Fixture: the known-good built program (build_good.py, then build_built.py). Its hand-written
# mutation and contact records are deleted and re-made by the verbs; the soak (30 h of samples)
# and the reviewer rounds stay as the fixture wrote them.

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
  FX="$BATS_TEST_DIRNAME/fixtures/research-kit"
  "$FX/build_good.py" "$W" > "$BATS_FILE_TMPDIR/records-path"
  "$FX/build_built.py" "$W"
  REC="$(cat "$BATS_FILE_TMPDIR/records-path")"
  /usr/bin/python3 - "$REC" "$CC_RESEARCH_HOME/demo/built" "$CC_NOW" <<'PY'
import json, os, sys
rec, sealed, now = sys.argv[1:4]
# the acceptance check reads the built artifact; ten sealed mutants each break what it reads
acc = json.load(open(f"{rec}/acceptance.json"))
acc["rows"][0]["check_cmd"] = 'grep -q "echo ok" "$ARTIFACT/daemon.sh"'
json.dump(acc, open(f"{rec}/acceptance.json", "w"))
os.makedirs(sealed, exist_ok=True)
json.dump([{"id": f"M-{i}", "file": "daemon.sh", "search": "echo ok", "replace": f"echo bad-{i}"}
           for i in range(1, 11)], open(f"{sealed}/mutants.json", "w"))
# the skeleton probe gets the command it ran, as probe_run.py records it
open(f"{rec}/probes.jsonl", "a").write(json.dumps({"id": "P-3", "cmd": ["/bin/bash", "daemon.sh"]}) + "\n")
# a research certificate as gate.sh run writes it: issued, with the split forecast
cert = json.load(open(f"{rec}/cert/CERT-v1.json"))
cert.update(issued=now, changes_at_issue=[], forecast={
    "desk_mean": 6.0, "desk_n95": 9, "invisible_mean": 0.5, "invisible_bound95": 2,
    "before_impl_mean": 3.8, "after_impl_mean": 2.7, "after_impl_bound95": 11,
    "build_findable_share": 0.585},
    stop="dry", quiet_streak=2, rounds=2, profile="lite",
    fingerprint={"model": "m", "rules": "r", "memory": "x"},
    state={"decisions": 1, "populations": 1, "checks": 1, "premises_at_level": 1, "premises": 1,
           "sources": 1, "ruled_90": 1, "operator_ruled": 0, "by_default": [], "carried": [],
           "parked": 0, "frame_defects": 0, "unasked_intent": 0})
json.dump(cert, open(f"{rec}/cert/CERT-v1.json", "w"))
os.remove(f"{rec}/built/mutation.json")
os.remove(f"{rec}/built/contact.jsonl")
PY
  "$FX/build_built.py" "$W" resign
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
  export CC_RESEARCH_CALIBRATION="$W/calibration.jsonl"
  rsync -a --delete "$BATS_FILE_TMPDIR/golden/" "$W/"
  REC="$(cat "$BATS_FILE_TMPDIR/records-path")"
  OUT="$BATS_TEST_TMPDIR/rows.json"
}

rowstat() {
  /usr/bin/python3 -c "import json,sys; print([r['status'] for r in json.load(open(sys.argv[1])) if r['num'] == $1][0])" "$OUT"
}
state() { /usr/bin/python3 -c "import json; print(json.load(open('$CC_RESEARCH_REGISTRY'))['programs'][0]['state'])"; }
# instruments: the real verbs write the mutation and contact records.
instruments() {
  "$R" built mutate --program demo
  "$R" built contact --program demo --target P-3 --negative-control 'test -f missing.sh'
  "$R" built contact --program demo --target AM-1 --negative-control 'grep -q "echo ok" /dev/null'
}

@test "records written by the real verbs pass the built gate, which certifies and states both forecasts" {
  instruments
  run "$G" built-run --program demo
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -cE '^2[0-5]\. .* PASS$')" -eq 6 ]
  [[ "$output" == *"BUILD-CERTIFIED demo"* ]] || false
  [ "$(state)" = "build-certified" ]
  md="$REC/built/BUILT-CERT-v1.md"
  # 1 material finding with a repro and 1 fixed mutation finding in the fixture; no change since signoff
  grep -qx 'Before implementation signoff: 2 material changes observed (forecast about 3.8)' "$md"
  grep -q '^After implementation signoff: forecast about 0.2; at most 3 at 95% (mutant kill rate 10 of 10' "$md"
}

@test "render in build-certified relays the research certificate and the built one" {
  instruments
  "$G" built-run --program demo
  run "$G" render --program demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"Split: before implementation signoff about 3.8"* ]] || false
  [[ "$output" == *"Built: certified"*"BUILT-CERT-v1"* ]]
}

@test "without the instruments run, the gate fails rows 22 and 23 and certifies nothing" {
  run "$G" built-run --program demo --json
  [ "$status" -eq 1 ]
  printf '%s' "$output" > "$OUT"
  [ "$(rowstat 22)" = "FAIL" ]
  [ "$(rowstat 23)" = "FAIL" ]
  [ "$(rowstat 24)" = "PASS" ]
  [ "$(state)" = "build-certifying" ]
  [ -z "$(ls "$REC/built" | grep BUILT-CERT || true)" ]
}

@test "a mutant the harness misses, recorded by the verb, fails rows 21 and 22 until a harness row kills it" {
  /usr/bin/python3 -c "
import json; p='$CC_RESEARCH_HOME/demo/built/mutants.json'; m=json.load(open(p))
m.append({'id': 'M-11', 'file': 'daemon.sh', 'search': '#!/bin/bash', 'replace': '#!/bin/sh'})
json.dump(m, open(p, 'w'))"
  run "$R" built mutate --program demo
  [ "$status" -eq 1 ]
  "$R" built contact --program demo --target P-3 --no-negative-control "an inventory read"
  "$R" built contact --program demo --target AM-1 --no-negative-control "an inventory read"
  run "$G" built-run --program demo --json
  [ "$status" -eq 1 ]
  printf '%s' "$output" > "$OUT"
  [ "$(rowstat 21)" = "FAIL" ]
  [ "$(rowstat 22)" = "FAIL" ]
  # the harness fix: a second row that reads the interpreter line; the survivor's finding re-runs it
  /usr/bin/python3 -c "
import json; p='$REC/acceptance.json'; d=json.load(open(p))
d['rows'].append(dict(d['rows'][0], id='AM-2', check_cmd='head -1 \"\$ARTIFACT/daemon.sh\" | grep -qx \"#!/bin/bash\"'))
json.dump(d, open(p, 'w'))"
  fid="$(/usr/bin/python3 -c "
import json
print([json.loads(l) for l in open('$REC/built/findings.jsonl') if json.loads(l).get('mutant') == 'M-11'][0]['id'])")"
  run "$R" built finding fix --program demo --id "$fid"
  [ "$status" -eq 0 ]
  "$R" built contact --program demo --target AM-2 --no-negative-control "an inventory read"
  run "$G" built-run --program demo --json
  printf '%s' "$output" | /usr/bin/python3 -c "import json,sys; json.dump(json.JSONDecoder().raw_decode(sys.stdin.read())[0], open('$OUT','w'))"
  [ "$(rowstat 21)" = "PASS" ]
  [ "$(rowstat 22)" = "PASS" ]
}
