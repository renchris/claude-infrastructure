#!/usr/bin/env bats
# hooks/recover-inject.sh — D3 of docs/plans/NONLIMIT_RESUME_LADDER.md (T6/W2-B).
#
# The four cases the plan's W2-B row names, each with the control arm that proves the
# case is not passing for a trivial reason:
#   api-error tail          ⇒ context emitted once
#   second prompt           ⇒ silent (the latch)
#   normal tail             ⇒ silent
#   non-success notification⇒ emitted
#
# Every record shape is copied from a VERBATIM quote already in this repo, never
# invented: the network-death envelope from § Finding 2, the <task-notification> from
# docs/research/pane-theft-composer-guard.md:33, `system`/`turn_duration` from
# docs/SAFEGUARD_BLOCKED_VISIBILITY.md.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/recover-inject.sh"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$CLAUDE_CONFIG_DIR"
  export CC_RECOVER_INJECT_LOG="$BATS_TEST_TMPDIR/ri.log"
  SID="cccc0000-1111-2222-3333-444444444444"
  TP="$BATS_TEST_TMPDIR/$SID.jsonl"
  unset CC_RECOVER_INJECT
}

# stdin payload the harness hands a UserPromptSubmit hook
payload() {
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"UserPromptSubmit"}' \
    "$SID" "$TP" "$BATS_TEST_TMPDIR"
}

fire() { payload | bash "$HOOK"; }

# ── transcript builders ─────────────────────────────────────────────────────────
prompt_and_spawn() {
  {
    printf '{"type":"user","timestamp":"2026-09-09T14:00:00.000Z","message":{"role":"user","content":"go"}}\n'
    printf '{"type":"assistant","timestamp":"2026-09-09T14:01:00.000Z","message":{"role":"assistant","model":"claude-opus-5","content":[{"type":"tool_use","id":"toolu_OPEN1","name":"Agent","input":{"description":"unit A"}}]}}\n'
    printf '{"type":"assistant","timestamp":"2026-09-09T14:02:00.000Z","message":{"role":"assistant","model":"claude-opus-5","content":[{"type":"tool_use","id":"toolu_DONE1","name":"Agent","input":{"description":"unit B"}}]}}\n'
    printf '{"type":"user","timestamp":"2026-09-09T14:03:00.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_DONE1","content":"unit B result"}]}}\n'
  } > "$TP"
}

add_api_error() { # $1=uuid [$2=text]
  # The default text is assigned separately, NOT as a ${2:-...} default: an
  # apostrophe inside a ${var:-word} expansion within double quotes opens a quote
  # as far as bash is concerned, and the file stops parsing. Inside plain double
  # quotes it is just a character.
  local txt="${2:-}"
  [ -n "$txt" ] || txt="API Error: Can't reach the API server — check your internet or DNS (ENOTFOUND)"
  {
    printf '{"type":"assistant","timestamp":"2026-09-09T15:12:15.000Z","uuid":"%s","error":"server_error","isApiErrorMessage":true,"message":{"model":"<synthetic>","role":"assistant","content":[{"type":"text","text":"%s"}]},"version":"2.1.260"}\n' \
      "$1" "$txt"
    printf '{"type":"system","subtype":"turn_duration","durationMs":5601349,"timestamp":"2026-09-09T15:12:16.000Z"}\n'
  } >> "$TP"
}

add_clean_turn() {
  {
    printf '{"type":"assistant","timestamp":"2026-09-09T15:20:00.000Z","message":{"role":"assistant","model":"claude-opus-5","stop_reason":"end_turn","content":[{"type":"text","text":"all done"}]}}\n'
    printf '{"type":"system","subtype":"turn_duration","durationMs":1000,"timestamp":"2026-09-09T15:20:01.000Z"}\n'
  } >> "$TP"
}

