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
case " ${FAKE_PARTIAL:-} " in *" $vendor "*) st=partial ;; esac
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
  [[ "$output" == *"stale"* ]] || false
  [ ! -e "$CC_RESEARCH_RECORDS/rounds/1" ]
}

@test "a dead lane in a fresh preflight refuses a certification round" {
  fc_done; preflight 1 openai
  run_cert 1
  [ "$status" -eq 3 ]
  [[ "$output" == *"dead lane(s) openai"* ]] || false
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

@test "a partial slot is re-run like a dead one, and a lane still partial after its reruns is dead, so the round is uncounted and closes" {
  fc_done
  FAKE_PARTIAL=google run_cert 1
  [ "$status" -eq 3 ]
  [ "$(field 1 'm["counted"], m["lanes"]["google"]')" = "False dead" ]
  [ "$(grep -c '^google ' "$CC_RESEARCH_RECORDS/runs.log")" -eq 6 ]
  run "$R" close --program demo --round 1
  [ "$status" -eq 0 ]
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
  [[ "$output" == *"r2p2 (partial)"* ]] || false
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
  [[ "$output" == *"resumed"*"r1p2"* ]] || false
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

@test "close: a material hole from a frame-critique round is skipped by seed match, never parsed as a round number" {
  seeded_round_2
  local fc_hole='{"id":"H-0","round":"fc1","locus":{"path":"PLAN.md","lines":"61"},"taxonomy_class":"C4","claim":"the daemon retries a failed write forever: the retry count is unbounded","verification":{"status":"CONFIRMED"},"materiality":{"level":"MATERIAL"}}'
  printf '%s\n' "$fc_hole" "$SEED_HOLE" > "$CC_RESEARCH_RECORDS/holes.jsonl"
  run "$R" close --program demo --round 2
  [ "$status" -eq 0 ]
  [ "$(seed_match_of H-0)" = "None" ]
  [ "$(seed_match_of H-1)" = "S-1" ]
}

@test "close: a round whose only material finding is a caught seed is quiet" {
  seeded_round_2
  printf '%s\n' "$SEED_HOLE" > "$CC_RESEARCH_RECORDS/holes.jsonl"
  run "$R" close --program demo --round 2
  [ "$status" -eq 0 ]
  [ "$(field 2 'm["quiet"], m["seeds_caught"], m["new_material"]')" = "True 1 0" ]
}

# Re-close (2026-10-11): a round closed under a matcher that missed its seed catches is recomputed
# from the re-tagged holes, with the replaced values kept. RED-proof: `close --reclose` was an
# unknown argument before.
closed_round_2() { # round 2 as an earlier matcher closed it: the seed hole counted as a real finding
  seeded_round_2
  /usr/bin/python3 -c "import json; p='$CC_RESEARCH_RECORDS/rounds/2/matrix.json'; m=json.load(open(p)); m.update(closed=True, new_material=1, seeds_caught=0, quiet=False); json.dump(m, open(p,'w'))"
  printf '%s\n' "$SEED_HOLE" > "$CC_RESEARCH_RECORDS/holes.jsonl"
}

@test "close --reclose: re-runs seed match, recomputes the round and keeps the values it replaced" {
  closed_round_2
  run "$R" close --program demo --round 2 --reclose --reason "matcher fixed"
  [ "$status" -eq 0 ]
  [ "$(seed_match_of H-1)" = "S-1" ]
  [ "$(field 2 'm["new_material"], m["seeds_caught"], m["quiet"], m["closed"]')" = "0 1 True True" ]
  [ "$(field 2 '[(r["reason"], sorted(r["previous"].items())) for r in m["reclosed"]]')" = "[('matcher fixed', [('forecast', None), ('kappa', None), ('new_material', 1), ('quiet', False), ('r_max', None), ('seeds_caught', 0)])]" ]
}

@test "close --reclose: round 1's forecast and R_max are recomputed" {
  fc_done
  mat 1 certification 1 ',"quiet":false,"new_material":7,"forecast":{"p50":40,"p90":41},"r_max":99'
  : > "$CC_RESEARCH_RECORDS/holes.jsonl"
  run "$R" close --program demo --round 1 --reclose --reason "matcher fixed"
  [ "$status" -eq 0 ]
  [ "$(field 1 'm["new_material"], m["quiet"], m["reclosed"][0]["previous"]["forecast"]["p90"], m["reclosed"][0]["previous"]["r_max"]')" = "0 True 41 99" ]
  [ "$(field 1 'm["forecast"]["p90"] != 41 and m["r_max"] <= 6')" = "True" ]
}

@test "close --reclose is refused for an open round, after a later round opened, and without a reason" {
  closed_round_2
  run "$R" close --program demo --round 2 --reclose
  [ "$status" -eq 2 ]
  [[ "$output" == *"needs --reason"* ]] || false
  mkdir -p "$CC_RESEARCH_RECORDS/rounds/3"
  printf '{"round":"3","seq":3,"kind":"certification"}\n' > "$CC_RESEARCH_RECORDS/rounds/3/plan.json"
  run "$R" close --program demo --round 2 --reclose --reason x
  [ "$status" -eq 2 ]
  [[ "$output" == *"later round(s) 3 already opened"* ]] || false
  open_with_slots 4 complete True
  run "$R" close --program demo --round 4 --reclose --reason x
  [ "$status" -eq 2 ]
  [[ "$output" == *"round 4 is not closed"* ]] || false
  [ "$(field 2 '"reclosed" in m, m["new_material"]')" = "False 1" ]
  [ "$(seed_match_of H-1)" = "None" ]
}

# act <python over the activities module>: run it with the kit's lib on the path.
act() { /usr/bin/python3 -c "import sys; sys.path.insert(0, '$REPO/scripts/research-kit/lib'); import activities; $1"; }
cr_open() { act "print(activities.ensure_open('demo', 'certification-round'))"; }
cr_state() { act "print(' '.join(a['state'] for a in activities.load()['activities'] if a['kind'] == 'certification-round'))"; }

@test "close: the certification-round activity stays open while the next certification round is due" {
  fc_done; certs 1 1; open_with_slots 2 complete True
  aid="$(cr_open)"
  run "$R" close --program demo --round 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"certification activity open: $aid"* ]] || false
  [ "$(cr_state)" = open ]
}

