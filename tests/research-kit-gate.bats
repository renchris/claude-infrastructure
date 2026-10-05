#!/usr/bin/env bats
# research-kit-gate — scripts/research-kit/gate.sh, the REPORT.md §3.10 gate (rows 1-15, plus row 16:
# rounds and stage time against their caps, §10 item 17, and row 17: an honest stop), the freeze that
# sets the registry to certifying (§10 item 1), and the render a completeness turn relays.
#
# One known-good program (tests/fixtures/research-kit/build_good.py) passes all 17 rows and
# certifies. Every other test restores it and plants ONE defect, then asserts that the named row
# turns FAIL: "every gate row has a planted-input test that must fail" (REPORT.md §3.10).

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
  export W="$BATS_FILE_TMPDIR/w"
  export CC_RESEARCH_HOME="$W/home" CC_RESEARCH_REGISTRY="$W/home/programs.json"
  CC_NOW="$(cat "$BATS_FILE_TMPDIR/now")"
  export CC_NOW CC_RESEARCH_VAULT_KEY="test-key"
  export CC_DECISIONS_DIR="$W/decisions" CC_IDL="$W/idl.jsonl"
  export CC_RESEARCH_ROUTER="$W/router.sh"
  export CC_RESEARCH_CALIBRATION="$W/calibration.jsonl"
  rsync -a --delete "$BATS_FILE_TMPDIR/golden/" "$W/"
  REC="$(cat "$BATS_FILE_TMPDIR/records-path")"
}

# rowstat <n>: the status of gate row n on this run.
rowstat() {
  "$G" run --program demo --json 2>/dev/null | /usr/bin/python3 -c "import json,sys; print([r['status'] for r in json.load(sys.stdin) if r['num'] == $1][0])"
}
# rowtext <n>: the evidence lines of row n.
rowtext() {
  "$G" run --program demo --json 2>/dev/null | /usr/bin/python3 -c "import json,sys; print('\n'.join([r for r in json.load(sys.stdin) if r['num'] == $1][0]['evidence']))"
}
# jedit <file under REC> <python statement over d>: edit a JSON record in place.
jedit() {
  /usr/bin/python3 -c "import json; p='$REC/$1'; d=json.load(open(p)); $2; json.dump(d, open(p, 'w'))"
}
state() { /usr/bin/python3 -c "import json; print(json.load(open('$CC_RESEARCH_REGISTRY'))['programs'][0]['state'])"; }

@test "the known-good program passes all 17 rows, certifies, and the registry reads certified" {
  run "$G" run --program demo
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -cE '^ ?[0-9]+\. .* PASS$')" -eq 17 ]
  [ "$(state)" = "certified" ]
  [ -f "$REC/cert/CERT-v1.json" ]
}

@test "render relays the certificate's state lines and writes nothing" {
  "$G" run --program demo
  before="$(find "$W" -type f -newer "$REC/cert/CERT-v1.json" | wc -l)"
  run "$G" --render --program demo
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "Research: demo version 1. CERTIFIED"* ]] || false
  [[ "$output" == *"Signed frame: 100.00% closed."* ]] || false
  [[ "$output" == *"uncalibrated"* ]] || false
  [ "$(find "$W" -type f -newer "$REC/cert/CERT-v1.json" | wc -l)" -eq "$before" ]
}

@test "render reads the records live: a counted escape after the issue moves the After-signoff line" {
  "$G" run --program demo
  run "$G" --render --program demo
  [ "$status" -eq 0 ]
  before="$output"
  [[ "$output" == *"After signoff: 0 material changes"* ]] || false
  ts="$(date -u -v+1H +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"id":"CR-80","cause":"operator_new","status":"parked","justification":"idea","ts":"%s"}\n' "$ts" \
    >> "$REC/changes.jsonl"
  run "$G" --render --program demo
  [ "$output" = "$before" ]
  printf '{"id":"CR-90","cause":"escape","challenge":"CH-90","justification":"planted","ts":"%s"}\n' "$ts" \
    >> "$REC/changes.jsonl"
  run "$G" --render --program demo
  [ "$status" -eq 0 ]
  [ "$output" != "$before" ]
  [[ "$output" == *"After signoff: 1 material change (1 escape; forecast about"* ]] || false
  [[ "$output" != *"unchanged since"* ]] || false
}

