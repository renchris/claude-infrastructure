#!/usr/bin/env bats
# dispatch-assert.sh — Stop hook: narrated-not-dispatched follow-on work must become a durable
# record (backlog event | fired-pane registry row | decision packet) before the turn may close.
# Fire predicate: naming-tell ∧ no-queue-write-since-turn-start ∧ ¬kill-switch. Proves:
#   · FIRE on a naming-tell with zero records; block carries the exact enqueue commands
#   · discharge by EACH record type (backlog add / backlog block / registry mtime / decide packet)
#   · obligation survives the block's window reset ($SKEY.pending), re-fires, then caps + clears
#   · kill-switch and DISPATCH_ASSERT_DISABLE abstain; every fail path exits 0 silent
#   · fixture-parity: backlog events are written by the REAL cc-backlog, never hand-rolled JSON
#   · B-3: one IDL {fired|abstained} line per invocation

setup() {
  # Project labels in this suite are FIXTURES, not projects — and `cc-backlog add` now WARNS on an
  # explicit --project outside the dispatch set (df2b6a40a5dc), which bats folds into $output. Off
  # here because dispatchability is not this suite's subject; tests/cc-backlog-project-dispatch.bats
  # owns it, unfixtured, in both directions.
  export CC_BACKLOG_PROJECT_WARN=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/dispatch-assert.sh"
  BACKLOG="$REPO/bin/cc-backlog"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # hermetic: never touch the live ~/
  export DISPATCH_ASSERT_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export DISPATCH_ASSERT_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export DISPATCH_ASSERT_MAX=2
  export DISPATCH_ASSERT_MAX_TOTAL=6
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/registry"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
  # Fixturing $HOME above does NOT close the dispatch_kick seam that `cc-backlog add` fires: kick_bin()
  # tries `command -v cc-dispatch` FIRST, and PATH still points at the operator's live ~/.claude/bin.
  # Measured at 1 real `cc-dispatch --decide` spawn per run of this suite, journaling a TEST backlog's
  # decisions into the production IDL. Same seam that reddened tests/cc-dispatch.bats case (b).
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/.dispatch-kick"
  export CC_BACKLOG_KICK_BIN="$BATS_TEST_TMPDIR/no-such-dispatch"
  mkdir -p "$CC_REGISTRY_DIR" "$CC_DECISIONS_DIR"
  : > "$CC_BACKLOG_FILE"
}

# Fixture times: the turn starts at T_USER; records at/after it are "this turn".
T_USER="2026-07-25T10:00:00.000Z"
T_ASST="2026-07-25T10:00:05.000Z"
T_LATER="2026-07-25T10:00:09.000Z"

# mktx <assistant-text> [path] → transcript: genuine user turn, then one assistant text.
mktx() {
  local text="$1" path="${2:-$BATS_TEST_TMPDIR/tx-${BATS_TEST_NUMBER}-$RANDOM.jsonl}"
  {
    jq -nc --arg ts "$T_USER" '{type:"user",timestamp:$ts,message:{content:"do the task"}}'
    jq -nc --arg ts "$T_ASST" --arg t "$text" \
      '{type:"assistant",timestamp:$ts,message:{content:[{type:"text",text:$t}]}}'
  } > "$path"
  printf '%s' "$path"
}

run_da() { # $1=transcript $2=sid
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s"}' \
    "${2:-sid-$BATS_TEST_NUMBER}" "$1" "$BATS_TEST_TMPDIR" | "$HOOK"
}
fired() { printf '%s' "$1" | grep -q '"decision":"block"'; }

TELL="The cc-inbox-guard cost profile deserves its own scoped pass — 52.8s of every sweep."

# ── the live instance: naming-tell + zero records ⇒ FIRE with the enqueue commands ──
@test "naming-tell with no durable record ⇒ FIRE; reason names cc-backlog add / block / cc-decide" {
  run run_da "$(mktx "$TELL")"
  [ "$status" -eq 0 ]; fired "$output"
  printf '%s' "$output" | grep -q 'cc-backlog add --title'
  printf '%s' "$output" | grep -q -- '--needs'
  printf '%s' "$output" | grep -q 'cc-decide open'
  grep -q '"disposition":"fired","reason":"narrated-not-dispatched"' "$DISPATCH_ASSERT_IDL"
}

@test "a spread of naming idioms all FIRE (worth a separate pass / park this for / follow-up task / should be backlogged)" {
  local tells=(
    "That refactor is worth a separate pass once this lands."
    "I am parking this for the next session to pick up."
    "The flaky retry is a follow-up task we identified."
    "The stale goldens should be backlogged."
  )
  local i=0
  for t in "${tells[@]}"; do
    i=$((i+1))
    rm -rf "$DISPATCH_ASSERT_STATE_DIR"
    run run_da "$(mktx "$t")" "spread-$i"
    [ "$status" -eq 0 ]
    if ! fired "$output"; then echo "idiom #$i DID NOT FIRE: $t" >&2; false; fi
  done
}

