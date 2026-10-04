#!/usr/bin/env bats
# research-kit-seed — scripts/research-kit/seed.py (REPORT.md §3.9): seeds are validated, omission
# operators are required, the vault is encrypted and never printed, and a seed counts as caught only
# when a MATERIAL-rated hole covers its detection span.

setup() {
  unset CC_BATS_ACTIVE
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SEED="$REPO/scripts/research-kit/seed.py"
  export CC_RESEARCH_HOME="$BATS_TEST_TMPDIR/research"
  export CC_RESEARCH_REGISTRY="$CC_RESEARCH_HOME/programs.json"
  export CC_RESEARCH_RECORDS="$BATS_TEST_TMPDIR/records"
  export CC_RESEARCH_VAULT_KEY="test-key"
  mkdir -p "$CC_RESEARCH_RECORDS"
  PLAN="$BATS_TEST_TMPDIR/PLAN.md"
  {
    for i in $(seq 1 60); do echo "filler line $i of the plan that says nothing at all"; done
    echo "The sync daemon retries a failed write three times with a 2 s backoff."
    echo "Population: callers are hooks/a.sh, hooks/b.sh and the launchd job cc-sync."
    echo "Option census for DR-04: do nothing, use what exists, and the new daemon."
  } > "$PLAN"
  A1="The sync daemon retries a failed write three times with a 2 s backoff."
  A2="Population: callers are hooks/a.sh, hooks/b.sh and the launchd job cc-sync."
}

seedline() { # <sid> <op> <anchor> <replacement> <span> [defect statement]
  /usr/bin/python3 -c 'import json,sys; a=sys.argv; print(json.dumps({"sid":a[1],"cohort":"original","class":"C4","op":a[2],"anchor_quote":a[3],"replacement":a[4],"defect_statement":a[6],"detect_span":a[5]}))' "$1" "$2" "$3" "$4" "$5" "${6:-planted}"
}

good_set() {
  { seedline S-1 replace "$A1" "The sync daemon retries a failed write forever with no backoff at all." "PLAN.md:61-61"
    seedline S-2 delete-member "$A2" "" "PLAN.md:62-62"; } > "$BATS_TEST_TMPDIR/seeds.jsonl"
}

@test "a valid set plants, and the vault holds no anchor text" {
  good_set
  run "$SEED" plant --program demo --plan "$PLAN" --seeds "$BATS_TEST_TMPDIR/seeds.jsonl" --profile lite
  [ "$status" -eq 0 ]
  run grep -q "sync daemon" "$CC_RESEARCH_HOME/demo/vault/seeds.enc"
  [ "$status" -eq 1 ]
  run "$SEED" status --program demo
  [ "${lines[0]}" = '{"original": {"caught": 0, "k_left": 2, "orphaned": 0, "s_eff": 2}}' ]
}

@test "an anchor shorter than 40 characters is refused" {
  { seedline S-1 replace "retries a failed write" "x" "PLAN.md:61-61"
    seedline S-2 delete-member "$A2" "" "PLAN.md:62-62"; } > "$BATS_TEST_TMPDIR/seeds.jsonl"
  run "$SEED" plant --program demo --plan "$PLAN" --seeds "$BATS_TEST_TMPDIR/seeds.jsonl" --profile lite
  [ "$status" -eq 2 ]
  [[ "$output" == *"shorter than 40"* ]]
}

@test "an anchor that occurs twice is refused" {
  dup="filler line 1 of the plan that says nothing at all"
  { seedline S-1 replace "$dup" "x" "PLAN.md:1-1"
    seedline S-2 delete-member "$A2" "" "PLAN.md:62-62"; } > "$BATS_TEST_TMPDIR/seeds.jsonl"
  echo "$dup" >> "$PLAN"
  run "$SEED" plant --program demo --plan "$PLAN" --seeds "$BATS_TEST_TMPDIR/seeds.jsonl" --profile lite
  [ "$status" -eq 2 ]
  [[ "$output" == *"occurs 2 times"* ]]
}

@test "an original set with no omission operator is refused" {
  seedline S-1 replace "$A1" "x" "PLAN.md:61-61" > "$BATS_TEST_TMPDIR/seeds.jsonl"
  run "$SEED" plant --program demo --plan "$PLAN" --seeds "$BATS_TEST_TMPDIR/seeds.jsonl" --profile lite
  [ "$status" -eq 2 ]
  [[ "$output" == *"omission"* ]]
}

@test "more original seeds than 1 per 25 plan lines is refused" {
  head -n 30 "$PLAN" > "$BATS_TEST_TMPDIR/short.md"
  echo "$A1" >> "$BATS_TEST_TMPDIR/short.md"
  echo "$A2" >> "$BATS_TEST_TMPDIR/short.md"
  good_set
  run "$SEED" plant --program demo --plan "$BATS_TEST_TMPDIR/short.md" --seeds "$BATS_TEST_TMPDIR/seeds.jsonl" --profile lite
  [ "$status" -eq 2 ]
  [[ "$output" == *"exceed the cap 1"* ]]
}

