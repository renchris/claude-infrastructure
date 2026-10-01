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
