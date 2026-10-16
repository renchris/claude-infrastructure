#!/usr/bin/env bats
# research-program-frame-delta — `intake.py delta-apply` (scripts/research-kit/lib/frame_delta.py), the
# sanctioned writer of a frame-delta cycle's rows (REPORT.md §5.4 step 1; RECORDS.md "Frame deltas").
# Before it, `intake.py set` wrote only scalars and `known_rows_applied`, so applying a drafted delta
# meant hand-editing frame.json or re-running a program's generator over weeks of records. Contracts:
#   - a clean apply writes the rows, bumps the version, lists the known rows and appends the delta,
#     the replaced row's old text included, to frame-deltas.jsonl; --dry-run writes nothing;
#   - every refusal (exit 2) leaves frame.json and acceptance.json byte-identical and records nothing,
#     and its message names the guard that fired, so a case refused by another guard fails;
#   - the apply is not the evidence: until the operator re-signs, gate.delta_signature finds none and
#     the sweep closes the row by its default; after the re-sign it spares it.
# RED-proof (2026-10-16): on the pre-change intake.py every case fails; the verb does not exist, and
# argparse's exit 2 ("invalid choice") matches no case's message.

setup_file() {
  export HOME="$BATS_FILE_TMPDIR/home"
  mkdir -p "$HOME"
  export W="$BATS_FILE_TMPDIR/w"
  export CC_RESEARCH_HOME="$W/home" CC_RESEARCH_REGISTRY="$W/home/programs.json"
  CC_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "$CC_NOW" > "$BATS_FILE_TMPDIR/now"
  export CC_NOW CC_RESEARCH_VAULT_KEY="test-key"
  mkdir -p "$W"
  "$BATS_TEST_DIRNAME/fixtures/research-kit/build_good.py" "$W" > "$BATS_FILE_TMPDIR/records-path"
  cp -Rp "$W" "$BATS_FILE_TMPDIR/golden"
}

setup() {
  export HOME="$BATS_FILE_TMPDIR/home"
  unset CC_BATS_ACTIVE CC_RESEARCH_RECORDS CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID CC_SESSION_ID
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  I="$REPO/scripts/research-kit/intake.py"
  G="$REPO/scripts/research-kit/gate.sh"
  LIB="$REPO/scripts/research-kit/lib"
  export W="$BATS_FILE_TMPDIR/w"
  export CC_RESEARCH_HOME="$W/home" CC_RESEARCH_REGISTRY="$W/home/programs.json"
  CC_NOW="$(cat "$BATS_FILE_TMPDIR/now")"
  export CC_NOW CC_RESEARCH_VAULT_KEY="test-key" CC_RESEARCH_OWNER="lead"
  rsync -a --delete "$BATS_FILE_TMPDIR/golden/" "$W/"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions" CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  REC="$(cat "$BATS_FILE_TMPDIR/records-path")"
  D="$BATS_TEST_TMPDIR/delta.json"
  # KR-1 held after the fixture's frame signature (2026-09-30T00:00Z), its re-sign due already past
  printf '{"id":"KR-1","kind":"frame-omission","status":"open","resign_due":"2026-09-30T06:00:00Z","default":"descope","blocks_waves":["B2"],"ts":"2026-09-30T01:00:00Z"}\n' \
    >> "$REC/known_rows.jsonl"
  printf '{"id":"KR-9","kind":"cap-round","status":"open","blocks_waves":[]}\n' >> "$REC/known_rows.jsonl"
  state certifying
  mk ''
}

state() {
  /usr/bin/env python3 -c "
import sys; sys.path.insert(0, '$LIB'); import kit
p = kit.registry_get('demo'); kit.registry_set('demo', '$1', p['aliases'], p['cwd_roots'])"
}

# mk '<python statements over d>': write the valid base delta to $D, edited by the statements
mk() {
  /usr/bin/env python3 - "$D" "$1" <<'PY'
import json, sys
d = {
    "program": "demo", "base_version": 1, "known_rows": ["KR-1"],
    "why": "KR-1: the frame lacked the write-path population and its row",
    "frame": {"populations": [{"op": "add", "value": "writers"}],
              "am": [{"op": "add", "value": "AM-2"}]},
    "acceptance": [
        {"op": "replace", "id": "AM-1", "fields": {"predicate": "loses 0 writes in 2000 trials"}},
        {"op": "add", "row": {"id": "AM-2", "predicate": "every writer retries 3 times",
                              "check_cmd": "grep -q ok \"$FIXTURE\"",
                              "threshold": {"metric": "retries", "op": "==", "value": 3},
                              "negative_branch": "redesign the writer"}},
    ],
}
exec(sys.argv[2])
json.dump(d, open(sys.argv[1], "w"))
PY
}