@test "apply writes the seeded plan; the omission removes its member" {
  good_set
  "$SEED" plant --program demo --plan "$PLAN" --seeds "$BATS_TEST_TMPDIR/seeds.jsonl" --profile lite
  run "$SEED" apply --program demo --plan "$PLAN" --out "$BATS_TEST_TMPDIR/seeded.md"
  [ "$output" = "applied 2 seed(s); skipped 0" ]
  grep -q "forever with no backoff" "$BATS_TEST_TMPDIR/seeded.md"
  run grep -q "launchd job cc-sync" "$BATS_TEST_TMPDIR/seeded.md"
  [ "$status" -eq 1 ]
}

@test "match: a MATERIAL hole over the span catches the seed; a REFINEMENT one does not" {
  good_set
  "$SEED" plant --program demo --plan "$PLAN" --seeds "$BATS_TEST_TMPDIR/seeds.jsonl" --profile lite
  printf '%s\n' \
    '{"id":"H-1","round":1,"locus":{"path":"PLAN.md","lines":"60-61"},"taxonomy_class":"C4","materiality":{"level":"MATERIAL"}}' \
    '{"id":"H-2","round":1,"locus":{"path":"PLAN.md","lines":"62"},"materiality":{"level":"REFINEMENT"}}' \
    > "$CC_RESEARCH_RECORDS/holes.jsonl"
  run "$SEED" match --program demo --round 1 --plan "$PLAN"
  [ "$output" = '{"original": {"caught": 1, "k_left": 1, "orphaned": 0, "s_eff": 2}}' ]
}

@test "match: a fix that rewrites a seed's anchor orphans the seed" {
  good_set
  "$SEED" plant --program demo --plan "$PLAN" --seeds "$BATS_TEST_TMPDIR/seeds.jsonl" --profile lite
  sed -i '' 's/three times with a 2 s backoff/five times with a 3 s backoff/' "$PLAN"
  : > "$CC_RESEARCH_RECORDS/holes.jsonl"
  run "$SEED" match --program demo --round 2 --plan "$PLAN"
  [ "$output" = '{"original": {"caught": 0, "k_left": 1, "orphaned": 1, "s_eff": 1}}' ]
}

@test "the vault does not open under the wrong key" {
  good_set
  "$SEED" plant --program demo --plan "$PLAN" --seeds "$BATS_TEST_TMPDIR/seeds.jsonl" --profile lite
  CC_RESEARCH_VAULT_KEY=wrong run "$SEED" status --program demo
  [ "$status" -eq 2 ]
  [[ "$output" == *"decrypt failed"* ]]
}

@test "match: a hole on the seed's lines about a different defect does not catch it" {
  { seedline S-1 replace "$A1" "The sync daemon retries a failed write forever with no backoff at all." "PLAN.md:61-61" \
      "the retry count is unbounded, so a failed write loops forever"
    seedline S-2 delete-member "$A2" "" "PLAN.md:62-62"; } > "$BATS_TEST_TMPDIR/seeds.jsonl"
  "$SEED" plant --program demo --plan "$PLAN" --seeds "$BATS_TEST_TMPDIR/seeds.jsonl" --profile lite
  printf '%s\n' \
    '{"id":"H-1","round":1,"locus":{"path":"PLAN.md","lines":"61"},"taxonomy_class":"C4","claim":"the 2 s backoff figure has no source and contradicts the measured p95","materiality":{"level":"MATERIAL"}}' \
    > "$CC_RESEARCH_RECORDS/holes.jsonl"
  run "$SEED" match --program demo --round 1 --plan "$PLAN"
  [ "$output" = '{"original": {"caught": 0, "k_left": 2, "orphaned": 0, "s_eff": 2}}' ]
  run grep -c seed_match "$CC_RESEARCH_RECORDS/holes.jsonl"
  [ "$output" = "0" ]
}