@test "close: the certification-round activity closes when the stop rule fires" {
  fc_done; certs 1 1; mat 2 certification 2 ',"quiet":true,"new_material":0'
  open_with_slots 3 complete True
  cr_open >/dev/null
  run "$R" close --program demo --round 3
  [ "$status" -eq 0 ]
  [[ "$output" == *"certification activity closed:"*"stop rule has fired"* ]] || false
  [ "$(cr_state)" = closed ]
}

@test "close: the certification-round activity closes at R_max" {
  fc_done; certs 1 4
  /usr/bin/python3 -c "import json; p='$CC_RESEARCH_RECORDS/rounds/1/matrix.json'; m=json.load(open(p)); m['forecast']={'p50':1,'p90':1}; json.dump(m, open(p,'w'))"
  open_with_slots 5 complete True
  cr_open >/dev/null
  run "$R" close --program demo --round 5
  [ "$status" -eq 0 ]
  [[ "$output" == *"certification activity closed:"*"past R_max = 5"* ]] || false
  [ "$(cr_state)" = closed ]
}

@test "activities: ensure_open is idempotent per kind, and close_kind flips only that kind" {
  a="$(cr_open)"; b="$(cr_open)"
  [ "$a" = "$b" ]
  esc="$(act "print(activities.open_activity('demo', 'escape'))")"
  [ "$esc" != "$a" ]
  [ "$(act "print(activities.close_kind('demo', 'certification-round'))")" = "['$a']" ]
  [ "$(act "print(activities.open_ids('demo', 'escape'))")" = "['$esc']" ]
  [ "$(act "print(activities.open_ids('demo', 'certification-round'))")" = "[]" ]
  # a closed kind re-opens as a new row, never by reviving the old one
  c="$(cr_open)"
  [ "$c" != "$a" ]
  [ "$(cr_state)" = "closed open" ]
}

# Settling a round before any plan edit (2026-10-11, lib/settle.py). RED-proof: `artifact`, `split`,
# `verify-split` and `repass` were unknown verbs, and close counted an artifact as new material.
evidence() { mkdir -p "$CC_RESEARCH_RECORDS/evidence"; printf '%s\n' "$2" > "$CC_RESEARCH_RECORDS/evidence/$1"; }

