#!/usr/bin/env bats
# research-kit-heldout — scripts/research-kit/heldout.py, the sealed held-out set gate row 15 reads
# (REPORT.md §10 item 13). It is sealed once, holds at least 40 prompts across every stratum, is
# encrypted at rest, and never prints a prompt outside the rater sheet.

setup() {
  unset CC_BATS_ACTIVE
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  H="$REPO/scripts/research-kit/heldout.py"
  export CC_RESEARCH_HOME="$BATS_TEST_TMPDIR/research" CC_RESEARCH_VAULT_KEY="test-key"
  e1l_ready
}

# e1l_ready: what wave E1l's read needs besides consent — RULE E1k's passing real-load figures on
# record, and a quiet machine (a load planted in the fixture home; the live store never reads one).
e1l_ready() {
  mkdir -p "$CC_RESEARCH_HOME/router-heldout"
  printf '{"rule":"E1k","run":2,"source":"fixture","rows":120,"fallbacks":1,"held_one_silent":0,"verdict":"PASS"}\n' \
    > "$CC_RESEARCH_HOME/router-heldout/real-load.json"
  printf '5\n' > "$CC_RESEARCH_HOME/router-heldout/load1.fixture"
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
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" evaluate --consent-sealed-read
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
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" evaluate --consent-sealed-read
  [ "$status" -eq 1 ]
  [[ "$output" == *"held-out set v2: 48 sealed item(s)"* ]] || false
  [[ "$output" == *"48 of 48 routed item(s) fell back"* ]] || false
  [[ "$output" == *"regex-matched 12 of 12 · regex-missed 12 of 12 · pushback 12 of 12 · other 12 of 12"* ]] || false
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" --set v1 evaluate --consent-sealed-read
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
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" evaluate --consent-sealed-read --record "$BATS_TEST_TMPDIR/rec.jsonl"
  # the 7 agreed pushback prompts are all relayed, so the row passes; the 5 split ones do not count
  [ "$status" -eq 0 ]
  [[ "$output" == *"5 item(s) excluded for rater disagreement"* ]] || false
  [[ "$output" == *"stratum pushback: 7/7"* ]] || false
  [[ "$output" == *"0 of 43 routed item(s) fell back"* ]] || false
  [[ "$output" == *"two different relay labels), relayed / items / fell back: regex-matched 0/0/0 · regex-missed 0/0/0 · pushback 3/5/0"* ]] || false
  [ "$(wc -l < "$BATS_TEST_TMPDIR/rec.jsonl" | tr -d ' ')" -eq 48 ]
  [ "$(jq -s '[.[] | select(.counted | not)] | length' "$BATS_TEST_TMPDIR/rec.jsonl")" -eq 5 ]
  [ "$(jq -r 'keys | join(",")' "$BATS_TEST_TMPDIR/rec.jsonl" | sort -u)" = "counted,got,id,load1,set,stratum,wall_s" ]
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
ALL=(regex-matched regex-missed pushback other)
router_says() { printf '#!/bin/bash\ncat >/dev/null\necho %s\n' "$1" > "$BATS_TEST_TMPDIR/router"; chmod +x "$BATS_TEST_TMPDIR/router"; }

@test "wave E1h: draw takes a fresh per-stratum sample that no sealed set or excluded file holds, the same on a re-run, and prints no prompt" {
  mk first 12 "${ALL[@]}" > "$BATS_TEST_TMPDIR/c.jsonl"
  "$H" seal --candidates "$BATS_TEST_TMPDIR/c.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t.jsonl" --fraction 1.0
  printf '{"prompt":"fresh prompt other 3"}\n' > "$BATS_TEST_TMPDIR/tuning-old.jsonl"
  { mk first 12 "${ALL[@]}"; mk fresh 60 "${ALL[@]}"; } > "$BATS_TEST_TMPDIR/pool.jsonl"
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
  [ "$n" -gt 0 ] && [ "$n" -lt 20 ] || false
  # a stratum with too few fresh prompts is refused, never short-filled in silence
  run "$H" draw --candidates "$BATS_TEST_TMPDIR/pool.jsonl" --strata other --take other=500 \
    --exclude "$BATS_TEST_TMPDIR/tuning-old.jsonl" --out "$BATS_TEST_TMPDIR/d3.jsonl"
  [ "$status" -eq 2 ]
  [[ "$output" == *"stratum other: 59 fresh candidate(s)"* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/d3.jsonl" ]
}

@test "wave E1h: retire writes a read-twice set out as tuning data with its labels, leaves the sealed file byte-identical, and the set carries no verdict again" {
  mk first 12 "${ALL[@]}" > "$BATS_TEST_TMPDIR/c.jsonl"
  "$H" seal --candidates "$BATS_TEST_TMPDIR/c.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t.jsonl" --fraction 1.0
  mk second 12 "${ALL[@]}" > "$BATS_TEST_TMPDIR/c2.jsonl"
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
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" --set v2 evaluate --consent-sealed-read
  [ "$status" -eq 2 ]
  [[ "$output" == *"v2 is retired"* ]] || false
  # a retired set's prompts are still never drawn or sealed again
  run "$H" draw --candidates "$BATS_TEST_TMPDIR/c2.jsonl" --strata other --take other=1 --out "$BATS_TEST_TMPDIR/d.jsonl"
  [ "$status" -eq 2 ]
}

@test "wave E1h: a subset seal holds only its declared strata, takes N or all of each, and stores them" {
  mk first 12 "${ALL[@]}" > "$BATS_TEST_TMPDIR/c.jsonl"
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
  mk first 12 "${ALL[@]}" > "$BATS_TEST_TMPDIR/c.jsonl"
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
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" evaluate --consent-sealed-read --record "$BATS_TEST_TMPDIR/rec.jsonl"
  [ "$status" -eq 1 ]
  [[ "$output" == *"stratum other: relay-decision rate 0/20"* ]] || false
  [[ "$output" == *"stratum regex-matched: 20/20"* ]] || false
  [[ "$output" == *"stratum regex-missed: 12/12"* ]] || false
  [[ "$output" == *"stratum pushback: 12/12"* ]] || false
  [[ "$output" == *"0 of 64 routed item(s) fell back"* ]] || false
  [ "$(jq -r '"\(.stratum) \(.set)"' "$BATS_TEST_TMPDIR/rec.jsonl" | sort | uniq -c | tr -s ' ' | tr '\n' ';')" = " 20 other v4; 12 pushback v1; 20 regex-matched v4; 12 regex-missed v1;" ]
  run grep -c 'prompt' "$BATS_TEST_TMPDIR/rec.jsonl"
  [ "$output" = 0 ]
  # the gate's own call (no --set) read the instrument above; a named set still reads that set alone
  # (one instrument read here, not two: a second would make this v1 read a third of pushback, wave E1l)
  router_says work-order
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" --set v1 evaluate --consent-sealed-read
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
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" evaluate --consent-sealed-read
  [[ "$output" == *"stratum other of set v4: read 0 time(s) before"* ]] || false
  [[ "$output" == *"stratum pushback of set v1: read 0 time(s) before"* ]] || false
  [ "$(jq -r 'select(.event=="read") | "\(.set) \(.stratum)"' "$CC_RESEARCH_HOME/router-heldout/reads.jsonl" | sort | tr '\n' ';')" = "v1 pushback;v1 regex-missed;v4 other;v4 regex-matched;" ]
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" --set v1 evaluate --consent-sealed-read
  [[ "$output" == *"stratum pushback of set v1: read 1 time(s) before"* ]] || false
  [[ "$output" == *"stratum other of set v1: read 0 time(s) before"* ]] || false
  # wave E1l: pushback and regex-missed of v1 are now read twice, so the instrument's next read is
  # refused before it reads, and the refusal says how often each was read
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" evaluate --consent-sealed-read
  [ "$status" -eq 2 ]
  [[ "$output" == *"pushback of v1 (read 2 times, 0 signed)"* ]] || false
  [[ "$output" != *"other of v4"* ]] || false
  # reads made before the ledger existed are counted from a planted row, as the real sets' are
  printf '{"event":"read","set":"v4","stratum":"other","at":"2026-10-01T00:00:00Z","before_ledger":true}\n' >> "$CC_RESEARCH_HOME/router-heldout/reads.jsonl"
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" evaluate --consent-sealed-read
  [[ "$output" == *"other of v4 (read 2 times, 0 signed)"* ]] || false
}

@test "wave E1i: other is scored on the relay decision (floor 0.90), a fallback or a missed relay is a miss, and the exact label is shown only" {
  mk first 12 "${ALL[@]}" > "$BATS_TEST_TMPDIR/c.jsonl"
  "$H" seal --candidates "$BATS_TEST_TMPDIR/c.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t.jsonl" --fraction 1.0
  label_all v1
  mk fourth 20 other regex-matched > "$BATS_TEST_TMPDIR/c4.jsonl"
  "$H" --set v4 seal --candidates "$BATS_TEST_TMPDIR/c4.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t4.jsonl" --fraction 1.0 --strata other,regex-matched
  # gold: other 1-4 are re-asks (completeness), other 5-20 work orders; regex-matched completeness
  "$H" --set v4 rater-sheet --out "$BATS_TEST_TMPDIR/sheet.jsonl"
  /usr/bin/python3 -c "
import json
rows = [json.loads(l) for l in open('$BATS_TEST_TMPDIR/sheet.jsonl')]
lab = lambda p: ('completeness' if int(p.split()[-1]) <= 4 else 'work-order') if ' other ' in p else 'completeness'
open('$BATS_TEST_TMPDIR/l.jsonl', 'w').writelines(json.dumps({'id': r['id'], 'label': lab(r['prompt'])}) + '\n' for r in rows)"
  "$H" --set v4 label --rater r1 --labels "$BATS_TEST_TMPDIR/l.jsonl"
  "$H" --set v4 label --rater r2 --labels "$BATS_TEST_TMPDIR/l.jsonl"
  "$H" instrument --pin other=v4,regex-matched=v4,regex-missed=v1,pushback=v1
  # 1-3 relayed (right), 4 not relayed (a missed re-ask), 5 a fallback, 6-20 `concern`: the wrong
  # non-relay label, which the relay decision scores right. 18 of 20 = 0.90 passes; WRONG6 relays 6.
  cat > "$BATS_TEST_TMPDIR/router" <<'R'
#!/bin/bash
p="$(cat)"
case "$p" in
  "fourth prompt other "[123]) echo completeness ;;
  "fourth prompt other 4") echo concern ;;
  "fourth prompt other 5") exit 1 ;;
  "fourth prompt other 6") if [ -n "${WRONG6:-}" ]; then echo completeness; else echo concern; fi ;;
  *" other "*) echo concern ;;
  *) echo completeness ;;