sums() { shasum -a 256 "$REC/frame.json" "$REC/acceptance.json"; }
fr() { /usr/bin/python3 -c "import json; print(json.dumps(json.load(open('$REC/frame.json')).get('$1')))"; }
kr_st() { /usr/bin/python3 -c "
import json; s = {}
for l in open('$REC/known_rows.jsonl'):
    if l.strip(): r = json.loads(l); s.setdefault(r['id'], {}).update(r)
print(s['$1'].get('status'))"; }
# frame_sig <at_iso>: a VALID operator frame signature at that time, pinning frame.json as it is now
frame_sig() {
  /usr/bin/python3 - "$1" "$REC/frame.json" "$CC_RESEARCH_HOME/demo/signoff.jsonl" "$REPO/scripts/lib" <<'PY'
import calendar, json, sys, time
at_iso, frame, log, lib = sys.argv[1:5]
sys.path.insert(0, lib)
import operator_sign
from pathlib import Path
rec = {"row": "research:demo/frame", "action": "frame", "target": None,
       "at": calendar.timegm(time.strptime(at_iso, "%Y-%m-%dT%H:%M:%SZ")), "at_iso": at_iso,
       "evidence": "fixture re-sign", "pins": {"frame.json": operator_sign.file_pin(Path(frame))},
       "provenance": {"claude_ancestor": False, "chain": ["zsh", "kitty"]}}
open(log, "a").write(json.dumps(rec) + "\n")
PY
}

@test "a clean apply writes the rows, bumps the version, lists the known row and records the delta with the old row" {
  run "$I" delta-apply --program demo --file "$D"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"FD-1 frame v1 -> v2"* ]] || { echo "$output"; false; }
  [[ "$output" == *"WARNING census/writers.json does not exist"* ]] || { echo "$output"; false; }
  [ "$(fr version)" = 2 ]
  [ "$(fr known_rows_applied)" = '["KR-1"]' ]
  [ "$(fr populations)" = '["callers", "writers"]' ]
  [ "$(fr am)" = '["AM-2"]' ]
  /usr/bin/python3 - "$REC" "$D" <<'PY'
import hashlib, json, sys
rec, dpath = sys.argv[1:3]
acc = {r["id"]: r for r in json.load(open(rec + "/acceptance.json"))["rows"]}
assert acc["AM-1"]["predicate"] == "loses 0 writes in 2000 trials", acc["AM-1"]
assert acc["AM-1"]["check_cmd"] == 'grep -q ok "$FIXTURE"'  # fields the replace did not name stay
assert acc["AM-2"]["negative_branch"] == "redesign the writer"
lines = open(rec + "/frame-deltas.jsonl").read().splitlines()
assert len(lines) == 1, lines
r = json.loads(lines[0])
dsha = hashlib.sha256(open(dpath, "rb").read()).hexdigest()
assert (r["id"], r["sha256"], r["base_version"], r["version"]) == ("FD-1", dsha, 1, 2), r
assert r["known_rows"] == ["KR-1"] and r["registry_state"] == "certifying" and r["by"] == "lead"
rep = next(o for o in r["ops"] if o["op"] == "replace")
assert rep["before"]["predicate"] == "loses 0 writes in 1000 trials", rep  # the old row is kept
assert r["rows_before"]["acceptance"] == ["AM-1"] and r["rows_after"]["acceptance"] == ["AM-1", "AM-2"]
pin = json.load(open(rec + "/frame.json"))["frame_deltas"][0]
asha = hashlib.sha256(open(rec + "/acceptance.json", "rb").read()).hexdigest()
assert pin == {"id": "FD-1", "version": 2, "sha256": dsha, "acceptance_sha256": asha}, pin
PY
}

@test "--dry-run prints the diff and writes nothing" {
  before="$(sums)"
  run "$I" delta-apply --program demo --file "$D" --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qE '^\+ +"version": 2,?$' <<< "$output" || { echo "$output"; false; }
  grep -qE '^- +"predicate": "loses 0 writes in 1000 trials",$' <<< "$output" || { echo "$output"; false; }
  grep -qE '^\+ +"predicate": "loses 0 writes in 2000 trials",$' <<< "$output" || { echo "$output"; false; }
  [[ "$output" == *"DRY RUN, nothing written"* ]] || { echo "$output"; false; }
  [ "$(sums)" = "$before" ]
  [ ! -e "$REC/frame-deltas.jsonl" ]
  [ ! -e "$REC/intake.jsonl" ] || ! grep -q delta-apply "$REC/intake.jsonl"
}

