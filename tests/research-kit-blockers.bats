#!/usr/bin/env bats
# research-kit-blockers — method v1.2, REPORT.md §12.2 and §12.3: a decision below 90 is tagged by
# what blocks it (research, production, operator), only production- and operator-blocked rows may
# be defaulted or carried, and the operator's menu prices one research extension per decision.
#
# Covers lib/blockers.py (the one tag), gate row 19, the extension items of `cc-research menu`,
# the `extend-decision` signature and `decision add --timebox-days`. Every case plants ONE decision
# into the known-good program (tests/fixtures/research-kit/build_good.py) and asserts the verdict.
# Times are hours before the suite's fixed CC_NOW.

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
  jedit frame.json "d['method_version']='1.2'"
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
# add <file> <json>: append one record.
add() { printf '%s\n' "$2" >> "$REC/$1"; }
# ago <hours>: that many hours before CC_NOW, ISO.
ago() {
  /usr/bin/python3 -c "import calendar,time; n=calendar.timegm(time.strptime('$CC_NOW','%Y-%m-%dT%H:%M:%SZ')); print(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(n-$1*3600)))"
}
# premise <id> <truth_lives_in>: a load-bearing premise below its required level (no probe).
premise() {
  add premises.jsonl "{\"id\":\"$1\",\"truth_lives_in\":\"$2\",\"verdict\":\"holds\",\"probes\":[],\"load_bearing_for\":[\"DR-9\"],\"origin\":{\"tier\":\"E0\"}}"
}
# decision <how: default|carried|operator> <started hours ago> <premise ids, comma separated> [flip result]
# DR-9, timebox 1 day, flip probe P-2 (a valid probe of the fixture).
decision() {
  local how='"status":"ruled","ruled_by":"packet-default","decided_by_default_at":44'
  [ "$1" = carried ] && how='"status":"carried"'
  [ "$1" = operator ] && how='"status":"ruled","ruled_by":"operator"'
  local prems; prems="$(printf '%s' "$3" | /usr/bin/python3 -c "import json,sys; print(json.dumps([x for x in sys.stdin.read().split(',') if x]))")"
  add decisions.jsonl "{\"id\":\"DR-9\",\"question\":\"queue\",$how,\"options\":[{\"label\":\"do-nothing\"},{\"label\":\"use-what-exists\"}],\"tally\":{\"premises\":$prems,\"flip_probe\":\"P-2\",\"flip_result\":\"${4:-negative}\"},\"reversibility\":\"reversible\",\"timebox_days\":1,\"research_started\":\"$(ago "$2")\"}"
}
# residual <premise id> <why>: a residual row naming that premise.
residual() {
  add residual.jsonl "{\"id\":\"RS-$1\",\"premise\":\"$1\",\"why_unreachable\":\"$2\",\"closest_probe\":\"P-1\",\"verify_cmd\":\"true\",\"owner\":\"agent\",\"due\":\"later\",\"backlog_id\":\"b9\",\"falsifier\":\"true\"}"
}
# sign <decision id>: a VALID operator extend-decision signature, as the operator's terminal leaves it.
sign() {
  mkdir -p "$CC_RESEARCH_HOME/demo"
  printf '{"action":"extend-decision","target":"%s","at":%s,"pins":{},"provenance":{"claude_ancestor":false,"chain":["zsh","kitty"]}}\n' \
    "$1" "$(date +%s)" >> "$CC_RESEARCH_HOME/demo/signoff.jsonl"
}
# tagof <field>: blockers.tag for DR-9.
tagof() {
  /usr/bin/python3 -c "
import json, sys
for p in ('$REPO/scripts/research-kit/lib', '$REPO/scripts/lib', '$REPO/scripts/research-kit'): sys.path.insert(0, p)
import blockers, gate, kit
ctx = gate.make_ctx('demo')
print(blockers.tag(ctx, kit.fold(ctx.jsonl('decisions.jsonl'))['DR-9'])['$1'])"
}
menu_ids() { "$R" menu --program demo --json | /usr/bin/python3 -c "import json,sys; print(' '.join(m['id'] for m in json.load(sys.stdin)))"; }

@test "tag: a premise below its level that a probe could raise is blocked by research" {
  premise PR-9 code
  decision default 10 PR-9
  [ "$(tagof tag)" = "research" ]
  [ "$(tagof conviction)" = "0" ]
  [ "$(tagof reachable_max)" = "90" ]
}