# ── no tell ⇒ silent ──
@test "plain close with no naming-tell ⇒ ABSTAIN silent" {
  run run_da "$(mktx "All three fixes are committed and the suite is green.")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  grep -q '"reason":"no-naming-tell"' "$DISPATCH_ASSERT_IDL"
}

# ── discharge by each record type (fixture-parity: REAL producers) ──
@test "naming-tell + REAL cc-backlog add this turn ⇒ ABSTAIN already-recorded" {
  "$BACKLOG" add --title "inbox-guard scoped pass" --project claude-infrastructure >/dev/null
  run run_da "$(mktx "$TELL")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  grep -q '"reason":"already-recorded"' "$DISPATCH_ASSERT_IDL"
}

@test "naming-tell + cc-backlog block --needs (operator park) ⇒ ABSTAIN (block IS a legitimate record)" {
  local id; id="$("$BACKLOG" add --title "guard pass" --project x)"
  "$BACKLOG" block "$id" --needs "operator: rotate the key" >/dev/null
  run run_da "$(mktx "$TELL")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "naming-tell + fresh cc-registry row (a real fire) ⇒ ABSTAIN" {
  printf '{"pane":"X"}\n' > "$CC_REGISTRY_DIR/deadbeef.json"   # mtime = now ≥ turn-start
  run run_da "$(mktx "$TELL")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "naming-tell + decision packet created this turn ⇒ ABSTAIN" {
  jq -nc --arg c "$T_LATER" '{id:"d1",class:"C",status:"open",created:$c,what_plain:"call it"}' \
    > "$CC_DECISIONS_DIR/d1.json"
  run run_da "$(mktx "$TELL")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "a worker's own claim RE-KEY does NOT discharge (a SessionStart hook wrote it, not the model)" {
  # `cc-backlog reclaim` (worker-keyed claims, backlog a13fb1d41044) is written by session-register.sh
  # at SessionStart, so it is not evidence that identified work was enqueued. A /compact or resume
  # mid-turn re-fires SessionStart, and counting its record would discharge this obligation with one
  # the model never authored — satisfying the guard without doing the thing it guards.
  local id; id="$("$BACKLOG" add --title "reclaim discharge" --project x)"
  "$BACKLOG" claim "$id" --by "host-1" >/dev/null
  : > "$CC_BACKLOG_FILE"                       # drop the add/claim: only the re-key is in the window
  jq -nc --arg t "$T_LATER" --arg i "$id" '{id:$i,ts:$t,event:"claim",by:"host-2",reclaim:true}' \
    > "$CC_BACKLOG_FILE"
  run run_da "$(mktx "$TELL")"
  [ "$status" -eq 0 ]; fired "$output"
}

@test "a NON-reclaim claim in the window still discharges (the exclusion must be narrow)" {
  # The positive control: only `reclaim:true` is excluded. An ordinary claim is a real ledger
  # engagement and must keep discharging, or the exclusion would have silently disabled path (1).
  jq -nc --arg t "$T_LATER" '{id:"c1",ts:$t,event:"claim",by:"host-2"}' > "$CC_BACKLOG_FILE"
  run run_da "$(mktx "$TELL")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "a backlog event from BEFORE the turn does NOT discharge (stale record ≠ this naming)" {
  jq -nc '{id:"old1",ts:"2026-07-25T09:00:00Z",event:"add",project:"x",title:"old"}' \
    > "$CC_BACKLOG_FILE"
  run run_da "$(mktx "$TELL")"
  [ "$status" -eq 0 ]; fired "$output"
}

