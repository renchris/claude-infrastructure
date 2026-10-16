#!/usr/bin/env bats
# research-kit-sweep — `gate.sh sweep` and `gate.sh file-packet` (REPORT.md §3.5, §5.4, §5.6; §10 items 4
# and 9). Fired class-B defaults reach the decision records; only an operator-SIGNED veto stops one;
# a class-C row past its due date converts to class B on its reversible option and descopes its waves;
# a frame-omission known row past its re-sign date closes by its default. Real bin/cc-decide, in a
# scratch decisions dir. RED-proof (2026-10-11): on the pre-fix gate_sweep.py the trigger, label and dropped-option
# refusals filed a packet (exit 0) and the fired default's ruling line carried no revisit_trigger.

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
  mkdir -p "$HOME"
  unset CC_BATS_ACTIVE CC_RESEARCH_RECORDS CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID CC_SESSION_ID
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  G="$REPO/scripts/research-kit/gate.sh"
  D="$REPO/bin/cc-decide"
  CR="$REPO/bin/cc-research"
  export W="$BATS_FILE_TMPDIR/w"
  export CC_RESEARCH_HOME="$W/home" CC_RESEARCH_REGISTRY="$W/home/programs.json"
  CC_NOW="$(cat "$BATS_FILE_TMPDIR/now")"
  export CC_NOW CC_RESEARCH_VAULT_KEY="test-key"
  rsync -a --delete "$BATS_FILE_TMPDIR/golden/" "$W/"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions" CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  REC="$(cat "$BATS_FILE_TMPDIR/records-path")"
  printf '{"id":"DR-1","status":"carried","blocks_waves":["B1"]}\n' >> "$REC/decisions.jsonl"
}

pkt() { /usr/bin/python3 -c "import json; print(json.load(open('$CC_DECISIONS_DIR/$1.json'))$2)"; }
dec() { /usr/bin/python3 -c "
import json; d={}
for l in open('$REC/decisions.jsonl'):
    r=json.loads(l)
    if r['id']=='DR-1': d.update(r)
print($1)"; }
B_OPTS=(--option "retry::writes retried" --option "do-nothing::no change" --option "use-what-exists::the current path")
file_b() {
  "$G" file-packet --program demo --decision DR-1 --class B --what "retry policy" "${B_OPTS[@]}" \
    --default retry --deadline "${1:-2026-10-01T00:00:00Z}" --conviction 80 --receipt "$REC/frame.json" \
    | awk '{print $2}'
}
last_dec() { tail -n 1 "$REC/decisions.jsonl" | /usr/bin/python3 -c "import json,sys; print(json.load(sys.stdin).get('$1'))"; }
no_trigger() { printf '{"id":"DR-1","revisit_trigger":null}\n' >> "$REC/decisions.jsonl"; }
n_packets() { find "$CC_DECISIONS_DIR" -name '*.json' 2>/dev/null | wc -l | tr -d ' '; }
file_c() {
  "$G" file-packet --program demo --decision DR-1 --class C --what "storage backend" --option "a::x" --option "b::y" \
    --conviction 70 --receipt "$REC/frame.json" --due "${1:-2026-09-30T00:00:00Z}" | awk '{print $2}'
}
sig() { # <action> <target|null>
  mkdir -p "$CC_RESEARCH_HOME/demo"
  printf '{"action":"%s","target":%s,"at":9e9,"at_iso":"2099-01-01T00:00:00Z","pins":{},"because":"x","provenance":{"claude_ancestor":false,"chain":["zsh","kitty"]}}\n' \
    "$1" "$2" >> "$CC_RESEARCH_HOME/demo/signoff.jsonl"
}

@test "file-packet files class B with the program's --project and --default-effect no-change" {
  id="$(file_b)"
  [ "$(pkt "$id" '["subject_project"]')" = "$W/repo" ] || [ "$(pkt "$id" '["subject_project"]')" = "$(cd "$W/repo" && pwd -P)" ]
  [ "$(pkt "$id" '["default_effect"]')" = "no-change" ]
  [ "$(dec 'd["packet"]["id"]')" = "$id" ]
}

@test "file-packet refuses a class-C packet with no due date" {
  run "$G" file-packet --program demo --decision DR-1 --class C --what x --option "a::x" --option "b::y" --conviction 70 --receipt "$REC/frame.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--due"* ]]
}

