#!/usr/bin/env bats
# research-kit-round — scripts/research-kit/round.sh enforces every round cap in code (REPORT.md
# §10 item 17, §6.5): the frame critique is exactly 2 rounds over >= 3 vendor families; certification
# rounds run in order up to R_max = min(round-1 p90 + 4, hard cap), +1 only for a VALID operator-signed
# extra round set; the stop rule ends review; a dead lane makes a round uncounted and is never filled.
# Prior rounds are written as fixture matrices; a fake courier stands in for the vendor CLIs.

setup() {
  unset CC_BATS_ACTIVE
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  R="$REPO/scripts/research-kit/round.sh"
  export CC_RESEARCH_HOME="$BATS_TEST_TMPDIR/research"
  export CC_RESEARCH_REGISTRY="$CC_RESEARCH_HOME/programs.json"
  export CC_RESEARCH_RECORDS="$BATS_TEST_TMPDIR/records"
  mkdir -p "$CC_RESEARCH_RECORDS/rounds"
  printf '{"profile":"lite","plan":"PLAN.md"}\n' > "$CC_RESEARCH_RECORDS/frame.json"
  printf '# plan\n' > "$CC_RESEARCH_RECORDS/PLAN.md"
  echo "review" > "$BATS_TEST_TMPDIR/brief.txt"
  export CC_RESEARCH_COURIER="$BATS_TEST_TMPDIR/courier"
  cat > "$CC_RESEARCH_COURIER" <<'EOF'
#!/bin/bash
verb="$1"; shift
rid=""; pid=""; vendor=""
while [ $# -gt 0 ]; do
  case "$1" in --round) rid="$2" ;; --pid) pid="$2" ;; --vendor) vendor="$2" ;; esac
  shift
done
if [ "$verb" = bundle ]; then echo "bundle $rid" >> "$CC_RESEARCH_RECORDS/runs.log"; exit 0; fi
[ "$verb" = run ] || exit 0
d="$CC_RESEARCH_RECORDS/rounds/$rid/panels"; mkdir -p "$d"
st=complete; rc=0
case " ${FAKE_DEAD:-} " in *" $vendor "*) st=dead; rc=3 ;; esac
printf '{"pid":"%s","status":"%s"}\n' "$pid" "$st" > "$d/$pid.json"
echo "$vendor $pid" >> "$CC_RESEARCH_RECORDS/runs.log"
exit "$rc"
EOF
  chmod +x "$CC_RESEARCH_COURIER"
  preflight 1
}

preflight() { # <age in hours> [dead vendor]: preflight.json as courier.sh preflight writes it
  mkdir -p "$CC_RESEARCH_HOME/demo"
  /usr/bin/python3 -c "
import json, sys, time
at = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(time.time() - float(sys.argv[1]) * 3600))
json.dump({v: {'ok': v != sys.argv[2], 'model_id': None, 'error': None if v != sys.argv[2] else 'walled', 'at': at}
           for v in ('anthropic', 'frontier', 'openai', 'google')}, open(sys.argv[3], 'w'))" \
    "$1" "${2:-}" "$CC_RESEARCH_HOME/demo/preflight.json"
}

mat() { # <dir> <kind> <seq> [extra json fields]
  mkdir -p "$CC_RESEARCH_RECORDS/rounds/$1"
  printf '{"round":"%s","kind":"%s","seq":%s,"closed":true,"counted":true%s}\n' "$1" "$2" "$3" "${4:-}" \
    > "$CC_RESEARCH_RECORDS/rounds/$1/matrix.json"
}
fc_done() { mat fc1 frame-critique 1; mat fc2 frame-critique 2; }
certs() { # <from> <to> [extra json]: closed, counted, not quiet
  local i; for i in $(seq "$1" "$2"); do mat "$i" certification "$i" ",\"quiet\":false,\"new_material\":1${3:-}"; done
}
run_cert() { run "$R" run --program demo --kind certification --round "$1" --plan "$CC_RESEARCH_RECORDS/PLAN.md" --brief "$BATS_TEST_TMPDIR/brief.txt"; }
sig() { # <chain-json>
  mkdir -p "$CC_RESEARCH_HOME/demo"
  printf '{"action":"extra-round","target":null,"at":1,"pins":{},"because":"x","provenance":{"claude_ancestor":false,"chain":%s}}\n' "$1" \
    >> "$CC_RESEARCH_HOME/demo/signoff.jsonl"
}
field() { /usr/bin/python3 -c "import json; m=json.load(open('$CC_RESEARCH_RECORDS/rounds/$1/matrix.json')); print($2)"; }

