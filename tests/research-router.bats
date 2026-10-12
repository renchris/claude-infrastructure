#!/usr/bin/env bats
# research-router — the re-ask router and the research block, wave B1 of
# docs/plans/RESEARCH_PROGRAM_BUILD.md (REPORT.md §4.1, §4.2, §8 items 5 and 6). Every REPORT.md §10
# open item B1 owns gets a planted input here that fails without the change: item 1 (the deny half),
# 2, 3 and 8; items 11-13 are pinned in research-router-heldout.bats. The hooks are driven through
# their real wrappers with a stub classifier (tests/fixtures/research-router/classifier-stub.sh) and a
# stub certificate render, so nothing reaches a vendor.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_FIRE_CAPACITY_GATE=off CC_ADMIT_GATE=off   # this file names handoff-fire; it never runs it
  # …and the lint's rule 5 reads that name as a reach into handoff-fire's non-$HOME seams, so they
  # are pinned absent too (nothing here executes it).
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/no-sweep-stamp" \
    CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-claude-accounts" CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  unset CC_RESEARCH_BLOCK CC_RESEARCH_ROUTER CC_RESEARCH_ROUTER_INNER CC_RESEARCH_RECORDS
  export CC_RESEARCH_HOME="$BATS_TEST_TMPDIR/rh" CC_RESEARCH_REGISTRY="$BATS_TEST_TMPDIR/rh/programs.json"
  export CC_NOW="2026-10-01T12:00:00Z" CC_RESEARCH_VAULT_KEY="test-key"
  export CC_RESEARCH_CLASSIFIER="$REPO/tests/fixtures/research-router/classifier-stub.sh"
  export CC_RESEARCH_CLASSIFIER_TIMEOUT=2
  export STUB_LOG="$BATS_TEST_TMPDIR/stub.log"
  export CC_RESEARCH_RENDER='printf "Research: demo — CERTIFIED Oct 16\nSigned frame: 100.00%% closed. 14/14 decisions\n"'
  NUDGE="$REPO/hooks/research-precognition-nudge.sh"
  BLOCK="$REPO/hooks/research-block.sh"
  ROUTER="$REPO/scripts/research-kit/router.py"
  G="$REPO/scripts/research-kit/gate.sh"
  PROG="$BATS_TEST_TMPDIR/repo"; mkdir -p "$PROG/src" "$BATS_TEST_TMPDIR/elsewhere"
  "$G" register --program demo --root "$PROG" --alias "the demo" >/dev/null
}

# Set the program's registry state. gate.sh is the registry's only writer and reaches `certified`
# only through a full gate run, so the fixture writes the state directly — the router only reads it.
state() {
  python3 - "$CC_RESEARCH_REGISTRY" "$1" <<'EOF'
import json, sys
p, s = sys.argv[1], sys.argv[2]
d = json.load(open(p))
d["programs"][0]["state"] = s
json.dump(d, open(p, "w"))
EOF
}

# prompt <text> [cwd] [sid] — one UserPromptSubmit through the real hook.
prompt() {
  jq -nc --arg p "$1" --arg c "${2:-$PROG/src}" --arg s "${3:-s1}" '{session_id:$s,cwd:$c,prompt:$p}' \
    | bash "$NUDGE"
}

# tool <name> <command-or-prompt> [cwd] [sid] — one PreToolUse; prints deny or allow.
tool() {
  local ti
  if [ "$1" = Bash ]; then ti="$(jq -nc --arg c "$2" '{command:$c}')"
  else ti="$(jq -nc --arg p "$2" '{prompt:$p,description:$p}')"; fi
  jq -nc --arg t "$1" --argjson i "$ti" --arg c "${3:-$PROG/src}" --arg s "${4:-s1}" \
    '{session_id:$s,cwd:$c,tool_name:$t,tool_input:$i}' \
    | bash "$BLOCK" | jq -r '.hookSpecificOutput.permissionDecision // empty' | grep -q deny \
    && echo deny || echo allow
}

label() { python3 "$ROUTER" status --session "${1:-s1}" | jq -r '.label // "none"'; }

@test "§10 item 1: a completeness prompt in a CERTIFYING program denies Agent, Workflow, handoff-fire.sh and the vendor CLIs" {
  state certifying
  prompt "are we done?" >/dev/null
  [ "$(label)" = completeness ]
  [ "$(tool Agent 'audit it again')" = deny ]
  [ "$(tool Workflow 'x')" = deny ]
  [ "$(tool Bash 'bash scripts/handoff-fire.sh --brief b.md')" = deny ]
  [ "$(tool Bash 'codex exec "review"')" = deny ]
  [ "$(tool Bash 'gemini -p hi')" = deny ]
  [ "$(tool Bash '/opt/agy/bin/agy --print hi --mode plan')" = deny ]
  [ "$(tool Bash 'antigravity --print hi')" = deny ]
  [ "$(tool Bash 'claude -p "look again"')" = deny ]
  # …and every other tool too, except the one certificate read.
  [ "$(tool Read 'x')" = deny ]
  [ "$(tool Bash 'ls')" = deny ]
  [ "$(tool Bash 'scripts/research-kit/gate.sh --render --program demo')" = allow ]
  [ "$(tool Bash 'scripts/research-kit/gate.sh --render --program demo; codex x')" = deny ]
}

@test "§10 item 1: the same holds once the program is certified, and the routed turn relays the certificate" {
  state certified
  run prompt "is this 100.00/100.00?"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | test("Signed frame: 100.00% closed")' >/dev/null
  printf '%s' "$output" | jq -e '.hookSpecificOutput.hookEventName == "UserPromptSubmit"' >/dev/null
  [ "$(tool Agent 'x')" = deny ]
}

@test "a REGISTERED program (not yet frozen) is neither routed nor blocked" {
  prompt "are we done?" >/dev/null
  [ "$(label)" = none ]
  [ ! -s "$STUB_LOG" ]
  [ "$(tool Agent 'x')" = allow ]
}

@test "a closed program is neither routed nor blocked" {
  state closed
  prompt "are we done?" >/dev/null
  [ "$(label)" = none ]
  [ "$(tool Agent 'x')" = allow ]
}

@test "§10 item 2: no single-active fallback — another pane's close question is not routed to the one active program" {
  state certified
  run prompt "are we done? good to close?" "$BATS_TEST_TMPDIR/elsewhere" s2
  [ "$status" -eq 0 ]
  [ "$(label s2)" = none ]
  [ ! -s "$STUB_LOG" ]
  [ "$(tool Agent 'x' "$BATS_TEST_TMPDIR/elsewhere" s2)" = allow ]
  # The ordinary research nudge still runs in that pane, untouched.
  run prompt "research the options for caching" "$BATS_TEST_TMPDIR/elsewhere" s2
  printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | test("PRE-COGNITION")' >/dev/null
}

