#!/usr/bin/env bats
# suggest-filter — the guard on bin/cc-suggest-filter and bin/cc-1p-events.
#
# The load-bearing test is the DIFFERENTIAL CONTROL: the Python ladder is checked against the REAL
# `TM_` extracted from the installed Claude Code binary and executed in node, not against fixtures
# it agrees with by construction (memory: control-must-replay-the-real-artifact). That control has
# already earned its keep — it caught a `re.S` in `_META_WRAPPED` that made Python's `.` match a
# newline where JS's never does, mis-classifying a real prompt as `meta_wrapped`.
#
# Two things a control like this must have, and both are asserted here:
#   · it must be able to FAIL — proven with a mutant classifier, or "identical" means nothing;
#   · it must not SKIP silently — no node, or no ladder in the binary, is a loud skip, never a pass.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  F="$REPO/bin/cc-suggest-filter"
  E="$REPO/bin/cc-1p-events"
  ORACLE="$REPO/tests/suggest-ladder-oracle.mjs"
  PINNED="$REPO/tests/fixtures/suggest-ladder-2.1.220.js"
  CORPUS="$REPO/tests/fixtures/suggest-differential-corpus.jsonl"
  D="$BATS_TEST_TMPDIR"

  # Resolve the real binary BEFORE fixturing $HOME — cc-claude-bin's authoritative rung reads the
  # operator's ~/.zshrc, which a fixtured $HOME hides, and the fallback rung would then pick a
  # different binary than sessions actually run. Declaring it as an explicit seam keeps the one
  # genuinely-live read visible instead of ambient (memory: hermetic-home-routes-tests-into-fallback).
  if [ -z "${CC_CLAUDE_BIN:-}" ] && [ -x "$REPO/bin/cc-claude-bin" ]; then
    CC_CLAUDE_BIN="$("$REPO/bin/cc-claude-bin" 2>/dev/null || true)"
    [ -n "$CC_CLAUDE_BIN" ] && export CC_CLAUDE_BIN
  fi

  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
}

# ── the port ──────────────────────────────────────────────────────────────────────────────────

@test "self-test: every ladder rung has a fixture that reaches IT" {
  run "$F" self-test
  [ "$status" -eq 0 ]
  [[ "$output" == *"20/20"* ]]
}

@test "classify emits one reason per line and 'pass' for a survivor" {
  run bash -c "printf 'run the tests\nlet me run the tests\n' | '$F' classify"
  [ "$status" -eq 0 ]
  # grep, not [[ ]] — a non-final [[ ]] is errexit-exempt in a bats body, so its failure is
  # discarded and the test passes anyway (scripts/bats-assert-liveness.py).
  printf '%s\n' "${lines[0]}" | grep -q '^pass	run the tests$'
  printf '%s\n' "${lines[1]}" | grep -q '^claude_voice	'
}

@test "ladder order is load-bearing: too_many_words beats claude_voice" {
  # `claude_voice` is the LAST rung; a 13-word Claude-voice string must report the earlier rule or
  # the port has lost the short-circuit that makes the distribution a first-cause distribution.
  run bash -c "printf \"let me go ahead and run the whole test suite for you right now\n\" | '$F' classify"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "too_many_words"* ]]
}

# ── the differential control ──────────────────────────────────────────────────────────────────

@test "DIFFERENTIAL: the port agrees with the REAL ladder from the installed binary" {
  command -v node >/dev/null || skip "node absent — the control cannot run (NOT a pass)"
  run "$F" ladder-source
  [ "$status" -eq 0 ] || skip "no ladder in the installed binary — control cannot run (NOT a pass)"
  printf '%s\n' "$output" > "$D/ladder.js"

  # HARNESS SELF-CHECK: prove the extraction really is the ladder before believing either side.
  grep -q 'too_many_words' "$D/ladder.js"
  grep -q 'claude_voice' "$D/ladder.js"

  # A CRAFTED corpus, not the live transcripts: deterministic, hermetic, and deliberately loaded
  # with the shapes where JS and Python regex disagree — multi-line parens (`.` vs DOTALL), a
  # trailing newline (`$` vs `\Z`), a non-ASCII word char before a colon (`\w` ASCII vs Unicode),
  # dotted-I casing, and the word/char count boundaries. Both bugs this control has caught diverge
  # on it, which is what makes it a control rather than a corpus that happens to agree.
  [ -s "$CORPUS" ]
  node "$ORACLE" "$D/ladder.js" < "$CORPUS" > "$D/oracle.jsonl"
  "$F" classify --jsonl < "$CORPUS" > "$D/port.jsonl"

  run python3 -c "
import json,sys
o=[json.loads(l)['reason'] for l in open('$D/oracle.jsonl')]
p=[json.loads(l)['reason'] for l in open('$D/port.jsonl')]
assert len(o)==len(p) and o, 'length mismatch %d vs %d' % (len(o),len(p))
bad=[(a,b) for a,b in zip(o,p) if a!=b]
print('%d rows, %d divergences' % (len(o), len(bad)))
sys.exit(1 if bad else 0)
"
  [ "$status" -eq 0 ] || {
    echo "port disagrees with the real ladder: $output" >&2
    false
  }
}