@test "render never prints a literal take-backs 0" {
  "$G" run --program demo
  run "$G" --render --program demo
  [ "$status" -eq 0 ]
  [[ "$output" != *"take-backs 0"* ]] || false
  [[ "$(cat "$REC/cert/CERT-v1.md")" != *"take-backs 0"* ]] || false
}

@test "render: a residual row renders the Residuals and Scheduled checks lines; none renders neither" {
  "$G" run --program demo
  run "$G" --render --program demo
  [[ "$output" == *"Residuals: 1 declared (elapsed-time 1)"* ]] || false
  [[ "$output" == *"Scheduled checks: 1 production or elapsed-time check with owner and date (next due "* ]] || false
  # the due date is build_good.py's residual row, read back rather than restated here
  due="$(jq -r .due "$REC/residual.jsonl")"
  [[ "$output" == *"(next due $due)"* ]] || false
  : > "$REC/residual.jsonl"
  run "$G" --render --program demo
  [[ "$output" != *"Residuals:"* ]] || false
  [[ "$output" != *"Scheduled checks:"* ]] || false
  printf '{"id":"P-fresh-PR-1","at":"%s","exit":0}\n' "$CC_NOW" >> "$REC/probes.jsonl"
  run "$G" --render --program demo
  [[ "$output" == *"Scheduled checks: last freshness run "*", no verdict changed"* ]] || false
}

@test "render: Built and Live read unknown, and Calibration counts the calibration rows" {
  "$G" run --program demo
  run "$G" --render --program demo
  [[ "$output" == *"Built – · Live – · Calibration: none measured (uncalibrated)"* ]] || false
  printf '{"plan":"a"}\n{"plan":"b"}\n' > "$CC_RESEARCH_CALIBRATION"
  run "$G" --render --program demo
  [[ "$output" == *"Calibration: 2 plans measured"* ]] || false
  [[ "$output" != *"uncalibrated"* ]] || false
}

@test "an uncertified program renders as not certified" {
  run "$G" render --program demo
  [[ "$output" == "Research: demo — registered; not certified."* ]]
}

@test "§10 item 1: freeze sets the registry to certifying" {
  run "$G" freeze --program demo
  [ "$status" -eq 0 ]
  [ "$(state)" = "certifying" ]
}

@test "freeze is refused while lint shows an error, and the registry stays registered" {
  echo "This is the best design." >> "$REC/PLAN.md"
  git -C "$W/repo" commit -qam "plan"
  run "$G" freeze --program demo
  [ "$status" -eq 2 ]
  [ "$(state)" = "registered" ]
}

@test "a failing row blocks the certificate and the registry stays registered" {
  printf '{"id":"DR-1","status":"open"}\n' >> "$REC/decisions.jsonl"
  run "$G" run --program demo
  [ "$status" -eq 1 ]
  [ "$(state)" = "registered" ]
  [ ! -e "$REC/cert/CERT-v1.json" ]
}

@test "row 1: a frame changed after it was signed fails as stale" {
  jedit frame.json 'd["version"] = 2'
  [ "$(rowstat 1)" = "FAIL" ]
  [[ "$(rowtext 1)" == *"STALE"* ]]
}

@test "row 1: a newer agent-written frame signature fails as void" {
  pin="$(/usr/bin/python3 -c "import json; print(json.loads(open('$CC_RESEARCH_HOME/demo/signoff.jsonl').readline())['pins']['frame.json'])")"
  printf '{"action":"frame","target":null,"at":9e9,"pins":{"frame.json":"%s"},"provenance":{"claude_ancestor":false,"chain":["zsh","claude"]}}\n' "$pin" \
    >> "$CC_RESEARCH_HOME/demo/signoff.jsonl"
  [[ "$(rowtext 1)" == *"VOID"* ]]
}

@test "row 1: a numberless superlative in an acceptance predicate fails" {
  jedit acceptance.json 'd["rows"][0]["predicate"] = "the best retry policy"'
  [ "$(rowstat 1)" = "FAIL" ]
}

@test "row 1: an unmapped checklist row fails" {
  jedit frame.json 'd["fac_map"] = [m for m in d["fac_map"] if m["fac"] != "FAC-17"]'
  [[ "$(rowtext 1)" == *"FAC-17"* ]]
}

