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

# Matching against what the reviewers actually read (2026-10-11, truememory-2-0 round 1 tagged 0 of
# 60 seeds while ~15 holes quoted seeded-only text). RED-proof: each test below but the class veto
# fails on seed.py before the fix — a multi-range locus never parsed, spans used the real plan's
# numbering, the detect_span basename had to equal the hole's, a quote was no evidence, and the
# seeded copy passed as --plan orphaned every seed.
DEFECT="the retry count is unbounded, so a failed write loops forever"
CLAIM="the daemon retries a failed write forever: the retry count is unbounded"
hole() { # <id> <path> <lines> <class> <claim> [quote]
  /usr/bin/python3 -c 'import json,sys; a=sys.argv
loc={"path":a[2],"lines":a[3]}
if len(a) > 6: loc["quote"]=a[6]
print(json.dumps({"id":a[1],"round":1,"locus":loc,"taxonomy_class":a[4],"claim":a[5],"materiality":{"level":"MATERIAL"}}))' "$@"
}
tag_of() { /usr/bin/python3 -c "import json; s={}
for l in open('$CC_RESEARCH_RECORDS/holes.jsonl'): r=json.loads(l); s.setdefault(r['id'], {}).update(r)
print(s['$1'].get('seed_match'))"; }
retry_seeds() { # S-1 replaces A1 (class C4, the retry defect), S-2 omits A2
  { seedline S-1 replace "$A1" "The sync daemon retries a failed write forever with no backoff at all." "PLAN.md:61-61" "$DEFECT"
    seedline S-2 delete-member "$A2" "" "PLAN.md:62-62"; } > "$BATS_TEST_TMPDIR/seeds.jsonl"
  "$SEED" plant --program demo --plan "${1:-$PLAN}" --seeds "$BATS_TEST_TMPDIR/seeds.jsonl" --profile lite
}

@test "match: a multi-range locus catches the seed when any of its ranges covers the span" {
  retry_seeds
  hole H-1 PLAN.md "5; 61, 70 - 72" C4 "$CLAIM" > "$CC_RESEARCH_RECORDS/holes.jsonl"
  run "$SEED" match --program demo --round 1 --plan "$PLAN"
  [ "$output" = '{"original": {"caught": 1, "k_left": 1, "orphaned": 0, "s_eff": 2}}' ]
  [ "$(tag_of H-1)" = "S-1" ]
}

@test "match: a hole citing the seeded copy's line numbers catches a seed that an omission above it moved" {
  # S-0 deletes an 8-line block above A1, so the seeded copy holds S-1's text 7 lines higher than
  # its detect_span says: further than SEEDED_SPAN_SLACK could explain.
  { for i in $(seq 1 20); do echo "filler line $i of the plan that says nothing at all"; done
    echo "Members of the sync population, every one of them a caller:"
    for i in $(seq 1 7); do echo "- member $i calls the daemon"; done
    for i in $(seq 29 60); do echo "filler line $i of the plan that says nothing at all"; done
    echo "$A1"; echo "$A2"; } > "$PLAN"
  block="$(sed -n 21,28p "$PLAN")"
  { seedline S-0 delete-member "$block" "" "PLAN.md:21-28"
    seedline S-1 replace "$A1" "The sync daemon retries a failed write forever with no backoff at all." "PLAN.md:61-61" "$DEFECT"; } \
    > "$BATS_TEST_TMPDIR/seeds.jsonl"
  "$SEED" plant --program demo --plan "$PLAN" --seeds "$BATS_TEST_TMPDIR/seeds.jsonl" --profile lite
  "$SEED" apply --program demo --plan "$PLAN" --out "$BATS_TEST_TMPDIR/seeded.md"
  n="$(grep -n "forever with no backoff" "$BATS_TEST_TMPDIR/seeded.md" | cut -d: -f1)"
  [ "$n" = "54" ]
  hole H-1 PLAN.md "$n" C4 "$CLAIM" > "$CC_RESEARCH_RECORDS/holes.jsonl"
  run "$SEED" match --program demo --round 1 --plan "$PLAN"
  [ "$(tag_of H-1)" = "S-1" ]
}

@test "match: a PLAN.md detect_span matches a hole that names the plan's own basename" {
  real="$BATS_TEST_TMPDIR/TRUEMEMORY_2_0.md"
  cp "$PLAN" "$real"
  retry_seeds "$real"
  hole H-1 docs/plans/TRUEMEMORY_2_0.md 61 C4 "$CLAIM" > "$CC_RESEARCH_RECORDS/holes.jsonl"
  run "$SEED" match --program demo --round 1 --plan "$real"
  [ "$(tag_of H-1)" = "S-1" ]
}

@test "match: a quote of the seed's planted text catches it whatever the claim says; a quote of text the real plan keeps does not" {
  retry_seeds
  { hole H-1 PLAN.md 61 C4 "the loop has no exit condition and will hammer the store" \
      "retries a failed write forever with no backoff"
    hole H-2 PLAN.md 61 C4 "the loop has no exit condition and will hammer the store" \
      "The sync daemon retries a failed write"; } > "$CC_RESEARCH_RECORDS/holes.jsonl"
  run "$SEED" match --program demo --round 1 --plan "$PLAN"
  [ "$(tag_of H-1)" = "S-1" ]
  [ "$(tag_of H-2)" = "None" ]
}

@test "match: a hole of a different class on the seed's span does not catch it, even quoting the planted text" {
  retry_seeds
  hole H-1 PLAN.md 61 C9 "$CLAIM" "retries a failed write forever with no backoff" > "$CC_RESEARCH_RECORDS/holes.jsonl"
  run "$SEED" match --program demo --round 1 --plan "$PLAN"
  [ "$output" = '{"original": {"caught": 0, "k_left": 2, "orphaned": 0, "s_eff": 2}}' ]
  [ "$(tag_of H-1)" = "None" ]
}

@test "match: the seeded copy passed as --plan is refused, and no seed is orphaned" {
  retry_seeds
  "$SEED" apply --program demo --plan "$PLAN" --out "$BATS_TEST_TMPDIR/seeded.md"
  : > "$CC_RESEARCH_RECORDS/holes.jsonl"
  run "$SEED" match --program demo --round 1 --plan "$BATS_TEST_TMPDIR/seeded.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"looks like the seeded copy; pass the real plan"* ]] || false
  run "$SEED" status --program demo
  [ "${lines[0]}" = '{"original": {"caught": 0, "k_left": 2, "orphaned": 0, "s_eff": 2}}' ]
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

# Settling a round before any plan edit (2026-10-11, round-settle kit). RED-proof: on seed.py before
# the change, detect_span overlapped a seed the copy holds (H-1 below was tagged), an artifact or
# split-off hole was tagged and caught its seed, and `match --dry-run` / `explain` did not parse.
shifted_plan() { # S-0 deletes 8 lines above A1, so S-1 sits on copy line 54 while its detect_span says 61
  { for i in $(seq 1 20); do echo "filler line $i of the plan that says nothing at all"; done
    echo "Members of the sync population, every one of them a caller:"
    for i in $(seq 1 7); do echo "- member $i calls the daemon"; done
    for i in $(seq 29 60); do echo "filler line $i of the plan that says nothing at all"; done
    echo "$A1"; echo "$A2"
    for i in $(seq 63 75); do echo "filler line $i of the plan that says nothing at all"; done; } > "$PLAN"
  { seedline S-0 delete-member "$(sed -n 21,28p "$PLAN")" "" "PLAN.md:21-28"
    seedline S-1 replace "$A1" "The sync daemon retries a failed write forever with no backoff at all." "PLAN.md:61-61" "$DEFECT"
    seedline S-2 delete-member "$A2" "" "PLAN.md:62-62" "the launchd caller is missing from the population"; } \
    > "$BATS_TEST_TMPDIR/seeds.jsonl"
  "$SEED" plant --program demo --plan "$PLAN" --seeds "$BATS_TEST_TMPDIR/seeds.jsonl" --profile lite
}

@test "match: an author's detect_span (real-plan lines) no longer tags a hole on the copy's line of that number" {
  shifted_plan
  # copy line 61 is filler 7 lines below where S-1 sits in the copy, beyond the slack
  { hole H-1 PLAN.md 61 C4 "$CLAIM"; hole H-2 PLAN.md 54 C4 "$CLAIM"; } > "$CC_RESEARCH_RECORDS/holes.jsonl"
  run "$SEED" match --program demo --round 1 --plan "$PLAN"
  [ "$status" -eq 0 ]
  [ "$(tag_of H-1)" = "None" ]
  [ "$(tag_of H-2)" = "S-1" ]
}

@test "match: an artifact or split-off hole restating a seed neither tags nor catches it" {
  retry_seeds
  { hole H-1 PLAN.md 61 C4 "$CLAIM"; hole H-2 PLAN.md 61 C4 "$CLAIM"; } > "$CC_RESEARCH_RECORDS/holes.jsonl"
  printf '%s\n' '{"id":"H-1","artifact":{"reason":"copy damage"}}' '{"id":"H-2","split_from":"H-0"}' \
    >> "$CC_RESEARCH_RECORDS/holes.jsonl"
  run "$SEED" match --program demo --round 1 --plan "$PLAN"
  [ "$output" = '{"original": {"caught": 0, "k_left": 2, "orphaned": 0, "s_eff": 2}}' ]
  [ "$(tag_of H-1)" = "None" ]
  [ "$(tag_of H-2)" = "None" ]
}

@test "match --dry-run: names the holes a real match would tag, counts the catches, and writes nothing" {
  shifted_plan
  { hole H-1 PLAN.md 61 C4 "$CLAIM"; hole H-2 PLAN.md 54 C4 "$CLAIM"
    hole H-3 PLAN.md 5 C4 "the cutover has no owner and no date"; } > "$CC_RESEARCH_RECORDS/holes.jsonl"
  before="$(shasum "$CC_RESEARCH_RECORDS/holes.jsonl" "$CC_RESEARCH_HOME/demo/vault/seeds.enc")"
  run "$SEED" match --program demo --round 1 --plan "$PLAN" --dry-run
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "would tag: H-2" ]
  [ "${lines[2]}" = "would catch: 1 · would orphan: 0" ]
  [ "$(shasum "$CC_RESEARCH_RECORDS/holes.jsonl" "$CC_RESEARCH_HOME/demo/vault/seeds.enc")" = "$before" ]
  [[ "$output" != *"S-"* ]] || false
  # a tag the matcher no longer derives is named, never removed
  printf '%s\n' '{"id":"H-1","seed_match":"S-1"}' >> "$CC_RESEARCH_RECORDS/holes.jsonl"
  run "$SEED" match --program demo --round 1 --plan "$PLAN" --dry-run
  [ "${lines[3]}" = "tagged but no longer derived (kept; match never removes a tag): H-1" ]
}

@test "explain: prints each rule's outcome for a named hole, never a seed's sid, op, state or text, and logs the call" {
  shifted_plan
  { hole H-1 PLAN.md 61 C4 "$CLAIM"; hole H-2 PLAN.md 54 C4 "$CLAIM"
    hole H-3 PLAN.md 55 C2 "the population names no launchd caller" "hooks/a.sh, hooks/b.sh"; } > "$CC_RESEARCH_RECORDS/holes.jsonl"
  run "$SEED" explain --program demo --round 1 --plan "$PLAN" --hole H-1 H-2 H-3
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "round 1 seeded copy: sha256 "*" lines" ]] || false
  [[ "$output" == *"H-1: tagged no"*"span none"*"first failing rule: span"* ]] || false
  [[ "$output" == *"H-2: tagged no"*"span exact"*"matches yes"* ]] || false
  [[ "$output" == *"H-3: tagged no"*"quote evidence none"* ]] || false
  # seed-blind: no sid, op type or state, and no 25-character window of any anchor, replacement or statement
  for w in S-0 S-1 S-2 replace delete-member live caught orphaned "n/a (omission"; do
    [[ "$output" != *"$w"* ]] || false
  done
  /usr/bin/python3 -c '
