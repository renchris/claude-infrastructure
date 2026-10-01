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

seedline() { # <sid> <op> <anchor> <replacement> <span>
  /usr/bin/python3 -c 'import json,sys; a=sys.argv; print(json.dumps({"sid":a[1],"cohort":"original","class":"C4","op":a[2],"anchor_quote":a[3],"replacement":a[4],"defect_statement":"planted","detect_span":a[5]}))' "$@"
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
  [ "$output" = '{"original": {"caught": 0, "k_left": 2, "orphaned": 0, "s_eff": 2}}' ]
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
    '{"id":"H-1","round":1,"locus":{"path":"PLAN.md","lines":"60-61"},"materiality":{"level":"MATERIAL"}}' \
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