@test "CONTROL CAN FAIL: a mutant ladder is caught by the same comparison" {
  command -v node >/dev/null || skip "node absent — the control cannot run (NOT a pass)"
  run "$F" ladder-source
  [ "$status" -eq 0 ] || skip "no ladder in the installed binary"
  # Mutate the word cap 12 -> 3. If the comparison above is real, this must diverge; if it passes,
  # the differential test proves nothing and every "IDENTICAL" it ever printed was vacuous.
  printf '%s\n' "$output" | sed 's/n>12/n>3/' > "$D/mutant.js"
  grep -q 'n>3' "$D/mutant.js"
  printf '{"text":"run the whole integration suite now"}\n' > "$D/one.jsonl"
  node "$ORACLE" "$D/mutant.js" < "$D/one.jsonl" > "$D/m.jsonl"
  run python3 -c "
import json
print(json.load(open('$D/m.jsonl')) if False else json.loads(open('$D/m.jsonl').read())['reason'])
"
  [ "$status" -eq 0 ]
  [ "$output" = "too_many_words" ]
  # and the unmutated port says the opposite for the same input
  run bash -c "printf 'run the whole integration suite now\n' | '$F' classify"
  [[ "${lines[0]}" == "pass"* ]]
}

@test "STALENESS: the installed ladder still matches the pinned copy" {
  run "$F" ladder-source
  [ "$status" -eq 0 ] || skip "no ladder in the installed binary"
  printf '%s\n' "$output" > "$D/live.js"
  # A byte diff, deliberately. The pinned copy is what the port was written against; if upstream
  # edits a rule the port silently becomes wrong, and nothing else in this suite would notice —
  # a control tuned to one implementation dies quietly when that implementation improves
  # (memory: control-calibrated-to-implementation-decays).
  run diff -q "$PINNED" "$D/live.js"
  [ "$status" -eq 0 ] || {
    echo "the installed ladder no longer matches tests/fixtures/suggest-ladder-2.1.220.js." >&2
    echo "Re-read TM_, update bin/cc-suggest-filter, then re-pin. Do NOT just re-pin." >&2
    false
  }
}

# ── extraction / no-data contracts ────────────────────────────────────────────────────────────

@test "ladder-source exits 3 (NO DATA) when the binary has no ladder, never 0" {
  printf 'not a claude binary' > "$D/fake"
  CC_CLAUDE_BIN="$D/fake" run "$F" ladder-source
  [ "$status" -eq 3 ]
}

@test "corpus rejects harness-injected user turns and keeps typed ones" {
  mkdir -p "$D/roots/proj"
  cat > "$D/roots/proj/s.jsonl" <<'EOF'
{"type":"user","userType":"external","isSidechain":false,"sessionId":"s","message":{"role":"user","content":"run the tests"}}
{"type":"user","userType":"external","isSidechain":false,"sessionId":"s","message":{"role":"user","content":"<teammate-message teammate_id=\"lead\">do the thing</teammate-message>"}}
{"type":"user","userType":"external","isSidechain":false,"sessionId":"s","message":{"role":"user","content":"[Image: original 100x100, displayed at 50x50]"}}
{"type":"user","userType":"external","isSidechain":false,"sessionId":"s","message":{"role":"user","content":"Another Claude session sent a message:\nhello"}}
{"type":"user","userType":"external","isSidechain":true,"sessionId":"s","message":{"role":"user","content":"sidechain prompt"}}
{"type":"user","userType":"external","isSidechain":false,"sessionId":"s","message":{"role":"user","content":[{"type":"tool_result","content":"x"}]}}
{"type":"assistant","message":{"role":"assistant","content":"hi"}}
EOF
  CC_SUGGEST_ROOTS="$D/roots" run "$F" corpus
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" == *"run the tests"* ]]
}