@test "a program named by its alias routes a prompt from any pane, and only that prompt" {
  state certified
  prompt "is The Demo good to close?" "$BATS_TEST_TMPDIR/elsewhere" s3 >/dev/null
  [ "$(label s3)" = completeness ]
  [ "$(tool Agent 'x' "$BATS_TEST_TMPDIR/elsewhere" s3)" = deny ]
  # The next prompt in that pane names no program: the pane is ordinary again.
  prompt "build the parser" "$BATS_TEST_TMPDIR/elsewhere" s3 >/dev/null
  [ "$(label s3)" = none ]
  [ "$(tool Agent 'x' "$BATS_TEST_TMPDIR/elsewhere" s3)" = allow ]
}

@test "an alias is matched as a whole word, never inside another word" {
  state certified
  prompt "is the demonstration good to close?" "$BATS_TEST_TMPDIR/elsewhere" s4 >/dev/null
  [ "$(label s4)" = none ]
}

@test "§10 item 3: a classifier ERROR is 'unavailable', not completeness — only the research verbs are denied" {
  state certified
  prompt "STUB-ERROR are we done" >/dev/null
  [ "$(label)" = unavailable ]
  [ "$(tool Agent 'x')" = deny ]
  [ "$(tool Bash 'codex exec x')" = deny ]
  [ "$(tool Bash 'ls -la')" = allow ]
  [ "$(tool Read 'x')" = allow ]
}

@test "§10 item 3: a classifier TIMEOUT, a MIXED label and an unknown label are each 'unavailable'" {
  state certified
  prompt "STUB-SLEEP" >/dev/null
  [ "$(label)" = unavailable ]
  prompt "STUB-MIXED" >/dev/null
  [ "$(label)" = unavailable ]
  prompt "STUB-JUNK" >/dev/null
  [ "$(label)" = unavailable ]
}

@test "§10 item 3: the next genuine prompt is classified afresh, and N fallbacks in a row tell the operator" {
  state certified
  prompt "STUB-ERROR 1" >/dev/null
  run prompt "STUB-ERROR 2"
  printf '%s' "$output" | jq -e 'has("systemMessage") | not' >/dev/null
  run prompt "STUB-ERROR 3"
  printf '%s' "$output" | jq -e '.systemMessage | test("classifier unavailable for 3 prompts")' >/dev/null
  prompt "build the next wave" >/dev/null
  [ "$(label)" = work-order ]
  [ "$(python3 "$ROUTER" status --session s1 | jq -r .fallbacks)" = 0 ]
  [ "$(tool Agent 'x')" = allow ]
}

@test "§10 item 3: a hook killed mid-classification leaves 'unavailable' recorded, never the previous label" {
  state certified
  prompt "build it" >/dev/null
  [ "$(label)" = work-order ]
  # The stub reads the route record while it is being classified: the pre-write is already there.
  export CC_RESEARCH_CLASSIFIER="python3 '$ROUTER' status --session s1 | jq -r .label >> '$STUB_LOG'; echo other"
  : > "$STUB_LOG"
  prompt "anything" >/dev/null
  # (two lines since wave E1g: the fast call and the careful call each run the stub)
  [ "$(sort -u "$STUB_LOG")" = unavailable ]
}

@test "§10 item 3: a machine-authored record keeps the last genuine label (a continuation inherits nothing new)" {
  state certified
  prompt "build it" >/dev/null
  [ "$(label)" = work-order ]
  : > "$STUB_LOG"
  prompt "<task-notification>are we done?</task-notification>" >/dev/null
  [ "$(label)" = work-order ]
  [ ! -s "$STUB_LOG" ]
}

@test "§10 item 3: the --requires-gate work-order marker is labeled without calling the classifier" {
  state certified
  prompt "fire wave 2 --requires-gate demo" >/dev/null
  [ "$(label)" = work-order ]
  [ ! -s "$STUB_LOG" ]
  [ "$(tool Agent 'x')" = allow ]
}

@test "a machine-envelope FIRST prompt (a fired or recycled successor) gets a deterministic non-completeness label" {
  state certifying
  : > "$STUB_LOG"
  prompt "Continue the program. HANDOFF-ENGAGE-1-2-3" "$PROG/src" succ-1 >/dev/null
  [ "$(label succ-1)" = other ]
  [ "$(python3 "$ROUTER" status --session succ-1 | jq -r .by)" = envelope ]
  [ "$(tool Read 'x' "$PROG/src" succ-1)" = allow ]
  [ "$(tool Edit 'x' "$PROG/src" succ-1)" = allow ]
  [ "$(tool Agent 'x' "$PROG/src" succ-1)" = deny ]
  [ ! -s "$STUB_LOG" ]
}

# RED-proof for the prose half: on c328f62f8 (any `--requires-gate demo` in an envelope counted)
# succ-2p read work-order, so a brief's author could grant the worker allow-all by writing the flag.
@test "a machine-envelope first prompt is a work order only on handoff-fire's admitted marker line" {
  state certifying
  : > "$STUB_LOG"
  prompt "$(printf 'Build wave 2.\n<!-- research work order: --requires-gate demo wave B2 (handoff-fire) -->\nHANDOFF-ENGAGE-1-2-3')" "$PROG/src" succ-2 >/dev/null
  [ "$(label succ-2)" = work-order ]
  [ "$(python3 "$ROUTER" status --session succ-2 | jq -r .by)" = envelope ]
  [ "$(tool Agent 'x' "$PROG/src" succ-2)" = allow ]
  prompt "Build wave 2: handoff-fire.sh --requires-gate demo --gate-wave B2. HANDOFF-ENGAGE-1-2-4" "$PROG/src" succ-2p >/dev/null
  [ "$(label succ-2p)" = other ]
  [ "$(tool Agent 'x' "$PROG/src" succ-2p)" = deny ]
  [ ! -s "$STUB_LOG" ]
}

# A recycle brief carries no HANDOFF-ENGAGE- (handoff-fire.sh sets ENGAGE_VERIFY only when RECYCLE=0).
# RED-proof for the fresh-fire half: on 5eb67c2a7 (any envelope inherited a named session's label)
# succ-4 and succ-5 read work-order, so a fired brief quoting a routed uuid laundered allow-all.
@test "only a recycle brief inherits a named predecessor's label; a fresh fire quoting a session inherits nothing" {
  state certifying
  prompt "build it" "$PROG/src" pred-1 >/dev/null
  [ "$(label pred-1)" = work-order ]
  : > "$STUB_LOG"
  prompt "[handoff recycle] predecessor session pred-1." "$PROG/src" succ-3 >/dev/null
  [ "$(label succ-3)" = work-order ]
  prompt "Run the next wave; predecessor session pred-1. HANDOFF-ENGAGE-4-5-6" "$PROG/src" succ-4 >/dev/null
  [ "$(label succ-4)" = other ]
  [ "$(tool Agent 'x' "$PROG/src" succ-4)" = deny ]
  prompt "[handoff 2] predecessor session pred-1. HANDOFF-ENGAGE-4-5-7" "$PROG/src" succ-5 >/dev/null
  [ "$(label succ-5)" = other ]
  [ ! -s "$STUB_LOG" ]
}