@test "a third frame-critique round is refused" {
  fc_done
  run "$R" run --program demo --kind frame-critique --round 3 --plan "$CC_RESEARCH_RECORDS/PLAN.md" --brief "$BATS_TEST_TMPDIR/brief.txt"
  [ "$status" -eq 2 ]
  [[ "$output" == *"exactly 2"* ]]
}

@test "a frame-critique round over two vendor families is refused" {
  printf '{"profile":"lite","frame_critique_slots":[["anthropic","s"],["frontier","s"],["anthropic","s"],["openai","s"],["openai","s"],["frontier","s"]]}\n' \
    > "$CC_RESEARCH_RECORDS/frame.json"
  run "$R" run --program demo --kind frame-critique --round 1 --plan "$CC_RESEARCH_RECORDS/PLAN.md" --brief "$BATS_TEST_TMPDIR/brief.txt"
  [ "$status" -eq 2 ]
  [[ "$output" == *"2 vendor families"* ]]
}

@test "a frame-critique round runs 6 slots across 3 families" {
  run "$R" run --program demo --kind frame-critique --round 1 --plan "$CC_RESEARCH_RECORDS/PLAN.md" --brief "$BATS_TEST_TMPDIR/brief.txt"
  [ "$status" -eq 0 ]
  [ "$(field fc1 'len(m["slots"]), m["counted"]')" = "6 True" ]
}

@test "certification before both frame-critique rounds is refused" {
  mat fc1 frame-critique 1
  run_cert 1
  [ "$status" -eq 2 ]
  [[ "$output" == *"frame-critique"* ]]
}

@test "skipping a certification round is refused" {
  fc_done
  run_cert 2
  [ "$status" -eq 2 ]
  [[ "$output" == *"out of order"* ]]
}

@test "a round before the previous one closed is refused" {
  fc_done; mat 1 certification 1 ',"quiet":false'
  /usr/bin/python3 -c "import json; p='$CC_RESEARCH_RECORDS/rounds/1/matrix.json'; m=json.load(open(p)); m['closed']=False; json.dump(m, open(p,'w'))"
  run_cert 2
  [ "$status" -eq 2 ]
  [[ "$output" == *"not closed"* ]]
}

@test "a round past R_max = round-1 p90 + 4 is refused" {
  fc_done; certs 1 5
  /usr/bin/python3 -c "import json; p='$CC_RESEARCH_RECORDS/rounds/1/matrix.json'; m=json.load(open(p)); m['forecast']={'p50':1,'p90':1}; json.dump(m, open(p,'w'))"
  run_cert 6
  [ "$status" -eq 2 ]
  [[ "$output" == *"past R_max = 5"* ]]
}

@test "the hard cap binds even when the forecast is generous" {
  fc_done; certs 1 6
  /usr/bin/python3 -c "import json; p='$CC_RESEARCH_RECORDS/rounds/1/matrix.json'; m=json.load(open(p)); m['forecast']={'p50':9,'p90':12}; json.dump(m, open(p,'w'))"
  run_cert 7
  [ "$status" -eq 2 ]
  [[ "$output" == *"past R_max = 6"* ]]
}

@test "a VALID extra round set allows one more round, and that round is verification-only" {
  fc_done; certs 1 6
  sig '["zsh","kitty"]'
  run_cert 7
  [ "$status" -eq 0 ]
  [ "$(field 7 'm["verification_only"], m["r_max"]')" = "True 7" ]
}

@test "an agent-written extra round signature buys nothing" {
  fc_done; certs 1 6
  sig '["zsh","claude"]'
  run_cert 7
  [ "$status" -eq 2 ]
  [[ "$output" == *"past R_max = 6"* ]]
}

