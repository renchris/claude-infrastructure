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
#   - the frame scalars `deliverable` and `locks` are written only by delta ops (set; add/replace);
#   - `cc-research decision annotate` writes a ruled or carried decision's display fields inside the
#     delta window, never moving its status, choice, tally, conviction or gate row 5; gate row 1 fails
#     until a delta pins the annotation (and the decisions.jsonl prefix) in the frame the operator
#     re-signs, and again if that pinned prefix is rewritten.
# RED-proof (2026-10-16): on the pre-change intake.py every case fails; the verb does not exist, and
# argparse's exit 2 ("invalid choice") matches no case's message.
# RED-proof (annotate, locks, deliverable; 2026-10-16): on f423c9222 `decision annotate` is an
# invalid choice (exit 2, no case's message) and a delta naming deliverable or locks is refused as
# "not a delta's"; per-site mutants (each guard deleted on a scratch copy) are listed at each test.

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
dec = open(rec + "/decisions.jsonl", "rb").read()
assert pin == {"id": "FD-1", "version": 2, "sha256": dsha, "acceptance_sha256": asha,
               "decisions_sha256": hashlib.sha256(dec).hexdigest(), "decisions_bytes": len(dec),
               "annotations": []}, pin
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
    'd["frame"]["deliverable"] = [{"op": "replace", "id": "deliverable", "value": "x"}]'$'\t''the deliverable takes op set'
    'd["frame"]["deliverable"] = [{"op": "set", "value": "a sync daemon that loses 0 writes in 1000 trials"}]'$'\t''the new deliverable equals the old one'
    'd["frame"]["locks"] = [{"op": "add", "id": "c.py", "value": {"path": "c.py", "sha256": "abc"}}]'$'\t''sha256 is not 64 lowercase hex digits'
    'd["frame"]["locks"] = [{"op": "add", "id": "c.py", "value": {"sha256": "a" * 64}}]'$'\t''a lock is an object with a path and a sha256'
    'd["frame"]["locks"] = [{"op": "replace", "id": "c.py", "value": {"path": "c.py", "sha256": "a" * 64}}]'$'\t'"'c.py' is not in frame.locks"
    'd["frame"]["locks"] = [{"op": "add", "id": "c.py", "value": {"path": "c.py", "sha256": "a" * 64}}] * 2'$'\t''c.py is already in frame.locks'
    'd["frame"]["deliverable"] = [{"op": "set", "value": "the best daemon"}]'$'\t''leaves gate row 1 failing where it passed: the deliverable sentence carries a numberless superlative'
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

# CR <args>: cc-research against the fixture program
CR() { "$REPO/bin/cc-research" "$@"; }
dsum() { shasum -a 256 "$REC/decisions.jsonl"; }
dfold() { /usr/bin/python3 -c "
import json; s = {}
for l in open('$REC/decisions.jsonl'):
    if l.strip(): r = json.loads(l); s.setdefault(r['id'], {}).update(r)
print(json.dumps(s['$1'].get('$2'), sort_keys=True))"; }
row_ev() { "$G" run --program demo --json 2>/dev/null | /usr/bin/python3 -c "import json,sys; print('\n'.join([r for r in json.load(sys.stdin) if r['num'] == $1][0]['evidence']))"; }

# Mutant: deleting apply_scalar_ops' call in apply_frame_ops turns this red ("not a delta's").
@test "deliverable and locks: a delta sets the sentence and adds a lock, keeping the old sentence in the record" {
  mk 'd["frame"]["deliverable"] = [{"op": "set", "value": "a sync daemon that loses 0 writes in 2000 trials"}]
d["frame"]["locks"] = [{"op": "add", "id": "compare.py", "value": {"path": "stage5/compare.py", "sha256": "b" * 64}}]'
  run "$I" delta-apply --program demo --file "$D"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"set deliverable deliverable"*"add locks compare.py"* ]] || { echo "$output"; false; }
  [ "$(fr deliverable)" = '"a sync daemon that loses 0 writes in 2000 trials"' ]
  [ "$(fr locks)" = '{"compare.py": {"path": "stage5/compare.py", "sha256": "'"$(printf 'b%.0s' {1..64})"'"}}' ]
  /usr/bin/python3 - "$REC" <<'PY'