@test "a machine-envelope prompt AFTER a relay turn is 'other' by envelope: the relay label is not carried" {
  state certifying
  prompt "are you sure?" "$PROG/src" s5 >/dev/null
  [ "$(label s5)" = pushback ]
  sha="$(python3 "$ROUTER" status --session s5 | jq -r .prompt_sha)"
  : > "$STUB_LOG"
  # The envelope carries --requires-gate: after a relay turn it is still `other`, never a work order.
  run prompt "Continue. --requires-gate demo HANDOFF-ENGAGE-7-8-9" "$PROG/src" s5
  printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | test("routed as other")' >/dev/null
  [ "$(label s5)" = other ]
  [ "$(python3 "$ROUTER" status --session s5 | jq -r .by)" = envelope ]
  [ "$(python3 "$ROUTER" status --session s5 | jq -r .prompt_sha)" = "$sha" ]
  [ "$(tool Read 'x' "$PROG/src" s5)" = allow ]
  [ "$(tool Agent 'x' "$PROG/src" s5)" = deny ]
  [ ! -s "$STUB_LOG" ]
}

@test "every relay turn tells the operator how the prompt was routed and the one word that undoes it" {
  state certified
  run prompt "are we done?"
  printf '%s' "$output" | jq -e '.systemMessage
    | test("routed as completeness") and test("reply with the one word: misrouted")' >/dev/null
  run prompt "are you sure?"
  printf '%s' "$output" | jq -e '.systemMessage | test("routed as pushback")' >/dev/null
  run prompt "hello there"
  [ "$(label)" = other ]
  printf '%s' "$output" | jq -e 'has("systemMessage") | not' >/dev/null
}

@test "a typed --requires-gate naming another program is classified, not a work order by the marker" {
  state certified
  : > "$STUB_LOG"
  prompt "are we done? --requires-gate otherslug" >/dev/null
  [ -s "$STUB_LOG" ]
  [ "$(label)" = completeness ]
  [ "$(tool Agent 'x')" = deny ]
  run bash -c "printf 'are we done? --requires-gate otherslug' | python3 '$ROUTER' classify --program demo"
  [ "$output" = completeness ]
  run bash -c "printf 'are we done? --requires-gate demo' | python3 '$ROUTER' classify --program demo"
  [ "$output" = work-order ]
}

@test "the one word 'misrouted' after a relay turn reroutes it as other, without the classifier, and is counted" {
  state certified
  prompt "are we done?" >/dev/null
  [ "$(label)" = completeness ]
  sha="$(python3 "$ROUTER" status --session s1 | jq -r .prompt_sha)"
  : > "$STUB_LOG"
  run prompt " Misrouted! "
  printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | test("PREVIOUS prompt")' >/dev/null
  [ ! -s "$STUB_LOG" ]
  [ "$(label)" = other ]
  rec="$(python3 "$ROUTER" status --session s1)"
  [ "$(jq -r .by <<<"$rec")" = override ]
  [ "$(jq -r .overrode <<<"$rec")" = completeness ]
  [ "$(jq -r .prompt_sha <<<"$rec")" = "$sha" ]
  [ "$(jq -r .fallbacks <<<"$rec")" = 0 ]
  [ "$(tool Read 'x')" = allow ]
  [ "$(tool Agent 'x')" = deny ]
  [ "$(tool Bash 'codex exec x')" = deny ]
  [ "$(jq -r '.programs.demo.overrides' "$CC_RESEARCH_HOME/route-counters.json")" = 1 ]
  [ "$(jq -r '.programs.demo.last_override_at | type' "$CC_RESEARCH_HOME/route-counters.json")" = string ]
}

@test "'misrouted' is one-shot: a second one in a row is an ordinary, classified prompt" {
  state certified
  prompt "are we done?" >/dev/null
  prompt "misrouted" >/dev/null
  [ "$(python3 "$ROUTER" status --session s1 | jq -r .by)" = override ]
  : > "$STUB_LOG"
  prompt "misrouted" >/dev/null
  [ -s "$STUB_LOG" ]
  [ "$(label)" = other ]
  [ "$(python3 "$ROUTER" status --session s1 | jq -r .by)" = cwd ]
  [ "$(jq -r '.programs.demo.overrides' "$CC_RESEARCH_HOME/route-counters.json")" = 1 ]
}

@test "'misrouted' as a first prompt, or after a work-order turn, is classified and overrides nothing" {
  state certified
  : > "$STUB_LOG"
  prompt "misrouted" "$PROG/src" s8 >/dev/null
  [ -s "$STUB_LOG" ]
  [ "$(python3 "$ROUTER" status --session s8 | jq -r .by)" = cwd ]
  prompt "build it" >/dev/null
  [ "$(label)" = work-order ]
  : > "$STUB_LOG"
  prompt "misrouted." >/dev/null
  [ -s "$STUB_LOG" ]
  [ "$(label)" = other ]
  [ "$(python3 "$ROUTER" status --session s1 | jq -r .by)" = cwd ]
  [ ! -e "$CC_RESEARCH_HOME/route-counters.json" ]
}

@test "the override counter survives a garbled counter file" {
  state certified
  mkdir -p "$CC_RESEARCH_HOME"; printf 'not json' > "$CC_RESEARCH_HOME/route-counters.json"
  prompt "are we done?" >/dev/null
  prompt "misrouted" >/dev/null
  [ "$(label)" = other ]
  [ "$(jq -r '.programs.demo.overrides' "$CC_RESEARCH_HOME/route-counters.json")" = 1 ]
}

