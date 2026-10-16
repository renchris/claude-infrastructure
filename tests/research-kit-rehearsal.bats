#!/usr/bin/env bats
# research-kit-rehearsal — a rehearsal find (REPORT.md §3.8 "Rehearsal": "A verified material find
# becomes a named known row") through round.sh's reserved `rehearsal` round: rehearsal-raise opens
# H-RH-<n>, rehearsal-verify and rehearsal-rate run the frozen verifier and rater briefs through
# courier.sh run on the certification round's rater assignment, and rehearsal-name writes a
# `rehearsal` known row applied in a build wave, blocking none. The plan is never edited.
# RED-proof: before lib/rehearsal.py the four verbs were unknown to round.sh (argparse exit 2), so
# no rehearsal find could be raised, adjudicated or named, and gate row 9 could only fail it.
# The real courier.sh runs; fake vendor CLIs stand in for claude, codex and agy.

setup() {
  unset CC_BATS_ACTIVE CC_RESEARCH_COURIER
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  R="$REPO/scripts/research-kit/round.sh"
  export CC_RESEARCH_HOME="$BATS_TEST_TMPDIR/research"
  export CC_RESEARCH_REGISTRY="$CC_RESEARCH_HOME/programs.json"
  export CC_RESEARCH_RECORDS="$BATS_TEST_TMPDIR/records"
  export CC_RESEARCH_CODEX_SESSIONS="$BATS_TEST_TMPDIR/codex-sessions"
  REC="$CC_RESEARCH_RECORDS"
  mkdir -p "$REC/rounds" "$BATS_TEST_TMPDIR/bin" "$CC_RESEARCH_CODEX_SESSIONS"
  printf '{"profile":"lite","plan":"PLAN.md","reviewer_pins":{"anthropic":"claude-opus-5-5","frontier":"claude-fable-5-1","openai":"gpt-x","google":"gemini-x"},"reask_map":[{"frame":"deployed and live","axis":"V7"},{"frame":"cost","axis":null,"excluded_quote":"not a frame"}]}\n' \
    > "$REC/frame.json"
  printf '# plan\n## Retry\nThe client retries three times with no backoff.\n## Storage\nRows are written once and never compacted.\n' > "$REC/PLAN.md"
  printf '{"snapshot_sha":"%s","plan_blob":"%s"}\n' "$(printf 'a%.0s' $(seq 40))" "$(git hash-object "$REC/PLAN.md")" > "$REC/freeze.json"
  export FAKE_ARGV_LOG="$BATS_TEST_TMPDIR/argv.log"
  : > "$FAKE_ARGV_LOG"
  B="$BATS_TEST_TMPDIR/bin"
  # Each fake answers FAKE_REPLY_<LANE> and fails on FAKE_FAIL_<LANE>; claude and codex log their argv.
  cat > "$B/claude" <<'EOF'
#!/bin/bash
printf 'claude %s\n' "$*" >> "$FAKE_ARGV_LOG"
m=""; while [ $# -gt 0 ]; do [ "$1" = "--model" ] && m="$2"; shift; done
[ -n "${FAKE_FAIL_ANTHROPIC:-}" ] && { echo "boom" >&2; exit 1; }
/usr/bin/python3 -c 'import json,os,sys; print(json.dumps({"is_error":False,"result":os.environ.get("FAKE_REPLY_ANTHROPIC",""),"modelUsage":{sys.argv[1]:{"outputTokens":9}}}))' "$m"
EOF
  cat > "$B/codex" <<'EOF'
#!/bin/bash
printf 'codex %s\n' "$*" >> "$FAKE_ARGV_LOG"
m=""; while [ $# -gt 0 ]; do [ "$1" = "-m" ] && m="$2"; shift; done
[ -n "${FAKE_FAIL_OPENAI:-}" ] && { echo "boom" >&2; exit 1; }
t="thread-$$"
printf '{"type":"session_meta","model":"%s"}\n' "$m" > "$CC_RESEARCH_CODEX_SESSIONS/rollout-x-$t.jsonl"
printf '{"type":"thread.started","thread_id":"%s"}\n' "$t"
/usr/bin/python3 -c 'import json,os; print(json.dumps({"type":"item.completed","item":{"type":"agent_message","text":os.environ.get("FAKE_REPLY_OPENAI","")}}))'
EOF
  cat > "$B/agy" <<'EOF'
#!/bin/bash
m=""; while [ $# -gt 0 ]; do [ "$1" = "--model" ] && m="$2"; shift; done
if [ -n "${FAKE_FAIL_GOOGLE:-}" ]; then echo '{"status":"ERROR","response":"","error":"walled"}'; exit 1; fi
/usr/bin/python3 -c 'import json,os,sys; print(json.dumps({"status":"SUCCESS","response":os.environ.get("FAKE_REPLY_GOOGLE",""),"model":sys.argv[1]}))' "$m"
EOF
  chmod +x "$B/claude" "$B/codex" "$B/agy"
  export CC_RESEARCH_BIN_ANTHROPIC="$B/claude" CC_RESEARCH_BIN_OPENAI="$B/codex" CC_RESEARCH_BIN_GOOGLE="$B/agy"
}

mat() { # <dir> <kind> <seq> [extra json fields]
  mkdir -p "$REC/rounds/$1"
  printf '{"round":"%s","kind":"%s","seq":%s,"closed":true,"counted":true%s}\n' "$1" "$2" "$3" "${4:-}" > "$REC/rounds/$1/matrix.json"
}
# stopped: both frame-critique rounds, then certification rounds 1-5 closed with R_max 5 spent (round 5 the
# verification-only cap round): no certification round is due, so the rehearsal may run.
stopped() {
  mat fc1 frame-critique 1; mat fc2 frame-critique 2
  mat 1 certification 1 ',"quiet":false,"new_material":1,"forecast":{"p50":1,"p90":1}'
  local i; for i in 2 3 4; do mat "$i" certification "$i" ',"quiet":false,"new_material":1'; done
  mat 5 certification 5 ',"quiet":true,"new_material":0,"verification_only":true'
}
raise() { run "$R" rehearsal-raise --program demo --frame "${1:-deployed and live}" --path PLAN.md --lines "${2:-3}" \
  --quote "${3:-retries three times with no backoff}" --claim "no backoff: three immediate retries make a retry storm" \
  --names AM-02 --receipt "read PLAN.md:3"; }
hole() { /usr/bin/python3 -c "
import json
h = {}
for l in open('$REC/holes.jsonl'):
    d = json.loads(l)
    if d.get('id') == '$1': h.update(d)
print($2)"; }
VERDICT='{"fid":"f1","status":"CONFIRMED","read":{"path":"PLAN.md","lines":"3","quote":"retries three times with no backoff"},"consequence":"a retry storm under load","probe":null}'
rating() { printf '{"ratings":[{"fid":"f1","rating":"%s","clause":%s,"reason":"r"}]}' "$1" "$2"; }
verified() { stopped; raise; FAKE_REPLY_ANTHROPIC="$VERDICT" "$R" rehearsal-verify --program demo --hole H-RH-1 --vendor anthropic >/dev/null; }
evidence() { mkdir -p "$REC/evidence"; printf '%s\n' "$2" > "$REC/evidence/$1"; }

@test "rehearsal-raise: a blind frame session's find opens H-RH-1 in the reserved rehearsal round, quoted on the real plan's lines" {
  stopped
  raise
  [ "$status" -eq 0 ]
  [[ "$output" == *"H-RH-1"* ]] || false
  [ "$(hole H-RH-1 'h["event"], h["round"], h["source"], h["raised_by"]["frame"], h["raised_by"]["blind"], h["locus"]["lines"], h["locus"]["numbering"], h["names"], h["receipt"]')" \
    = "raise rehearsal rehearsal deployed and live True 3 real ['AM-02'] read PLAN.md:3" ]
  [ "$(hole H-RH-1 'h["plan_blob"]')" = "$(git hash-object "$REC/PLAN.md")" ]
  raise "deployed and live" 5 "never compacted"
  [ "$status" -eq 0 ]
  [[ "$output" == *"H-RH-2"* ]] || false
  # no round count reads it: the reserved round has no matrix, and close's selection never sees "rehearsal"
  [ ! -e "$REC/rounds/rehearsal/matrix.json" ]
}

@test "rehearsal-raise is refused before the stop, on an unmapped frame, off the cited lines, on another file, without a claim, and once the plan moved from the freeze" {
  mat fc1 frame-critique 1; mat fc2 frame-critique 2
  mat 1 certification 1 ',"quiet":false,"new_material":1'
  raise
  [[ "$status" -eq 2 && "$output" == *"after the stop"* ]] || false
  stopped
  raise "cost"
  [[ "$status" -eq 2 && "$output" == *"reask_map frame with an axis"* ]] || false
  raise "never asked"
  [[ "$status" -eq 2 && "$output" == *"reask_map frame with an axis"* ]] || false
  raise "deployed and live" 5
  [[ "$status" -eq 2 && "$output" == *"--quote is not on lines 5"* ]] || false
  run "$R" rehearsal-raise --program demo --frame "deployed and live" --path OTHER.md --lines 3 --quote "retries" --claim c
  [[ "$status" -eq 2 && "$output" == *"the real plan is PLAN.md"* ]] || false
  run "$R" rehearsal-raise --program demo --frame "deployed and live" --path PLAN.md --lines 3 --quote "retries" --claim " "
  [[ "$status" -eq 2 && "$output" == *"--claim"* ]] || false
  echo "a late edit" >> "$REC/PLAN.md"
  raise
  [[ "$status" -eq 2 && "$output" == *"changed after the freeze"* ]] || false
  [ ! -e "$REC/holes.jsonl" ]
}

@test "rehearsal-verify and rehearsal-rate: the frozen briefs run through courier.sh run on the round's rater assignment, and the verdicts land on the hole" {
  stopped; raise
  run "$R" rehearsal-rate --program demo --hole H-RH-1
  [[ "$status" -eq 2 && "$output" == *"only a CONFIRMED hole is rated"* ]] || false
  echo '{"id":"H-5-001","event":"raise","round":5,"source":"panel"}' >> "$REC/holes.jsonl"
  run "$R" rehearsal-verify --program demo --hole H-5-001 --vendor anthropic
  [[ "$status" -eq 2 && "$output" == *"not a rehearsal find"* ]] || false
  FAKE_REPLY_ANTHROPIC="$VERDICT" run "$R" rehearsal-verify --program demo --hole H-RH-1 --vendor anthropic
  [ "$status" -eq 0 ]
  [[ "$output" == *"H-RH-1: CONFIRMED"* ]] || false
  # the frozen verifier brief, then the finding, through courier.sh run on the real plan's bundle
  grep -qF 'Verifier brief (frozen)' "$FAKE_ARGV_LOG"
  grep -qF 'retries three times with no backoff' "$FAKE_ARGV_LOG"
  # blind as a round's verifier: the brief names no hole id, so not where the find came from
  ! grep -qF 'H-RH' "$FAKE_ARGV_LOG" || false
  [ -f "$CC_RESEARCH_HOME/demo/rounds/rehearsal/bundle/manifest.json" ]
  grep -qF 'no backoff' "$CC_RESEARCH_HOME/demo/rounds/rehearsal/bundle/PLAN.md"
  [ "$(hole H-RH-1 'h["verification"]["status"], h["verification"]["against"], h["verification"]["vendor"], h["verification"]["panel"]')" \
    = "CONFIRMED real anthropic H-RH-1-verifier" ]
  [ -f "$REC/rounds/rehearsal/panels/H-RH-1-verifier.json" ]
  FAKE_REPLY_ANTHROPIC="$VERDICT" run "$R" rehearsal-verify --program demo --hole H-RH-1 --vendor anthropic
  [[ "$status" -eq 2 && "$output" == *"already verified"* ]] || false
  : > "$FAKE_ARGV_LOG"
  FAKE_REPLY_OPENAI="$(rating M '"b"')" FAKE_REPLY_GOOGLE="$(rating M '"c"')" FAKE_REPLY_ANTHROPIC="$(rating R null)" \
    run "$R" rehearsal-rate --program demo --hole H-RH-1
  [ "$status" -eq 0 ]
  [[ "$output" == *"H-RH-1: MATERIAL"* ]] || false
  # rater 1 non-Anthropic (openai), rater 2 another family (google), rater 3 the third, each on the frozen rater brief
  [ "$(grep -c 'Rater brief (frozen)' "$FAKE_ARGV_LOG")" -eq 2 ]
  grep -q '^codex ' "$FAKE_ARGV_LOG"
  grep -q '^claude ' "$FAKE_ARGV_LOG"
  [ "$(hole H-RH-1 'h["materiality"]["level"], h["materiality"]["clause"], [h["materiality"]["raters"][k]["rating"] for k in "123"], [h["materiality"]["raters"][k]["vendor"] for k in "123"]')" \
    = "MATERIAL b ['M', 'M', 'R'] ['openai', 'google', 'anthropic']" ]
  run "$R" rehearsal-rate --program demo --hole H-RH-1
  [[ "$status" -eq 2 && "$output" == *"already rated"* ]] || false
  [ ! -e "$REC/rounds/rehearsal/matrix.json" ]
}

# RED-proof: item() copied the raise's locus.path verbatim, so a find raised with the operator's absolute
# path sent the raters a path outside the bundle; agy's sandbox denied the read and it replied empty (dead).
@test "rehearsal-verify and rehearsal-rate: the briefs cite the plan by its path in the bundle, never the absolute path the raise recorded" {
  stopped
  run "$R" rehearsal-raise --program demo --frame "deployed and live" --path "$REC/PLAN.md" --lines 3 \
    --quote "retries three times with no backoff" --claim "no backoff: a retry storm"
  [ "$status" -eq 0 ]
  # the raise record keeps the absolute path as provenance
  [ "$(hole H-RH-1 'h["locus"]["path"]')" = "$REC/PLAN.md" ]
  FAKE_REPLY_ANTHROPIC="$VERDICT" run "$R" rehearsal-verify --program demo --hole H-RH-1 --vendor anthropic
  [ "$status" -eq 0 ]
  FAKE_REPLY_OPENAI="$(rating M '"b"')" FAKE_REPLY_GOOGLE="$(rating M '"c"')" FAKE_REPLY_ANTHROPIC="$(rating R null)" \
    run "$R" rehearsal-rate --program demo --hole H-RH-1
  [ "$status" -eq 0 ]
  [ -f "$CC_RESEARCH_HOME/demo/rounds/rehearsal/bundle/PLAN.md" ]
  local bf
  for bf in "$REC/rounds/rehearsal/briefs/H-RH-1-verifier.txt" "$REC/rounds/rehearsal/briefs/H-RH-1-rater.txt"; do
    # the item is the brief's last json block (the frozen verifier brief has a "path": "PLAN.md" example of its own)
    [ "$(/usr/bin/python3 -c 'import json,sys; print(json.loads(open(sys.argv[1]).read().rsplit("```json", 1)[1].split("```")[0])["locus"]["path"])' "$bf")" = "PLAN.md" ]
    ! grep -qF "$REC" "$bf" || false
  done
}

@test "rehearsal-rate: below two material calls the level is the median call; a lost rater records nothing and its re-run runs only that rater" {
  verified
  FAKE_FAIL_GOOGLE=1 FAKE_REPLY_OPENAI="$(rating M '"b"')" FAKE_REPLY_ANTHROPIC="$(rating C null)" \
    run "$R" rehearsal-rate --program demo --hole H-RH-1
  [ "$status" -eq 3 ]
  [[ "$output" == *"H-RH-1-rater2"* ]] || false
  [ "$(hole H-RH-1 '"materiality" in h')" = False ]
  : > "$FAKE_ARGV_LOG"
  FAKE_REPLY_GOOGLE="$(rating R null)" run "$R" rehearsal-rate --program demo --hole H-RH-1
  [ "$status" -eq 0 ]
  [ ! -s "$FAKE_ARGV_LOG" ]
  [ "$(hole H-RH-1 'h["materiality"]["level"], h["materiality"]["clause"]')" = "REFINEMENT None" ]
}

# RED-proof: cmd_rate recorded nothing unless all three calls were valid, and run_courier refused the lost
# slot past its re-run cap, so a hole whose rater 2 died three times stayed unrated forever even when the
# other two had fixed the median (H-RH-2, 2026-10-16: openai M, anthropic M, google dead 3 of 3).
@test "rehearsal-rate: a slot lost past its re-run cap records the level when no call of it could change it, and refuses when one could" {
  verified
  local i
  for i in 1 2 3; do
    FAKE_FAIL_GOOGLE=1 FAKE_REPLY_OPENAI="$(rating M '"b"')" FAKE_REPLY_ANTHROPIC="$(rating M '"b"')" \
      run "$R" rehearsal-rate --program demo --hole H-RH-1
    [ "$status" -eq 3 ]
  done
  [ "$(hole H-RH-1 '"materiality" in h')" = False ]
  : > "$FAKE_ARGV_LOG"
  FAKE_FAIL_GOOGLE=1 run "$R" rehearsal-rate --program demo --hole H-RH-1
  [ "$status" -eq 0 ]
  [[ "$output" == *"H-RH-1: MATERIAL (clause b)"*"rater2"*"google"* ]] || false
  # the spent slot is not re-run, and the two valid calls were not either
  [ ! -s "$FAKE_ARGV_LOG" ]
  [ "$(hole H-RH-1 'h["materiality"]["level"], h["materiality"]["clause"], sorted(h["materiality"]["raters"]), h["materiality"]["lost"]["slot"], h["materiality"]["lost"]["vendor"], h["materiality"]["lost"]["why"].startswith("dead")')" \
    = "MATERIAL b ['1', '3'] 2 google True" ]
}

@test "rehearsal-rate: a slot lost past its re-run cap still records nothing when its call could move the median" {
  verified
  local i
  for i in 1 2 3; do
    FAKE_FAIL_GOOGLE=1 FAKE_REPLY_OPENAI="$(rating M '"b"')" FAKE_REPLY_ANTHROPIC="$(rating C null)" \
      run "$R" rehearsal-rate --program demo --hole H-RH-1
    [ "$status" -eq 3 ]
  done
  FAKE_FAIL_GOOGLE=1 run "$R" rehearsal-rate --program demo --hole H-RH-1
  [ "$status" -eq 2 ]
  [[ "$output" == *"H-RH-1-rater2 ran 3 times"*"could change the level"* ]] || false
  [ "$(hole H-RH-1 '"materiality" in h')" = False ]
}

@test "rehearsal-name: names a CONFIRMED MATERIAL rehearsal find as an open rehearsal known row applied in a build wave, blocking none" {
  stopped
  hr() { /usr/bin/python3 -c 'import json, sys
i, rnd, st, lvl, cl = sys.argv[1:6]
print(json.dumps({"id": i, "event": "raise", "round": rnd if rnd == "rehearsal" else int(rnd),
  "source": "rehearsal" if rnd == "rehearsal" else "panel", "raised_by": {"frame": "deployed and live", "blind": True},
  "verification": {"status": st}, "materiality": {"level": lvl, "clause": cl}}))' "$@" >> "$REC/holes.jsonl"; }
  hr H-RH-1 rehearsal CONFIRMED MATERIAL b; hr H-RH-2 rehearsal CONFIRMED REFINEMENT b; hr H-RH-3 rehearsal REFUTED MATERIAL b
  hr H-RH-4 rehearsal CONFIRMED MATERIAL g; hr H-5-001 5 CONFIRMED MATERIAL b
  evidence ruling.txt "a verified material rehearsal find is a named known row applied in build wave 1"
  rn() { run "$R" rehearsal-name --program demo --hole "$1" --known-row "$2" --wave "${3:-W1}" --reason "rehearsal find" --evidence evidence/ruling.txt; }
  rn H-5-001 KR-09
  [[ "$status" -eq 2 && "$output" == *"not a rehearsal find"*"name-cap"* ]] || false
  rn H-RH-2 KR-09
  [[ "$status" -eq 2 && "$output" == *"only a CONFIRMED MATERIAL hole"* ]] || false
  rn H-RH-3 KR-09
  [[ "$status" -eq 2 && "$output" == *"only a CONFIRMED MATERIAL hole"* ]] || false
  rn H-RH-4 KR-09
  [[ "$status" -eq 2 && "$output" == *"clause-(g)"*"round.sh hold-g"* ]] || false
  rn H-RH-1 KR9
  [[ "$status" -eq 2 && "$output" == *"must read KR-<n>"* ]] || false
  rn H-RH-1 KR-09 "W 1"
  [[ "$status" -eq 2 && "$output" == *"--wave"* ]] || false
  echo '{"id":"KR-01","kind":"frame-omission","hole":"H-1-001","status":"open"}' > "$REC/known_rows.jsonl"
  rn H-RH-1 KR-01
  [[ "$status" -eq 2 && "$output" == *"KR-01: a known row with this id already exists"* ]] || false
  rn H-RH-1 KR-09
  [ "$status" -eq 0 ]
  [ "$(/usr/bin/python3 -c "import json; r=[json.loads(l) for l in open('$REC/known_rows.jsonl')][-1]; print(r['id'], r['kind'], r['hole'], r['round'], r['frame'], r['applied_in_wave'], r['blocks_waves'], r['status'], r['named']['evidence'])")" \
    = "KR-09 rehearsal H-RH-1 rehearsal deployed and live W1 [] open ['evidence/ruling.txt']" ]
  rn H-RH-1 KR-10
  [[ "$status" -eq 2 && "$output" == *"H-RH-1: already named by KR-09"* ]] || false
  # the plan is never edited by the rehearsal
  [ "$(git hash-object "$REC/PLAN.md")" = "$(/usr/bin/python3 -c "import json; print(json.load(open('$REC/freeze.json'))['plan_blob'])")" ]
}
