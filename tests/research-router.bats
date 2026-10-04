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
  [ "$(cat "$STUB_LOG")" = unavailable ]
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

@test "the real classifier call: haiku_latest from model-config, local settings only, an empty cwd, the inner guard set" {
  state certified
  unset CC_RESEARCH_CLASSIFIER
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf 'models:\n  haiku_latest: claude-haiku-test-9   # comment\n' > "$BATS_TEST_TMPDIR/model-config.yaml"
  export CC_MODEL_CONFIG="$BATS_TEST_TMPDIR/model-config.yaml"
  cat > "$BATS_TEST_TMPDIR/bin/claude" <<'STUB'
#!/bin/bash
{ printf 'argv=%s\n' "$*"; printf 'inner=%s\n' "${CC_RESEARCH_ROUTER_INNER:-}"; printf 'files=%s\n' "$(ls -A | wc -l | tr -d ' ')"; } > "$STUB_ARGS"
cat >/dev/null
echo completeness
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/claude"
  export STUB_ARGS="$BATS_TEST_TMPDIR/args"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" prompt "are we done?" >/dev/null
  [ "$(label)" = completeness ]
  grep -qx 'argv=-p --model claude-haiku-test-9 --setting-sources local' "$STUB_ARGS"
  grep -qx 'inner=1' "$STUB_ARGS"
  grep -qx 'files=0' "$STUB_ARGS"
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