@test "file-packet refuses a class-B packet on a reversible decision with no revisit_trigger, and files nothing" {
  no_trigger
  run "$G" file-packet --program demo --decision DR-1 --class B --what x "${B_OPTS[@]}" --default retry \
    --deadline 2026-10-01T00:00:00Z --conviction 80 --receipt "$REC/frame.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"revisit_trigger"* ]] || false
  [ "$(n_packets)" = 0 ]
}

@test "file-packet --revisit-trigger records the trigger, and the fired default's ruling carries it" {
  no_trigger
  run "$G" file-packet --program demo --decision DR-1 --class B --what x "${B_OPTS[@]}" --default retry \
    --deadline 2026-10-01T00:00:00Z --conviction 80 --receipt "$REC/frame.json" --revisit-trigger "a retry storm"
  [ "$status" -eq 0 ]
  [ "$(last_dec revisit_trigger)" = "a retry storm" ]
  /bin/bash "$D" expire-sweep >/dev/null
  run "$G" sweep --program demo
  [ "$status" -eq 0 ]
  [ "$(last_dec ruled_by)" = "packet-default" ]
  [ "$(last_dec revisit_trigger)" = "a retry storm" ]
}

@test "file-packet refuses a class-B --option label that is not among the decision's options" {
  run "$G" file-packet --program demo --decision DR-1 --class B --what x "${B_OPTS[@]}" --option "rewrite::new store" \
    --default retry --deadline 2026-10-01T00:00:00Z --conviction 80 --receipt "$REC/frame.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"rewrite are not among DR-1's options"* ]] || false
  [ "$(n_packets)" = 0 ]
}

@test "file-packet refuses a class-B packet that drops one of the decision's options" {
  run "$G" file-packet --program demo --decision DR-1 --class B --what x --option "retry::writes retried" \
    --option "do-nothing::no change" --default retry --deadline 2026-10-01T00:00:00Z --conviction 80 --receipt "$REC/frame.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"drops DR-1's option(s) use-what-exists"* ]] || false
  [ "$(n_packets)" = 0 ]
}

@test "class C files with no trigger and its own labels, and an irreversible class-B decision files with no trigger" {
  no_trigger
  id="$(file_c)"
  [ "$(pkt "$id" '["class"]')" = "C" ]
  printf '{"id":"DR-1","reversibility":"irreversible","packet":null}\n' >> "$REC/decisions.jsonl"
  run "$G" file-packet --program demo --decision DR-1 --class B --what x --option "retry::writes retried" \
    --option "do-nothing::no change" --option "use-what-exists::the current path" --default retry \
    --deadline 2026-10-01T00:00:00Z --conviction 80 --receipt "$REC/frame.json"
  [ "$status" -eq 0 ]
}

overrun_stage4() {
  /usr/bin/python3 -c "
import json; p='$REC/budget.json'; d=json.load(open(p))
d.setdefault('stages', {})['4'] = {'started': '2026-09-01T00:00:00Z', 'ended': '2026-09-08T00:00:00Z'}
json.dump(d, open(p, 'w'))"
}
budget_pkt() { /usr/bin/python3 -c "import json; print((json.load(open('$REC/budget.json')).get('overrun_packets') or {}).get('$1', ''))"; }

@test "§6.5: --overrun-stage refuses a stage that is not over its cap, and writes nothing" {
  run "$G" file-packet --program demo --overrun-stage 4
  [ "$status" -eq 2 ]
  [[ "$output" == *"no overrun packet is due"* ]] || false
  [ -z "$(budget_pkt 4)" ]
}

@test "§6.5: --overrun-stage files one class-B proceed packet, records it, and row 12's check covers it" {
  overrun_stage4
  run "$G" file-packet --program demo --overrun-stage 4
  [ "$status" -eq 0 ]
  id="$(budget_pkt 4)"
  [ -n "$id" ]
  [ "$(pkt "$id" '["class"]')" = "B" ]
  [ "$(pkt "$id" '["default_if_no_veto"]')" = "proceed" ]
  [ "$(pkt "$id" '["default_effect"]')" = "no-change" ]
  [[ "$(pkt "$id" '["receipt"]')" == *"decisions closed"* ]] || false
  run "$G" file-packet --program demo --overrun-stage 4
  [ "$status" -eq 2 ]
  [[ "$output" == *"already has overrun packet $id"* ]] || false
  run "$G" sweep --program demo
  [ "$status" -eq 0 ]
}