@test "relay-check on an override turn: a reply opening with a verdict that adds an item is blocked, ordinary work passes" {
  state certified
  prompt "are we done?" >/dev/null
  prompt "misrouted" >/dev/null
  run bash -c "printf 'Yes. One more thing: the retry path in sync.py.\nResearch: demo — CERTIFIED Oct 16\n' \
    | python3 '$ROUTER' relay-check --session s1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"override"* ]] || false
  [[ "$output" == *"sync.py"* ]] || false
  run bash -c "printf 'Edited sync.py to add a retry; one more thing is still open.' \
    | python3 '$ROUTER' relay-check --session s1"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "§10 item 3: the operator kill switches turn the block and the routing off" {
  state certified
  prompt "are we done?" >/dev/null
  [ "$(tool Agent 'x')" = deny ]
  CC_RESEARCH_BLOCK=0 run tool Agent 'x'
  [ "$output" = allow ]
  : > "$STUB_LOG"
  CC_RESEARCH_ROUTER=off prompt "are we done again?" "$PROG/src" s9 >/dev/null
  [ "$(label s9)" = none ]
  [ ! -s "$STUB_LOG" ]
}

@test "a session with no routed prompt in a certified program counts as completeness (§4.2)" {
  state certified
  [ "$(tool Agent 'x' "$PROG" fresh)" = deny ]
  [ "$(tool Bash 'ls' "$PROG" fresh)" = deny ]
  [ "$(tool Bash "$REPO/scripts/research-kit/gate.sh --render --program demo" "$PROG" fresh)" = allow ]
}

@test "work orders and new ideas allow research; concern, other and pushback do not" {
  state certified
  prompt "build the importer" >/dev/null;   [ "$(tool Agent 'x')" = allow ]
  prompt "what about a competitor" >/dev/null; [ "$(label)" = new-idea ]; [ "$(tool Workflow 'x')" = allow ]
  prompt "line 212 assumes the token lasts 30 days" >/dev/null; [ "$(label)" = concern ]
  [ "$(tool Agent 'x')" = deny ]; [ "$(tool Bash 'ls')" = allow ]
  prompt "hello there" >/dev/null; [ "$(label)" = other ]
  [ "$(tool Bash 'handoff-fire.sh --x')" = deny ]; [ "$(tool Edit 'x')" = allow ]
  prompt "are you sure?" >/dev/null; [ "$(label)" = pushback ]
  [ "$(tool Edit 'x')" = deny ]
}

@test "the verb detector reads the command position, through wrappers, every separator and quotes" {
  state certified
  prompt "hello there" >/dev/null
  [ "$(label)" = other ]
  [ "$(tool Bash 'git commit -m "codex; gemini and claude -p were compared"')" = allow ]
  [ "$(tool Bash "echo 'codex exec x'")" = allow ]
  [ "$(tool Bash 'grep -r codex docs/')" = allow ]
  [ "$(tool Bash 'env A=1 timeout 30 codex exec x')" = deny ]
  [ "$(tool Bash 'bash -c "gemini -p q"')" = deny ]
  [ "$(tool Bash "$(printf 'ls\n/opt/bin/codex exec x')")" = deny ]
  [ "$(tool Bash 'echo "$(claude --print hi)"')" = deny ]
  [ "$(tool Bash 'cd x && ~/.claude/scripts/handoff-fire.sh y')" = deny ]
  [ "$(tool Bash 'cc-research reopen demo')" = deny ]
  [ "$(tool Bash 'cc-research verdict demo')" = allow ]
  [ "$(tool Bash 'claude --version')" = allow ]
}

@test "a research order runs the kit's rounds while certifying, and nothing while certified" {
  state certifying
  prompt "do exhaustive research on the open rows" >/dev/null
  [ "$(label)" = research-order ]
  [ "$(tool Bash 'scripts/research-kit/round.sh run --program demo --kind certification --round 3')" = allow ]
  [ "$(tool Agent 'x')" = deny ]
  state certified
  prompt "do exhaustive research on the open rows" >/dev/null
  [ "$(tool Bash 'scripts/research-kit/round.sh run --program demo --kind certification --round 4')" = deny ]
  [ "$(tool Bash 'scripts/research-kit/courier.sh run --program demo')" = deny ]
}

@test "§10 item 8: an OPEN contract-listed activity lets its tagged delta round, courier and Agent through" {
  state certified
  printf '{"activities":[{"program":"demo","id":"esc-7","kind":"escape","state":"open"},{"program":"demo","id":"esc-1","kind":"escape","state":"closed"}]}\n' \
    > "$CC_RESEARCH_HOME/activities.json"
  prompt "hello there" >/dev/null
  [ "$(tool Bash 'CC_RESEARCH_ACTIVITY=esc-7 scripts/research-kit/round.sh run --program demo --kind delta --round 1')" = allow ]
  [ "$(tool Bash 'CC_RESEARCH_ACTIVITY=esc-7 scripts/research-kit/courier.sh run --program demo')" = allow ]
  [ "$(tool Agent '[activity:esc-7] verify the fix')" = allow ]
  # untagged, closed, unknown and non-delta all stay denied
  [ "$(tool Bash 'scripts/research-kit/round.sh run --program demo --kind delta --round 1')" = deny ]
  [ "$(tool Bash 'CC_RESEARCH_ACTIVITY=esc-1 scripts/research-kit/courier.sh run')" = deny ]
  [ "$(tool Bash 'CC_RESEARCH_ACTIVITY=esc-9 scripts/research-kit/courier.sh run')" = deny ]
  [ "$(tool Bash 'CC_RESEARCH_ACTIVITY=esc-7 scripts/research-kit/round.sh run --kind certification')" = deny ]
  [ "$(tool Agent '[activity:esc-1] x')" = deny ]
  # …and never inside a completeness turn, which denies every tool but the certificate read
  prompt "are we done?" >/dev/null
  [ "$(tool Agent '[activity:esc-7] verify the fix')" = deny ]
}

# cert_round_open: an open kit-opened certification-round activity cr-1, as gate.sh freeze writes it.
cert_round_open() {
  printf '{"activities":[{"program":"demo","id":"cr-1","kind":"certification-round","state":"open"}]}\n' \
    > "$CC_RESEARCH_HOME/activities.json"
}

@test "a certification-round activity lets a dispatched round session (label other) run only its round's verbs" {
  state certifying
  cert_round_open
  prompt "Run certification round 1 of demo. HANDOFF-ENGAGE-1-2-3" >/dev/null
  [ "$(label)" = other ]
  K=scripts/research-kit
  [ "$(tool Bash "CC_RESEARCH_ACTIVITY=cr-1 $K/round.sh run --program demo --kind certification --round 1")" = allow ]
  [ "$(tool Bash "CC_RESEARCH_ACTIVITY=cr-1 $K/round.sh run --program demo --kind=certification --round 1")" = allow ]
  [ "$(tool Bash "CC_RESEARCH_ACTIVITY=cr-1 $K/round.sh close --program demo --round 1")" = allow ]
  for v in artifact split verify-split repass; do
    [ "$(tool Bash "CC_RESEARCH_ACTIVITY=cr-1 $K/round.sh $v --program demo --hole H-1-001")" = allow ]
    [ "$(tool Bash "$K/round.sh $v --program demo --hole H-1-001")" = deny ]
  done
  [ "$(tool Bash ". scripts/lib/detach.sh; detach \"\$LOG\" env CC_RESEARCH_ACTIVITY=cr-1 $K/round.sh run --kind certification")" = allow ]
  [ "$(tool Bash "CC_RESEARCH_ACTIVITY=cr-1 $K/courier.sh run --program demo")" = allow ]
  [ "$(tool Agent '[activity:cr-1] blind dedup')" = allow ]
  [ "$(tool Bash 'CC_RESEARCH_ACTIVITY=cr-1 codex exec -s read-only -m x p')" = allow ]
  [ "$(tool Bash 'CC_RESEARCH_ACTIVITY=cr-1 codex exec --sandbox=read-only p')" = allow ]
  # untagged, another round kind, a writable or overridden codex, other vendors and the fire stay denied
  [ "$(tool Bash "$K/round.sh run --program demo --kind certification --round 1")" = deny ]
  [ "$(tool Bash "CC_RESEARCH_ACTIVITY=cr-1 $K/round.sh run --program demo --kind frame-critique --round 1")" = deny ]
  [ "$(tool Bash "CC_RESEARCH_ACTIVITY=cr-1 $K/round.sh run --program demo --kind delta --round 1")" = deny ]
  [ "$(tool Bash 'CC_RESEARCH_ACTIVITY=cr-1 codex exec p')" = deny ]
  [ "$(tool Bash 'CC_RESEARCH_ACTIVITY=cr-1 codex exec -s read-only --full-auto p')" = deny ]
  [ "$(tool Bash 'CC_RESEARCH_ACTIVITY=cr-1 codex exec -s read-only -c sandbox_mode=danger-full-access p')" = deny ]
  [ "$(tool Bash 'codex exec -s read-only p')" = deny ]
  [ "$(tool Bash 'CC_RESEARCH_ACTIVITY=cr-1 gemini p')" = deny ]
  [ "$(tool Bash 'CC_RESEARCH_ACTIVITY=cr-1 handoff-fire.sh --x')" = deny ]
  [ "$(tool Bash 'CC_RESEARCH_ACTIVITY=cr-1 claude -p hi')" = deny ]
  [ "$(tool Agent 'blind dedup')" = deny ]
}

# RED-proof: on 7dab6ce0d (research_clause returned "handoff-fire.sh" for every invocation) both
# self-close assertions read deny — a fired peer in a certifying program could not retire its pane.
@test "a certifying program lets a session self-close through handoff-fire.sh, and blocks every fire" {
  state certifying
  prompt "hello there" >/dev/null
  [ "$(label)" = other ]
  # shellcheck disable=SC2088  # the literal ~ is the point: the router reads the command as typed
  [ "$(tool Bash '~/.claude/scripts/handoff-fire.sh self-close --terminal')" = allow ]
  # shellcheck disable=SC2088
  [ "$(tool Bash '~/.claude/scripts/handoff-fire.sh self-close --successor 4')" = allow ]
  [ "$(tool Bash 'handoff-fire.sh --recycle --prompt-file x')" = deny ]
  [ "$(tool Bash 'handoff-fire.sh --prompt-file x --worktree b')" = deny ]
  [ "$(tool Bash 'bash scripts/handoff-fire.sh --prompt-file x')" = deny ]
  [ "$(tool Bash 'handoff-fire.sh --prompt-file x self-close')" = deny ]
}

# RED-proof: on 55444343d (envelope_prompt labeled every unrouted envelope naming the program) the
# lead, fresh and goalonly panes read `other` and the lead's fire reads deny — the 2026-10-11 lead
# re-routed by peer mail. The worker and inroot halves pin what must survive the fix (mutants: drop
# `a.by == "prompt"` and inroot's Read is denied; drop the FIRE_BRIEF exception and worker reads none).
@test "outside every root, an envelope naming the program leaves an ordinary pane ordinary; a fire brief still routes" {
  state certifying
  E="$BATS_TEST_TMPDIR/elsewhere"
  prompt 'the demo: build the parser' "$E" lead >/dev/null
  [ "$(label lead)" = work-order ]
  prompt 'upgraded, continue' "$E" lead >/dev/null
  [ "$(label lead)" = none ]
  : > "$STUB_LOG"
  prompt '<task-notification>peer mail: the demo round 1 complete</task-notification>' "$E" lead >/dev/null
  [ "$(label lead)" = none ]
  [ "$(tool Bash 'handoff-fire.sh --prompt-file x --worktree fix/kit' "$E" lead)" = allow ]
  prompt '<task-notification>the demo: round 2 is due</task-notification>' "$E" fresh >/dev/null
  [ "$(label fresh)" = none ]
  # The accepted widening, pinned: a /goal echo naming the program leaves an unrouted pane alone too.
  prompt 'Goal set: the demo round 2 is due' "$E" goalonly >/dev/null
  [ "$(label goalonly)" = none ]
  [ ! -s "$STUB_LOG" ]
  prompt 'Fix the kit for the demo. HANDOFF-ENGAGE-1-2-3' "$E" worker >/dev/null
  [ "$(label worker)" = other ]
  [ "$(tool Agent 'x' "$E" worker)" = deny ]
  [ "$(tool Bash 'handoff-fire.sh --prompt-file x --worktree fix/kit' "$E" worker)" = deny ]
  prompt '[handoff recycle] continue the demo kit fix' "$E" recycled >/dev/null
  [ "$(label recycled)" = other ]
  prompt '<task-notification>peer mail: the demo round 1 complete</task-notification>' "$PROG/src" inroot >/dev/null
  [ "$(label inroot)" = other ]
  [ "$(tool Read 'x' "$PROG/src" inroot)" = allow ]
}

# RED-proof is by mutant: an exemption in research_clause for a fire whose --worktree/--cwd/--repo
# lies outside every root flips both fires below to allow (operator ruling 2026-10-11: every fire
# stays a research verb on a turn routed other, wherever it is aimed).
@test "a pane outside every root routed as other by a genuine prompt keeps every fire blocked, wherever it fires" {
  state certifying
  E="$BATS_TEST_TMPDIR/elsewhere"
  prompt 'the demo status please' "$E" lead2 >/dev/null
  [ "$(label lead2)" = other ]
  [ "$(tool Bash 'handoff-fire.sh --prompt-file x --worktree fix/kit --repo /tmp/other' "$E" lead2)" = deny ]
  [ "$(tool Bash 'handoff-fire.sh --prompt-file x --cwd /tmp/outside' "$E" lead2)" = deny ]
}

# Decision (2026-10-11 follow-up): a teammate's first prompt is not a fire brief. Mutant: add
# `<teammate-message` to FIRE_BRIEF and mate reads other — a work-order lead's teammate denied Agent.
@test "outside every root a teammate whose first prompt names the program starts ordinary; only an Agent-capable pane can spawn one" {
  state certifying
  E="$BATS_TEST_TMPDIR/elsewhere"
  prompt 'the demo status please' "$E" spawner >/dev/null
  [ "$(label spawner)" = other ]
  [ "$(tool Agent 'spawn a teammate' "$E" spawner)" = deny ]
  prompt '<teammate-message teammate_id="team-lead">the demo: fix the parser</teammate-message>' "$E" mate >/dev/null
  [ "$(label mate)" = none ]
  [ "$(tool Agent 'x' "$E" mate)" = allow ]
}

@test "a certification-round activity unlocks nothing once the program is certified" {
  state certified
  cert_round_open
  prompt "hello there" >/dev/null
  [ "$(label)" = other ]
  [ "$(tool Bash 'CC_RESEARCH_ACTIVITY=cr-1 scripts/research-kit/round.sh run --kind certification --round 4')" = deny ]
  [ "$(tool Bash 'CC_RESEARCH_ACTIVITY=cr-1 scripts/research-kit/courier.sh run --program demo')" = deny ]
  [ "$(tool Bash 'CC_RESEARCH_ACTIVITY=cr-1 codex exec -s read-only p')" = deny ]
  [ "$(tool Agent '[activity:cr-1] blind dedup')" = deny ]
}

@test "the verb detector reads through a detach <log> prefix" {
  state certifying
  prompt "hello there" >/dev/null
  [ "$(label)" = other ]
  [ "$(tool Bash '. scripts/lib/detach.sh; detach "$LOG" scripts/research-kit/round.sh run --kind certification')" = deny ]
  [ "$(tool Bash 'detach /tmp/x.log codex exec p')" = deny ]
}

@test "a /goal echo and a subagent hand-back are machine envelopes: they keep the session's label, unclassified" {
  state certifying
  prompt "Run round 1. HANDOFF-ENGAGE-1-2-3" >/dev/null
  [ "$(label)" = other ]
  : > "$STUB_LOG"
  prompt "Goal set: round 1 of demo is closed; build and fix it" >/dev/null
  [ "$(label)" = other ]
  prompt '<\agent-message from="a1">fix the build</agent-message>' >/dev/null
  [ "$(label)" = other ]
  [ ! -s "$STUB_LOG" ]
}

@test "an envelope that only quotes --requires-gate (no program slug) is other, never a work order" {
  state certifying
  prompt "[handoff 1] the --requires-gate cannot carry a round HANDOFF-ENGAGE-1-2-3" "$PROG/src" q1 >/dev/null
  [ "$(label q1)" = other ]
  [ "$(tool Agent 'x' "$PROG/src" q1)" = deny ]
}

@test "a completeness turn denies a certification-round activity's tagged round and Agent" {
  state certifying
  cert_round_open
  prompt "are we done?" >/dev/null
  [ "$(label)" = completeness ]
  [ "$(tool Bash 'CC_RESEARCH_ACTIVITY=cr-1 scripts/research-kit/round.sh run --kind certification --round 1')" = deny ]
  [ "$(tool Agent '[activity:cr-1] blind dedup')" = deny ]
}

@test "no registry at all: both hooks are inert and the nudge is unchanged" {
  rm -f "$CC_RESEARCH_REGISTRY"
  run prompt "are we done?"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(tool Agent 'x')" = allow ]
}

@test "a routed prompt makes no classifier call from inside the classifier (the router cannot trigger itself)" {
  state certified
  : > "$STUB_LOG"
  CC_RESEARCH_ROUTER_INNER=1 prompt "are we done?" >/dev/null
  [ ! -s "$STUB_LOG" ]
  CC_RESEARCH_ROUTER_INNER=1 run tool Agent 'x'
  [ "$output" = allow ]
}

@test "route records older than a week are reaped on the next write (growth-coverage.conf route-state row)" {
  state certified
  mkdir -p "$CC_RESEARCH_HOME/route-state"
  printf '{}' > "$CC_RESEARCH_HOME/route-state/old.json"
  touch -t 202609010000 "$CC_RESEARCH_HOME/route-state/old.json"
  prompt "build it" >/dev/null
  [ ! -e "$CC_RESEARCH_HOME/route-state/old.json" ]
  [ -f "$CC_RESEARCH_HOME/route-state/s1.json" ]
}

# Wave E1m's careful-call pin (router.py CAREFUL_PIN, ruling 8633d354bd41), asserted literally below.
PIN_MODEL=claude-haiku-4-5
PIN_EFFORT=''          # empty: the careful call carries no --effort flag
# shellcheck disable=SC2088  # the pin is written with a literal ~, as router.py carries it
PIN_CLAUDE='~/.claude-293/node_modules/.bin/claude'
PIN_ID=3eb7e253415c           # classifier_config() with the pinned binary at version 2.1.293

# A claude install laid out as npm lays one out (package.json two levels above the binary), at VERSION,
# with .bin/claude linked to it: plant_claude DIR VERSION.
plant_claude() {
  mkdir -p "$1/node_modules/@anthropic-ai/claude-code/bin" "$1/node_modules/.bin"
  printf '{"name": "@anthropic-ai/claude-code", "version": "%s"}\n' "$2" > "$1/node_modules/@anthropic-ai/claude-code/package.json"
  printf '#!/bin/bash\ncat >/dev/null\necho other\n' > "$1/node_modules/@anthropic-ai/claude-code/bin/claude.exe"
  chmod +x "$1/node_modules/@anthropic-ai/claude-code/bin/claude.exe"
  ln -sf ../@anthropic-ai/claude-code/bin/claude.exe "$1/node_modules/.bin/claude"
}
router_py() { /usr/bin/python3 -c "import sys; sys.path[:0]=['$REPO/scripts/research-kit/lib','$REPO/scripts/research-kit']; import router; $1"; }

@test "E1m pin: the careful call's model, effort and binary are pinned in router.py, not read from model-config" {
  run router_py 'print(router.CAREFUL_PIN["model"], router.CAREFUL_PIN["effort"] or "", router.CAREFUL_PIN["claude"], sep="|")'
  [ "$status" -eq 0 ]
  [ "$output" = "$PIN_MODEL|$PIN_EFFORT|$PIN_CLAUDE" ]
  unset CC_RESEARCH_CLASSIFIER   # setup's stub seam would stand in for the real command line
  plant_claude "$HOME/.claude-293" 2.1.293
  printf 'models:\n  sonnet_latest: claude-sonnet-5-5\n  haiku_latest: claude-haiku-old-1\n' > "$BATS_TEST_TMPDIR/m1.yaml"
  printf 'models:\n  sonnet_latest: claude-sonnet-5-5\n  haiku_latest: claude-haiku-new-2\n' > "$BATS_TEST_TMPDIR/m2.yaml"
  argv() { CC_MODEL_CONFIG="$1" router_py 'print(" ".join(router.classifier_argv("careful")))'; }
  # a move of haiku_latest (as on 2026-10-07) no longer reaches the careful call or the configuration id
  [ "$(argv "$BATS_TEST_TMPDIR/m1.yaml")" = "$(argv "$BATS_TEST_TMPDIR/m2.yaml")" ]
  [[ "$(argv "$BATS_TEST_TMPDIR/m1.yaml")" == "$HOME/.claude-293/node_modules/.bin/claude ${PIN_EFFORT:+--effort $PIN_EFFORT }-p --model $PIN_MODEL "* ]] || false
  cfg() { CC_MODEL_CONFIG="$1" router_py 'print(router.classifier_config())'; }
  [ "$(cfg "$BATS_TEST_TMPDIR/m1.yaml")" = "$(cfg "$BATS_TEST_TMPDIR/m2.yaml")" ]
}

@test "E1m pin: the careful binary's version is part of the configuration id, and a missing pinned binary is no careful classifier, never another one" {
  plant_claude "$HOME/.claude-293" 2.1.293
  a="$(router_py 'print(router.classifier_config())')"
  plant_claude "$HOME/.claude-293" 2.1.294        # the same path, another version under it
  b="$(router_py 'print(router.classifier_config())')"
  [ -n "$a" ]
  [ -n "$b" ]
  [ "$a" != "$b" ]
  run router_py 'print(router.claude_version(router.careful_claude()))'
  [ "$output" = 2.1.294 ]
  mv "$HOME/.claude-293" "$HOME/.claude-293.gone"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/bash\necho other\n' > "$BATS_TEST_TMPDIR/bin/claude"; chmod +x "$BATS_TEST_TMPDIR/bin/claude"
  unset CC_RESEARCH_CLASSIFIER
  run env PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin" /usr/bin/python3 -c "import sys; sys.path[:0]=['$REPO/scripts/research-kit/lib','$REPO/scripts/research-kit']; import router; print(router.classifier_argv('careful')); print(router.classifier_argv('fast')[0])"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = None ]
  [ "${lines[1]}" = "$BATS_TEST_TMPDIR/bin/claude" ]
}

@test "the real classifier call: the fast call's model from model-config (sonnet_latest), the careful call pinned (wave E1m), local settings only, an empty cwd, the inner guard set" {
  state certified
  unset CC_RESEARCH_CLASSIFIER
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf 'models:\n  sonnet_latest: claude-sonnet-test-7   # comment\n  haiku_latest: claude-haiku-test-9   # comment\n' > "$BATS_TEST_TMPDIR/model-config.yaml"
  export CC_MODEL_CONFIG="$BATS_TEST_TMPDIR/model-config.yaml"
  cat > "$BATS_TEST_TMPDIR/bin/claude" <<'STUB'
#!/bin/bash
{ printf 'argv=%s\n' "$*"; printf 'inner=%s\n' "${CC_RESEARCH_ROUTER_INNER:-}"; printf 'files=%s\n' "$(ls -A | wc -l | tr -d ' ')"; } > "$STUB_ARGS.$CC_RESEARCH_CLASSIFIER_KIND"
cat >/dev/null
# the fast call's `other` ends nothing, so the router waits for the careful call and both are seen
if [ "$CC_RESEARCH_CLASSIFIER_KIND" = fast ]; then echo other; else echo completeness; fi
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/claude"
  export STUB_ARGS="$BATS_TEST_TMPDIR/args"
  export CC_RESEARCH_CAREFUL_CLAUDE="$BATS_TEST_TMPDIR/bin/claude"   # the pinned binary's test seam
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" prompt "are we done?" >/dev/null
  [ "$(label)" = completeness ]
  # Since wave E1g the classifier is two calls. Since wave E1m the careful one's model and effort are
  # pinned in router.py, so model-config's haiku_latest (claude-haiku-test-9 here) no longer reaches
  # it. The fast one adds its own flags (tests/research-classifier-warm.bats pins those) and, since
  # wave E1i, runs sonnet_latest.
  grep -qx "argv=${PIN_EFFORT:+--effort $PIN_EFFORT }-p --model $PIN_MODEL --setting-sources local --tools  --strict-mcp-config --no-session-persistence" "$STUB_ARGS.careful"
  grep -q '^argv=-p --model claude-sonnet-test-7 --setting-sources local --tools  --strict-mcp-config --no-session-persistence --disable-slash-commands ' "$STUB_ARGS.fast"
  # the fast call's model is part of the configuration id, so a resident classifier started on the
  # old one reads as not ready and migration 0059 restarts it
  printf 'models:\n  sonnet_latest: claude-sonnet-test-8\n  haiku_latest: claude-haiku-test-9\n' > "$BATS_TEST_TMPDIR/model-config-2.yaml"
  cfg() { CC_MODEL_CONFIG="$1" /usr/bin/python3 -c "import sys; sys.path[:0]=['$REPO/scripts/research-kit/lib','$REPO/scripts/research-kit']; import router; print(router.classifier_config())"; }
  a="$(cfg "$BATS_TEST_TMPDIR/model-config.yaml")" b="$(cfg "$BATS_TEST_TMPDIR/model-config-2.yaml")"
  [ -n "$a" ]
  [ "$a" != "$b" ]
  for k in fast careful; do
    grep -qx 'inner=1' "$STUB_ARGS.$k"
    grep -qx 'files=0' "$STUB_ARGS.$k"
  done
}

@test "the live classifier's configuration id is pinned: wave E1m's careful pin, on claude 2.1.293" {
  # Wave E1j added tracing only and wave E1k's hedge changed no flag, model or brief, so the id stayed
  # 983448663980 until wave E1m pinned the careful call (model, effort, binary and its version, brief).
  # The resident daemon serves the id it was started with, so this id is the one migration 0059's
  # restart must bring the daemon to.
  plant_claude "$HOME/.claude-293" 2.1.293
  printf 'models:\n  sonnet_latest: claude-sonnet-5-5\n  haiku_latest: claude-haiku-5-5\n' > "$BATS_TEST_TMPDIR/model-config.yaml"
  run env CC_MODEL_CONFIG="$BATS_TEST_TMPDIR/model-config.yaml" /usr/bin/python3 -c "import sys; sys.path[:0]=['$REPO/scripts/research-kit/lib','$REPO/scripts/research-kit']; import router; print(router.classifier_config())"
  [ "$status" -eq 0 ]
  [ "$output" = "$PIN_ID" ]
}

# ── the block's fast exit (docs/research/concurrency-scale-2026-10-04 fix row 4) ────────────────
# RED-proof: on the pre-fix hook (git show 13b27133f:hooks/research-block.sh) the first case below
# fails — the router's python starts on every tool call, program or not.
#
# pyspy <cwd> <sid> — one PreToolUse through the real hook with a python3 on PATH that records its
# start and then runs the real interpreter, so the decision is the router's own. Prints the
# decision, then "py=<starts>".
pyspy() {
  local real; real="$(command -v python3)"
  mkdir -p "$BATS_TEST_TMPDIR/spy"
  printf '#!/bin/bash\necho x >> "%s"\nexec "%s" "$@"\n' "$BATS_TEST_TMPDIR/py.log" "$real" > "$BATS_TEST_TMPDIR/spy/python3"
  chmod +x "$BATS_TEST_TMPDIR/spy/python3"
  : > "$BATS_TEST_TMPDIR/py.log"
  jq -nc --arg c "$1" --arg s "$2" '{session_id:$s,cwd:$c,tool_name:"Agent",tool_input:{prompt:"x",description:"x"}}' \
    | PATH="$BATS_TEST_TMPDIR/spy:$PATH" bash "$BLOCK" | jq -r '.hookSpecificOutput.permissionDecision // empty' | grep -q deny \
    && echo deny || echo allow
  echo "py=$(wc -l < "$BATS_TEST_TMPDIR/py.log" | tr -d ' ')"
}

@test "fast exit: a tool call outside every program root, in a session with no route record, allows without starting python" {
  state certified
  run pyspy "$BATS_TEST_TMPDIR/elsewhere" s-none
  [ "$output" = "allow"$'\n'"py=0" ]
}

@test "fast exit is not taken inside a program root, nor for a session that carries a route record" {
  state certified
  run pyspy "$PROG/src" s-none
  [ "$output" = "deny"$'\n'"py=1" ]
  prompt "are we done?" "$PROG/src" s-routed >/dev/null
  run pyspy "$BATS_TEST_TMPDIR/elsewhere" s-routed
  [ "$output" = "deny"$'\n'"py=1" ]
}

@test "fast exit is not taken for a session id the router would rename, so its sanitized record still decides" {
  state certified
  prompt "are we done?" "$PROG/src" "a/b c" >/dev/null
  [ -f "$CC_RESEARCH_HOME/route-state/a_b_c.json" ]
  run pyspy "$BATS_TEST_TMPDIR/elsewhere" "a/b c"
  [ "$output" = "deny"$'\n'"py=1" ]
}

# fer_open: an open kit-opened front-end-return activity fer-1 (gate.sh return-activity) beside a
# closed one, fer-0, and the certification-round activity that opening the return closed.
fer_open() {
  printf '{"activities":[{"program":"demo","id":"cr-1","kind":"certification-round","state":"closed"},{"program":"demo","id":"fer-0","kind":"front-end-return","area":"A0","state":"closed"},{"program":"demo","id":"fer-1","kind":"front-end-return","area":"A1","state":"open"}]}\n' \
    > "$CC_RESEARCH_HOME/activities.json"
}

# wf <tool_input json>: one Workflow PreToolUse whose input is a script and its args.
wf() {
  jq -nc --argjson i "$1" --arg c "$PROG/src" '{session_id:"s1",cwd:$c,tool_name:"Workflow",tool_input:$i}' \
    | bash "$BLOCK" | jq -r '.hookSpecificOutput.permissionDecision // empty' | grep -q deny \
    && echo deny || echo allow
}

# RED-proof: on 931209017 (before the front-end-return kind) the tagged Workflow args and the read-only
# codex read deny, and the fer-tagged courier.sh and delta round read allow (any open activity let
# both through). The five handoff-fire lines hold on that commit too; their red is the mutant that
# adds `or fer` to research_clause's handoff-fire arm (the prototype's exemption): all five flip to
# allow (measured 2026-10-12).
@test "a front-end-return activity lets a return session (label other) fan out to Agents, Workflows and read-only codex, and nothing else" {
  state certifying
  fer_open
  prompt "Area A1, Stages 2-5. HANDOFF-ENGAGE-1-2-3" >/dev/null
  [ "$(label)" = other ]
  K=scripts/research-kit
  [ "$(tool Agent '[activity:fer-1] census A1')" = allow ]
  [ "$(tool Task '[activity:fer-1] census A1')" = allow ]
  [ "$(tool Workflow '[activity:fer-1] census A1')" = allow ]
  # a Workflow input is a script and its args: the tag is read wherever the input carries it
  [ "$(wf '{"script":"census.workflow.js","args":{"note":"[activity:fer-1] A1"}}')" = allow ]
  [ "$(wf '{"script":"census.workflow.js","args":{"note":"A1"}}')" = deny ]
  [ "$(tool Bash 'CC_RESEARCH_ACTIVITY=fer-1 codex exec -s read-only -m x p')" = allow ]
  # handoff-fire stays denied under the return's tag, in each measured escape form; self-close passes
  [ "$(tool Bash 'CC_RESEARCH_ACTIVITY=fer-1 handoff-fire.sh --prompt-file b.md --worktree w')" = deny ]
  [ "$(tool Bash 'CC_RESEARCH_ACTIVITY=fer-1 bash scripts/handoff-fire.sh --recycle --prompt-file b.md')" = deny ]
  [ "$(tool Bash 'CC_RESEARCH_ACTIVITY=fer-1 CC_RESEARCH_GATE=/tmp/x handoff-fire.sh --requires-gate demo --gate-wave X --prompt-file b.md')" = deny ]
  [ "$(tool Bash "CC_RESEARCH_ACTIVITY=fer-1 handoff-fire.sh --prompt-file b.md --extra '--resume u'")" = deny ]
  [ "$(tool Bash 'CC_RESEARCH_ACTIVITY=fer-1 handoff-fire.sh --prompt-file b.md --cwd /elsewhere')" = deny ]
  [ "$(tool Bash 'CC_RESEARCH_ACTIVITY=fer-1 handoff-fire.sh self-close --terminal')" = allow ]
  # untagged, closed, unknown, a writable codex, other vendors, claude -p, round verbs and buying verbs
  [ "$(tool Agent 'census A1')" = deny ]
  [ "$(tool Agent '[activity:fer-0] census A0')" = deny ]
  [ "$(tool Agent '[activity:cr-1] census A1')" = deny ]
  [ "$(tool Bash 'CC_RESEARCH_ACTIVITY=fer-0 codex exec -s read-only p')" = deny ]
  [ "$(tool Bash 'CC_RESEARCH_ACTIVITY=fer-9 codex exec -s read-only p')" = deny ]
  [ "$(tool Bash 'CC_RESEARCH_ACTIVITY=fer-1 codex exec p')" = deny ]
  [ "$(tool Bash 'CC_RESEARCH_ACTIVITY=fer-1 codex exec -s read-only --full-auto p')" = deny ]
  [ "$(tool Bash 'CC_RESEARCH_ACTIVITY=fer-1 gemini p')" = deny ]
  [ "$(tool Bash 'CC_RESEARCH_ACTIVITY=fer-1 agy --print p')" = deny ]
  [ "$(tool Bash 'CC_RESEARCH_ACTIVITY=fer-1 claude -p hi')" = deny ]
  [ "$(tool Bash "CC_RESEARCH_ACTIVITY=fer-1 $K/courier.sh run --program demo --role reviewer")" = deny ]
  [ "$(tool Bash "CC_RESEARCH_ACTIVITY=fer-1 $K/round.sh run --program demo --kind delta --round 1")" = deny ]
  [ "$(tool Bash "CC_RESEARCH_ACTIVITY=fer-1 $K/round.sh run --program demo --kind certification --round 2")" = deny ]
  [ "$(tool Bash "CC_RESEARCH_ACTIVITY=fer-1 $K/round.sh close --program demo --round 1")" = deny ]
  [ "$(tool Bash 'CC_RESEARCH_ACTIVITY=fer-1 cc-research rehearse --program demo')" = deny ]
}

# RED-proof: on 931209017 the certified fer-1 Agent reads allow (only certification-round ids were
# dropped outside certifying).
@test "a front-end-return activity unlocks nothing once certified, nor on a completeness turn" {
  state certified
  fer_open
  prompt "hello there" >/dev/null
  [ "$(label)" = other ]
  [ "$(tool Agent '[activity:fer-1] census A1')" = deny ]
  [ "$(wf '{"script":"census.workflow.js","args":{"note":"[activity:fer-1] A1"}}')" = deny ]
  [ "$(tool Bash 'CC_RESEARCH_ACTIVITY=fer-1 codex exec -s read-only p')" = deny ]
  [ "$(tool Bash 'CC_RESEARCH_ACTIVITY=fer-1 handoff-fire.sh --prompt-file b.md')" = deny ]
  state certifying
  prompt "are we done?" >/dev/null
  [ "$(label)" = completeness ]
  [ "$(tool Agent '[activity:fer-1] census A1')" = deny ]
  [ "$(tool Bash 'CC_RESEARCH_ACTIVITY=fer-1 codex exec -s read-only p')" = deny ]
}
