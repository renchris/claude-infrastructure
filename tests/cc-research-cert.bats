#!/usr/bin/env bats
# cc-research-cert — the certification verbs of bin/cc-research (lib/cli_cert.py, REPORT.md §8 item
# 11, §3.8): the slot plan is round.py's, the rater assignment and the responding-model check are
# computed in code (check-round voids a slot, exit 4), and `rehearse record` passes the relay test
# only on >= 20 clean trials with one asked from outside the program root, one re-test allowed.
# The Workflows are checked by syntax and by a stub harness (tests/fixtures/research-kit/run-workflow.mjs).

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
  T="$BATS_FILE_TMPDIR/t$BATS_TEST_NUMBER"
  ROOT="$T/prog"
  export CC_RESEARCH_HOME="$T/home"
  export CC_RESEARCH_REGISTRY="$T/home/programs.json"
  export CC_RESEARCH_RECORDS="$ROOT/docs/research/demo"
  mkdir -p "$CC_RESEARCH_HOME" "$CC_RESEARCH_RECORDS/rounds" "$T/elsewhere"
  printf '{"programs":[{"slug":"demo","aliases":["the demo"],"cwd_roots":["%s"],"state":"certified"}]}\n' \
    "$ROOT" > "$CC_RESEARCH_REGISTRY"
  frame '{}'
  export CC_RESEARCH_RENDER='printf "demo: certified on snapshot abc\n"'
}

frame() { # <extra json merged into the lite frame>
  /usr/bin/python3 -c "
import json, sys
f = {'profile': 'lite', 'plan': 'PLAN.md', 'reviewer_pins': {'anthropic': 'claude-opus-5-5',
     'frontier': 'claude-fable-5-1', 'openai': 'gpt-6', 'google': 'gemini-4'},
     'reask_map': [{'frame': 'are you sure', 'axis': 'conviction'}, {'frame': 'old', 'axis': None}]}
f.update(json.loads(sys.argv[1]))
json.dump(f, open('$CC_RESEARCH_RECORDS/frame.json', 'w'))" "$1"
}

fc_done() {
  local r
  for r in 1 2; do
    mkdir -p "$CC_RESEARCH_RECORDS/rounds/fc$r"
    printf '{"round":"fc%s","kind":"frame-critique","seq":%s,"closed":true,"counted":true}\n' "$r" "$r" \
      > "$CC_RESEARCH_RECORDS/rounds/fc$r/matrix.json"
  done
}

panel() { # <pid> <vendor> <role> <responding model> [raw text]
  local d="$CC_RESEARCH_RECORDS/rounds/1/panels"
  mkdir -p "$d"
  printf '{"pid":"%s","vendor":"%s","role":"%s","responding_model":"%s","status":"complete","integrity":{"hits":[]}}\n' \
    "$1" "$2" "$3" "$4" > "$d/$1.json"
  printf '%s\n' "${5:-a clean review}" > "$d/$1.raw"
}

good_panels() {
  panel r1p1 anthropic reviewer claude-opus-5-5
  panel r1p2 frontier reviewer claude-fable-5-1
  panel r1p3 openai reviewer gpt-6
  panel r1p4 google reviewer gemini-4
}

trials() { # <n> <cwd of trial 1> [reply of trial 2] [tool of trial 3]
  /usr/bin/python3 -c "
import json, sys
n, cwd1, reply2, tool3, inside = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
with open(sys.argv[6], 'w') as fh:
    for i in range(1, n + 1):
        fh.write(json.dumps({'trial': i, 'prompt': 'Are you sure?',
            'reply': reply2 if i == 2 and reply2 else 'demo: certified on snapshot abc',
            'tools': [tool3 if i == 3 and tool3 else 'cc-research verdict demo'],
            'cwd': cwd1 if i == 1 else inside}) + '\n')
" "$1" "$2" "${3:-}" "${4:-}" "$ROOT" "$T/trials.jsonl"
}

rh() { /usr/bin/python3 -c "import json; r=json.load(open('$CC_RESEARCH_RECORDS/rehearsal.json')); print($1)"; }

# ── slots ───────────────────────────────────────────────────────────────────────────────────────