esac
R
  chmod +x "$BATS_TEST_TMPDIR/router"
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" evaluate --consent-sealed-read
  [ "$status" -eq 0 ]
  [[ "$output" == *"stratum other: 18/20 (relay decision)"* ]] || false
  [[ "$output" == *"other, exact label (shown only, never a failure): 3/20"* ]] || false
  [[ "$output" == *"relayed although both raters gave a non-relay label: other 0/16"* ]] || false
  WRONG6=1 CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" evaluate --consent-sealed-read
  [ "$status" -eq 1 ]
  [[ "$output" == *"stratum other: relay-decision rate 17/20 = 0.85, below 0.9"* ]] || false
  [[ "$output" == *"relayed although both raters gave a non-relay label: other 1/16"* ]] || false
}

@test "wave E1h: the notes give the false-relay rate on agreed non-relay items and split other by store, and neither can fail the row" {
  composite
  router_says completeness
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" evaluate --consent-sealed-read
  [[ "$output" == *"relayed although both raters gave a non-relay label: other 20/20"* ]] || false
  [[ "$output" == *"other by store, relay decision right / items: history 0/10 · transcript 0/10"* ]] || false
  router_says work-order
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" --set v4 evaluate --consent-sealed-read
  [[ "$output" == *"relayed although both raters gave a non-relay label: other 0/20"* ]] || false
  [[ "$output" == *"other by store, relay decision right / items: history 10/10 · transcript 10/10"* ]] || false
  [[ "$output" != *"stratum other:"*"below"* ]] || false
}