@test "row 2: a census method whose re-run drops a member fails" {
  jedit census/callers.json 'd["methods"][1]["cmd"] = "echo a"'
  [ "$(rowstat 2)" = "FAIL" ]
}

@test "row 2: an empty grid cell fails" {
  jedit census/callers.json 'd["grid"] = {"cells": [{"row": "write", "col": "wrong-duration"}]}'
  [ "$(rowstat 2)" = "FAIL" ]
}

@test "row 3: a consulted source whose evidence is missing fails" {
  printf '{"id":"E-1","status":"consulted","evidence":["evidence/P-404"]}\n' > "$REC/sources.jsonl"
  [ "$(rowstat 3)" = "FAIL" ]
}

@test "row 4: a code premise held only by recall fails (E0, needs E2)" {
  printf '{"id":"PR-1","truth_lives_in":"code","verdict":"holds","probes":[],"load_bearing_for":["DR-1"],"origin":{"tier":"E1"}}\n' \
    > "$REC/premises.jsonl"
  [ "$(rowstat 4)" = "FAIL" ]
}

@test "row 5: an agent-ruled decision whose flip probe never ran computes 89 and fails" {
  printf '{"id":"DR-1","tally":{"premises":["PR-1"]}}\n' >> "$REC/decisions.jsonl"
  [[ "$(rowtext 5)" == *"agent-ruled at 89%"* ]]
}

@test "row 5: a typed conviction that the rule does not compute fails" {
  printf '{"id":"DR-1","conviction":95}\n' >> "$REC/decisions.jsonl"
  [[ "$(rowtext 5)" == *"typed, not computed"* ]]
}

@test "row 5: a reversible decision researched 3 times fails" {
  printf '{"id":"DR-1","runs_used":3}\n' >> "$REC/decisions.jsonl"
  [ "$(rowstat 5)" = "FAIL" ]
}

@test "row 6: an acceptance check that passes its known-bad fixture fails" {
  jedit acceptance.json 'd["rows"][0]["check_cmd"] = "true"'
  [[ "$(rowtext 6)" == *"cannot fail"* ]]
}

@test "row 7: an environment the doctor found but no probe crossed fails" {
  grep -v '"P-4"' "$REC/probes.jsonl" > "$REC/p.tmp"; mv "$REC/p.tmp" "$REC/probes.jsonl"
  [[ "$(rowtext 7)" == *"interactive-zsh never crossed"* ]]
}

@test "row 8: a record citing a /tmp path fails" {
  echo "see /tmp/notes.txt" >> "$REC/research.md"
  [ "$(rowstat 8)" = "FAIL" ]
}

@test "row 8: a research heading with no trace fails" {
  printf '\n## Untraced claim\n' >> "$REC/research.md"
  [[ "$(rowtext 8)" == *"untraced-claim"* ]]
}

@test "row 8: a private receipt whose cited span changed fails" {
  printf 'one\ntwo\n' > "$W/mem.md"
  h="$(printf 'one\ntwo' | shasum -a 256 | awk '{print $1}')"
  jedit frame.json "d['private_receipts'] = [{'path': '$W/mem.md', 'span': '1-2', 'sha256': '$h'}]"
  "$G" run --program demo --json >/dev/null 2>&1 || true
  printf 'one\nTWO\n' > "$W/mem.md"
  [[ "$(rowtext 8)" == *"the cited span changed"* ]]
}

@test "row 9: a plan edited after the freeze fails" {
  echo "A late edit of 2 lines." >> "$REC/PLAN.md"
  [[ "$(rowtext 9)" == *"changed after the freeze"* ]]
}

@test "row 9: a plan citing a probe that never ran fails lint" {
  echo "Measured by P-77." >> "$REC/PLAN.md"
  [[ "$(rowtext 9)" == *"P-77"* ]]
}

@test "row 10: a premise re-check older than 24 hours fails" {
  CC_NOW="$(date -u -v+48H +%Y-%m-%dT%H:%M:%SZ)" run rowstat 10
  [ "$output" = "FAIL" ]
}

@test "row 11: a residual with a reason outside the allowed list fails" {
  printf '{"id":"RS-2","why_unreachable":"too-hard"}\n' >> "$REC/residual.jsonl"
  printf '{"id":"residual:RS-2","disposition":"done"}\n' >> "$REC/reconcile.jsonl"
  [ "$(rowstat 11)" = "FAIL" ]
}

