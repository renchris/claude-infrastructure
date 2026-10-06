#!/usr/bin/env bats
# research-kit-heldout — scripts/research-kit/heldout.py, the sealed held-out set gate row 15 reads
# (REPORT.md §10 item 13). It is sealed once, holds at least 40 prompts across every stratum, is
# encrypted at rest, and never prints a prompt outside the rater sheet.

setup() {
  unset CC_BATS_ACTIVE
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  H="$REPO/scripts/research-kit/heldout.py"
  export CC_RESEARCH_HOME="$BATS_TEST_TMPDIR/research" CC_RESEARCH_VAULT_KEY="test-key"
}

cands() { # <per-stratum count> [strata...]
  local n="$1"; shift
  local s i
  for s in "${@:-regex-matched regex-missed pushback other}"; do
    for s2 in $s; do for i in $(seq 1 "$n"); do printf '{"prompt":"secret prompt %s %s","stratum":"%s"}\n' "$s2" "$i" "$s2"; done; done
  done > "$BATS_TEST_TMPDIR/c.jsonl"
}

@test "a sealed split under 40 prompts is refused" {
  cands 5
  run "$H" seal --candidates "$BATS_TEST_TMPDIR/c.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t.jsonl" --fraction 1.0
  [ "$status" -eq 2 ]
  [[ "$output" == *"holds 20 prompt(s) (need 40)"* ]]
}

@test "a sealed split missing a stratum is refused" {
  cands 15 "regex-matched regex-missed other"
  run "$H" seal --candidates "$BATS_TEST_TMPDIR/c.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t.jsonl" --fraction 1.0
  [ "$status" -eq 2 ]
  [[ "$output" == *"no pushback stratum"* ]]
}

@test "the set is encrypted, sealed once, and status never prints a prompt" {
  cands 12
  run "$H" seal --candidates "$BATS_TEST_TMPDIR/c.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t.jsonl" --fraction 1.0
  [ "$status" -eq 0 ]
  run grep -q "secret prompt" "$CC_RESEARCH_HOME/router-heldout/sealed.enc"
  [ "$status" -eq 1 ]
  run "$H" seal --candidates "$BATS_TEST_TMPDIR/c.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t.jsonl" --fraction 1.0
  [ "$status" -eq 2 ]
  [[ "$output" == *"sealed once"* ]] || false
  run "$H" status
  [ "$status" -eq 0 ]
  [[ "$output" != *"secret prompt"* ]]
}

@test "a half split keeps sealed prompts out of the tuning set" {
  cands 40
  "$H" seal --candidates "$BATS_TEST_TMPDIR/c.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t.jsonl"
  "$H" rater-sheet --out "$BATS_TEST_TMPDIR/sheet.jsonl"
  sealed="$(wc -l < "$BATS_TEST_TMPDIR/sheet.jsonl")"
  tuning="$(wc -l < "$BATS_TEST_TMPDIR/t.jsonl")"
  [ $((sealed + tuning)) -eq 160 ]
  [ "$sealed" -ge 40 ]
  /usr/bin/python3 -c "
import json
s = {json.loads(l)['prompt'] for l in open('$BATS_TEST_TMPDIR/sheet.jsonl')}
t = {json.loads(l)['prompt'] for l in open('$BATS_TEST_TMPDIR/t.jsonl')}
assert not s & t, s & t"
}

@test "a label outside the route list is refused" {
  cands 12
  "$H" seal --candidates "$BATS_TEST_TMPDIR/c.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t.jsonl" --fraction 1.0
  "$H" rater-sheet --out "$BATS_TEST_TMPDIR/sheet.jsonl"
  head -n 1 "$BATS_TEST_TMPDIR/sheet.jsonl" | /usr/bin/python3 -c 'import json,sys; print(json.dumps({"id": json.load(sys.stdin)["id"], "label": "maybe"}))' > "$BATS_TEST_TMPDIR/l.jsonl"
  run "$H" label --rater r1 --labels "$BATS_TEST_TMPDIR/l.jsonl"
  [ "$status" -eq 2 ]
}