import json, sys
r = json.loads(open(sys.argv[1] + "/frame-deltas.jsonl").readline())
o = {x["list"]: x for x in r["ops"]}
assert o["deliverable"]["before"] == "a sync daemon that loses 0 writes in 1000 trials", o
assert o["locks"]["before"] is None and o["locks"]["after"]["path"] == "stage5/compare.py", o
assert r["rows_before"]["locks"] == [] and r["rows_after"]["locks"] == ["compare.py"], r
PY
  # a second delta replaces the lock; replacing it with itself is refused
  mk 'd["base_version"] = 2
d["frame"] = {"locks": [{"op": "replace", "id": "compare.py", "value": {"path": "stage5/compare.py", "sha256": "c" * 64}}]}
del d["acceptance"]'
  run "$I" delta-apply --program demo --file "$D"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$(fr locks)" == *'"sha256": "cccc'* ]] || fr locks
}

# Mutants: deleting the window check, the conviction comparison, or the decision_findings
# comparison in decision_annotate each turns one case below green-to-red (registered, DR-3, DR-4).
@test "decision annotate: each refusal exits 2 naming its guard and leaves decisions.jsonl byte-identical" {
  printf '%s\n' \
    '{"id":"PR-2","truth_lives_in":"production","verdict":"unknown","probes":[]}' >> "$REC/premises.jsonl"
  printf '%s\n' \
    '{"id":"DR-2","status":"open","options":[{"label":"do-nothing"}],"reversibility":"reversible"}' \
    '{"id":"DR-3","status":"ruled","ruled_by":"operator","receipt":"he said x","chosen":"x","options":[{"label":"x"}],"premises":["PR-1"],"reversibility":"irreversible"}' \
    '{"id":"DR-4","status":"ruled","ruled_by":"operator","receipt":"he said y","chosen":"y","options":[{"label":"y"}],"reversibility":"reversible"}' \
    >> "$REC/decisions.jsonl"
  before="$(dsum)"
  cases=(
    "--id|DR-2|--group|G1"$'\t'"status 'open'; an annotation is written on a ruled or carried decision"
    "--id|DR-1"$'\t'"nothing to annotate"
    "--id|DR-1|--revisit-trigger|a lost write in build"$'\t'"the annotation changes nothing"
    "--id|DR-1|--premise|PR-9"$'\t'"--premise PR-9 is not in premises.jsonl"
    "--id|DR-1|--ruling|status=ruled"$'\t'"--ruling status names a field the kit or another verb owns"
    "--id|DR-1|--ruling|chosen=retry"$'\t'"--ruling chosen names a field the kit or another verb owns"
    "--id|DR-1|--ruling|question=x"$'\t'"--ruling question names a field the kit or another verb owns"
    "--id|DR-1|--ruling|Bad=1"$'\t'"is NAME=VALUE"
    "--id|DR-1|--ruling|ghsa2={oops"$'\t'"--ruling ghsa2: not a JSON object"
    "--id|DR-1|--group| "$'\t'"--group is empty"
    "--id|DR-3|--premise|PR-2"$'\t'"the annotation would move conviction (89 -> 0)"
    "--id|DR-4|--revisit-trigger|a moved base"$'\t'"the annotation would move gate row 5"
  )
  for c in "${cases[@]}"; do
    IFS='|' read -r -a args <<< "${c%%$'\t'*}"
    run CR decision annotate --program demo "${args[@]}" --why "KR-1"
    [ "$status" -eq 2 ] || { echo "case: $c"; echo "$output"; false; }
    [[ "$output" == *"${c#*$'\t'}"* ]] || { echo "case: $c"; echo "$output"; false; }
    [ "$(dsum)" = "$before" ] || { echo "case wrote: $c"; false; }
  done
  state registered
  run CR decision annotate --program demo --id DR-1 --group G1 --why KR-1
  [ "$status" -eq 2 ]
  [[ "$output" == *"demo is registered: a decision annotation is written while the program is certifying or certified"* ]] || { echo "$output"; false; }
  [ "$(dsum)" = "$before" ]
}