# ── wave E1l (rulings a7fd5e2ee7c8, 915d7fb98b7f, 17aff7158fa6) ─────────────────────────────────────
# spoil <file>: a sealed file replaced by bytes that cannot be decrypted, kept in <file>.bak. A refusal
# that comes before any decrypt reads the same with it; a read that got as far as decrypting cannot.
spoil() { cp "$CC_RESEARCH_HOME/router-heldout/$1" "$CC_RESEARCH_HOME/router-heldout/$1.bak"; printf 'not a sealed set' > "$CC_RESEARCH_HOME/router-heldout/$1"; }
unspoil() { mv "$CC_RESEARCH_HOME/router-heldout/$1.bak" "$CC_RESEARCH_HOME/router-heldout/$1"; }
ledger_rows() { cat "$CC_RESEARCH_HOME/router-heldout/reads.jsonl" 2>/dev/null | wc -l | tr -d ' '; }
# sig <set>.<stratum> [chain-json]: a third-read signature as the operator's own terminal leaves it
sig() {
  mkdir -p "$CC_RESEARCH_HOME/demo"
  printf '{"action":"third-read","target":"%s","at":%s,"at_iso":"2026-10-08T00:00:00Z","because":"fixture","pins":{},"provenance":{"claude_ancestor":false,"chain":%s}}\n' \
    "$1" "$(date +%s)" "${2:-[\"zsh\",\"kitty\"]}" >> "$CC_RESEARCH_HOME/demo/signoff.jsonl"
}

