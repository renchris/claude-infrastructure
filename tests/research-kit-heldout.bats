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
  [ "$(jq -r 'keys | join(",")' "$BATS_TEST_TMPDIR/rec.jsonl" | sort -u)" = "counted,got,id,stratum,wall_s" ]
  run grep -c "secret prompt" "$BATS_TEST_TMPDIR/rec.jsonl"
  [ "$output" = 0 ]
}