@test "slots equal round.plan_slots for a lite certification round" {
  fc_done
  run "$CR" slots --program demo --kind certification --round 1 --json
  [ "$status" -eq 0 ]
  echo "$output" > "$T/slots.json"
  run /usr/bin/python3 -c "
import json, sys
sys.path.insert(0, '$REPO/scripts/research-kit/lib'); sys.path.insert(0, '$REPO/scripts/lib')
import round as r
rid, slots, _, _ = r.plan_slots('demo', 'certification', 1, None)
got = json.load(open('$T/slots.json'))
want = [{'pid': 'r%sp%d' % (rid, i), 'vendor': v, 'strategy': s, 'role': 'reviewer'} for i, (v, s) in enumerate(slots, 1)]
assert [{k: g[k] for k in ('pid', 'vendor', 'strategy', 'role')} for g in got] == want, got
assert len(got) == 8
print('same')"
  [ "$status" -eq 0 ]
  [ "$output" = same ]
}

# ── raters ──────────────────────────────────────────────────────────────────────────────────────

@test "raters: rater 1 is never Anthropic and the three raters span three families" {
  run "$CR" raters --program demo --round 1 --json
  [ "$status" -eq 0 ]
  echo "$output" > "$T/r.json"
  run /usr/bin/python3 -c "
import json; r = json.load(open('$T/r.json'))
fam = [x['family'] for x in r]
assert fam[0] != 'anthropic', fam
assert len(set(fam)) == 3, fam
print('ok')"
  [ "$output" = ok ]
}

@test "raters: two-vendor default makes rater 3 a fresh process from rater 1's vendor" {
  frame '{"degraded":"two vendors","dead_lanes":["google"]}'
  run "$CR" raters --program demo --round 1 --json
  [ "$status" -eq 0 ]
  echo "$output" > "$T/r.json"
  run /usr/bin/python3 -c "
import json; r = json.load(open('$T/r.json'))
assert r[0]['vendor'] == 'openai' and r[1]['family'] == 'anthropic', r
assert r[2]['vendor'] == r[0]['vendor'] and r[2]['fresh_process'] is True, r
print('ok')"
  [ "$output" = ok ]
}

@test "raters: refused (exit 3) with one live family" {
  frame '{"degraded":"two vendors","dead_lanes":["openai","google"]}'
  run "$CR" raters --program demo --round 1 --json
  [ "$status" -eq 3 ]
  [[ "$output" == *"non-Anthropic"* ]]
}

# ── check-round ─────────────────────────────────────────────────────────────────────────────────

@test "check-round passes a set whose responding models match the pins" {
  good_panels
  run "$CR" check-round --program demo --round 1
  [ "$status" -eq 0 ]
  [ ! -s "$CC_RESEARCH_RECORDS/rounds/1/check.jsonl" ]
}

@test "check-round voids a panel whose responding model differs from its pin (exit 4)" {
  good_panels
  panel r1p3 openai reviewer gpt-5-mini
  run "$CR" check-round --program demo --round 1 --json
  [ "$status" -eq 4 ]
  grep -q '"pid": "r1p3"' "$CC_RESEARCH_RECORDS/rounds/1/check.jsonl"
  grep -q 'gpt-5-mini' "$CC_RESEARCH_RECORDS/rounds/1/check.jsonl"
  run /usr/bin/python3 -c "import json; print(json.load(open('$CC_RESEARCH_RECORDS/rounds/1/panels/r1p3.json'))['status'])"
  [ "$output" = void ]
}

@test "check-round voids a rater from the wrong vendor" {
  good_panels
  panel r1rater1 google rater gemini-4
  run "$CR" check-round --program demo --round 1 --json
  [ "$status" -eq 4 ]
  grep -q '"pid": "r1rater1"' "$CC_RESEARCH_RECORDS/rounds/1/check.jsonl"
  grep -q 'rater slot 1' "$CC_RESEARCH_RECORDS/rounds/1/check.jsonl"
}