@test "§6.5: --overrun-stage refuses a typed conviction" {
  overrun_stage4
  run "$G" file-packet --program demo --overrun-stage 4 --conviction 80
  [ "$status" -eq 2 ]
  [ -z "$(budget_pkt 4)" ]
}

@test "an expired class-B default is applied to the decision record" {
  id="$(file_b)"
  /bin/bash "$D" expire-sweep >/dev/null
  [ "$(pkt "$id" '["status"]')" = "expired-actioned" ]
  run "$G" sweep --program demo
  [ "$status" -eq 0 ]
  [ "$(dec 'd["status"], d["ruled_by"], d["chosen"], d["decided_by_default_at"]')" = "ruled packet-default retry 90" ]
  [ "$(last_dec revisit_trigger)" = "a lost write in build" ]
}

@test "a class-B default not yet expired is left alone" {
  file_b "$(date -u -v+96H +%Y-%m-%dT%H:%M:%SZ)" >/dev/null
  /bin/bash "$D" expire-sweep >/dev/null
  "$G" sweep --program demo
  [ "$(dec 'd["status"]')" = "carried" ]
}

@test "an operator-signed veto stops the default" {
  file_b >/dev/null
  /bin/bash "$D" expire-sweep >/dev/null
  sig veto '"DR-1"'
  run "$G" sweep --program demo
  [[ "$output" == *"vetoed-by-operator DR-1"* ]] || false
  [ "$(dec 'd["status"]')" = "carried" ]
}

@test "an agent-written veto signature does not stop the default" {
  file_b >/dev/null
  /bin/bash "$D" expire-sweep >/dev/null
  printf '{"action":"veto","target":"DR-1","at":9e9,"pins":{},"because":"x","provenance":{"claude_ancestor":false,"chain":["zsh","claude"]}}\n' \
    >> "$CC_RESEARCH_HOME/demo/signoff.jsonl"
  "$G" sweep --program demo
  [ "$(dec 'd["ruled_by"]')" = "packet-default" ]
}

@test "a cc-decide veto with no operator signature fails the sweep as UNSIGNED" {
  id="$(file_b "$(date -u -v+96H +%Y-%m-%dT%H:%M:%SZ)")"
  /bin/bash "$D" veto "$id" >/dev/null
  run "$G" sweep --program demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"UNSIGNED VETO"* ]]
}

@test "a class-C row past its due date converts to class B on its reversible option and descopes its waves" {
  old="$(file_c)"
  run "$G" sweep --program demo
  [ "$status" -eq 0 ]
  new="$(dec 'd["packet"]["id"]')"
  [ "$new" != "$old" ]
  [ "$(pkt "$old" '["status"]')" = "actioned" ]
  [ "$(pkt "$new" '["class"]')" = "B" ]
  [ "$(pkt "$new" '["default_if_no_veto"]')" = "do-nothing" ]
  [ "$(pkt "$new" '["default_effect"]')" = "no-change" ]
  [ "$(dec 'd["descoped_waves"]')" = "['B1']" ]
}

@test "a class-C row not yet due is left waiting" {
  old="$(file_c "$(date -u -v+1500H +%Y-%m-%dT%H:%M:%SZ)")"
  "$G" sweep --program demo
  [ "$(dec 'd["packet"]["id"]')" = "$old" ]
  [ "$(pkt "$old" '["status"]')" = "open" ]
}

@test "a class-C row past due with no reversible option cannot convert and fails the sweep" {
  printf '{"id":"DR-1","options":[{"label":"a"},{"label":"b"}]}\n' >> "$REC/decisions.jsonl"
  file_c >/dev/null
  run "$G" sweep --program demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"CANNOT CONVERT DR-1"* ]]
}