@test "tag: every premise at level but the flip probe not back negative is blocked by research" {
  decision default 10 PR-1 null
  [ "$(tagof tag)" = "research" ]
  [ "$(tagof gaps)" = "['flip-probe']" ]
}

@test "tag: a gap named by a production-traffic residual is blocked by production" {
  premise PR-9 behavior
  residual PR-9 production-traffic
  decision default 10 PR-9
  [ "$(tagof tag)" = "production" ]
}

@test "tag: a gap whose truth lives with the operator is blocked by the operator, and so is a decision with no factual premise" {
  premise PR-9 operator
  decision default 10 PR-9
  [ "$(tagof tag)" = "operator" ]
  decision default 10 ""
  [ "$(tagof tag)" = "operator" ]
  [ "$(tagof conviction)" = "None" ]
}

@test "tag: one research gap beside production and operator gaps reads research" {
  premise PR-7 operator
  premise PR-8 behavior
  residual PR-8 elapsed-time
  premise PR-9 code
  decision default 10 PR-7,PR-8,PR-9
  [ "$(tagof tag)" = "research" ]
  # research can close PR-9 only: 89 x 1 of 3
  [ "$(tagof reachable_max)" = "29" ]
}

@test "row 19: a decision defaulted while research could still close its gap fails, naming the gap" {
  premise PR-9 code
  decision default 10 PR-9
  [ "$(rowstat 19)" = "FAIL" ]
  [[ "$(rowtext 19)" == *"DR-9: decided by default at 0% while research can still close PR-9"* ]]
}

@test "row 19: a carried decision blocked by research fails the same way" {
  premise PR-9 code
  decision carried 10 PR-9
  [ "$(rowstat 19)" = "FAIL" ]
  [[ "$(rowtext 19)" == *"DR-9: carried at 0%"* ]]
}

@test "row 19: the same default blocked by production passes, and so does one blocked by the operator" {
  premise PR-9 behavior
  residual PR-9 production-traffic
  decision default 10 PR-9
  [ "$(rowstat 19)" = "PASS" ]
  [[ "$(rowtext 19)" == *"blocked by production"* ]] || false
  premise PR-8 operator
  decision default 10 PR-8
  [ "$(rowstat 19)" = "PASS" ]
  [[ "$(rowtext 19)" == *"blocked by operator"* ]]
}

@test "row 19: a research-blocked default past twice its timebox passes as defaulted at the research ceiling" {
  premise PR-9 code
  decision default 50 PR-9
  [ "$(rowstat 19)" = "PASS" ]
  [[ "$(rowtext 19)" == *"DR-9 defaulted at the research ceiling"* ]]
}

@test "row 19: a signed extension moves the ceiling one timebox later" {
  premise PR-9 code
  decision default 60 PR-9
  [ "$(rowstat 19)" = "PASS" ]
  sign DR-9
  [ "$(rowstat 19)" = "FAIL" ]
  [[ "$(rowtext 19)" == *"its research ceiling is not reached"* ]]
}

@test "row 19: a research-blocked default with no timebox on record fails as unknown" {
  premise PR-9 code
  decision default 50 PR-9
  add decisions.jsonl '{"id":"DR-9","timebox_days":null}'
  [ "$(rowstat 19)" = "FAIL" ]
  [[ "$(rowtext 19)" == *"timebox_days or research_started is not on record"* ]]
}

@test "row 19: two valid extensions on one decision fail the cap" {
  premise PR-9 code
  decision default 90 PR-9
  sign DR-9
  sign DR-9
  [ "$(rowstat 19)" = "FAIL" ]
  [[ "$(rowtext 19)" == *"2 research extensions signed; the cap is 1"* ]]
}

@test "row 19: a decision the operator ruled below 90 is not this row's business" {
  premise PR-9 code
  decision operator 10 PR-9
  [ "$(rowstat 19)" = "PASS" ]
}

@test "row 19: a frame signed under method 1.1 is not applicable" {
  premise PR-9 code
  decision default 10 PR-9
  jedit frame.json "d.pop('method_version')"
  [ "$(rowstat 19)" = "PASS" ]
  [[ "$(rowtext 19)" == *"not applicable"* ]]
}