lost() { # <round>...: closed rounds lost to a dead lane (uncounted)
  local i; for i in "$@"; do
    mat "$i" certification "$i" ',"quiet":false,"new_material":0'
    /usr/bin/python3 -c "import json; p='$CC_RESEARCH_RECORDS/rounds/$i/matrix.json'; m=json.load(open(p)); m['counted']=False; json.dump(m, open(p,'w'))"
  done
}

@test "rounds lost to a dead lane do not spend R_max: the counted round at the boundary still runs" {
  fc_done; certs 1 4; lost 5 6
  /usr/bin/python3 -c "import json; p='$CC_RESEARCH_RECORDS/rounds/1/matrix.json'; m=json.load(open(p)); m['forecast']={'p50':1,'p90':1}; json.dump(m, open(p,'w'))"
  run_cert 7
  [ "$status" -eq 0 ]
  [ "$(field 7 'm["verification_only"], m["r_max"]')" = "True 5" ]
}

@test "past the cap on uncounted rounds no round opens until the lane is restored" {
  fc_done; certs 1 2; lost 3 4 5
  run_cert 6
  [ "$status" -eq 2 ]
  [[ "$output" == *"uncounted"*"restored"* ]]
}

@test "a stale vendor preflight refuses a certification round before any round dir is written" {
  fc_done; preflight 30
  run_cert 1
  [ "$status" -eq 3 ]
  [[ "$output" == *"stale"* ]]
  [ ! -e "$CC_RESEARCH_RECORDS/rounds/1" ]
}

@test "a dead lane in a fresh preflight refuses a certification round" {
  fc_done; preflight 1 openai
  run_cert 1
  [ "$status" -eq 3 ]
  [[ "$output" == *"dead lane(s) openai"* ]]
  [ ! -e "$CC_RESEARCH_RECORDS/rounds/1" ]
}

@test "after K quiet counted rounds the stop rule refuses another round" {
  fc_done; certs 1 1
  mat 2 certification 2 ',"quiet":true,"new_material":0'
  mat 3 certification 3 ',"quiet":true,"new_material":0'
  run_cert 4
  [ "$status" -eq 2 ]
  [[ "$output" == *"stop rule has fired"* ]]
}

@test "a dead lane leaves the round uncounted, retries its slots twice, and never reassigns them" {
  fc_done
  FAKE_DEAD=google run_cert 1
  [ "$status" -eq 3 ]
  [ "$(field 1 'm["counted"], m["lanes"]["google"], len(m["slots"])')" = "False dead 8" ]
  [ "$(grep -c '^google ' "$CC_RESEARCH_RECORDS/runs.log")" -eq 6 ]
  [ "$(grep -c '^openai ' "$CC_RESEARCH_RECORDS/runs.log")" -eq 2 ]
}

@test "close: a round that catches only seeds stays quiet" {
  fc_done; mat 2 certification 2 ',"quiet":false'
  /usr/bin/python3 -c "import json; p='$CC_RESEARCH_RECORDS/rounds/2/matrix.json'; m=json.load(open(p)); m['closed']=False; json.dump(m, open(p,'w'))"
  printf '%s\n' '{"id":"H-1","round":2,"verification":{"status":"CONFIRMED"},"materiality":{"level":"MATERIAL"},"seed_match":"S-3"}' \
    > "$CC_RESEARCH_RECORDS/holes.jsonl"
  run "$R" close --program demo --round 2
  [ "$status" -eq 0 ]
  [ "$(field 2 'm["quiet"], m["seeds_caught"], m["new_material"]')" = "True 1 0" ]
}

@test "close: a confirmed material finding breaks the quiet streak" {
  fc_done; mat 2 certification 2 ',"quiet":false'
  /usr/bin/python3 -c "import json; p='$CC_RESEARCH_RECORDS/rounds/2/matrix.json'; m=json.load(open(p)); m['closed']=False; json.dump(m, open(p,'w'))"
  printf '%s\n' '{"id":"H-2","round":2,"verification":{"status":"CONFIRMED"},"materiality":{"level":"MATERIAL"}}' \
    > "$CC_RESEARCH_RECORDS/holes.jsonl"
  "$R" close --program demo --round 2
  [ "$(field 2 'm["quiet"], m["new_material"]')" = "False 1" ]
}