@test "§10 item 9: a frame-omission known row past its re-sign date closes by descoping its waves" {
  printf '{"id":"KR-1","kind":"frame-omission","status":"open","resign_due":"2026-09-30T06:00:00Z","default":"descope","blocks_waves":["B2"]}\n' \
    >> "$REC/known_rows.jsonl"
  run "$G" sweep --program demo
  [ "$status" -eq 0 ]
  tail -n 1 "$REC/known_rows.jsonl" | grep -q '"status": "closed"'
  tail -n 1 "$REC/known_rows.jsonl" | grep -q '"B2"'
}

@test "§10 item 9: a known row whose frame was re-signed after its due date stays open" {
  printf '{"id":"KR-1","kind":"frame-omission","status":"open","resign_due":"2026-09-29T00:00:00Z","default":"descope","blocks_waves":["B2"]}\n' \
    >> "$REC/known_rows.jsonl"
  "$G" sweep --program demo
  [ "$(grep -c '"closed"' "$REC/known_rows.jsonl")" -eq 0 ]
}

@test "§10 item 9: a class-b known-row default files a no-change class-B packet and closes the row" {
  printf '{"id":"KR-2","kind":"frame-omission","status":"open","resign_due":"2026-09-30T06:00:00Z","default":"class-b","names_rows":["AM-9"]}\n' \
    >> "$REC/known_rows.jsonl"
  run "$G" sweep --program demo
  [ "$status" -eq 0 ]
  id="$(tail -n 1 "$REC/known_rows.jsonl" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["packets"][0])')"
  [ "$(pkt "$id" '["default_effect"]')" = "no-change" ]
}

# ── an answer after a sweep conversion (RECORDS.md "An answer after a sweep conversion") ─────────
# RED-proof (2026-10-16): on ef35bed4e the decision verbs left `descoped_waves` in place and the
# converted class-B packet open, so `requires` refused the wave, the stub saw no `action`, and step 1
# ruled the answered decision by its default. The never-converted CONTROL passes on both.

certify() {
  /usr/bin/python3 -c "
import json, os
rec, reg = '$REC', '$CC_RESEARCH_REGISTRY'
os.makedirs(os.path.join(rec, 'cert'), exist_ok=True)
rows = {str(n): 'PASS' for n in range(1, 18)}
json.dump({'cert': 'CERT-v1', 'program': 'demo', 'version': 1, 'rows': rows},
          open(os.path.join(rec, 'cert', 'CERT-v1.json'), 'w'))
d = json.load(open(reg))
for p in d['programs']:
    if p['slug'] == 'demo':
        p['state'] = 'certified'
json.dump(d, open(reg, 'w'))"
}
convert() {
  file_c >/dev/null
  "$G" sweep --program demo >/dev/null
  [ "$(dec 'd["descoped_waves"]')" = "['B1']" ]
}
set_file() {
  printf '%s\n' '{"members":[{"label":"a","feasibility_probe":"P-1"},{"label":"b","feasibility_probe":"P-2"}],"narrowing_probe":{"wave":"B1","owner":"lead","due":"2099-01-01T00:00:00Z"},"revision_budget_h":4}' \
    > "$BATS_TEST_TMPDIR/set.json"
  echo "$BATS_TEST_TMPDIR/set.json"
}
# stub_decide <list-json|FAIL>: the kit's cc-decide seam pointed at a stub that logs its argv
stub_decide() {
  export CC_RESEARCH_CC_DECIDE="$BATS_TEST_TMPDIR/cc-decide-stub"
  export STUB_LOG="$BATS_TEST_TMPDIR/stub.log" STUB_LIST="$BATS_TEST_TMPDIR/stub-list"
  printf '%s\n' "$1" > "$STUB_LIST"
  printf '%s\n' '#!/bin/bash' \
    'printf "%s\n" "$*" >> "$STUB_LOG"' \
    '[ "$1" = list ] || exit 0' \
    'grep -qx FAIL "$STUB_LIST" && { echo "cc-decide: store unreadable" >&2; exit 1; }' \
    'cat "$STUB_LIST"' > "$CC_RESEARCH_CC_DECIDE"
}

