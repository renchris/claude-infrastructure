#!/usr/bin/env bats
# research-relay-check — the Stop check of REPORT.md §4.4 (§8 item 6, wave B1): in a turn routed as a
# completeness question or pushback, inside a certifying or certified program, a reply may add
# nothing the relayed certificate does not carry, whether it opens "yes" or "no". The must-block
# fixtures are the census's own "yes, plus one more item" replies
# (docs/research/upfront-research-exhaustion-2026-09-30/evidence/adversary/llm/ask_turns.out, the
# YES+item lines, as printed there: the first 140 characters), kept where hand review agreed each
# one adds an item: 4 of the 9 unique lines. The other 5 say "nothing of mine is open" and are the
# census regex's false positives (§10 open item 15).

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  unset CC_RESEARCH_BLOCK CC_RESEARCH_ROUTER CC_RESEARCH_ROUTER_INNER CC_RESEARCH_RELAY_CHECK
  export CC_RESEARCH_HOME="$BATS_TEST_TMPDIR/rh" CC_RESEARCH_REGISTRY="$BATS_TEST_TMPDIR/rh/programs.json"
  export CC_NOW="2026-10-01T12:00:00Z" CC_RESEARCH_VAULT_KEY="test-key"
  export CC_RESEARCH_CLASSIFIER="$REPO/tests/fixtures/research-router/classifier-stub.sh"
  export CC_RESEARCH_CLASSIFIER_TIMEOUT=2
  CERT1="Research: demo version 3. CERTIFIED Oct 16 (standard profile; stopped after 3 quiet rounds)"
  CERT2="Signed frame: 100.00% closed. 14/14 decisions · 12/12 populations enumerated two ways"
  CERT3="Decisions: 13 ruled at 90%+ · 1 decided by default at 84% (sync retry; reversible)"
  export CC_RESEARCH_RENDER="printf '%s\n%s\n%s\n' '$CERT1' '$CERT2' '$CERT3'"
  ROUTER="$REPO/scripts/research-kit/router.py"
  PROG="$BATS_TEST_TMPDIR/repo"; mkdir -p "$PROG"
  "$REPO/scripts/research-kit/gate.sh" register --program demo --root "$PROG" >/dev/null
  python3 - "$CC_RESEARCH_REGISTRY" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1])); d["programs"][0]["state"] = "certified"; json.dump(d, open(sys.argv[1], "w"))
EOF
}

route() {
  jq -nc --arg p "$1" --arg c "$PROG" '{session_id:"s1",cwd:$c,prompt:$p}' \
    | bash "$REPO/hooks/research-precognition-nudge.sh" >/dev/null
}
check() { printf '%s' "$1" | python3 "$ROUTER" relay-check --session s1; }

@test "the verbatim certificate plus up to 3 explaining lines passes" {
  route "are we done?"
  run check "$(printf '%s\n%s\n%s\n\nThe frame is fully closed.\nOne decision was taken by default and is reversible.' "$CERT1" "$CERT2" "$CERT3")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "must-block (census 7c30d524): a yes that names a file and a flag the certificate does not carry" {
  route "are we done?"
  run check '✅ Done and pushed to origin/main: cli.sh now has a default limit, a `--limit N` flag, and rejects a bad limit. The last piece, the bad-limit'
  [ "$status" -eq 1 ]
  [[ "$output" == *"cli.sh"* ]]
}

@test "must-block (census 58a82f15): a yes that names a work item that was still open" {
  route "good to close?"
  run check '✅ Complete and landed on trunk: cli.sh hardening is finished, including W3 (`--limit` validation), which was still open when you asked, so I'
  [ "$status" -eq 1 ]
  [[ "$output" == *"still open"* ]]
}

@test "must-block (census 42e8e755): a yes that names a wave and a commit" {
  route "are we done?"
  run check '✅ Clean and landed. The cli.sh hardening plan is finished: W3 (`--limit` validation) is now on trunk as `aade3f5`. Good to close: yes. Nothi'
  [ "$status" -eq 1 ]
  [[ "$output" == *"aade3f5"* ]]
}

@test "must-block (census 0f577aec): a reply that names a commit beyond the certificate" {
  route "are we done?"
  run check '✅ Clean and landed. The `--limit` flag work (`cea1e45`) is on `origin/main`, and the working tree matches it exactly. Good to close: no. A h'
  [ "$status" -eq 1 ]
  [[ "$output" == *"cea1e45"* ]]
}

@test "must-block: 'yes, plus one more thing' with no location still adds an item" {
  route "are we done?"
  run check "$(printf '%s\n%s\nYes. One more thing worth flagging: the retry path.' "$CERT1" "$CERT2")"
  [ "$status" -eq 1 ]
}