open_with_slots() { # <round> <status of slot 2> <True|False counted>: an unclosed round whose matrix records its slots
  mat "$1" certification "$1" ',"quiet":false'
  /usr/bin/python3 -c "import json; p='$CC_RESEARCH_RECORDS/rounds/$1/matrix.json'; m=json.load(open(p)); m['closed']=False; m['counted']=$3
m['slots']=[{'pid':'r$1p1','vendor':'openai','status':'complete'},{'pid':'r$1p2','vendor':'google','status':'$2'}]
json.dump(m, open(p,'w'))"
}

@test "close: a counted round with a planned slot that is not complete is refused and stays open" {
  fc_done; open_with_slots 2 partial True
  run "$R" close --program demo --round 2
  [ "$status" -eq 2 ]
  [[ "$output" == *"r2p2 (partial)"* ]]
  [ "$(field 2 'm["closed"]')" = "False" ]
}

@test "close: a counted round whose planned slots all completed closes" {
  fc_done; open_with_slots 2 complete True
  run "$R" close --program demo --round 2
  [ "$status" -eq 0 ]
  [ "$(field 2 'm["closed"], m["quiet"]')" = "True True" ]
}

@test "close: an uncounted round with a dead slot still closes, as uncounted" {
  fc_done; open_with_slots 2 dead False
  run "$R" close --program demo --round 2
  [ "$status" -eq 0 ]
  [ "$(field 2 'm["closed"], m["counted"], m["quiet"]')" = "True False False" ]
}

interrupted_round_1() { # the process died after the bundle and plan: r1p1 complete, r1p2 partial, no matrix
  fc_done
  mkdir -p "$CC_RESEARCH_HOME/demo/rounds/1/bundle" "$CC_RESEARCH_RECORDS/rounds/1/panels"
  /usr/bin/python3 -c "import json, sys; sys.path.insert(0, '$REPO/scripts/research-kit/lib'); import round as r
rid, slots, vonly, rmax = r.plan_slots('demo', 'certification', 1, None)
rows = [{'pid': 'r%sp%d' % (rid, i), 'vendor': v, 'strategy': s, 'role': 'reviewer', 'round': rid} for i, (v, s) in enumerate(slots, 1)]
json.dump({'round': rid, 'seq': 1, 'kind': 'certification', 'escape': None, 'verification_only': vonly, 'r_max': rmax, 'slots': rows},
          open('$CC_RESEARCH_RECORDS/rounds/1/plan.json', 'w'))"
  printf '{"pid":"r1p1","status":"complete"}\n' > "$CC_RESEARCH_RECORDS/rounds/1/panels/r1p1.json"
  printf '{"pid":"r1p2","status":"partial"}\n' > "$CC_RESEARCH_RECORDS/rounds/1/panels/r1p2.json"
}

@test "re-entering a round that died before its matrix resumes it: only the slots with no complete panel re-run" {
  interrupted_round_1
  run_cert 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"resumed"*"r1p2"* ]]
  run grep -c '^bundle ' "$CC_RESEARCH_RECORDS/runs.log"
  [ "$output" = "0" ]
  run grep -c ' r1p' "$CC_RESEARCH_RECORDS/runs.log"
  [ "$output" = "7" ]
  run grep -c ' r1p1$' "$CC_RESEARCH_RECORDS/runs.log"
  [ "$output" = "0" ]
  [ "$(field 1 'len(m["slots"]), sorted({s["status"] for s in m["slots"]}), m["counted"]')" = "8 ['complete'] True" ]
}

@test "a fresh round builds its bundle and records its plan before any slot runs" {
  fc_done
  run_cert 1
  [ "$status" -eq 0 ]
  run grep -c '^bundle 1$' "$CC_RESEARCH_RECORDS/runs.log"
  [ "$output" = "1" ]
  [ -f "$CC_RESEARCH_RECORDS/rounds/1/plan.json" ]
}