@test "items the two raters disagree on are excluded, and too few agreed items fail the evaluation" {
  cands 12
  "$H" seal --candidates "$BATS_TEST_TMPDIR/c.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t.jsonl" --fraction 1.0
  "$H" rater-sheet --out "$BATS_TEST_TMPDIR/sheet.jsonl"
  /usr/bin/python3 -c "
import json
rows = [json.loads(l) for l in open('$BATS_TEST_TMPDIR/sheet.jsonl')]
open('$BATS_TEST_TMPDIR/a.jsonl', 'w').writelines(json.dumps({'id': r['id'], 'label': 'completeness'}) + '\n' for r in rows)
open('$BATS_TEST_TMPDIR/b.jsonl', 'w').writelines(json.dumps({'id': r['id'], 'label': 'completeness' if i % 2 else 'other'}) + '\n' for i, r in enumerate(rows))"
  "$H" label --rater r1 --labels "$BATS_TEST_TMPDIR/a.jsonl"
  "$H" label --rater r2 --labels "$BATS_TEST_TMPDIR/b.jsonl"
  printf '#!/bin/bash\ncat >/dev/null\necho completeness\n' > "$BATS_TEST_TMPDIR/router"
  chmod +x "$BATS_TEST_TMPDIR/router"
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" evaluate
  [ "$status" -eq 1 ]
  [[ "$output" == *"24 agreed sealed item(s); at least 40"* ]]
}

# ── wave E1c: a second sealed set beside v1 ─────────────────────────────────────────────────────

# label_all <set> — two raters agree on every item: completeness outside `other`, work-order in it.
label_all() {
  "$H" --set "$1" rater-sheet --out "$BATS_TEST_TMPDIR/sheet.jsonl"
  /usr/bin/python3 -c "
import json
rows = [json.loads(l) for l in open('$BATS_TEST_TMPDIR/sheet.jsonl')]
open('$BATS_TEST_TMPDIR/l.jsonl', 'w').writelines(json.dumps({'id': r['id'], 'label': 'work-order' if ' other ' in r['prompt'] else 'completeness'}) + '\n' for r in rows)"
  "$H" --set "$1" label --rater r1 --labels "$BATS_TEST_TMPDIR/l.jsonl"
  "$H" --set "$1" label --rater r2 --labels "$BATS_TEST_TMPDIR/l.jsonl"
}

@test "wave E1c: --set v2 seals a second set beside v1, and v1 stays sealed once and byte-identical" {
  cands 12
  "$H" seal --candidates "$BATS_TEST_TMPDIR/c.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t.jsonl" --fraction 1.0
  cp "$CC_RESEARCH_HOME/router-heldout/sealed.enc" "$BATS_TEST_TMPDIR/v1.before"
  sed 's/secret prompt/second prompt/' "$BATS_TEST_TMPDIR/c.jsonl" > "$BATS_TEST_TMPDIR/c2.jsonl"
  run "$H" seal --candidates "$BATS_TEST_TMPDIR/c2.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t2.jsonl" --fraction 1.0
  [ "$status" -eq 2 ]
  [[ "$output" == *"v1 is already sealed; it is sealed once"*"--set v2"* ]] || false
  # a dry run states the counts and seals nothing
  run "$H" --set v2 seal --candidates "$BATS_TEST_TMPDIR/c2.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t2.jsonl" --fraction 1.0 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would seal 48 prompt(s) as set v2"*"nothing written"* ]] || false
  [ ! -e "$CC_RESEARCH_HOME/router-heldout/sealed-v2.enc" ]
  [ ! -e "$BATS_TEST_TMPDIR/t2.jsonl" ]
  run "$H" --set v2 seal --candidates "$BATS_TEST_TMPDIR/c2.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t2.jsonl" --fraction 1.0
  [ "$status" -eq 0 ]
  [[ "$output" == *"sealed 48 prompt(s) as set v2"*'"pushback": 12'* ]] || false
  [ -s "$CC_RESEARCH_HOME/router-heldout/sealed-v2.enc" ]
  cmp "$BATS_TEST_TMPDIR/v1.before" "$CC_RESEARCH_HOME/router-heldout/sealed.enc"
  run grep -q "second prompt" "$CC_RESEARCH_HOME/router-heldout/sealed-v2.enc"
  [ "$status" -eq 1 ]
  # v2 is sealed once too, and labeling it leaves v1 alone.
  run "$H" --set v2 seal --candidates "$BATS_TEST_TMPDIR/c2.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t2.jsonl" --fraction 1.0
  [ "$status" -eq 2 ]
  [[ "$output" == *"v2 is already sealed"* ]] || false
  label_all v2
  cmp "$BATS_TEST_TMPDIR/v1.before" "$CC_RESEARCH_HOME/router-heldout/sealed.enc"
  [ "$("$H" --set v1 status 2>/dev/null | jq '[.[].raters | length] | add')" -eq 0 ]
  [ "$("$H" --set v2 status 2>/dev/null | jq '[.[].agreed] | add')" -eq 48 ]
}