@test "a ruling after a sweep conversion restores its waves, closes the class-B packet, and requires admits the wave" {
  printf '{"id":"DR-1","status":"reopened","reopened_by":"operator"}\n' >> "$REC/decisions.jsonl"
  convert
  new="$(dec 'd["packet"]["id"]')"
  certify
  run "$G" requires --program demo --wave B1
  [ "$status" -eq 1 ]
  [[ "$output" == *"DR-1: descoped wave B1"* ]] || false
  run "$CR" decision rule --program demo --id DR-1 --chosen retry --by operator \
    --receipt "operator: retry" --revisit-trigger "a retry storm"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DR-1: restored waves B1"* ]] || false
  [ "$(last_dec restored_waves)" = "['B1']" ]
  [ "$(dec 'd["descoped_waves"]')" = "[]" ]
  [ "$(pkt "$new" '["status"]')" = "actioned" ]
  run "$G" requires --program demo --wave B1
  [ "$status" -eq 0 ]
}

@test "a carry after a sweep conversion restores its waves, and requires admits the wave owning the set's narrowing probe" {
  convert
  certify
  run "$CR" decision carry --program demo --id DR-1 --because "converted by the sweep" \
    --receipt "operator: carry it" --set "$(set_file)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DR-1: restored waves B1"* ]] || false
  [ "$(dec 'd["descoped_waves"]')" = "[]" ]
  run "$G" requires --program demo --wave B1
  [ "$status" -eq 0 ]
}

@test "the verb actions the converted packet in cc-decide, and with cc-decide unreachable refuses and appends nothing (hermetic stub)" {
  printf '{"id":"DR-1","packet":{"id":"pkB","class":"B","due":"2099-01-01T00:00:00Z"},"converted_from":"pkC","descoped_waves":["B1"]}\n' \
    >> "$REC/decisions.jsonl"
  stub_decide FAIL
  before="$(cksum < "$REC/decisions.jsonl")"
  run env PATH=/usr/bin:/bin "$CR" decision carry --program demo --id DR-1 --because x \
    --receipt "operator: carry" --set "$(set_file)"
  [ "$status" -ne 0 ]
  [[ "$output" == *"nothing recorded"* ]] || false
  [ "$(cksum < "$REC/decisions.jsonl")" = "$before" ]
  stub_decide '[{"id":"pkB","class":"B","status":"open"}]'
  run env PATH=/usr/bin:/bin "$CR" decision carry --program demo --id DR-1 --because x \
    --receipt "operator: carry" --set "$(set_file)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"closed converted class-B packet pkB"* ]] || false
  grep -q '^action pkB --evidence answered by decision carry --by operator 20' "$STUB_LOG"
}

@test "sweep step 1 does not apply a fired default whose decision was answered after the conversion" {
  convert
  new="$(dec 'd["packet"]["id"]')"
  # an answer whose verb did not close the packet, so cc-decide still fires its default
  printf '{"id":"DR-1","status":"carried","carried_by":"operator","ts":"%s"}\n' "$CC_NOW" >> "$REC/decisions.jsonl"
  CC_NOW="$(date -u -v+100H +%Y-%m-%dT%H:%M:%SZ)" /bin/bash "$D" expire-sweep >/dev/null
  [ "$(pkt "$new" '["status"]')" = "expired-actioned" ]
  run "$G" sweep --program demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"default of $new not applied: DR-1 answered at $CC_NOW after conversion"* ]] || false
  [ "$(dec 'd["status"], d.get("ruled_by")')" = "carried agent" ]
  ! grep -q packet-default "$REC/decisions.jsonl"
}

@test "CONTROL: an answer to a decision the sweep never converted writes no wave fields and never calls cc-decide" {
  printf '{"id":"DR-1","status":"reopened","reopened_by":"operator"}\n' >> "$REC/decisions.jsonl"
  stub_decide FAIL
  run env PATH=/usr/bin:/bin "$CR" decision rule --program demo --id DR-1 --chosen retry --by operator \
    --receipt "operator: retry" --revisit-trigger t
  [ "$status" -eq 0 ]
  [ ! -e "$STUB_LOG" ]
  [ "$(last_dec descoped_waves)" = "None" ]
  [ "$(last_dec restored_waves)" = "None" ]
}