@test "§10 item 7: a method-created residual renders FILED, not FAIL, and the gate still certifies" {
  printf '{"id":"RS-2","why_unreachable":"depth-cap","owner_wave":"B1","due":"%s","closing_probe":"P-9"}\n' "$(date -u -v+720H +%Y-%m-%d)" >> "$REC/residual.jsonl"
  printf '{"id":"residual:RS-2","disposition":"filed","ref":"RS-2"}\n' >> "$REC/reconcile.jsonl"
  [ "$(rowstat 11)" = "FILED" ]
  git -C "$W/repo" add -A
  git -C "$W/repo" commit -qm "residual"
  run "$G" run --program demo
  [ "$status" -eq 0 ]
}

@test "§10 item 7: a method-created residual with no closing probe fails" {
  printf '{"id":"RS-2","why_unreachable":"stub-validated","owner_wave":"B1","due":"%s"}\n' "$(date -u -v+720H +%Y-%m-%d)" >> "$REC/residual.jsonl"
  printf '{"id":"residual:RS-2","disposition":"filed","ref":"RS-2"}\n' >> "$REC/reconcile.jsonl"
  [ "$(rowstat 11)" = "FAIL" ]
}

@test "row 12: a dirty file in the deliverable repo that nothing reconciles fails" {
  echo x > "$W/repo/stray.txt"
  [[ "$(rowtext 12)" == *"unmapped: dirty:stray.txt"* ]]
}

@test "row 12 / §10 item 4: a program packet filed without --project fails" {
  id="$(/bin/bash "$REPO/bin/cc-decide" open --class C --what "pick a store" --option "a::x" --option "b::y" --conviction 70 --receipt "$REC/frame.json")"
  printf '{"id":"DR-1","packet":{"id":"%s","class":"C","due":"%s"}}\n' "$id" "$(date -u -v+1500H +%Y-%m-%dT%H:%M:%SZ)" >> "$REC/decisions.jsonl"
  [[ "$(rowtext 12)" == *"MALFORMED PACKET"* ]]
}

@test "row 13: a vendor preflight run after the contract page fails" {
  jedit frame.json 'd["contract_page_at"] = "2026-09-29T00:00:00Z"'
  [ "$(rowstat 13)" = "FAIL" ]
}

@test "row 13: a counted round whose reviewer answered as an unpinned model fails" {
  /usr/bin/python3 -c "import json; p='$REC/rounds/2/panels/r2p5.json'; d=json.load(open(p)); d['responding_model']='gpt-old'; json.dump(d, open(p,'w'))"
  [[ "$(rowtext 13)" == *"gpt-old"* ]]
}

@test "row 13: a counted round whose reviewer ran at an effort other than the frame's pin fails" {
  [ "$(rowstat 13)" = "PASS" ]
  jedit frame.json 'd["reviewer_effort"] = {"openai": "xhigh"}'
  [[ "$(rowtext 13)" == *"r2p5 ran at effort CLI default, pinned xhigh"* ]]
}

@test "row 13: a counted round with a dead vendor lane fails" {
  jedit rounds/3/matrix.json 'd["lanes"]["google"] = "dead"'
  [[ "$(rowtext 13)" == *"dead vendor lane"* ]]
}

@test "row 14: a relay test that failed without 'relay unstable' fails" {
  jedit rehearsal.json 'd["relay"]["passed"] = False'
  [ "$(rowstat 14)" = "FAIL" ]
}

@test "row 15: no router built fails" {
  CC_RESEARCH_ROUTER="" run rowtext 15
  [[ "$output" == *"router not built"* ]]
}

@test "row 15: a router that labels everything a work order fails on recall" {
  printf '#!/bin/bash\ncat >/dev/null\necho work-order\n' > "$W/router.sh"
  [[ "$(rowtext 15)" == *"recall 0/12"* ]]
}

@test "row 15: a router that errors on every prompt fails on the fallback rate" {
  printf '#!/bin/bash\nexit 1\n' > "$W/router.sh"
  [[ "$(rowtext 15)" == *"fallback rate 1.00"* ]]
}

@test "row 15: a router that answers two labels at once is a fallback" {
  printf '#!/bin/bash\ncat >/dev/null\necho completeness work-order\n' > "$W/router.sh"
  [ "$(rowstat 15)" = "FAIL" ]
}