@test "prescreen: a seed the pre-screen caught is discarded; plant and apply skip it" {
  A3="Option census for DR-04: do nothing, use what exists, and the new daemon."
  A4="The store keeps ninety days of history before the nightly compaction runs."
  for i in $(seq 1 30); do echo "more filler $i that the reviewers will read past quickly"; done >> "$PLAN"
  echo "$A4" >> "$PLAN"
  { seedline S-1 replace "$A1" "The sync daemon retries a failed write forever with no backoff at all." "PLAN.md:61-61"
    seedline S-2 delete-member "$A2" "" "PLAN.md:62-62"
    seedline S-3 drop-option "$A3" "" "PLAN.md:63-63"; } > "$BATS_TEST_TMPDIR/seeds.jsonl"
  "$SEED" plant --program demo --plan "$PLAN" --seeds "$BATS_TEST_TMPDIR/seeds.jsonl" --profile lite
  run "$SEED" prescreen --program demo --caught S-9
  [ "$status" -eq 2 ]
  echo S-3 > "$BATS_TEST_TMPDIR/caught.txt"
  run "$SEED" prescreen --program demo --caught "$BATS_TEST_TMPDIR/caught.txt"
  [ "$status" -eq 0 ]
  run "$SEED" status --program demo
  [ "${lines[0]}" = '{"original": {"caught": 0, "k_left": 2, "orphaned": 0, "s_eff": 2}}' ]
  run "$SEED" apply --program demo --plan "$PLAN" --out "$BATS_TEST_TMPDIR/seeded.md"
  [ "$output" = "applied 2 seed(s); skipped 1" ]
  run grep -c "Option census for DR-04" "$BATS_TEST_TMPDIR/seeded.md"
  [ "$output" = "1" ]
  # 94 lines carry 3 originals at lite; the discarded seed no longer holds one of them.
  seedline S-4 drop-plan-item "$A4" "" "PLAN.md:94-94" \
    > "$BATS_TEST_TMPDIR/more.jsonl"
  run "$SEED" plant --program demo --plan "$PLAN" --seeds "$BATS_TEST_TMPDIR/more.jsonl" --profile lite
  [ "$status" -eq 0 ]
}

@test "status prints seed realism beside the real-hole detection rate and flags easier seeds" {
  { seedline S-1 replace "$A1" "The sync daemon retries a failed write forever with no backoff at all." "PLAN.md:61-61" \
      "the retry count is unbounded, so a failed write loops forever"
    seedline S-2 delete-member "$A2" "" "PLAN.md:62-62"; } > "$BATS_TEST_TMPDIR/seeds.jsonl"
  "$SEED" plant --program demo --plan "$PLAN" --seeds "$BATS_TEST_TMPDIR/seeds.jsonl" --profile lite
  ok='"verification":{"status":"CONFIRMED"},"materiality":{"level":"MATERIAL"}'
  printf '%s\n' \
    '{"id":"H-1","round":1,"source":"panel","locus":{"path":"PLAN.md","lines":"61"},"taxonomy_class":"C4","claim":"a failed write loops forever: the retry count is unbounded",'"$ok"'}' \
    '{"id":"H-2","round":1,"source":"panel","locus":{"path":"PLAN.md","lines":"5"},"claim":"no owner for the cutover",'"$ok"'}' \
    '{"id":"H-3","round":1,"source":"build","locus":{"path":"PLAN.md","lines":"9"},"claim":"the quota figure is stale",'"$ok"'}' \
    '{"id":"H-4","round":1,"source":"operator","locus":{"path":"PLAN.md","lines":"12"},"claim":"the wrong tenant",'"$ok"'}' \
    > "$CC_RESEARCH_RECORDS/holes.jsonl"
  "$SEED" match --program demo --round 1 --plan "$PLAN"
  run "$SEED" status --program demo
  [ "$status" -eq 0 ]
  [[ "${lines[1]}" == *"realism 1/2 = 0.50"* ]] || false
  [[ "${lines[1]}" == *"real detection 1/3 = 0.33"* ]] || false
  [[ "${lines[1]}" == *"seeds easier"* ]]
}

@test "two concurrent plants both land in the vault (the vault write is locked)" {
  good_set
  A3="Option census for DR-04: do nothing, use what exists, and the new daemon."
  /usr/bin/python3 -c 'import json,sys; print(json.dumps({"sid":"S-3","cohort":"shadow-r1","class":"C4","op":"drop-option","anchor_quote":sys.argv[1],"defect_statement":"planted","detect_span":"PLAN.md:63-63"}))' "$A3" > "$BATS_TEST_TMPDIR/shadow.jsonl"
  # CC_RESEARCH_TEST_VAULT_DELAY (test-only) holds each writer between loading and saving the vault.
  CC_RESEARCH_TEST_VAULT_DELAY=0.5 "$SEED" plant --program demo --plan "$PLAN" --seeds "$BATS_TEST_TMPDIR/seeds.jsonl" --profile lite > "$BATS_TEST_TMPDIR/p1" 2>&1 &
  CC_RESEARCH_TEST_VAULT_DELAY=0.5 "$SEED" plant --program demo --plan "$PLAN" --seeds "$BATS_TEST_TMPDIR/shadow.jsonl" --profile lite > "$BATS_TEST_TMPDIR/p2" 2>&1 &
  wait
  run /usr/bin/python3 -c "import sys; sys.path.insert(0, '$REPO/scripts/research-kit'); import seed; v, _ = seed.load_vault('demo'); print(','.join(sorted(s['sid'] for s in v['seeds'])))"
  [ "$status" -eq 0 ]
  [ "$output" = "S-1,S-2,S-3" ]
}