@test "a third delta round for one escape is refused" {
  mat delta-H-9-1 delta 1 ',"escape":"H-9"'
  mat delta-H-9-2 delta 2 ',"escape":"H-9"'
  run "$R" run --program demo --kind delta --escape H-9 --round 3 --plan "$CC_RESEARCH_RECORDS/PLAN.md" --brief "$BATS_TEST_TMPDIR/brief.txt"
  [ "$status" -eq 2 ]
  [[ "$output" == *"capped at 2"* ]]
}

seeded_round_2() { # plants S-1 (replace, class C4) on PLAN.md:61 and an omission seed, opens round 2
  export CC_RESEARCH_VAULT_KEY="test-key"
  local p="$CC_RESEARCH_RECORDS/PLAN.md" i
  : > "$p"
  for i in $(seq 1 60); do echo "filler line $i of the plan that says nothing at all" >> "$p"; done
  echo "The sync daemon retries a failed write three times with a 2 s backoff." >> "$p"
  echo "Population: callers are hooks/a.sh, hooks/b.sh and the launchd job cc-sync." >> "$p"
  /usr/bin/python3 -c 'import json
print(json.dumps({"sid":"S-1","cohort":"original","class":"C4","op":"replace","anchor_quote":"The sync daemon retries a failed write three times with a 2 s backoff.","replacement":"The sync daemon retries a failed write forever with no backoff at all.","defect_statement":"the retry count is unbounded, so a failed write loops forever","detect_span":"PLAN.md:61-61"}))
print(json.dumps({"sid":"S-2","cohort":"original","class":"C2","op":"delete-member","anchor_quote":"Population: callers are hooks/a.sh, hooks/b.sh and the launchd job cc-sync.","replacement":"","defect_statement":"the launchd caller is missing from the population","detect_span":"PLAN.md:62-62"}))' \
    > "$BATS_TEST_TMPDIR/seeds.jsonl"
  "$REPO/scripts/research-kit/seed.py" plant --program demo --plan "$p" --seeds "$BATS_TEST_TMPDIR/seeds.jsonl"
  fc_done; mat 2 certification 2 ',"quiet":false'
  /usr/bin/python3 -c "import json; p='$CC_RESEARCH_RECORDS/rounds/2/matrix.json'; m=json.load(open(p)); m['closed']=False; json.dump(m, open(p,'w'))"
}
# Same lines, same class: H-1 states the seed's defect, H-2 a different one.
SEED_HOLE='{"id":"H-1","round":2,"locus":{"path":"PLAN.md","lines":"61"},"taxonomy_class":"C4","claim":"the daemon retries a failed write forever: the retry count is unbounded","verification":{"status":"CONFIRMED"},"materiality":{"level":"MATERIAL"}}'
REAL_HOLE='{"id":"H-2","round":2,"locus":{"path":"PLAN.md","lines":"61"},"taxonomy_class":"C4","claim":"the 2 s backoff figure has no source and contradicts the measured p95 of the store","verification":{"status":"CONFIRMED"},"materiality":{"level":"MATERIAL"}}'
seed_match_of() { /usr/bin/python3 -c "import json; s={}
for l in open('$CC_RESEARCH_RECORDS/holes.jsonl'): r=json.loads(l); s.setdefault(r['id'], {}).update(r)
print(s['$1'].get('seed_match'))"; }

@test "close: a caught seed is tagged and is not a real finding; a different defect on its lines is" {
  seeded_round_2
  printf '%s\n' "$SEED_HOLE" "$REAL_HOLE" > "$CC_RESEARCH_RECORDS/holes.jsonl"
  run "$R" close --program demo --round 2
  [ "$status" -eq 0 ]
  [ "$(field 2 'm["new_material"], m["seeds_caught"], m["quiet"]')" = "1 1 False" ]
  [ "$(seed_match_of H-1)" = "S-1" ]
  [ "$(seed_match_of H-2)" = "None" ]
}

@test "close: a round whose only material finding is a caught seed is quiet" {
  seeded_round_2
  printf '%s\n' "$SEED_HOLE" > "$CC_RESEARCH_RECORDS/holes.jsonl"
  run "$R" close --program demo --round 2
  [ "$status" -eq 0 ]
  [ "$(field 2 'm["quiet"], m["seeds_caught"], m["new_material"]')" = "True 1 0" ]
}