@test "artifact: an untagged hole proved copy damage leaves every count with no catch credit; its evidence must name the real plan" {
  seeded_round_2
  printf '%s\n' "$SEED_HOLE" "$REAL_HOLE" > "$CC_RESEARCH_RECORDS/holes.jsonl"
  "$R" close --program demo --round 2
  [ "$(field 2 'm["new_material"], m["seeds_caught"]')" = "1 1" ]
  blob="$(git hash-object "$CC_RESEARCH_RECORDS/PLAN.md")"
  evidence bad.txt "grep -c on the plan: 0"
  evidence real.txt "blob $blob: grep -c on the plan: 0"
  run "$R" artifact --program demo --hole H-2 --reason "copy damage" --evidence evidence/bad.txt
  [ "$status" -eq 2 ]
  [[ "$output" == *"names the real plan's blob"* ]] || false
  run "$R" artifact --program demo --hole H-1 --reason "copy damage" --evidence evidence/real.txt
  [ "$status" -eq 2 ]
  [[ "$output" == *"seed-tagged"* ]] || false
  run "$R" artifact --program demo --hole H-2 --reason "copy damage" --evidence evidence/real.txt
  [ "$status" -eq 0 ]
  run "$R" close --program demo --round 2 --reclose --reason "artifact H-2"
  [ "$status" -eq 0 ]
  [ "$(field 2 'm["new_material"], m["seeds_caught"], m["quiet"], m["artifacts"]')" = "0 1 True ['H-2']" ]
  [ "$(seed_match_of H-2)" = "None" ]
  run /usr/bin/python3 -c "import sys; sys.path[:0]=['$REPO/scripts/research-kit', '$REPO/scripts/research-kit/lib', '$REPO/scripts/lib']; import estimate; print([h['id'] for h in estimate.counted_holes('demo', [{'round': '2', 'seq': 2}])])"
  [ "$output" = "[]" ]
}

@test "split: the seed catch stays, the real defect opens as a new hole that counts only once verified on the real plan" {
  seeded_round_2
  printf '%s\n' '{"id":"H-2-001","event":"raise","round":2,"source":"panel","finding":"f1"}' \
    '{"id":"H-2-001","event":"raise","round":2,"source":"panel","finding":"f2"}' \
    "${SEED_HOLE/H-1/H-2-001}" > "$CC_RESEARCH_RECORDS/holes.jsonl"
  "$R" close --program demo --round 2
  [ "$(seed_match_of H-2-001)" = "S-1" ]
  evidence split.txt "blind adjudicator: f2 is the backoff figure, f1 the planted retry"
  sp() { run "$R" split --program demo --hole H-2-001 --path PLAN.md --lines 61 --claim "the 2 s backoff has no source" \
    --reason "over-merge" --evidence evidence/split.txt "$@"; }
  sp --findings f9 --quote "three times with a 2 s backoff"
  [[ "$status" -eq 2 && "$output" == *"not raise events of H-2-001"* ]] || false
  sp --findings f1 f2 --quote "three times with a 2 s backoff"
  [[ "$status" -eq 2 && "$output" == *"the seed catch must keep one"* ]] || false
  sp --findings f2 --quote "forever with no backoff"
  [[ "$status" -eq 2 && "$output" == *"not on lines 61 of the real plan"* ]] || false
  sp --findings f2 --quote "three times with a 2 s backoff"
  [ "$status" -eq 0 ]
  [[ "$output" == *"H-2-002 opened from 1 finding"* ]] || false
  run "$R" close --program demo --round 2 --reclose --reason "split"
  [[ "$status" -eq 2 && "$output" == *"H-2-002 not yet verified against the real plan"* ]] || false
  "$REPO/scripts/research-kit/seed.py" apply --program demo --plan "$CC_RESEARCH_RECORDS/PLAN.md" --out "$BATS_TEST_TMPDIR/seeded.md"
  vs() { run "$R" verify-split --program demo --hole H-2-002 --status CONFIRMED --by verifier --evidence evidence/split.txt --read-plan "$1"; }
  vs "$BATS_TEST_TMPDIR/seeded.md"
  [[ "$status" -eq 2 && "$output" == *"never the seeded bundle"* ]] || false
  vs "$CC_RESEARCH_RECORDS/PLAN.md"
  [ "$status" -eq 0 ]
  printf '%s\n' '{"id":"H-2-002","event":"rate","materiality":{"level":"MATERIAL"}}' >> "$CC_RESEARCH_RECORDS/holes.jsonl"
  run "$R" close --program demo --round 2 --reclose --reason "split H-2-001"
  [ "$status" -eq 0 ]
  [ "$(field 2 'm["new_material"], m["seeds_caught"], m["splits"]')" = "1 1 [{'from': 'H-2-001', 'to': 'H-2-002'}]" ]
  [ "$(seed_match_of H-2-002)" = "None" ]
}

rated() { # <id> <r1> <r2> <r3|-> <level>: a confirmed round-2 hole and its three ratings
  /usr/bin/python3 -c 'import json, sys
i, r1, r2, r3, lvl = sys.argv[1:]
raters = {"1": {"rating": r1}, "2": {"rating": r2}}
if r3 != "-": raters["3"] = {"rating": r3}
print(json.dumps({"id": i, "round": 2, "verification": {"status": "CONFIRMED"}, "materiality": {"level": lvl, "raters": raters}}))' "$@"
}