@test "wave E1c: v2 never seals a prompt v1 sealed or an excluded tuning set holds" {
  cands 12
  "$H" seal --candidates "$BATS_TEST_TMPDIR/c.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t.jsonl" --fraction 1.0
  printf '{"prompt":"second prompt other 3"}\n' > "$BATS_TEST_TMPDIR/tuning-v1.jsonl"
  {
    sed 's/secret prompt/second prompt/' "$BATS_TEST_TMPDIR/c.jsonl"
    # the same v1 prompts again, as another store spells them
    sed 's/secret prompt/SECRET   prompt/' "$BATS_TEST_TMPDIR/c.jsonl"
  } > "$BATS_TEST_TMPDIR/c2.jsonl"
  run "$H" --set v2 seal --candidates "$BATS_TEST_TMPDIR/c2.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t2.jsonl" --fraction 1.0 --exclude "$BATS_TEST_TMPDIR/tuning-v1.jsonl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sealed 47 prompt(s) as set v2"*"49 candidate(s) dropped as already used"* ]] || false
  "$H" --set v2 rater-sheet --out "$BATS_TEST_TMPDIR/sheet2.jsonl"
  run grep -ci "secret" "$BATS_TEST_TMPDIR/sheet2.jsonl"
  [ "$output" = 0 ]
  run grep -c "second prompt other 3\"" "$BATS_TEST_TMPDIR/sheet2.jsonl"
  [ "$output" = 0 ]
}

@test "wave E1c: with v2 sealed the gate reads v2, --set v1 still reads v1, and fallbacks are counted per stratum" {
  cands 12
  "$H" seal --candidates "$BATS_TEST_TMPDIR/c.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t.jsonl" --fraction 1.0
  label_all v1
  sed 's/secret prompt/second prompt/' "$BATS_TEST_TMPDIR/c.jsonl" > "$BATS_TEST_TMPDIR/c2.jsonl"
  "$H" --set v2 seal --candidates "$BATS_TEST_TMPDIR/c2.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t2.jsonl" --fraction 1.0
  label_all v2
  # A router that knows v1's prompts only: it fails every v2 prompt, as an error (a fallback).
  cat > "$BATS_TEST_TMPDIR/router" <<'R'
#!/bin/bash
p="$(cat)"
case "$p" in
  "secret prompt other"*) echo work-order ;;
  "secret prompt"*) echo completeness ;;
  *) exit 1 ;;
esac
R
  chmod +x "$BATS_TEST_TMPDIR/router"
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" evaluate
  [ "$status" -eq 1 ]
  [[ "$output" == *"held-out set v2: 48 sealed item(s)"* ]] || false
  [[ "$output" == *"48 of 48 routed item(s) fell back"* ]] || false
  [[ "$output" == *"regex-matched 12 of 12 · regex-missed 12 of 12 · pushback 12 of 12 · other 12 of 12"* ]] || false
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" --set v1 evaluate
  [ "$status" -eq 0 ]
  [[ "$output" == *"held-out set v1: 48 sealed item(s)"* ]] || false
  [[ "$output" == *"regex-matched 0 of 12 · regex-missed 0 of 12 · pushback 0 of 12 · other 0 of 12"* ]]
}