@test "corpus --dedupe collapses exact repeats (the automation sensitivity check)" {
  mkdir -p "$D/roots2/proj"
  for _ in 1 2 3; do
    printf '%s\n' '{"type":"user","userType":"external","isSidechain":false,"sessionId":"s","message":{"role":"user","content":"(Checking in)"}}'
  done > "$D/roots2/proj/s.jsonl"
  CC_SUGGEST_ROOTS="$D/roots2" run "$F" corpus
  [ "${#lines[@]}" -eq 3 ]
  CC_SUGGEST_ROOTS="$D/roots2" run "$F" corpus --dedupe
  [ "${#lines[@]}" -eq 1 ]
}

@test "kill switch: CC_SUGGEST_FILTER=off exits 0 and prints nothing" {
  CC_SUGGEST_FILTER=off run "$F" self-test
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── cc-1p-events ──────────────────────────────────────────────────────────────────────────────

@test "1p-events decodes reason out of base64 additional_metadata" {
  # A real record shape, with the metadata bag encoded exactly as the exporter encodes it.
  python3 - "$D/spool.json" <<'EOF'
import base64, json, sys
meta = {"source":"cli","outcome":"suppressed","reason":"too_many_words","prompt_id":"user_intent"}
rec = {"event_type":"ClaudeCodeInternalEvent","event_data":{
    "event_name":"tengu_prompt_suggestion","client_timestamp":"2026-08-05T00:00:00Z",
    "session_id":"abc","env":{"version":"2.1.220"},
    "additional_metadata": base64.b64encode(json.dumps(meta).encode()).decode()}}
open(sys.argv[1],"w").write(json.dumps(rec)+"\n")
EOF
  run "$E" suggest --glob "$D/spool.json"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "too_many_words"
  printf '%s\n' "$output" | grep -qF "n = 1 events"
  # The provenance clause must NOT claim "failed exports" for a non-spool store.
  ! printf '%s\n' "$output" | grep -qF "failed exports"
}

@test "1p-events exits 3 (NO DATA) on an empty store, never 0" {
  : > "$D/empty.json"
  run "$E" suggest --glob "$D/empty.json"
  [ "$status" -eq 3 ]
}

@test "1p-events activation PRINTS without touching config unless --apply" {
  # A fixtured ~/.claude.json, so this can never touch the operator's real one even if the
  # no-write contract regresses — the assertion below would otherwise be checked by mutating it.
  printf '%s\n' '{"cachedGrowthBookFeatures":{"tengu_other":{}}}' > "$HOME/.claude.json"
  cp "$HOME/.claude.json" "$D/before.json"
  run "$E" activation --port 9999
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "127.0.0.1:9999"
  printf '%s\n' "$output" | grep -qiF "self-expiring"
  run diff -q "$D/before.json" "$HOME/.claude.json"
  [ "$status" -eq 0 ]
}

@test "1p-events activation --apply then --revert round-trips the live config" {
  # The write path, exercised against a fixtured config. Untested it would ship unverified, and it
  # is the one thing here that edits a file every session reads.
  printf '%s\n' '{"other":1,"cachedGrowthBookFeatures":{"tengu_other":{}}}' > "$HOME/.claude.json"
  run "$E" activation --apply --port 9999
  [ "$status" -eq 0 ]
  python3 -c "
import json; d=json.load(open('$HOME/.claude.json'))
c=d['cachedGrowthBookFeatures']['tengu_1p_event_batch_config']
assert c['baseUrl']=='http://127.0.0.1:9999', c
assert c['skipAuth'] is True, c
assert d['other']==1, 'unrelated keys must survive'
assert d['cachedGrowthBookFeatures']['tengu_other']=={}, 'sibling features must survive'
"
  # the backup must hold the ORIGINAL bytes, not the edited doc
  python3 -c "
import json; b=json.load(open('$HOME/.claude.json.bak'))
assert 'tengu_1p_event_batch_config' not in b['cachedGrowthBookFeatures'], b
"
  run "$E" activation --revert
  [ "$status" -eq 0 ]
  python3 -c "
import json; d=json.load(open('$HOME/.claude.json'))
assert 'tengu_1p_event_batch_config' not in d['cachedGrowthBookFeatures'], d
assert d['other']==1
"
}