@test "wave E1l: with no read consent, the kill switch, or a router that is not found, evaluate refuses before it decrypts and logs no read" {
  composite
  router_says completeness
  spoil sealed.enc
  spoil sealed-v4.enc
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" evaluate
  [ "$status" -eq 2 ]
  [[ "$output" == *"no read consent"* ]] || false
  for v in off OFF " off "; do
    CC_RESEARCH_ROUTER="$v" run "$H" evaluate --consent-sealed-read
    [ "$status" -eq 2 ]
    [[ "$output" == *"the router's kill switch"* ]] || false
  done
  CC_RESEARCH_ROUTER="no-such-router-e1l classify" run "$H" evaluate --consent-sealed-read
  [ "$status" -eq 2 ]
  [[ "$output" == *"'no-such-router-e1l', which is not found"* ]] || false
  [ "$(ledger_rows)" = 0 ]
  # control: with every guard met the same spoiled files are decrypted, and the read dies there
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" evaluate --consent-sealed-read
  [ "$status" -ne 0 ]
  [[ "$output" != *"no read consent"* && "$output" != *"kill switch"* ]] || false
  # and unspoiled, the real read goes through and is logged
  unspoil sealed.enc
  unspoil sealed-v4.enc
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" evaluate --consent-sealed-read
  [ "$status" -eq 1 ]
  [ "$(ledger_rows)" = 4 ]
}

@test "wave E1l: a third read of a stratum is refused before any decrypt; each valid operator signature buys one, printed as a disclosed cost" {
  composite
  router_says completeness
  export CC_RESEARCH_RECORDS="$BATS_TEST_TMPDIR/records"
  mkdir -p "$CC_RESEARCH_RECORDS"
  for i in 1 2; do
    CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" evaluate --consent-sealed-read
    [ "$status" -eq 1 ]
  done
  [ "$(ledger_rows)" = 8 ]
  spoil sealed.enc
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" evaluate --consent-sealed-read --program demo
  [ "$status" -eq 2 ]
  [[ "$output" == *"a read beyond the second is refused without a signed override"* ]] || false
  [[ "$output" == *"regex-missed of v1 (read 2 times, 0 signed)"* ]] || false
  [[ "$output" == *"other of v4 (read 2 times, 0 signed)"* ]] || false
  [ "$(ledger_rows)" = 8 ]
  unspoil sealed.enc
  # an agent-written signature is void and buys nothing; one stratum signed still leaves three refused
  sig v1.regex-missed '["claude","zsh"]'
  sig v1.pushback
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" evaluate --consent-sealed-read --program demo
  [ "$status" -eq 2 ]
  [[ "$output" == *"regex-missed of v1 (read 2 times, 0 signed)"* ]] || false
  [[ "$output" != *"pushback of v1"* ]] || false
  # a signature counts only for the program it names
  sig v1.regex-missed
  sig v4.other
  sig v4.regex-matched
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" evaluate --consent-sealed-read
  [ "$status" -eq 2 ]
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" evaluate --consent-sealed-read --program demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"stratum pushback of set v1: read 3, beyond the second, a disclosed cost under operator signature 2026-10-08T00:00:00Z (fixture)"* ]] || false
  [ "$(ledger_rows)" = 12 ]
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" evaluate --consent-sealed-read --program demo
  [ "$status" -eq 2 ]
  [[ "$output" == *"pushback of v1 (read 3 times, 1 signed)"* ]] || false
}

@test "wave E1l: instrument --await unpins strata without opening a set, and evaluate refuses while one waits" {
  composite
  spoil sealed.enc
  spoil sealed-v4.enc
  run "$H" instrument --await regex-missed,pushback
  [ "$status" -eq 0 ]
  [[ "$output" == *"regex-missed (was v1), pushback (was v1) now await a fresh set"* ]] || false
  [ "$(jq -c .strata "$CC_RESEARCH_HOME/router-heldout/instrument.json")" = '{"other":"v4","pushback":null,"regex-matched":"v4","regex-missed":null}' ]
  router_says completeness
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" evaluate --consent-sealed-read
  [ "$status" -eq 2 ]
  [[ "$output" == *"stratum regex-missed, pushback: no set pinned, it awaits a fresh set"* ]] || false
  [ "$(ledger_rows)" = 0 ]
  run "$H" instrument --await regex-missed,bogus
  [ "$status" -eq 2 ]
}