@test "wave E1c: a prompt the raters relay under two labels stays uncounted, is shown apart, and --record keeps no prompt or label" {
  cands 12
  "$H" seal --candidates "$BATS_TEST_TMPDIR/c.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t.jsonl" --fraction 1.0
  "$H" rater-sheet --out "$BATS_TEST_TMPDIR/sheet.jsonl"
  # r1: completeness everywhere outside `other`; r2: pushback on the pushback stratum's first 5.
  /usr/bin/python3 -c "
import json
rows = [json.loads(l) for l in open('$BATS_TEST_TMPDIR/sheet.jsonl')]
def lab(r, second):
    if ' other ' in r['prompt']: return 'work-order'
    if second and ' pushback ' in r['prompt'] and int(r['prompt'].split()[-1]) <= 5: return 'pushback'
    return 'completeness'
open('$BATS_TEST_TMPDIR/a.jsonl', 'w').writelines(json.dumps({'id': r['id'], 'label': lab(r, False)}) + '\n' for r in rows)
open('$BATS_TEST_TMPDIR/b.jsonl', 'w').writelines(json.dumps({'id': r['id'], 'label': lab(r, True)}) + '\n' for r in rows)"
  "$H" label --rater r1 --labels "$BATS_TEST_TMPDIR/a.jsonl"
  "$H" label --rater r2 --labels "$BATS_TEST_TMPDIR/b.jsonl"
  # relays everything but pushback prompts 1 and 2, which it calls a work order
  cat > "$BATS_TEST_TMPDIR/router" <<'R'
#!/bin/bash
p="$(cat)"
case "$p" in
  "secret prompt other"*|"secret prompt pushback 1"|"secret prompt pushback 2") echo work-order ;;
  *) echo completeness ;;
esac
R
  chmod +x "$BATS_TEST_TMPDIR/router"
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" evaluate --record "$BATS_TEST_TMPDIR/rec.jsonl"
  # the 7 agreed pushback prompts are all relayed, so the row passes; the 5 split ones do not count
  [ "$status" -eq 0 ]
  [[ "$output" == *"5 item(s) excluded for rater disagreement"* ]] || false
  [[ "$output" == *"stratum pushback: 7/7"* ]] || false
  [[ "$output" == *"0 of 43 routed item(s) fell back"* ]] || false
  [[ "$output" == *"two different relay labels), relayed / items / fell back: regex-matched 0/0/0 · regex-missed 0/0/0 · pushback 3/5/0"* ]] || false
  [ "$(wc -l < "$BATS_TEST_TMPDIR/rec.jsonl" | tr -d ' ')" -eq 48 ]
  [ "$(jq -s '[.[] | select(.counted | not)] | length' "$BATS_TEST_TMPDIR/rec.jsonl")" -eq 5 ]
  [ "$(jq -r 'keys | join(",")' "$BATS_TEST_TMPDIR/rec.jsonl" | sort -u)" = "counted,got,id,set,stratum,wall_s" ]
  run grep -c "secret prompt" "$BATS_TEST_TMPDIR/rec.jsonl"
  [ "$output" = 0 ]
}