@test "must-block: a 'no' that cites none of the three events" {
  route "are you sure?"
  run check "$(printf 'No — not yet.\n%s\n%s' "$CERT1" "$CERT2")"
  [ "$status" -eq 1 ]
  [[ "$output" == *"opens 'no'"* ]]
}

@test "a 'no' citing a triaged escape is not blocked for opening no" {
  route "are you sure?"
  run check "$(printf 'No: a triaged escape reopened one row.\n%s\n%s\n%s' "$CERT1" "$CERT2" "$CERT3")"
  [ "$status" -eq 0 ]
}

@test "must-block: more than 3 lines beyond the certificate" {
  route "are we done?"
  run check "$(printf '%s\nline a\nline b\nline c\nline d' "$CERT1")"
  [ "$status" -eq 1 ]
  [[ "$output" == *"4 lines beyond"* ]]
}

@test "a pushback turn may carry the one fixed line" {
  route "are you sure?"
  run check "$(printf '%s\n%s\n%s\nA concern needs a place, a file and line or a decision or check number, and it will be checked in the next scheduled review.' "$CERT1" "$CERT2" "$CERT3")"
  [ "$status" -eq 0 ]
}

@test "outside a completeness or pushback turn the check abstains" {
  route "build the importer"
  run check '✅ Done: cli.sh has a `--limit` flag; one more thing is still open.'
  [ "$status" -eq 0 ]
}

@test "an UNAVAILABLE turn whose reply opens with a verdict and adds an item is blocked" {
  route "STUB-ERROR are we done?"
  [ "$(python3 "$ROUTER" status --session s1 | jq -r .label)" = unavailable ]
  run check "$(printf 'Yes — and one more thing: the retry path in sync.py.\n%s\n%s' "$CERT1" "$CERT2")"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unavailable"* ]] || false
  [[ "$output" == *"sync.py"* ]]
  run check "No - not yet."
  [ "$status" -eq 1 ]
  [[ "$output" == *"opens 'no'"* ]]
}

@test "an UNAVAILABLE turn whose reply does not open with a verdict is ordinary work, not checked" {
  route "STUB-ERROR fix the importer"
  run check 'Edited cli.sh to add a --limit flag; one more thing is still open.'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a program no longer certifying or certified is not checked" {
  route "are we done?"
  python3 - "$CC_RESEARCH_REGISTRY" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1])); d["programs"][0]["state"] = "registered"; json.dump(d, open(sys.argv[1], "w"))
EOF
  run check '✅ Done: cli.sh has a `--limit` flag.'
  [ "$status" -eq 0 ]
}

# ── through hooks/completion-assert.sh: the arm latches, caps and blocks with its own class ─────

ca_setup() {
  export COMPLETION_STATE_DIR="$BATS_TEST_TMPDIR/state" COMPLETION_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export WRAP_LEDGER_BIN="$BATS_TEST_TMPDIR/no-ledger"
  TP="$BATS_TEST_TMPDIR/t.jsonl"
}
stop_with() {
  jq -nc --arg t "$1" '{type:"assistant",message:{content:[{type:"text",text:$t}]}}' > "$TP"
  jq -nc --arg tp "$TP" --arg c "$PROG" '{session_id:"s1",transcript_path:$tp,cwd:$c}' \
    | bash "$REPO/hooks/completion-assert.sh"
}

@test "completion-assert: a relay violation blocks once with class relay, and the same message never re-fires" {
  ca_setup
  route "are we done?"
  run stop_with '✅ Done: cli.sh has a `--limit` flag.'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.decision == "block" and (.reason | test("Research relay check")) and (.reason | test("relay 1/2"))' >/dev/null
  run stop_with '✅ Done: cli.sh has a `--limit` flag.'
  [ "$(printf '%s' "$output" | grep -c 'Research relay check')" -eq 0 ]
  grep -q '"research-relay"' "$COMPLETION_IDL"
}

@test "completion-assert: the relay arm is capped at COMPLETION_RELAY_MAX" {
  ca_setup
  export COMPLETION_RELAY_MAX=1
  route "are we done?"
  stop_with '✅ Done: a.sh changed.' >/dev/null
  run stop_with '✅ Done: b.sh changed.'
  [ "$(printf '%s' "$output" | grep -c 'Research relay check')" -eq 0 ]
  grep -q 'capped:relay:1>=1' "$COMPLETION_IDL"
}

@test "completion-assert: CC_RESEARCH_RELAY_CHECK=0 turns the arm off" {
  ca_setup
  route "are we done?"
  CC_RESEARCH_RELAY_CHECK=0 run stop_with '✅ Done: cli.sh has a `--limit` flag.'
  [ "$(printf '%s' "$output" | grep -c 'Research relay check')" -eq 0 ]
}