@test "check-round voids an integrity hit and stays append-only on a second pass" {
  good_panels
  panel r1p4 google reviewer gemini-4 "read $CC_RESEARCH_RECORDS/frame.json"
  run "$CR" check-round --program demo --round 1
  [ "$status" -eq 4 ]
  run "$CR" check-round --program demo --round 1
  [ "$status" -eq 4 ]
  [ "$(grep -c '"pid": "r1p4"' "$CC_RESEARCH_RECORDS/rounds/1/check.jsonl")" -eq 1 ]
}

# ── rehearse record ─────────────────────────────────────────────────────────────────────────────

@test "rehearse record passes 20 clean trials with one asked from outside the root" {
  trials 20 "$T/elsewhere"
  run "$CR" rehearse record --program demo --frames-typed "are you sure" --trials "$T/trials.jsonl"
  [ "$status" -eq 0 ]
  [ "$(rh "r['relay']['passed'], r['relay']['trials'], r['relay']['unstable'], r['frames_typed']")" = "True 20 False ['are you sure']" ]
}

@test "rehearse record fails 19 trials" {
  trials 19 "$T/elsewhere"
  run "$CR" rehearse record --program demo --frames-typed x --trials "$T/trials.jsonl"
  [ "$status" -eq 1 ]
  [ "$(rh "r['relay']['passed']")" = False ]
}

@test "rehearse record fails a reply naming a row the certificate does not carry" {
  trials 20 "$T/elsewhere" "demo: certified on snapshot abc
row 7 is still open"
  run "$CR" rehearse record --program demo --frames-typed x --trials "$T/trials.jsonl"
  [ "$status" -eq 1 ]
  [[ "$output" == *"trial 2"* ]]
}

@test "rehearse record fails a tool other than the certificate read" {
  trials 20 "$T/elsewhere" "" "cat $ROOT/docs/research/demo/frame.json"
  run "$CR" rehearse record --program demo --frames-typed x --trials "$T/trials.jsonl"
  [ "$status" -eq 1 ]
  [[ "$output" == *"trial 3"* ]]
}

@test "rehearse record fails when every trial is inside the program root" {
  trials 20 "$ROOT/docs"
  run "$CR" rehearse record --program demo --frames-typed x --trials "$T/trials.jsonl"
  [ "$status" -eq 1 ]
  [[ "$output" == *"outside"* ]]
}

@test "rehearse: a failed re-test marks relay unstable and a third record is refused" {
  trials 19 "$T/elsewhere"
  run "$CR" rehearse record --program demo --frames-typed x --trials "$T/trials.jsonl"
  [ "$status" -eq 1 ]
  run "$CR" rehearse record --program demo --frames-typed x --trials "$T/trials.jsonl" --retest
  [ "$status" -eq 1 ]
  [ "$(rh "r['relay']['unstable']")" = True ]
  run "$CR" rehearse record --program demo --frames-typed x --trials "$T/trials.jsonl" --retest
  [ "$status" -eq 2 ]
}

# ── workflows ───────────────────────────────────────────────────────────────────────────────────

@test "every workflow parses as the async body the Workflow runtime compiles" {
  # A bare `node --check` refuses every Workflow script (top-level return/await, as in
  # docs/research/research-calibration/workflows/review.workflow.js); --check compiles the body.
  local f
  for f in round frame-critique rehearsal; do
    run node "$REPO/tests/fixtures/research-kit/run-workflow.mjs" --check "$REPO/scripts/research-kit/workflows/$f.workflow.js"
    [ "$status" -eq 0 ]
    [ "$output" = "parse ok" ]
  done
}

@test "round.workflow.js calls check-round after the slots, and names only cc-research commands" {
  run node "$REPO/tests/fixtures/research-kit/run-workflow.mjs" "$REPO/scripts/research-kit/workflows/round.workflow.js"
  [ "$status" -eq 0 ]
  [[ "$output" == *"order ok"* ]] || false
  [[ "$output" == *"commands ok"* ]]
}

@test "frame-critique and rehearsal workflows name only cc-research commands" {
  local f
  for f in frame-critique rehearsal; do
    run node "$REPO/tests/fixtures/research-kit/run-workflow.mjs" "$REPO/scripts/research-kit/workflows/$f.workflow.js"
    [ "$status" -eq 0 ]
    [[ "$output" == *"commands ok"* ]] || false
  done
}