@test "wave E1g: --set v3 seals a third set whole, without a prompt v1, v2 or a tuning file holds, and a repeated candidate once" {
  cands 12
  "$H" seal --candidates "$BATS_TEST_TMPDIR/c.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t.jsonl" --fraction 1.0
  sed 's/secret prompt/second prompt/' "$BATS_TEST_TMPDIR/c.jsonl" > "$BATS_TEST_TMPDIR/c2.jsonl"
  "$H" --set v2 seal --candidates "$BATS_TEST_TMPDIR/c2.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t2.jsonl" --fraction 1.0
  cp "$CC_RESEARCH_HOME/router-heldout/sealed.enc" "$BATS_TEST_TMPDIR/v1.before"
  cp "$CC_RESEARCH_HOME/router-heldout/sealed-v2.enc" "$BATS_TEST_TMPDIR/v2.before"
  printf '{"prompt":"third prompt other 3"}\n' > "$BATS_TEST_TMPDIR/tuning-v1.jsonl"
  {
    sed 's/secret prompt/third prompt/' "$BATS_TEST_TMPDIR/c.jsonl"     # 48 new, one of them in a tuning file
    sed 's/secret prompt/THIRD  prompt/' "$BATS_TEST_TMPDIR/c.jsonl"    # the same 48 as a second store spells them
    cat "$BATS_TEST_TMPDIR/c.jsonl" "$BATS_TEST_TMPDIR/c2.jsonl"         # everything v1 and v2 sealed
  } > "$BATS_TEST_TMPDIR/c3.jsonl"
  run "$H" --set v3 seal --candidates "$BATS_TEST_TMPDIR/c3.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t3.jsonl" --fraction 1.0 --exclude "$BATS_TEST_TMPDIR/tuning-v1.jsonl" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would seal 47 prompt(s) as set v3"*"0 to the tuning set"*"145 candidate(s) dropped as already used"* ]] || false
  [ ! -e "$CC_RESEARCH_HOME/router-heldout/sealed-v3.enc" ]
  run "$H" --set v3 seal --candidates "$BATS_TEST_TMPDIR/c3.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t3.jsonl" --fraction 1.0 --exclude "$BATS_TEST_TMPDIR/tuning-v1.jsonl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sealed 47 prompt(s) as set v3"*"0 written to the tuning set"* ]] || false
  [ ! -s "$BATS_TEST_TMPDIR/t3.jsonl" ]
  "$H" --set v3 rater-sheet --out "$BATS_TEST_TMPDIR/sheet3.jsonl"
  [ "$(jq -r .id "$BATS_TEST_TMPDIR/sheet3.jsonl" | sort -u | wc -l | tr -d ' ')" -eq 47 ]
  run grep -ci 'secret prompt\|second prompt' "$BATS_TEST_TMPDIR/sheet3.jsonl"
  [ "$output" = 0 ]
  # the earlier sets are untouched, v3 is sealed once, and the gate now reads v3
  cmp "$BATS_TEST_TMPDIR/v1.before" "$CC_RESEARCH_HOME/router-heldout/sealed.enc"
  cmp "$BATS_TEST_TMPDIR/v2.before" "$CC_RESEARCH_HOME/router-heldout/sealed-v2.enc"
  run "$H" --set v3 seal --candidates "$BATS_TEST_TMPDIR/c3.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t3.jsonl" --fraction 1.0
  [ "$status" -eq 2 ]
  [[ "$output" == *"v3 is already sealed"* ]] || false
  run "$H" status
  [[ "$output" == *"set v3"* ]] || false
}

# ── wave E1h: a fresh tuning draw, a retired set, a subset seal, a pinned instrument, a reads ledger ──

# mk <word> <n> <strata…> — n candidates per stratum whose prompts start with <word>; history-sourced
# in even rows, so a note can split `other` by store.
mk() {
  local w="$1" n="$2" s i; shift 2
  for s in "$@"; do for i in $(seq 1 "$n"); do
    printf '{"prompt":"%s prompt %s %s","stratum":"%s","source":"%s"}\n' "$w" "$s" "$i" "$s" \
      "$([ $((i % 2)) -eq 0 ] && echo "history:.claude@1" || echo "abcd1234@2026-09-20T10:00:00")"
  done; done
}
ALL="regex-matched regex-missed pushback other"
router_says() { printf '#!/bin/bash\ncat >/dev/null\necho %s\n' "$1" > "$BATS_TEST_TMPDIR/router"; chmod +x "$BATS_TEST_TMPDIR/router"; }