@test "repass: low rater agreement earns ONE re-pass whose ratings supersede, and a kappa still low reaches the certificate as Adjudication unstable" {
  fc_done; open_with_slots 2 complete True
  { rated H-1 M R M MATERIAL; rated H-2 R M M MATERIAL; rated H-3 M R R REFINEMENT; rated H-4 R M R REFINEMENT; } \
    > "$CC_RESEARCH_RECORDS/holes.jsonl"
  run "$R" close --program demo --round 2
  [[ "$output" == *"rater kappa -1.0 over 4 (below 0.7: rating re-pass due"* ]] || false
  [ "$(field 2 'm["new_material"], m["kappa"]["repass"], m["kappa"]["unstable"]')" = "2 False False" ]
  printf '%s\n' '{"id":"H-1","raters":{"1":"M","2":"M"},"level":"MATERIAL"}' \
    '{"id":"H-2","raters":{"1":"R","2":"R"},"level":"MATERIAL"}' > "$BATS_TEST_TMPDIR/bad.jsonl"
  run "$R" repass --program demo --round 2 --ratings "$BATS_TEST_TMPDIR/bad.jsonl" --reason "kappa low"
  [[ "$status" -eq 2 && "$output" == *"H-2: level MATERIAL disagrees"* && "$output" == *"missing H-3, H-4"* ]] || false
  { printf '%s\n' '{"id":"H-1","raters":{"1":"M","2":"M"},"level":"MATERIAL"}' \
      '{"id":"H-2","raters":{"1":"R","2":"R"},"level":"REFINEMENT"}' \
      '{"id":"H-3","raters":{"1":"M","2":"R","3":"R"},"level":"REFINEMENT"}' \
      '{"id":"H-4","raters":{"1":"R","2":"M","3":"R"},"level":"REFINEMENT"}'; } > "$BATS_TEST_TMPDIR/repass.jsonl"
  run "$R" repass --program demo --round 2 --ratings "$BATS_TEST_TMPDIR/repass.jsonl" --reason "kappa low"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rater kappa -1.0 -> 0.0 · Adjudication unstable"* ]] || false
  [ "$(field 2 'm["new_material"], m["kappa"]["materiality"], m["kappa"]["repass"], m["kappa"]["unstable"]')" = "1 0.0 True True" ]
  run "$R" repass --program demo --round 2 --ratings "$BATS_TEST_TMPDIR/repass.jsonl" --reason "again"
  [[ "$status" -eq 2 && "$output" == *"one rating re-pass already ran"* ]] || false
  run /usr/bin/python3 -c "
import sys; sys.path[:0] = ['$REPO/scripts/research-kit/lib', '$REPO/scripts/lib', '$REPO/scripts/research-kit']
import gate, gate_cert, gate_rows_b
ctx = gate.make_ctx('demo')
u = gate_rows_b.unstable_rounds(ctx)
st = dict(decisions=0, populations=0, checks=0, premises_at_level=0, premises=0, sources=0, ruled_90=0,
          operator_ruled=0, by_default=[], carried=[], parked=0, frame_defects=0, unasked_intent=0)
cert = dict(version=1, profile='lite', issued='2026-10-11T00:00:00Z', stop='dry', quiet_streak=2, rounds=3,
            forecast=dict(desk_mean=1.0, invisible_mean=0.5, desk_n95=3, invisible_bound95=1), state=st,
            fingerprint=dict(model='m', rules='r', memory='x'), adjudication_unstable=u)
live = dict(after=0, escapes=0, residual={}, scheduled=0, fresh_at=None, flipped=0, calibration=0, last_change=None)
print(u, gate_cert.lines_for('demo', cert, 'certified', live)[0])"
  [[ "$output" == "['2'] Adjudication unstable (round 2: rater agreement still low after the re-pass) · Research: demo"* ]] || false
}

@test "repass is refused when rater agreement is not low" {
  fc_done; open_with_slots 2 complete True
  { rated H-1 M M - MATERIAL; rated H-2 R R - REFINEMENT; } > "$CC_RESEARCH_RECORDS/holes.jsonl"
  "$R" close --program demo --round 2
  printf '%s\n' '{"id":"H-1","raters":{"1":"M","2":"M"},"level":"MATERIAL"}' '{"id":"H-2","raters":{"1":"R","2":"R"},"level":"REFINEMENT"}' \
    > "$BATS_TEST_TMPDIR/repass.jsonl"
  run "$R" repass --program demo --round 2 --ratings "$BATS_TEST_TMPDIR/repass.jsonl" --reason x
  [[ "$status" -eq 2 && "$output" == *"rater kappa 1.0 is not below 0.7; no re-pass"* ]] || false
  [ "$(field 2 'm["kappa"]["materiality"], m["kappa"]["unstable"]')" = "1.0 False" ]
}