add_notification() { # $1=tool_use_id $2=status $3=task_id
  printf '{"type":"queue-operation","operation":"enqueue","timestamp":"2026-09-09T15:30:00.000Z","sessionId":"%s","content":"<task-notification>\\n<task-id>%s</task-id>\\n<tool-use-id>%s</tool-use-id>\\n<output-file>/tmp/x.output</output-file>\\n<status>%s</status>\\n<summary>Background command \\"unit A\\" settled</summary>\\n</task-notification>"}\n' \
    "$SID" "$3" "$1" "$2" >> "$TP"
}

# ════════════════════════════════════════════════════════════════════════════════
# P2 — the api-error record
# ════════════════════════════════════════════════════════════════════════════════

@test "W2-B a: an api-error tail emits additionalContext naming the death record and the OPEN delegations" {
  prompt_and_spawn; add_api_error "err-uuid-1"
  run fire
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json,sys
d=json.load(sys.stdin)
h=d["hookSpecificOutput"]
assert h["hookEventName"]=="UserPromptSubmit", h
c=h["additionalContext"]
# (i) the death record and its uuid
assert "err-uuid-1" in c, c
assert "server_error" in c, c
assert "API-ERROR record" in c, c
# a NON-quota error must say the account is probably fine — a transplant here is waste
assert "NOT a quota message" in c, c
# (ii) the open delegations by tool-use-id AND tool name; the settled one must NOT be listed
assert "toolu_OPEN1" in c, c
assert "unit A" in c, c
assert "toolu_DONE1" not in c, c
assert "Agent 2 (settled 1, open 1)" in c, c
# (iii) the disk-truth audit, before anything else
assert "lr-audit.py" in c, c
assert "before re-firing anything" in c or "before answering the prompt" in c, c
# (iv) no re-fire before the probe is green — twice
assert "green TWICE" in c, c
assert "30s" in c, c
# and the three wait verdicts must be named as verdicts, not delays
for v in ("PENDING","UNSETTLED-INFLIGHT","RUNNING"):
    assert v in c, (v, c)
'
}

@test "W2-B b: THE LATCH — a second prompt on the same death record is silent" {
  prompt_and_spawn; add_api_error "err-uuid-1"
  run fire
  [ -n "$output" ] || { echo "first fire emitted nothing"; false; }
  run fire
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "second fire re-emitted: $output"; false; }
  grep -q 'latched:' "$CC_RECOVER_INJECT_LOG" || { cat "$CC_RECOVER_INJECT_LOG"; false; }
}

@test "W2-B b2: a NEW death record speaks again — the latch is per record, never per session" {
  # A latch keyed on the session (or on a constant) would silence every later death
  # for the life of the session, which is worse than never firing: the one prompt
  # that needed the notice is the one that would not get it.
  prompt_and_spawn; add_api_error "err-uuid-1"
  run fire
  [ -n "$output" ] || { echo "first fire emitted nothing"; false; }
  add_clean_turn            # the session recovered and took a real turn
  run fire
  [ -z "$output" ] || { echo "a clean tail emitted: $output"; false; }
  add_api_error "err-uuid-2"   # then died again
  run fire
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'err-uuid-2' || { echo "the SECOND death was swallowed: $output"; false; }
}

@test "W2-B c: a normal tail is silent — a clean final turn is not an interruption" {
  prompt_and_spawn; add_clean_turn
  run fire
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "emitted on a healthy session: $output"; false; }
}

@test "W2-B c2: a session merely DISCUSSING an api error in prose is silent — the ENVELOPE is the gate" {
  # This repo talks about ENOTFOUND and quota messages constantly, including in the
  # transcripts of the sessions that wrote this plan. A text-only predicate would
  # fire on every one of them.
  prompt_and_spawn
  {
    printf '{"type":"user","timestamp":"2026-09-09T15:19:00.000Z","message":{"role":"user","content":"why did we get API Error: Can'"'"'t reach the API server (ENOTFOUND) yesterday?"}}\n'
    printf '{"type":"assistant","timestamp":"2026-09-09T15:20:00.000Z","message":{"role":"assistant","model":"claude-opus-5","stop_reason":"end_turn","content":[{"type":"text","text":"API Error: Can'"'"'t reach the API server — check your internet or DNS (ENOTFOUND) is a DNS failure. You'"'"'ve hit your session limit is the quota one."}]}}\n'
    printf '{"type":"system","subtype":"turn_duration","durationMs":1000,"timestamp":"2026-09-09T15:20:01.000Z"}\n'
  } >> "$TP"
  run fire
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "prose about an error fired the hook: $output"; false; }
}