@test "decision annotate: a clean annotate appends one event; status, chosen, tally, conviction and gate row 5 read the same" {
  show0="$(CR decision show --program demo --id DR-1)"
  row5_0="$(row_ev 5)"
  for f in status chosen tally ruled_by; do eval "b_$f=\$(dfold DR-1 $f)"; done
  run CR decision annotate --program demo --id DR-1 --affects 'PLAN#retry-policy (the writer)' \
    --affects 'PLAN#5-4' --group G1 --premise PR-1 --revisit-trigger 'a lost write in build or W3' \
    --default-if-unanswered 'retry stays' --ruling 'ghsa2={"ruling": "Hold for the talk", "packet": "25f7e77b65ce"}' \
    --why 'KR-1 item 3'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"DR-1: annotated affects, default_if_unanswered, ghsa2, group, premises, revisit_trigger as DA-1"* ]] || { echo "$output"; false; }
  [ "$(dfold DR-1 affects)" = '["PLAN#retry-policy (the writer)", "PLAN#5-4"]' ]
  [ "$(dfold DR-1 group)" = '"G1"' ]
  [ "$(dfold DR-1 ghsa2)" = '{"packet": "25f7e77b65ce", "ruling": "Hold for the talk"}' ]
  [ "$(dfold DR-1 annotation)" = '"DA-1"' ]
  for f in status chosen tally ruled_by; do
    [ "$(dfold DR-1 $f)" = "$(eval echo "\$b_$f")" ] || { echo "$f moved"; false; }
  done
  [ "$(CR decision show --program demo --id DR-1)" = "$show0" ]
  [ "$(row_ev 5)" = "$row5_0" ]
  # one appended line, the earlier ones untouched; a later annotation may rewrite its own named field
  [ "$(grep -c '"annotation"' "$REC/decisions.jsonl")" = 1 ]
  run CR decision annotate --program demo --id DR-1 --ruling 'ghsa2={"ruling": "Filed"}' --why 'KR-1 re-ruled'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(dfold DR-1 annotation)" = '"DA-2"' ]
}

# Mutants: deleting pin_fails' call in gate row 1, or the decisions pin in the new frame's
# frame_deltas entry, each turns this red.
@test "the re-sign covers annotations: row 1 fails until a delta pins them, and again on a later annotation or a rewritten prefix" {
  CR decision annotate --program demo --id DR-1 --group G1 --why KR-1 > /dev/null
  run "$I" lint --program demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"decision annotation(s) DA-1 carried by no frame delta"* ]] || { echo "$output"; false; }
  run "$I" delta-apply --program demo --file "$D"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"pin DA-1"* ]] || { echo "$output"; false; }
  /usr/bin/python3 - "$REC" <<'PY'
import hashlib, json, sys
rec = sys.argv[1]
pin = json.load(open(rec + "/frame.json"))["frame_deltas"][-1]
dec = open(rec + "/decisions.jsonl", "rb").read()
assert pin["annotations"] == ["DA-1"], pin
assert (pin["decisions_sha256"], pin["decisions_bytes"]) == (hashlib.sha256(dec).hexdigest(), len(dec)), pin
r = json.loads(open(rec + "/frame-deltas.jsonl").readline())
assert r["annotations"] == ["DA-1"] and r["decisions_sha256"] == pin["decisions_sha256"], r
PY
  run "$I" lint --program demo
  [[ "$output" != *"carried by no frame delta"* ]] || { echo "$output"; false; }
  # the operator's re-sign pins frame.json, which now carries the decisions hash
  frame_sig 2026-10-02T00:00:00Z
  run row_ev 1
  [[ "$output" != *"STALE"* && "$output" != *"decision annotation"* ]] || { echo "$output"; false; }
  # a later annotation is under no re-sign until the next delta; one with no row ops pins it alone
  CR decision annotate --program demo --id DR-1 --group G2 --why KR-1 > /dev/null
  run "$I" lint --program demo
  [[ "$output" == *"decision annotation(s) DA-2 carried by no frame delta"* ]] || { echo "$output"; false; }
  mk 'd["base_version"] = 2
del d["frame"], d["acceptance"]'
  run "$I" delta-apply --program demo --file "$D"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"FD-2 frame v2 -> v3 (pin DA-2)"* ]] || { echo "$output"; false; }
  # with nothing pending, a delta with no ops is still refused
  mk 'd["base_version"] = 3
del d["frame"], d["acceptance"]'
  run "$I" delta-apply --program demo --file "$D"
  [ "$status" -eq 2 ]
  [[ "$output" == *"the delta has no ops"* ]] || { echo "$output"; false; }
  # rewriting a pinned annotation's text in place breaks the pin
  /usr/bin/python3 -c "
p = '$REC/decisions.jsonl'; t = open(p).read(); open(p, 'w').write(t.replace('\"group\": \"G1\"', '\"group\": \"G7\"'))"
  run "$I" lint --program demo
  [[ "$output" == *"decisions.jsonl no longer holds the"*"bytes FD-1 pinned"* ]] || { echo "$output"; false; }
}
