#!/usr/bin/env bats
# goal-inert-watch — the sensor that makes a SKIPPED /goal loud.
#
# Subject: hooks/goal-inert-watch.sh. Mechanism it reports on:
# docs/research/goal-in-handoff-2026-08-08.md § RESOLVED 2026-08-09.
#
# The two tests that carry this suite are the MUTATION checks at the bottom. Both guard a defect that
# produces a hook which is CLEAN, GREEN and permanently silent:
#   M1  `background_tasks[].type` is the DISPLAY name ("shell"), not the raw one ("local_bash").
#       Keying on the raw name matches nothing and reports all-clear forever.
#   M2  `grep goal_status` on a transcript also matches the assistant's own PROSE about goals.
#       Dropping the `type=="attachment"` filter makes the hook fire on a session with NO goal.
#   M3  an EMPTY `background_tasks` is not evidence that nothing is deferring: CC's payload is a
#       backgrounded-only view (`isBackgrounded === false` is filtered out) while the deferral gate
#       reads the raw registry. Treating empty as all-clear — the pre-2026-08-14 behaviour — makes
#       the hook silent on exactly the case it exists to catch: a FOREGROUND bash.
# Each neuters exactly one behaviour in a COPY of the real file and asserts the corresponding
# positive test flips — so no positive test can be passing vacuously.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  H="$REPO/hooks/goal-inert-watch.sh"
  D="$BATS_TEST_TMPDIR"
  # Per-test damp dir: damping must never make one test's fire suppress another's.
  export CC_PAGE_DAMP_DIR="$D/damp"
  if ! command -v jq >/dev/null 2>&1; then skip "jq not installed"; fi
}

# ── fixtures ──────────────────────────────────────────────────────────────────────────────────────

# An ARMED, never-evaluated goal. Lines 1-2 are the PROSE DECOY: they contain the token
# `goal_status` but are not attachments. A correct hook must ignore them.
mk_armed() {
  cat > "$D/t.jsonl" <<'EOF'
{"type":"user","message":{"role":"user","content":"how does goal_status work?"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"one goal_status attachment is written at arm time"}]}}
{"type":"attachment","timestamp":"2026-08-09T07:13:38Z","attachment":{"type":"goal_status","met":false,"sentinel":true,"condition":"land every leg of the migration"}}
EOF
  printf '%s' "$D/t.jsonl"
}

# PROSE ONLY — the token appears, no attachment does. This is M2's control.
mk_prose_only() {
  cat > "$D/t.jsonl" <<'EOF'
{"type":"user","message":{"role":"user","content":"explain goal_status and sentinel:true"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"a goal_status record with sentinel true and met false is the arm marker"}]}}
EOF
  printf '%s' "$D/t.jsonl"
}

# ARMED, then turns go by with no evaluation record — the shape arm 3b proves a skip from when the
# payload names no deferrer. The two decoys are load-bearing: a tool_result is also `type:"user"`
# but carries ARRAY content, and a system-injected turn carries isMeta. Neither means the session
# ever went idle, so neither may count as a turn. `$1` = how many REAL user turns to append.
mk_armed_stale() {
  mk_armed >/dev/null
  cat >> "$D/t.jsonl" <<'EOF'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"./slow.sh"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}
{"type":"user","message":{"role":"user","content":"<system-reminder>ignore me</system-reminder>"},"isMeta":true}
EOF
  i=0
  while [ "$i" -lt "${1:-2}" ]; do
    printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"working"}]}}' >> "$D/t.jsonl"
    printf '%s\n' '{"type":"user","message":{"role":"user","content":"still going?"}}' >> "$D/t.jsonl"
    i=$((i + 1))
  done
  printf '%s' "$D/t.jsonl"
}

payload() { # <transcript> <tasks-json> [sid]
  printf '{"session_id":"%s","transcript_path":"%s","hook_event_name":"Stop","background_tasks":%s}' \
    "${3:-s-$BATS_TEST_NUMBER}" "$1" "$2"
}
SHELL_TASK='[{"id":"b1","type":"shell","status":"running","command":"cc-await-ping --timeout 14400 --interval 15"}]'