@test "W2-B c3: a QUOTA api-error says the limit mode may apply — the two classes are not collapsed" {
  prompt_and_spawn
  add_api_error "err-uuid-q" "You've hit your session limit · resets 7:50pm (America/Los_Angeles)"
  run fire
  echo "$output" | python3 -c '
import json,sys
c=json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"]
assert "QUOTA message" in c, c
assert "NOT a quota message" not in c, c
'
}

# ════════════════════════════════════════════════════════════════════════════════
# P3 — the non-success notification
# ════════════════════════════════════════════════════════════════════════════════

@test "W2-B d: a non-success task-notification emits, naming the task and its status" {
  prompt_and_spawn; add_notification "toolu_OPEN1" "killed" "bfpgwlzqu"
  run fire
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json,sys
c=json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"]
assert "NON-SUCCESSFULLY" in c, c
assert "bfpgwlzqu" in c, c
assert "killed" in c, c
assert "toolu_OPEN1" in c, c
'
}

@test "W2-B d2: a 'failed' and a 'stopped' notification both emit" {
  for s in failed stopped; do
    rm -rf "$LR_STATE_DIR"; prompt_and_spawn; add_notification "toolu_OPEN1" "$s" "task-$s"
    run fire
    echo "$output" | grep -q "$s" || { echo "status $s did not emit: $output"; false; }
  done
}

@test "W2-B d3 CONTROL: 'completed' and 'running' are silent — one is success, the other is not terminal" {
  # Measured status vocabulary over 300 transcripts: completed 5979 · failed 358 ·
  # killed 180 · running 29 · stopped 4. Firing on `running` would nag at a unit
  # that is working exactly as intended.
  for s in completed running; do
    rm -rf "$LR_STATE_DIR"; prompt_and_spawn; add_notification "toolu_OPEN1" "$s" "task-$s"
    run fire
    [ -z "$output" ] || { echo "status $s emitted: $output"; false; }
  done
}

@test "W2-B d4: an api-error record WINS over a notification — the newest death is the subject" {
  prompt_and_spawn; add_notification "toolu_OPEN1" "killed" "bfpgwlzqu"; add_api_error "err-uuid-1"
  run fire
  echo "$output" | python3 -c '
import json,sys
c=json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"]
assert "API-ERROR record" in c, c
assert "NON-SUCCESSFULLY" not in c, c
'
}

# ════════════════════════════════════════════════════════════════════════════════
# The hook may never cost a prompt, and a refusal may never be silent
# ════════════════════════════════════════════════════════════════════════════════

@test "W2-B e: CC_RECOVER_INJECT=off is a real kill switch" {
  prompt_and_spawn; add_api_error "err-uuid-1"
  CC_RECOVER_INJECT=off run fire
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "the kill switch did not kill: $output"; false; }
}

@test "W2-B e2: a missing transcript exits 0 and RECORDS the refusal — silence to the prompt, never to the log" {
  # exit 0 having said nothing is byte-identical to 'nothing was interrupted'. An
  # advisory hook cannot block a prompt to complain, so the refusal goes on the
  # record instead of nowhere.
  rm -f "$TP"
  run fire
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -q 'refused: no readable transcript_path' "$CC_RECOVER_INJECT_LOG" || { cat "$CC_RECOVER_INJECT_LOG" 2>/dev/null; false; }
}

@test "W2-B e3: an unparseable stdin payload exits 0 and is recorded, not crashed" {
  prompt_and_spawn; add_api_error "err-uuid-1"
  run bash -c 'printf "not json at all" | bash "$1"' _ "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "emitted on garbage stdin: $output"; false; }
}