@test "menu: a research-blocked decision gets one priced extension with its conviction, gaps and reach" {
  premise PR-9 code
  decision default 10 PR-9
  [ "$(menu_ids)" = "extra-round extend-decision/DR-9 reopen" ]
  run "$R" menu --program demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"price 1 research days on this decision"* ]] || false
  [[ "$output" == *"conviction now 0%; still below level: PR-9; research can raise it to at most 90%"* ]] || false
  [[ "$output" == *"cc-signoff research:demo/extend-decision/DR-9"* ]]
}

@test "menu: no extension for a production-blocked decision, nor once it is bought" {
  premise PR-9 behavior
  residual PR-9 production-traffic
  decision default 10 PR-9
  [ "$(menu_ids)" = "extra-round reopen" ]
  premise PR-8 code
  decision default 10 PR-8
  [ "$(menu_ids)" = "extra-round extend-decision/DR-9 reopen" ]
  sign DR-9
  [ "$(menu_ids)" = "extra-round reopen" ]
}

@test "menu: no extension under a 1.1 frame" {
  premise PR-9 code
  decision default 10 PR-9
  jedit frame.json "d.pop('method_version')"
  [ "$(menu_ids)" = "extra-round reopen" ]
}

# py <code>: the signing library with the operator's own terminal as its ancestry.
py() {
  /usr/bin/python3 -c "
import sys
for p in ('$REPO/scripts/lib', '$REPO/scripts/research-kit/lib'): sys.path.insert(0, p)
import operator_sign as o
o.ancestry = lambda pid=None: [{'pid': 2, 'comm': 'zsh', 'depth': 0}, {'pid': 3, 'comm': 'kitty', 'depth': 1}]
$1"
}

@test "signing: one extension per decision, a second for the same decision is refused, another decision is not" {
  premise PR-9 code
  decision default 10 PR-9
  run py "
o.sign_research('research:demo/extend-decision/DR-9', because='worth one more day')
o.sign_research('research:demo/extend-decision/DR-1', because='a different decision')
try:
    o.sign_research('research:demo/extend-decision/DR-9', because='again')
except o.Refused as e:
    print('REFUSED', 'already bought for DR-9' in str(e))
print(len(o.research_records('demo', 'extend-decision')))"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "REFUSED True" ]
  [ "${lines[1]}" = "2" ]
}

@test "signing: an extension needs a decision id, a reason, and a decision that exists" {
  run py "
print(o.parse_row('research:demo/extend-decision'))
for row, why in (('research:demo/extend-decision/DR-1', None), ('research:demo/extend-decision/DR-404', 'x')):
    try:
        o.sign_research(row, because=why)
    except o.Refused as e:
        print('REFUSED', 'needs --because' in str(e), 'is not a decision of demo' in str(e))"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "None" ]
  [ "${lines[1]}" = "REFUSED True False" ]
  [ "${lines[2]}" = "REFUSED False True" ]
  [ ! -e "$CC_RESEARCH_HOME/demo/signoff.jsonl" ] || [ "$(grep -c extend-decision "$CC_RESEARCH_HOME/demo/signoff.jsonl")" -eq 0 ]
}

@test "decision add: a 1.2 program needs the timebox and records when research started; 1.1 does not" {
  run "$R" decision add --program demo --id DR-20 --question q --option do-nothing --option use-what-exists
  [ "$status" -eq 2 ]
  [[ "$output" == *"needs --timebox-days"* ]] || false
  run "$R" decision add --program demo --id DR-20 --question q --option do-nothing --option use-what-exists --timebox-days 0.5
  [ "$status" -eq 0 ]
  [ "$(/usr/bin/python3 -c "import json; d=[json.loads(l) for l in open('$REC/decisions.jsonl')][-1]; print(d['timebox_days'], d['research_started'] == '$CC_NOW')")" = "0.5 True" ]
  jedit frame.json "d.pop('method_version')"
  run "$R" decision add --program demo --id DR-21 --question q --option do-nothing --option use-what-exists
  [ "$status" -eq 0 ]
  [ "$(/usr/bin/python3 -c "import json; d=[json.loads(l) for l in open('$REC/decisions.jsonl')][-1]; print('timebox_days' in d)")" = "False" ]
}