@test "wave E1l: the read waits for RULE E1k's pass: no record, a failing run or an unexercised one refuses it; a pass is stated beside the load bound" {
  composite
  router_says completeness
  rm "$CC_RESEARCH_HOME/router-heldout/real-load.json"
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" evaluate --consent-sealed-read
  [ "$status" -eq 2 ]
  [[ "$output" == *"RULE E1k's real-load figures above load 150 are not on record"* ]] || false
  printf 'verdict\n' > "$BATS_TEST_TMPDIR/run.txt"
  run "$H" real-load --run 2 --source "$BATS_TEST_TMPDIR/run.txt" --rows 39 --fallbacks 0 --held 0
  [ "$status" -eq 2 ]
  [[ "$output" == *"high load not exercised"* ]] || false
  [ ! -e "$CC_RESEARCH_HOME/router-heldout/real-load.json" ]
  run "$H" real-load --run 2 --source "$BATS_TEST_TMPDIR/run.txt" --rows 100 --fallbacks 4 --held 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"RULE E1k run 2: FAIL (4/100"* ]] || false
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" evaluate --consent-sealed-read
  [ "$status" -eq 2 ]
  [[ "$output" == *"RULE E1k run 2 did not pass: hedge-on fallback 4/100"* ]] || false
  [ "$(ledger_rows)" = 0 ]
  run "$H" real-load --run 3 --source "$BATS_TEST_TMPDIR/run.txt" --rows 100 --fallbacks 3 --held 2
  [[ "$output" == *"RULE E1k run 3: PASS"* ]] || false
  CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" evaluate --consent-sealed-read --record "$BATS_TEST_TMPDIR/rec.jsonl"
  [ "$status" -eq 1 ]
  [[ "$output" == *"load bound (ruling 17aff7158fa6), a stated condition of row 15: every routed item started at 1-min load <= 40 (highest 5.0); real-load companion, RULE E1k run 3 above load 150: hedge-on fallback 3/100, rows held with one call silent 2 ($BATS_TEST_TMPDIR/run.txt)"* ]] || false
  [ "$(jq -s 'map(.load1) | unique == [5]' "$BATS_TEST_TMPDIR/rec.jsonl")" = true ]
}

@test "wave E1l: above load 40 through the start cap the read is refused before any decrypt and logs nothing; a load that falls in time is waited out" {
  composite
  router_says completeness
  spoil sealed.enc
  printf '90\n' > "$CC_RESEARCH_HOME/router-heldout/load1.fixture"
  CC_RESEARCH_ROW15_START_CAP_S=0 CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" run "$H" evaluate --consent-sealed-read
  [ "$status" -eq 2 ]
  [[ "$output" == *"1-min load stayed above 40 for the start cap (0 s; last 90.0): nothing decrypted, no read logged"* ]] || false
  [ "$(ledger_rows)" = 0 ]
  unspoil sealed.enc
  printf '90\n41\n40\n' > "$CC_RESEARCH_HOME/router-heldout/load1.fixture"
  CC_RESEARCH_ROW15_START_CAP_S=30 CC_RESEARCH_ROW15_POLL_S=0.01 CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" \
    run "$H" evaluate --consent-sealed-read --record "$BATS_TEST_TMPDIR/rec.jsonl"
  [ "$status" -eq 1 ]
  [[ "$output" == *"(highest 40.0)"* ]] || false
  [ "$(jq -s 'length' "$BATS_TEST_TMPDIR/rec.jsonl")" = 64 ]
  [ "$(jq -s 'map(.load1) | max == 40' "$BATS_TEST_TMPDIR/rec.jsonl")" = true ]
}

@test "wave E1l: load above 40 past the total cap mid-read ends it 'read spent, no verdict', and the ledger keeps the read" {
  composite
  router_says completeness
  printf '5\n5\n5\n90\n' > "$CC_RESEARCH_HOME/router-heldout/load1.fixture"
  CC_RESEARCH_ROW15_TOTAL_CAP_S=0 CC_RESEARCH_ROUTER="$BATS_TEST_TMPDIR/router" \
    run "$H" evaluate --consent-sealed-read --record "$BATS_TEST_TMPDIR/rec.jsonl"
  [ "$status" -eq 1 ]
  [[ "$output" == *"read spent, no verdict: 1-min load stayed above 40 past the read's total cap (0 s; last 90.0) after 2 routed item(s); the reads ledger holds this read"* ]] || false
  [[ "$output" != *"fell back"* && "$output" != *"stratum other:"* && "$output" != *"load bound ("* ]] || false
  [ "$(jq -s 'length' "$BATS_TEST_TMPDIR/rec.jsonl")" = 2 ]
  [ "$(ledger_rows)" = 4 ]
}