# ── positive: the real-world shape ────────────────────────────────────────────────────────────────

@test "FIRES: armed goal + a running shell task (the cc-await-ping case)" {
  t="$(mk_armed)"
  run bash -c "printf '%s' '$(payload "$t" "$SHELL_TASK")' | '$H'"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  printf '%s' "$output" | jq -e '.systemMessage' >/dev/null
  printf '%s' "$output" | jq -r '.systemMessage' | grep -q "NOT BEING EVALUATED"
  printf '%s' "$output" | jq -r '.systemMessage' | grep -q "cc-await-ping"
}

@test "FIRES for subagent and workflow too (the other no-carve-out deferring types)" {
  t="$(mk_armed)"
  SUB_TASK='[{"id":"x","type":"subagent","status":"running","description":"research"}]'
  WF_TASK='[{"id":"y","type":"workflow","status":"running","description":"wave"}]'

  export CC_PAGE_DAMP_DIR="$D/damp-sub"
  run bash -c "printf '%s' '$(payload "$t" "$SUB_TASK" "s-sub")' | '$H'"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.systemMessage' >/dev/null

  export CC_PAGE_DAMP_DIR="$D/damp-wf"
  run bash -c "printf '%s' '$(payload "$t" "$WF_TASK" "s-wf")' | '$H'"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.systemMessage' >/dev/null
}

# ── the hook must be SILENT everywhere else ───────────────────────────────────────────────────────