@test "row 16: more rounds than R_max fails" {
  jedit rounds/1/matrix.json 'd["forecast"]["p90"] = -2'
  [[ "$(rowtext 16)" == *"R_max is 2"* ]]
}

@test "row 16: a second valid extra round set fails" {
  for i in 1 2; do
    printf '{"action":"extra-round","target":null,"at":%s,"pins":{},"provenance":{"claude_ancestor":false,"chain":["zsh","kitty"]}}\n' "$i" \
      >> "$CC_RESEARCH_HOME/demo/signoff.jsonl"
  done
  [[ "$(rowtext 16)" == *"2 extra round sets"* ]]
}

@test "row 16: a stage past 1.5x its budget with no overrun packet fails; with one it is FILED" {
  jedit budget.json 'd["stages"]["4"] = {"started": "2026-09-29T00:00:00Z", "ended": "2026-09-30T14:00:00Z"}'
  [ "$(rowstat 16)" = "FAIL" ]
  jedit budget.json 'd["overrun_packets"] = {"4": "abc123"}'
  [ "$(rowstat 16)" = "FILED" ]
}

@test "row 16: a missing row is FAIL, never a silent pass" {
  run /usr/bin/python3 -c "
import sys; sys.path.insert(0, '$REPO/scripts/research-kit/lib'); sys.path.insert(0, '$REPO/scripts/lib')
import gate, gate_rows_b
gate_rows_b.ROWS = [f for f in gate_rows_b.ROWS if f.row[0] != 16]
print([r.status for r in gate.run_rows(gate.make_ctx('demo')) if r.num == 16][0])"
  [ "$output" = "FAIL" ]
}

@test "row 17: the round cap reached with one uncounted round fails, and no certificate is issued" {
  jedit rounds/1/matrix.json 'd["forecast"]["p90"] = -1'
  jedit rounds/2/matrix.json 'd["counted"] = False; d["quiet"] = False; d["lanes"]["google"] = "dead"'
  git -C "$REC" commit -qam "plant: round 2 lost"  # row 12 would otherwise see the plant as dirty
  [[ "$(rowtext 17)" == *"1 lost round(s) (2)"* ]] || false
  run "$G" run --program demo
  [ "$status" -ne 0 ]
  [ "$(printf '%s\n' "$output" | grep -cE ' FAIL$')" -eq 1 ]
  [[ "$output" == *"17. "*" FAIL"* ]] || false
  [ ! -f "$REC/cert/CERT-v1.json" ]
  [ "$(state)" != "certified" ]
}

@test "row 17: rounds that ended dry pass despite a lost round, and the certificate states it separately" {
  cp -Rp "$REC/rounds/3" "$REC/rounds/4"
  jedit rounds/4/matrix.json 'd["round"] = "4"; d["seq"] = 4'
  jedit rounds/2/matrix.json 'd["counted"] = False; d["quiet"] = False; d["lanes"]["google"] = "dead"'
  git -C "$REC" add rounds
  git -C "$REC" commit -qm "plant: round 2 lost, round 4 quiet"
  run "$G" run --program demo
  [ "$status" -eq 0 ]
  run "$G" --render --program demo
  [[ "${lines[0]}" == *"stopped after 2 quiet rounds; 1 round lost to a dead lane and not counted (round 2)"* ]] || false
}

@test "a valid operator reopen after the certificate sets the registry back to registered" {
  "$G" run --program demo
  [ "$(state)" = "certified" ]
  printf '{"action":"reopen","target":null,"at":9e9,"pins":{},"because":"x","provenance":{"claude_ancestor":false,"chain":["zsh","kitty"]}}\n' \
    >> "$CC_RESEARCH_HOME/demo/signoff.jsonl"
  run "$G" run --program demo
  [[ "$output" == *"REOPENED"* ]]
}

@test "an agent-written reopen does nothing" {
  "$G" run --program demo
  printf '{"action":"reopen","target":null,"at":9e9,"pins":{},"because":"x","provenance":{"claude_ancestor":false,"chain":["claude"]}}\n' \
    >> "$CC_RESEARCH_HOME/demo/signoff.jsonl"
  run "$G" run --program demo
  [[ "$output" != *"REOPENED"* ]]
}