# ── the obligation survives the block's own window reset ──
@test "after a FIRE, the next Stop re-fires from the STORED turn-start (window reset immune), then discharge clears" {
  local tx; tx="$(mktx "$TELL")"
  run run_da "$tx" ob1; fired "$output"
  # the block reason re-enters as a NEW user turn; the tell is now outside the fresh window
  jq -nc '{type:"user",timestamp:"2026-07-25T10:01:00.000Z",message:{content:"hook: make it durable"}}' >> "$tx"
  jq -nc '{type:"assistant",timestamp:"2026-07-25T10:01:05.000Z",message:{content:[{type:"text",text:"Noted."}]}}' >> "$tx"
  run run_da "$tx" ob1
  [ "$status" -eq 0 ]; fired "$output"
  printf '%s' "$output" | grep -q 're-check 2/2'
  # now the model actually enqueues → discharged, pending cleared, close allowed
  "$BACKLOG" add --title "the named pass" --project x >/dev/null
  run run_da "$tx" ob1
  [ "$status" -eq 0 ]; [ -z "$output" ]
  grep -q '"reason":"discharged"' "$DISPATCH_ASSERT_IDL"
  [ ! -f "$DISPATCH_ASSERT_STATE_DIR"/*.pending ] 2>/dev/null || true
}

@test "undischarged obligation CAPS at DISPATCH_ASSERT_MAX and then allows the close (never a wedge)" {
  local tx; tx="$(mktx "$TELL")"
  run run_da "$tx" cap1; fired "$output"          # fire 1 (count=1)
  run run_da "$tx" cap1; fired "$output"          # re-check (count=2 == MAX)
  run run_da "$tx" cap1                            # capped → abstain + clear
  [ "$status" -eq 0 ]; [ -z "$output" ]
  grep -q '"reason":"capped:2>=2"' "$DISPATCH_ASSERT_IDL"
  run run_da "$tx" cap1                            # pending cleared; same window has the tell…
  fired "$output"                                  # …fresh cycle is allowed to start (by design)
}

# ── kill-switch + disable ──
@test "operator kill-phrase ('just do X') ⇒ ABSTAIN even with a naming-tell" {
  local tx="$BATS_TEST_TMPDIR/tx-kill.jsonl"
  {
    jq -nc --arg ts "$T_USER" '{type:"user",timestamp:$ts,message:{content:"just do the rename and nothing else"}}'
    jq -nc --arg ts "$T_ASST" --arg t "$TELL" \
      '{type:"assistant",timestamp:$ts,message:{content:[{type:"text",text:$t}]}}'
  } > "$tx"
  run run_da "$tx"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  grep -q '"reason":"kill-switch"' "$DISPATCH_ASSERT_IDL"
}

@test "kill-phrase clears a live pending obligation" {
  local tx; tx="$(mktx "$TELL")"
  run run_da "$tx" kp1; fired "$output"
  jq -nc '{type:"user",timestamp:"2026-07-25T10:02:00.000Z",message:{content:"leave it, stop here"}}' >> "$tx"
  run run_da "$tx" kp1
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "DISPATCH_ASSERT_DISABLE=1 ⇒ silent abstain" {
  DISPATCH_ASSERT_DISABLE=1 run run_da "$(mktx "$TELL")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── window mechanics ──
@test "tell in an EARLY assistant text still fires when later texts are clean (mid-grind identification)" {
  local tx="$BATS_TEST_TMPDIR/tx-mid.jsonl"
  {
    jq -nc --arg ts "$T_USER" '{type:"user",timestamp:$ts,message:{content:"go"}}'
    jq -nc --arg ts "$T_ASST" --arg t "$TELL" \
      '{type:"assistant",timestamp:$ts,message:{content:[{type:"text",text:$t}]}}'
    jq -nc '{type:"user",timestamp:"2026-07-25T10:00:06.000Z",message:{content:[{type:"tool_result",content:"ok"}]}}'
    jq -nc --arg ts "$T_LATER" \
      '{type:"assistant",timestamp:$ts,message:{content:[{type:"text",text:"Committed and green."}]}}'
  } > "$tx"
  run run_da "$tx"
  [ "$status" -eq 0 ]; fired "$output"
}

@test "tell from a PREVIOUS turn (before the last genuine user message) does NOT fire" {
  local tx="$BATS_TEST_TMPDIR/tx-prev.jsonl"
  {
    jq -nc '{type:"user",timestamp:"2026-07-25T09:00:00.000Z",message:{content:"first ask"}}'
    jq -nc --arg t "$TELL" '{type:"assistant",timestamp:"2026-07-25T09:00:05.000Z",message:{content:[{type:"text",text:$t}]}}'
    jq -nc --arg ts "$T_USER" '{type:"user",timestamp:$ts,message:{content:"different second ask"}}'
    jq -nc --arg ts "$T_ASST" '{type:"assistant",timestamp:$ts,message:{content:[{type:"text",text:"Renamed the flag, committed."}]}}'
  } > "$tx"
  run run_da "$tx"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "sidechain (subagent) text never fires the matcher" {
  local tx="$BATS_TEST_TMPDIR/tx-side.jsonl"
  {
    jq -nc --arg ts "$T_USER" '{type:"user",timestamp:$ts,message:{content:"go"}}'
    jq -nc --arg ts "$T_ASST" --arg t "$TELL" \
      '{type:"assistant",isSidechain:true,timestamp:$ts,message:{content:[{type:"text",text:$t}]}}'
    jq -nc --arg ts "$T_LATER" \
      '{type:"assistant",timestamp:$ts,message:{content:[{type:"text",text:"Done and committed."}]}}'
  } > "$tx"
  run run_da "$tx"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── fail-open safety ──
@test "missing transcript ⇒ exit 0 silent abstain" {
  printf '{"session_id":"s","transcript_path":"/nonexistent/t.jsonl","cwd":"/tmp"}' | "$HOOK"
}

@test "empty stdin ⇒ exit 0 silent" {
  printf '' | "$HOOK"
}

@test "B-3: exactly one IDL line per invocation" {
  run run_da "$(mktx "All committed, suite green.")"
  run run_da "$(mktx "$TELL")"
  [ "$(grep -c '"hook":"dispatch-assert"' "$DISPATCH_ASSERT_IDL")" -eq 2 ]
}

# ── DROP is a discharging disposition (backlog-zero W2a) ──────────────────────────────────────────
# WHY. Before this arm every remedy the gate offered WROTE a row — (a) fire, (b) add, (c) add+block,
# (d) decide — and discharged_since() could only see a written artifact, so "not worth doing" had no
# expressible form and the only way out was to eat blocks to the cap. Measured 2026-09-04: 131 fires
# in 14 days, the largest single producer of the live ad-hoc pile
# (docs/research/backlog-zero-2026-09-04/inflow.md §3, §5.1). A dropped item leaves no artifact BY
# CONSTRUCTION, so the model's own sentence is the only evidence there can be.

@test "a naming-tell whose turn also DROPS it ⇒ ABSTAIN (a dropped item needs no record)" {
  run run_da "$(mktx "$TELL Actually, dropping it: the sweep is 52.8s once a day and nobody waits on it.")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  # a DROP is not a RECORD: the IDL must be able to count the rows this arm prevents
  grep -q '"reason":"dropped"' "$DISPATCH_ASSERT_IDL"
  [ "$(grep -c '"reason":"already-recorded"' "$DISPATCH_ASSERT_IDL")" -eq 0 ]
}

@test "each drop idiom discharges (dropping / not worth / letting it go)" {
  local drops=(
    "dropping it: the cost is one sweep a day."
    "On reflection this is not worth doing — the caller is gone."
    "I am letting this go rather than filing it."
  )
  local i=0
  for d in "${drops[@]}"; do
    i=$((i+1))
    rm -rf "$DISPATCH_ASSERT_STATE_DIR"; : > "$CC_BACKLOG_FILE"
    run run_da "$(mktx "$TELL $d")" "drop-$i"
    [ "$status" -eq 0 ]
    if [ -n "$output" ]; then echo "drop idiom #$i STILL FIRED: $d" >&2; false; fi
  done
}

@test "a LIVE pending obligation is discharged by a drop stated on the re-check turn" {
  local tx; tx="$(mktx "$TELL")"
  run run_da "$tx" drp1; fired "$output"
  jq -nc '{type:"user",timestamp:"2026-07-25T10:01:00.000Z",message:{content:"hook: make it durable"}}' >> "$tx"
  jq -nc '{type:"assistant",timestamp:"2026-07-25T10:01:05.000Z",message:{content:[{type:"text",text:"Dropping the scoped pass: it costs more to track than to redo."}]}}' >> "$tx"
  run run_da "$tx" drp1
  [ "$status" -eq 0 ]; [ -z "$output" ]
  grep -q '"reason":"dropped"' "$DISPATCH_ASSERT_IDL"
}

@test "CONTROL — the drop matcher does not swallow an ordinary close (no drop phrase ⇒ still FIRES)" {
  run run_da "$(mktx "$TELL I will pick it up next time.")"
  [ "$status" -eq 0 ]; fired "$output"
}

@test "the remedy text offers DROP and no longer templates a per-session --source" {
  run run_da "$(mktx "$TELL")"
  fired "$output"
  printf '%s' "$output" | grep -q 'NOT WORTH DOING'
  printf '%s' "$output" | grep -q -- '--condition'
  [ "$(printf '%s' "$output" | grep -c -- '--source \\"sid-')" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c -- '--source \\"\$SID')" -eq 0 ]
}

@test "the RE-CHECK remedy text also offers DROP and templates --condition" {
  local tx; tx="$(mktx "$TELL")"
  run run_da "$tx" rc1; fired "$output"
  jq -nc '{type:"user",timestamp:"2026-07-25T10:01:00.000Z",message:{content:"hook: make it durable"}}' >> "$tx"
  jq -nc '{type:"assistant",timestamp:"2026-07-25T10:01:05.000Z",message:{content:[{type:"text",text:"Noted."}]}}' >> "$tx"
  run run_da "$tx" rc1
  fired "$output"
  printf '%s' "$output" | grep -q 're-check 2/2'
  printf '%s' "$output" | grep -q 'NOT WORTH DOING'
  printf '%s' "$output" | grep -q -- '--condition'
  [ "$(printf '%s' "$output" | grep -c -- '--source \\"sid-')" -eq 0 ]
}