@test "SILENT: armed goal but NO background work — nothing is deferring it" {
  t="$(mk_armed)"
  run bash -c "printf '%s' '$(payload "$t" '[]')' | '$H'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "SILENT: the goal IS evaluating — last record is a non-sentinel evaluation" {
  t="$(mk_armed)"
  cat >> "$t" <<'EOF'
{"type":"attachment","timestamp":"2026-08-09T07:20:00Z","attachment":{"type":"goal_status","met":false,"condition":"land every leg of the migration","iterations":1,"reason":"not yet"}}
EOF
  run bash -c "printf '%s' '$(payload "$t" "$SHELL_TASK")' | '$H'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "SILENT: the goal was CLEARED — sentinel with met:true is the clear marker, not an arm" {
  t="$(mk_armed)"
  cat >> "$t" <<'EOF'
{"type":"attachment","timestamp":"2026-08-09T07:30:00Z","attachment":{"type":"goal_status","met":true,"sentinel":true,"condition":"land every leg of the migration"}}
EOF
  run bash -c "printf '%s' '$(payload "$t" "$SHELL_TASK")' | '$H'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "SILENT: no goal in the transcript at all" {
  t="$(mk_prose_only)"
  run bash -c "printf '%s' '$(payload "$t" "$SHELL_TASK")' | '$H'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ABSTAINS on teammate / cloud session — CC's carve-outs are not in the payload" {
  # _We excludes in_process_teammate&&isIdle and remote_agent&&isLongRunning; cip() ships neither
  # flag, so we cannot reproduce CC's predicate for these two and must not guess.
  t="$(mk_armed)"
  run bash -c "printf '%s' '$(payload "$t" '[{"id":"x","type":"teammate","status":"running","description":"t"},{"id":"y","type":"cloud session","status":"running","description":"c"}]')' | '$H'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── arm 3b: the FOREGROUND-bash blind spot ────────────────────────────────────────────────────────
# CC's `cip()` filters `isBackgrounded === false` out of `background_tasks` (LR @283039039 in
# 2.1.231) but its deferral gate counts ANY non-terminal local_bash (vKo @290802207). So the payload
# can read EMPTY while a foreground bash holds the goal off. The hook cannot name such a task; what
# it can do is prove the skip happened, from turns elapsed with no evaluation record.

@test "FIRES BLIND: empty background_tasks, but the goal has gone unevaluated across 2 turns" {
  t="$(mk_armed_stale 2)"
  run bash -c "printf '%s' '$(payload "$t" '[]' "blind-2")' | '$H'"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  printf '%s' "$output" | jq -e '.systemMessage' >/dev/null
  printf '%s' "$output" | jq -r '.systemMessage' | grep -q "NOT BEING EVALUATED"
  # it must say WHY it cannot name the culprit, and not invent one
  printf '%s' "$output" | jq -r '.systemMessage' | grep -q "FOREGROUND bash"
  printf '%s' "$output" | jq -r '.systemMessage' | grep -q "isBackgrounded"
}

@test "SILENT BLIND: ONE turn is not enough — an interrupted turn produces no Stop at all" {
  # The interrupt guard. A user message can appear with no Stop in between (Esc mid-turn), so a
  # single elapsed turn is not proof that an evaluation was skipped. Two is.
  t="$(mk_armed_stale 1)"
  run bash -c "printf '%s' '$(payload "$t" '[]' "blind-1")' | '$H'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "SILENT BLIND: tool_results and isMeta turns are not turns" {
  # mk_armed_stale 0 leaves exactly the two decoys after the sentinel and no real user message.
  # If either were counted this would reach the threshold and fire.
  t="$(mk_armed_stale 0)"
  [ "$(grep -c '"type":"user"' "$t")" -ge 3 ]   # the fixture really does carry both decoys…
  run bash -c "printf '%s' '$(payload "$t" '[]' "blind-0")' | '$H'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]                              # …yet zero of them count
}

@test "SILENT BLIND: a stale-looking transcript whose goal IS evaluating stays silent" {
  # Turns elapsed is only half of arm 3b — the evaluation record still overrides it. Without this,
  # arm 3b would nag every long session with a healthy goal.
  t="$(mk_armed_stale 3)"
  cat >> "$t" <<'EOF'
{"type":"attachment","timestamp":"2026-08-09T07:20:00Z","attachment":{"type":"goal_status","met":false,"condition":"land every leg of the migration","iterations":1,"reason":"not yet"}}
EOF
  run bash -c "printf '%s' '$(payload "$t" '[]' "blind-healthy")' | '$H'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "SILENT: a payload with NO background_tasks key at all is not a Stop payload" {
  # Arm 3b keys off an EMPTY list, so the key's presence is what now separates a Stop payload from
  # anything else. Without this check arm 3b would fire on every non-Stop event that ships a
  # transcript_path.
  t="$(mk_armed_stale 3)"
  run bash -c "printf '{\"session_id\":\"nokey\",\"transcript_path\":\"$t\",\"hook_event_name\":\"Stop\"}' | '$H'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "SILENT: a terminal-status task does not defer anything" {
  t="$(mk_armed)"
  run bash -c "printf '%s' '$(payload "$t" '[{"id":"b1","type":"shell","status":"completed","command":"echo hi"}]')' | '$H'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── it must never be able to hold a session open ──────────────────────────────────────────────────

@test "NEVER blocks: advisory systemMessage only, no decision field, always exit 0" {
  t="$(mk_armed)"
  run bash -c "printf '%s' '$(payload "$t" "$SHELL_TASK")' | '$H'"
  [ "$status" -eq 0 ]
  run bash -c "printf '%s' '$(payload "$t" "$SHELL_TASK")' | '$H' | jq -r 'keys[]'"
  # damped on this second call ⇒ empty; either way the one key it can ever emit is systemMessage
  for k in $output; do [ "$k" = "systemMessage" ]; done
}

@test "degrades quietly on a malformed / non-Stop payload" {
  for p in '' 'not json' '{}' '{"transcript_path":"/nonexistent/nope.jsonl"}'; do
    run bash -c "printf '%s' '$p' | '$H'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}

@test "damped: the same live condition does not re-page every Stop" {
  t="$(mk_armed)"; p="$(payload "$t" "$SHELL_TASK" "damp-sid")"
  run bash -c "printf '%s' '$p' | '$H'"
  [ -n "$output" ]
  run bash -c "printf '%s' '$p' | '$H'"
  [ -z "$output" ]
}

# ── MUTATION CHECKS — each must FLIP a positive test above ────────────────────────────────────────

@test "MUTATION M1: keying on the RAW type name (local_bash) makes the fire case silent" {
  t="$(mk_armed)"
  m="$D/mutant1.sh"
  # Neuter exactly one thing: the display-name literal the payload actually carries.
  sed 's/"shell","subagent","workflow"/"local_bash","subagent","workflow"/' "$H" > "$m"
  chmod +x "$m"
  # the mutation must actually have applied — a no-op sed would pass this test vacuously
  grep -q '"local_bash"' "$m"
  ! grep -q '"shell","subagent"' "$m" || false
  export CC_PAGE_DAMP_DIR="$D/damp-m1"
  run bash -c "printf '%s' '$(payload "$t" "$SHELL_TASK" "m1")' | '$m'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]      # ← the whole point: the raw name matches nothing, hook goes blind
}

@test "MUTATION M2: dropping the sentinel test makes the hook fire on a HEALTHY goal" {
  # The sentinel/met discrimination is what separates "armed, never evaluated" from "evaluating
  # normally". Neuter it and the hook nags every session whose goal is working perfectly — the
  # always-fires polarity defect (memory alarm-polarity-and-attention-budget), which trains the
  # operator to ignore it and is strictly worse than not shipping the hook.
  t="$(mk_armed)"
  cat >> "$t" <<'EOF'
{"type":"attachment","timestamp":"2026-08-09T07:20:00Z","attachment":{"type":"goal_status","met":false,"condition":"land every leg of the migration","iterations":1,"reason":"not yet"}}
EOF
  # control: the real hook is silent on this transcript (same assertion as the SILENT test above)
  export CC_PAGE_DAMP_DIR="$D/damp-m2c"
  run bash -c "printf '%s' '$(payload "$t" "$SHELL_TASK" "m2-control")' | '$H'"
  [ -z "$output" ]

  m="$D/mutant2.sh"
  sed 's/\[ "\$IS_SENTINEL" = "true" \] && //' "$H" > "$m"
  chmod +x "$m"
  grep -q 'IS_SENTINEL' "$m"                                  # variable still assigned…
  ! grep -q '\[ "$IS_SENTINEL" = "true" \] &&' "$m" || false  # …but no longer gates the fire
  export CC_PAGE_DAMP_DIR="$D/damp-m2m"
  run bash -c "printf '%s' '$(payload "$t" "$SHELL_TASK" "m2-mutant")' | '$m'"
  [ "$status" -eq 0 ]
  [ -n "$output" ]      # ← flipped: the mutant nags a goal that is evaluating fine
}

@test "MUTATION M3: treating an EMPTY background_tasks as all-clear re-blinds the foreground case" {
  # The pre-2026-08-14 behaviour, restored as a one-line mutation: abstain the moment the payload
  # names no deferrer. That is precisely the false all-clear — the deferring set is a SUPERSET of
  # the reportable set, so "nothing reportable" never meant "nothing deferring".
  t="$(mk_armed_stale 2)"

  # control: the real hook FIRES on this transcript (same assertion as the arm-3b test above)
  export CC_PAGE_DAMP_DIR="$D/damp-m3c"
  run bash -c "printf '%s' '$(payload "$t" '[]' "m3-control")' | '$H'"
  [ -n "$output" ]

  m="$D/mutant3.sh"
  sed 's/^GI_ARM=named$/GI_ARM=named; [ -n "$DEFERRERS" ] || _gi_abstain/' "$H" > "$m"
  chmod +x "$m"
  grep -q 'GI_ARM=named; \[ -n "$DEFERRERS" \]' "$m"   # the mutation really applied
  export CC_PAGE_DAMP_DIR="$D/damp-m3m"
  run bash -c "printf '%s' '$(payload "$t" '[]' "m3-mutant")' | '$m'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]      # ← flipped: blind again, exactly as it was before the fix
}

@test "the prose-only fixture really does carry the trap (a bare grep WOULD match it)" {
  # Guards the SILENT-no-goal test from passing vacuously on a fixture that never contained the
  # decoy. This is the exact mistake that returned 6 hits where the truth was 1.
  t="$(mk_prose_only)"
  [ "$(grep -c 'goal_status' "$t")" -ge 2 ]
  # …yet zero of those lines are attachments, which is why the hook stays silent.
  [ "$(jq -rc --slurp '[ .[] | select(.type=="attachment") ] | length' < "$t")" -eq 0 ]
}