@test "wave E1h: draw takes a fresh per-stratum sample that no sealed set or excluded file holds, the same on a re-run, and prints no prompt" {
  mk first 12 $ALL > "$BATS_TEST_TMPDIR/c.jsonl"
  "$H" seal --candidates "$BATS_TEST_TMPDIR/c.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t.jsonl" --fraction 1.0
  printf '{"prompt":"fresh prompt other 3"}\n' > "$BATS_TEST_TMPDIR/tuning-old.jsonl"
  { mk first 12 $ALL; mk fresh 60 $ALL; } > "$BATS_TEST_TMPDIR/pool.jsonl"
  run "$H" draw --candidates "$BATS_TEST_TMPDIR/pool.jsonl" --strata other,regex-matched \
    --take other=20,regex-matched=10 --exclude "$BATS_TEST_TMPDIR/tuning-old.jsonl" --out "$BATS_TEST_TMPDIR/d1.jsonl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"drew 30 prompt(s)"*'"other": 20'*'"regex-matched": 10'* ]] || false
  [[ "$output" != *"fresh prompt"* ]] || false
  [ "$(jq -r .stratum "$BATS_TEST_TMPDIR/d1.jsonl" | sort | uniq -c | tr -s ' ' | tr '\n' ';')" = " 20 other; 10 regex-matched;" ]
  run grep -c 'first prompt\|fresh prompt other 3"' "$BATS_TEST_TMPDIR/d1.jsonl"
  [ "$output" = 0 ]
  "$H" draw --candidates "$BATS_TEST_TMPDIR/pool.jsonl" --strata other,regex-matched \
    --take other=20,regex-matched=10 --exclude "$BATS_TEST_TMPDIR/tuning-old.jsonl" --out "$BATS_TEST_TMPDIR/d2.jsonl"
  cmp "$BATS_TEST_TMPDIR/d1.jsonl" "$BATS_TEST_TMPDIR/d2.jsonl"
  # the draw's order is not seal's split hash: a half split of the drawn prompts lands on both sides
  jq -c 'select(.stratum=="other")' "$BATS_TEST_TMPDIR/d1.jsonl" > "$BATS_TEST_TMPDIR/d-other.jsonl"
  { cat "$BATS_TEST_TMPDIR/d-other.jsonl"; mk pad 40 regex-matched regex-missed pushback; } > "$BATS_TEST_TMPDIR/c2.jsonl"
  run "$H" --set v2 seal --candidates "$BATS_TEST_TMPDIR/c2.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t2.jsonl" --dry-run
  [ "$status" -eq 0 ]
  n="$(printf '%s' "$output" | sed 's/.*"other": \([0-9]*\).*/\1/')"
  [ "$n" -gt 0 ] && [ "$n" -lt 20 ]
  # a stratum with too few fresh prompts is refused, never short-filled in silence
  run "$H" draw --candidates "$BATS_TEST_TMPDIR/pool.jsonl" --strata other --take other=500 \
    --exclude "$BATS_TEST_TMPDIR/tuning-old.jsonl" --out "$BATS_TEST_TMPDIR/d3.jsonl"
  [ "$status" -eq 2 ]
  [[ "$output" == *"stratum other: 59 fresh candidate(s)"* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/d3.jsonl" ]
}

@test "wave E1h: retire writes a read-twice set out as tuning data with its labels, leaves the sealed file byte-identical, and the set carries no verdict again" {
  mk first 12 $ALL > "$BATS_TEST_TMPDIR/c.jsonl"
  "$H" seal --candidates "$BATS_TEST_TMPDIR/c.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t.jsonl" --fraction 1.0
  mk second 12 $ALL > "$BATS_TEST_TMPDIR/c2.jsonl"
  "$H" --set v2 seal --candidates "$BATS_TEST_TMPDIR/c2.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t2.jsonl" --fraction 1.0
  label_all v2
  cp "$CC_RESEARCH_HOME/router-heldout/sealed-v2.enc" "$BATS_TEST_TMPDIR/v2.before"
  run "$H" --set v2 retire --out "$REPO/tests/retired.jsonl"
  [ "$status" -eq 2 ]
  [[ "$output" == *"outside the repo"* ]] || false
  [ ! -e "$REPO/tests/retired.jsonl" ]
  run "$H" --set v2 retire --out "$BATS_TEST_TMPDIR/retired-v2.jsonl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"retired set v2"*"48 prompt(s)"* ]] || false
  [[ "$output" != *"second prompt"* ]] || false
  cmp "$BATS_TEST_TMPDIR/v2.before" "$CC_RESEARCH_HOME/router-heldout/sealed-v2.enc"
  [ "$(jq -r 'select(.labels.r1 and .labels.r2 and .prompt and .stratum) | .stratum' "$BATS_TEST_TMPDIR/retired-v2.jsonl" | wc -l | tr -d ' ')" -eq 48 ]
  [ "$(stat -f %Lp "$BATS_TEST_TMPDIR/retired-v2.jsonl")" = 600 ]
  [ "$(jq -r 'select(.event=="retire") | .set' "$CC_RESEARCH_HOME/router-heldout/reads.jsonl")" = v2 ]
  router_says completeness
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" --set v2 evaluate
  [ "$status" -eq 2 ]
  [[ "$output" == *"v2 is retired"* ]] || false
  # a retired set's prompts are still never drawn or sealed again
  run "$H" draw --candidates "$BATS_TEST_TMPDIR/c2.jsonl" --strata other --take other=1 --out "$BATS_TEST_TMPDIR/d.jsonl"
  [ "$status" -eq 2 ]
}

@test "wave E1h: a subset seal holds only its declared strata, takes N or all of each, and stores them" {
  mk first 12 $ALL > "$BATS_TEST_TMPDIR/c.jsonl"
  "$H" seal --candidates "$BATS_TEST_TMPDIR/c.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t.jsonl" --fraction 1.0
  mk fourth 40 other regex-matched regex-missed > "$BATS_TEST_TMPDIR/c4.jsonl"
  # without --strata the missing pushback stratum is still refused
  run "$H" --set v4 seal --candidates "$BATS_TEST_TMPDIR/c4.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t4.jsonl" --fraction 1.0
  [ "$status" -eq 2 ]
  [[ "$output" == *"no pushback stratum"* ]] || false
  run "$H" --set v4 seal --candidates "$BATS_TEST_TMPDIR/c4.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t4.jsonl" --fraction 1.0 \
    --strata other,regex-matched --take other=30,regex-matched=all
  [ "$status" -eq 0 ]
  [[ "$output" == *"sealed 70 prompt(s) as set v4"* ]] || false
  [ "$("$H" --set v4 status 2>/dev/null | jq -c '[.other.items, ."regex-matched".items, (has("regex-missed")), (has("pushback"))]')" = '[30,40,false,false]' ]
  # a declared stratum with no candidate is refused
  run "$H" --set v2 seal --candidates "$BATS_TEST_TMPDIR/c4.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t4.jsonl" --fraction 1.0 --strata other,pushback
  [ "$status" -eq 2 ]
  [[ "$output" == *"no pushback stratum"* ]] || false
}

# composite — v1 whole (all four strata), v4 a subset (other, regex-matched), both labeled; the
# instrument takes other and regex-matched from v4 and the rest from v1.
composite() {
  mk first 12 $ALL > "$BATS_TEST_TMPDIR/c.jsonl"
  "$H" seal --candidates "$BATS_TEST_TMPDIR/c.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t.jsonl" --fraction 1.0
  label_all v1
  mk fourth 20 other regex-matched > "$BATS_TEST_TMPDIR/c4.jsonl"
  "$H" --set v4 seal --candidates "$BATS_TEST_TMPDIR/c4.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t4.jsonl" --fraction 1.0 --strata other,regex-matched
  label_all v4
  "$H" instrument --pin other=v4,regex-matched=v4,regex-missed=v1,pushback=v1
}

@test "wave E1h: a pinned instrument scores each stratum from its own set, pools the item floor and the fallback share, and the record names the set" {
  composite
  [ "$(jq -c .strata "$CC_RESEARCH_HOME/router-heldout/instrument.json")" = '{"other":"v4","pushback":"v1","regex-matched":"v4","regex-missed":"v1"}' ]
  # a router that says completeness: every relay stratum passes, `other` (gold work-order) reads 0
  router_says completeness
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" evaluate --record "$BATS_TEST_TMPDIR/rec.jsonl"
  [ "$status" -eq 1 ]
  [[ "$output" == *"stratum other: correct-label rate 0/20"* ]] || false
  [[ "$output" == *"stratum regex-matched: 20/20"* ]] || false
  [[ "$output" == *"stratum regex-missed: 12/12"* ]] || false
  [[ "$output" == *"stratum pushback: 12/12"* ]] || false
  [[ "$output" == *"0 of 64 routed item(s) fell back"* ]] || false
  [ "$(jq -r '"\(.stratum) \(.set)"' "$BATS_TEST_TMPDIR/rec.jsonl" | sort | uniq -c | tr -s ' ' | tr '\n' ';')" = " 20 other v4; 12 pushback v1; 20 regex-matched v4; 12 regex-missed v1;" ]
  run grep -c 'prompt' "$BATS_TEST_TMPDIR/rec.jsonl"
  [ "$output" = 0 ]
  # the gate's own call (no --set) reads the instrument; a named set still reads that set alone
  router_says work-order
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" evaluate
  [[ "$output" == *"stratum regex-matched: recall 0/20"* ]] || false
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" --set v1 evaluate
  [[ "$output" == *"stratum regex-matched: recall 0/12"* ]] || false
  # an instrument that names an unsealed set, or a stratum the set does not hold, is refused
  run "$H" instrument --pin other=v3,regex-matched=v4,regex-missed=v1,pushback=v1
  [ "$status" -eq 2 ]
  run "$H" instrument --pin other=v4,regex-matched=v4,regex-missed=v4,pushback=v1
  [ "$status" -eq 2 ]
  [[ "$output" == *"v4 does not hold regex-missed"* ]] || false
}

@test "wave E1h: every evaluate is written to the reads ledger, and the notes say how often each stratum of each set was read before" {
  composite
  router_says completeness
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" evaluate
  [[ "$output" == *"stratum other of set v4: read 0 time(s) before"* ]] || false
  [[ "$output" == *"stratum pushback of set v1: read 0 time(s) before"* ]] || false
  [ "$(jq -r 'select(.event=="read") | "\(.set) \(.stratum)"' "$CC_RESEARCH_HOME/router-heldout/reads.jsonl" | sort | tr '\n' ';')" = "v1 pushback;v1 regex-missed;v4 other;v4 regex-matched;" ]
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" --set v1 evaluate
  [[ "$output" == *"stratum pushback of set v1: read 1 time(s) before"* ]] || false
  [[ "$output" == *"stratum other of set v1: read 0 time(s) before"* ]] || false
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" evaluate
  [[ "$output" == *"stratum other of set v4: read 1 time(s) before"* ]] || false
  [[ "$output" == *"stratum pushback of set v1: read 2 time(s) before"* ]] || false
  # reads made before the ledger existed are counted from a planted row, as the real sets' are
  printf '{"event":"read","set":"v4","stratum":"other","at":"2026-10-01T00:00:00Z","before_ledger":true}\n' >> "$CC_RESEARCH_HOME/router-heldout/reads.jsonl"
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" evaluate
  [[ "$output" == *"stratum other of set v4: read 3 time(s) before"* ]] || false
}

@test "wave E1h: the notes give the false-relay rate on agreed non-relay items and split other by store, and neither can fail the row" {
  composite
  router_says completeness
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" evaluate
  [[ "$output" == *"relayed although both raters gave a non-relay label: other 20/20"* ]] || false
  [[ "$output" == *"other by store, correct / items: history 0/10 · transcript 0/10"* ]] || false
  router_says work-order
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" --set v4 evaluate
  [[ "$output" == *"relayed although both raters gave a non-relay label: other 0/20"* ]] || false
  [[ "$output" == *"other by store, correct / items: history 10/10 · transcript 10/10"* ]] || false
  [[ "$output" != *"stratum other:"*"below"* ]] || false
}