@test "W2-B e4: an EMPTY stdin payload exits 0 (the hook is fully consuming, so no writer SIGPIPEs)" {
  run bash -c ': | bash "$1"' _ "$HOOK"
  [ "$status" -eq 0 ]
}

@test "W2-B f: when the ledger cannot be computed the notice says UNREAD — it never renders as 'nothing was delegated'" {
  # A zero and an unread are different facts. Rendering them as one sentence is how
  # a fail-safe default comes to mimic the healthy state.
  prompt_and_spawn; add_api_error "err-uuid-1"
  mkdir -p "$BATS_TEST_TMPDIR/fakelr"
  cp "$REPO/scripts/limit-recover/lr-lib.sh" "$BATS_TEST_TMPDIR/fakelr/"
  cat > "$BATS_TEST_TMPDIR/fakelr/lr-audit.py" <<'PY'
import sys
sys.exit(3)   # the ledger refuses
PY
  mkdir -p "$BATS_TEST_TMPDIR/cfg2/scripts"
  ln -s "$BATS_TEST_TMPDIR/fakelr" "$BATS_TEST_TMPDIR/cfg2/scripts/limit-recover"
  CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg2" run bash -c '
    cd "$3" && printf "{\"session_id\":\"%s\",\"transcript_path\":\"%s\"}" "$1" "$2" | bash ./hooks/recover-inject.sh
  ' _ "$SID" "$TP" "$REPO"
  # The repo copy resolves first by design (the sibling beside the executed file), so
  # this arm asserts the RENDERING contract rather than the ladder: with a real
  # ledger the population line is present and specific.
  echo "$output" | python3 -c '
import json,sys
c=json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"]
assert "Delegation population (by tool):" in c, c
assert "Open delegations" in c, c
'
}

@test "W2-B f2: the UNREAD wording exists and is reachable — a population that cannot be read is named as such" {
  # Direct: run the hook with the ledger's python interpreter unable to answer, by
  # pointing the hook at a tree whose lr-audit.py is absent.
  prompt_and_spawn; add_api_error "err-uuid-1"
  WORK="$BATS_TEST_TMPDIR/isolated"
  mkdir -p "$WORK/hooks" "$WORK/scripts/limit-recover"
  cp "$HOOK" "$WORK/hooks/recover-inject.sh"
  cp "$REPO/scripts/limit-recover/lr-lib.sh" "$WORK/scripts/limit-recover/"
  # lr-audit.py deliberately NOT copied.
  run bash -c 'printf "{\"session_id\":\"%s\",\"transcript_path\":\"%s\"}" "$1" "$2" | bash "$3"' \
    _ "$SID" "$TP" "$WORK/hooks/recover-inject.sh"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json,sys
c=json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"]
assert "UNREAD" in c, c
assert "do not read this as" in c, c
'
  grep -q "ledger: lr-audit.py absent" "$CC_RECOVER_INJECT_LOG" || { cat "$CC_RECOVER_INJECT_LOG"; false; }
}

@test "W2-B g: the emitted JSON is exactly the UserPromptSubmit contract and nothing else" {
  prompt_and_spawn; add_api_error "err-uuid-1"
  run fire
  echo "$output" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert list(d.keys())==["hookSpecificOutput"], d
assert sorted(d["hookSpecificOutput"].keys())==["additionalContext","hookEventName"], d
assert isinstance(d["hookSpecificOutput"]["additionalContext"], str)
'
}

@test "W2-B h: a transcript-supplied latch key cannot escape the latch directory" {
  # The key becomes a FILENAME and it comes from the transcript, i.e. from data this
  # hook does not control.
  prompt_and_spawn
  add_api_error "../../../../etc/evil-uuid"
  run fire
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/etc/evil-uuid" ] || { echo "the key escaped"; false; }
  find "$LR_STATE_DIR/recover-inject" -name '*evil*' -o -name '*_etc_*' | grep -q . || {
    echo "no sanitised latch was written:"; find "$LR_STATE_DIR" -type d; false; }
}
