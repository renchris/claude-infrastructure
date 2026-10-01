#!/usr/bin/env bats
# research-kit-courier — scripts/research-kit/courier.sh (REPORT.md §3.2 step 6, §3.8). A dead
# vendor lane is reported and never filled; a reply from the wrong model, or one that shows the real
# program path, voids its slot; the bundle carries what reviewers may read and nothing else.
# Fake vendor CLIs stand in for claude, codex and gemini; each fakes only the output shape the
# courier parses, and each can be told to fail.

setup() {
  unset CC_BATS_ACTIVE
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  C="$REPO/scripts/research-kit/courier.sh"
  export CC_RESEARCH_HOME="$BATS_TEST_TMPDIR/research"
  export CC_RESEARCH_REGISTRY="$CC_RESEARCH_HOME/programs.json"
  export CC_RESEARCH_RECORDS="$BATS_TEST_TMPDIR/records"
  export CC_RESEARCH_CODEX_SESSIONS="$BATS_TEST_TMPDIR/codex-sessions"
  mkdir -p "$CC_RESEARCH_RECORDS" "$BATS_TEST_TMPDIR/bin" "$CC_RESEARCH_CODEX_SESSIONS"
  printf '{"reviewer_pins":{"anthropic":"claude-opus-5-5","frontier":"claude-fable-5-1","openai":"gpt-x","google":"gemini-x"}}\n' \
    > "$CC_RESEARCH_RECORDS/frame.json"
  export FAKE_REPLY='{"lenses":[{"lens":"premise","result":"nothing material"}],"rows":[],"findings":[]}'
  B="$BATS_TEST_TMPDIR/bin"
  # claude: echoes the requested --model back as the responding model unless FAKE_MODEL overrides.
  cat > "$B/claude" <<'EOF'
#!/bin/bash
m=""; while [ $# -gt 0 ]; do [ "$1" = "--model" ] && m="$2"; shift; done
[ -n "${FAKE_FAIL:-}" ] && { echo "boom" >&2; exit 1; }
[ -n "${FAKE_SLEEP:-}" ] && sleep "$FAKE_SLEEP"
/usr/bin/python3 -c 'import json,os,sys; print(json.dumps({"is_error":False,"result":os.environ["FAKE_REPLY"],"modelUsage":{sys.argv[1]:{"outputTokens":9}}}))' "${FAKE_MODEL:-$m}"
EOF
  # codex: emits the JSONL event stream and writes the session record that names the model.
  cat > "$B/codex" <<'EOF'
#!/bin/bash
m=""; while [ $# -gt 0 ]; do [ "$1" = "-m" ] && m="$2"; shift; done
t="thread-$$"
printf '{"type":"session_meta","payload":{"model":"%s"}}\n' "${FAKE_MODEL:-$m}" > "$CC_RESEARCH_CODEX_SESSIONS/rollout-x-$t.jsonl"
sed -i '' 's/"payload":{"model"/"model"/' "$CC_RESEARCH_CODEX_SESSIONS/rollout-x-$t.jsonl"
printf '{"type":"thread.started","thread_id":"%s"}\n' "$t"
/usr/bin/python3 -c 'import json,os; print(json.dumps({"type":"item.completed","item":{"type":"agent_message","text":os.environ["FAKE_REPLY"]}}))'
EOF
  # gemini: refuses unless run read-only in plan mode with the per-call system settings file.
  cat > "$B/gemini" <<'EOF'
#!/bin/bash
case " $* " in *" --approval-mode plan "*) ;; *) echo "not plan mode" >&2; exit 1 ;; esac
[ -f "${GEMINI_CLI_SYSTEM_SETTINGS_PATH:-/nonexistent}" ] || { echo "no system settings" >&2; exit 1; }
m=""; while [ $# -gt 0 ]; do [ "$1" = "-m" ] && m="$2"; shift; done
/usr/bin/python3 -c 'import json,os,sys; print(json.dumps({"response":os.environ["FAKE_REPLY"],"stats":{"models":{sys.argv[1]:{}}}}))' "${FAKE_MODEL:-$m}"
EOF
  chmod +x "$B/claude" "$B/codex" "$B/gemini"
  export CC_RESEARCH_BIN_ANTHROPIC="$B/claude" CC_RESEARCH_BIN_OPENAI="$B/codex" CC_RESEARCH_BIN_GOOGLE="$B/gemini"
  printf '# plan\nline two\n' > "$BATS_TEST_TMPDIR/PLAN.md"
  BRIEF="$BATS_TEST_TMPDIR/brief.txt"
  echo "review the plan" > "$BRIEF"
}

lane() { /usr/bin/python3 -c "import json; d=json.load(open('$CC_RESEARCH_HOME/demo/preflight.json')); print(d['$1']['ok'], d['$1']['model_id'])"; }
panel() { /usr/bin/python3 -c "import json; d=json.load(open('$CC_RESEARCH_RECORDS/rounds/1/panels/$1.json')); print($2)"; }

@test "preflight: every live lane records its responding model id" {
  run "$C" preflight --program demo
  [ "$status" -eq 0 ]
  [ "$(lane anthropic)" = "True claude-opus-5-5" ]
  [ "$(lane openai)" = "True gpt-x" ]
  [ "$(lane google)" = "True gemini-x" ]
}

@test "preflight: a missing CLI is a dead lane, exit 3, never a reply" {
  CC_RESEARCH_BIN_GOOGLE="$BATS_TEST_TMPDIR/bin/nope" run "$C" preflight --program demo
  [ "$status" -eq 3 ]
  [ "$(lane google)" = "False None" ]
  [[ "$output" == *"google"*"DEAD"* ]]
}

@test "preflight: a CLI that exits non-zero is a dead lane" {
  FAKE_FAIL=1 run "$C" preflight --program demo
  [ "$status" -eq 3 ]
  [ "$(lane anthropic)" = "False None" ]
}

@test "preflight: a CLI that hangs past its timeout is a dead lane" {
  FAKE_SLEEP=5 run "$C" preflight --program demo --timeout 1
  [ "$status" -eq 3 ]
  [ "$(lane frontier)" = "False None" ]
}

@test "preflight: a responding model that differs from its pin is not a live lane" {
  FAKE_MODEL=gpt-old CC_RESEARCH_BIN_ANTHROPIC="$BATS_TEST_TMPDIR/bin/claude" run "$C" preflight --program demo
  [ "$status" -eq 3 ]
  [[ "$output" == *"!= pin"* ]]
}

@test "bundle: leaves out the hole ledger, rounds, .claude and CLAUDE.md, and refuses a second build" {
  mkdir -p "$CC_RESEARCH_RECORDS/rounds/0" "$CC_RESEARCH_RECORDS/.claude" "$CC_RESEARCH_RECORDS/evidence/P-1"
  echo '{}' > "$CC_RESEARCH_RECORDS/holes.jsonl"
  echo '{}' > "$CC_RESEARCH_RECORDS/.claude/settings.json"
  echo 'rules' > "$CC_RESEARCH_RECORDS/CLAUDE.md"
  echo 'out' > "$CC_RESEARCH_RECORDS/evidence/P-1/stdout"
  run "$C" bundle --program demo --round 1 --plan "$BATS_TEST_TMPDIR/PLAN.md"
  [ "$status" -eq 0 ]
  b="$CC_RESEARCH_HOME/demo/rounds/1/bundle"
  [ -f "$b/PLAN.md" ] && [ -f "$b/frame.json" ] && [ -f "$b/evidence/P-1/stdout" ] || false
  [ ! -e "$b/holes.jsonl" ] && [ ! -e "$b/rounds" ] && [ ! -e "$b/.claude" ] && [ ! -e "$b/CLAUDE.md" ] || false
  run "$C" bundle --program demo --round 1 --plan "$BATS_TEST_TMPDIR/PLAN.md"
  [ "$status" -eq 2 ]
}

@test "bundle: identical inputs give the same manifest hash in a fresh round" {
  h1="$("$C" bundle --program demo --round 1 --plan "$BATS_TEST_TMPDIR/PLAN.md" | awk '{print $2}')"
  h2="$("$C" bundle --program demo --round 2 --plan "$BATS_TEST_TMPDIR/PLAN.md" | awk '{print $2}')"
  [ -n "$h1" ] && [ "$h1" = "$h2" ]
}

@test "run: a reply in the brief's shape is complete, with raw output kept verbatim" {
  "$C" bundle --program demo --round 1 --plan "$BATS_TEST_TMPDIR/PLAN.md"
  run "$C" run --program demo --round 1 --pid r1p1 --vendor openai --strategy full-context --role reviewer --brief "$BRIEF"
  [ "$status" -eq 0 ]
  [ "$(panel r1p1 'd["status"], d["responding_model"], d["lenses"][0]["lens"]')" = "complete gpt-x premise" ]
  grep -q 'agent_message' "$CC_RESEARCH_RECORDS/rounds/1/panels/r1p1.raw"
}

@test "run: a dead CLI leaves a dead slot with no findings, exit 3" {
  "$C" bundle --program demo --round 1 --plan "$BATS_TEST_TMPDIR/PLAN.md"
  FAKE_FAIL=1 run "$C" run --program demo --round 1 --pid r1p2 --vendor anthropic --strategy plan-only --role reviewer --brief "$BRIEF"
  [ "$status" -eq 3 ]
  [ "$(panel r1p2 'd["status"], len(d["findings"]), len(d["lenses"])')" = "dead 0 0" ]
}

@test "run: a reply from the wrong model voids the slot, exit 4" {
  "$C" bundle --program demo --round 1 --plan "$BATS_TEST_TMPDIR/PLAN.md"
  FAKE_MODEL=claude-opus-4-8 run "$C" run --program demo --round 1 --pid r1p3 --vendor frontier --strategy full-context --role reviewer --brief "$BRIEF"
  [ "$status" -eq 4 ]
  [ "$(panel r1p3 'd["status"]')" = "void" ]
}

@test "run: google runs read-only in plan mode with its per-call settings file" {
  "$C" bundle --program demo --round 1 --plan "$BATS_TEST_TMPDIR/PLAN.md"
  run "$C" run --program demo --round 1 --pid r1p4 --vendor google --strategy full-context --role reviewer --brief "$BRIEF"
  [ "$status" -eq 0 ]
  [ "$(panel r1p4 'd["status"]')" = "complete" ]
}

@test "integrity: a raw output that shows the real records path is voided; a clean one is not" {
  "$C" bundle --program demo --round 1 --plan "$BATS_TEST_TMPDIR/PLAN.md"
  "$C" run --program demo --round 1 --pid clean --vendor openai --strategy full-context --role reviewer --brief "$BRIEF"
  FAKE_REPLY="I read $CC_RESEARCH_RECORDS/holes.jsonl" run "$C" run --program demo --round 1 --pid leak --vendor openai --strategy plan-only --role reviewer --brief "$BRIEF"
  [ "$status" -eq 4 ]
  run "$C" integrity --program demo --round 1
  [ "$status" -eq 4 ]
  [ "$output" = "voided: leak" ]
  [ "$(panel clean 'd["status"]')" = "complete" ]
}