import json, sys
out = sys.stdin.read()
norm = lambda t: " ".join(str(t).split())
for l in open(sys.argv[1]):
    s = json.loads(l)
    for t in [s.get("anchor_quote"), s.get("replacement"), s.get("defect_statement")]:
        t = norm(t or "")
        for i in range(len(t) - 24):
            assert t[i:i + 25] not in out, t[i:i + 25]' "$BATS_TEST_TMPDIR/seeds.jsonl" <<< "$output"
  run /usr/bin/python3 -c "import json; r=[json.loads(l) for l in open('$CC_RESEARCH_HOME/demo/explain.jsonl')]; print(len(r), r[0]['holes'], r[0]['round'])"
  [ "$output" = "1 ['H-1', 'H-2', 'H-3'] 1" ]
}

# Match scope (2026-10-12). RED-proof: with `round <= K` in match_inputs, `match --round 2` printed
# caught 1 and tagged round 1's H-1 with S-1, a seed no round-2 reviewer caught.
@test "match: round 2 tests only round 2's holes, so an earlier round's untagged hole neither tags nor catches" {
  retry_seeds
  hole H-1 PLAN.md 61 C4 "$CLAIM" > "$CC_RESEARCH_RECORDS/holes.jsonl"
  run "$SEED" match --program demo --round 2 --plan "$PLAN" --dry-run
  [ "${lines[1]}" = "would tag: none" ]
  [ "${lines[2]}" = "would catch: 0 · would orphan: 0" ]
  run "$SEED" match --program demo --round 2 --plan "$PLAN"
  [ "$output" = '{"original": {"caught": 0, "k_left": 2, "orphaned": 0, "s_eff": 2}}' ]
  [ "$(tag_of H-1)" = "None" ]
  # the same claim raised in round 2 is that round's catch, and round 1's hole stays as it was
  hole H-2 PLAN.md 61 C4 "$CLAIM" | sed 's/"round": 1/"round": 2/' >> "$CC_RESEARCH_RECORDS/holes.jsonl"
  run "$SEED" match --program demo --round 2 --plan "$PLAN"
  [ "$output" = '{"original": {"caught": 1, "k_left": 1, "orphaned": 0, "s_eff": 2}}' ]
  [ "$(tag_of H-2)" = "S-1" ]
  [ "$(tag_of H-1)" = "None" ]
}