@test "each refusal exits 2 naming its guard, and leaves both files byte-identical with nothing recorded" {
  before="$(sums)"
  cases=(
    'd["frame"]["rulings"] = [{"op": "add", "value": "x"}]'$'\t''a delta edits the row lists'
    'd["signatures"] = []'$'\t''only program, base_version'
    'd["frame"]["populations"] = [{"op": "add", "value": "callers"}]'$'\t''callers is already in frame.populations'
    'd["frame"]["populations"] = [{"op": "replace", "id": "nobody", "value": "nobody"}]'$'\t'"'nobody' is not in frame.populations"
    'd["frame"]["components"] = [{"op": "replace", "id": "daemon", "value": {"name": "cron"}}]'$'\t''a replace rewrites a row and keeps its id'
    'd["frame"]["am"] = [{"op": "replace", "id": "AM-2", "value": "AM-2"}]'$'\t''holds bare ids'
    'd["acceptance"][0]["fields"]["id"] = "AM-9"'$'\t'"a replace keeps the row's id"
    'd["acceptance"][0] = {"op": "replace", "id": "AM-7", "fields": {"predicate": "x"}}'$'\t'"'AM-7' is not in acceptance.json"
    'del d["acceptance"][1]["row"]["negative_branch"]'$'\t''the row lacks negative_branch'
    'd["frame"]["am"].append({"op": "add", "value": "AM-7"})'$'\t''frame.am adds AM-7, which acceptance.json does not hold'
    'd["frame"]["dr"] = [{"op": "add", "value": "DR-9"}]'$'\t''frame.dr adds DR-9, which decisions.jsonl does not hold'
    'd["frame"]["am"] = [{"op": "add", "value": "AM-1"}]'$'\t''acceptance adds AM-2 but frame.am does not name it'
    'd["acceptance"][0]["fields"]["predicate"] = "the best daemon"'$'\t''leaves gate row 1 failing where it passed: AM-1: numberless superlative'
    'd["known_rows"] = ["KR-9"]'$'\t''KR-9 is not an open frame-omission known row'
    'd["known_rows"] = []'$'\t''known_rows is empty'
    'd["base_version"] = 0'$'\t''drafted against frame v0; the frame is v1'
  )
  for c in "${cases[@]}"; do
    mk "${c%%$'\t'*}"
    run "$I" delta-apply --program demo --file "$D"
    [ "$status" -eq 2 ] || { echo "case: $c"; echo "$output"; false; }
    [[ "$output" == *"${c#*$'\t'}"* ]] || { echo "case: $c"; echo "$output"; false; }
    [ "$(sums)" = "$before" ] || { echo "case wrote: $c"; false; }
    [ ! -e "$REC/frame-deltas.jsonl" ] || { echo "case recorded: $c"; false; }
  done
}

@test "outside certifying and certified only an open frame-delta activity lets a delta through, and only it allows no known row" {
  state registered
  run "$I" delta-apply --program demo --file "$D"
  [ "$status" -eq 2 ]
  [[ "$output" == *"demo is registered: a frame delta applies while the program is certifying or certified"* ]] || { echo "$output"; false; }
  [ ! -e "$REC/frame-deltas.jsonl" ]
  act="$(/usr/bin/env python3 -c "import sys; sys.path.insert(0, '$LIB'); import activities; print(activities.open_activity('demo', 'frame-delta'))")"
  mk 'd["known_rows"] = []'
  run "$I" delta-apply --program demo --file "$D"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(/usr/bin/python3 -c "import json; print(json.loads(open('$REC/frame-deltas.jsonl').readline())['activity'])")" = "$act" ]
  [ "$(fr known_rows_applied)" = '[]' ]
}

@test "another owner's fresh program lease refuses the apply; the same run as the holder goes through" {
  CC_RESEARCH_OWNER=other "$REPO/bin/cc-research" lease acquire --program demo > /dev/null
  before="$(sums)"
  run "$I" delta-apply --program demo --file "$D"
  [ "$status" -eq 2 ]
  [[ "$output" == *"other"* ]] || { echo "$output"; false; }
  [ "$(sums)" = "$before" ]
  CC_RESEARCH_OWNER=other run "$I" delta-apply --program demo --file "$D"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "the apply is not the evidence: the sweep closes the row by its default until the operator re-signs the delta's frame" {
  "$I" delta-apply --program demo --file "$D" > /dev/null
  run "$G" sweep --program demo
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(kr_st KR-1)" = closed ] || { cat "$REC/known_rows.jsonl"; false; }
  # the same apply, then the operator's re-sign of the new frame: delta_signature finds it
  rsync -a --delete "$BATS_FILE_TMPDIR/golden/" "$W/"
  printf '{"id":"KR-1","kind":"frame-omission","status":"open","resign_due":"2026-09-30T06:00:00Z","default":"descope","blocks_waves":["B2"],"ts":"2026-09-30T01:00:00Z"}\n' \
    >> "$REC/known_rows.jsonl"
  state certifying
  "$I" delta-apply --program demo --file "$D" > /dev/null
  frame_sig 2026-10-02T00:00:00Z
  run "$G" sweep --program demo
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(kr_st KR-1)" = open ] || { cat "$REC/known_rows.jsonl"; false; }
}
