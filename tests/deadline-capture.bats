#!/usr/bin/env bats
# hooks/lib/deadline-capture.sh (C2 queue + C2b narrow block), driven through its real host,
# hooks/dispatch-assert.sh. Hermetic: HOME, DL_DIR, the personal root, the latch dir and the fired
# stamp store are temp dirs, and every snippet is synthetic. Acceptance A12 (DESIGN §7) is the
# spine: the fixture deferral blocks ONCE; only a dl event stamped with THIS session discharges it;
# a dl event from another session and an unrelated backlog event do not.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/dispatch-assert.sh"
  DL="$REPO/bin/dl"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export DL_DIR="$BATS_TEST_TMPDIR/personal/deadlines"
  export DL_PERSONAL_ROOT="$BATS_TEST_TMPDIR/personal"
  export DL_CAPTURE_STATE_DIR="$BATS_TEST_TMPDIR/capstate"
  export DL_TODAY=2026-09-30
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/fired"
  export CC_PANE_ID="pane-fixture"
  export DISPATCH_ASSERT_STATE_DIR="$BATS_TEST_TMPDIR/dastate"
  export DISPATCH_ASSERT_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/registry"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
  export CC_BACKLOG_KICK=off CC_BACKLOG_PROJECT_WARN=off
  export CC_BACKLOG_KICK_BIN="$BATS_TEST_TMPDIR/no-such-dispatch"
  export CLAUDE_CODE_ENTRYPOINT=cli
  unset CC_DEADLINE_CAPTURE ITERM_SESSION_ID
  mkdir -p "$DL_DIR" "$DL_PERSONAL_ROOT/notes" "$CC_REGISTRY_DIR" "$CC_DECISIONS_DIR" "$CC_FIRED_DIR"
  : > "$CC_BACKLOG_FILE"
  PERSONAL="$DL_PERSONAL_ROOT/notes"
  ELSEWHERE="$BATS_TEST_TMPDIR/work"; mkdir -p "$ELSEWHERE"
  # The turn starts a minute ago, so an event this test writes NOW is "since the turn began".
  T_USER="$(date -u -v-1M +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || date -u -d '-1 min' +%Y-%m-%dT%H:%M:%S.000Z)"
}

DEFER="Sounds good — we'll bring this up once it's time."

mktx() { # <assistant text> [entrypoint] → transcript path
  local p="$BATS_TEST_TMPDIR/tx-$RANDOM.jsonl" ep="${2:-cli}"
  {
    jq -nc --arg ts "$T_USER" --arg ep "$ep" '{type:"user",timestamp:$ts,entrypoint:$ep,message:{content:"plan it"}}'
    jq -nc --arg ts "$T_USER" --arg ep "$ep" --arg t "$1" \
      '{type:"assistant",timestamp:$ts,entrypoint:$ep,message:{content:[{type:"text",text:$t}]}}'
  } > "$p"
  printf '%s' "$p"
}
stop() { # <transcript> <cwd> [sid]
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s"}' "${3:-sid-A}" "$1" "$2" | "$HOOK"
}
blocked() { printf '%s' "$1" | grep -q '"decision":"block"' && printf '%s' "$1" | grep -q 'You deferred'; }
queued() { [ -s "$DL_DIR/.state/capture-queue.jsonl" ] && grep -c . "$DL_DIR/.state/capture-queue.jsonl"; }

@test "A12: the fixture deferral in a personal cwd is blocked ONCE, and queued" {
  tx="$(mktx "$DEFER")"
  run stop "$tx" "$PERSONAL"
  [ "$status" -eq 0 ]; blocked "$output"
  [[ "$output" == *"dl park --resurface"* ]]
  [[ "$output" == *"dl skip --why"* ]]
  [ "$(jq -r .arm "$DL_DIR/.state/capture-queue.jsonl")" = b ]
  [ "$(jq -r .session_id "$DL_DIR/.state/capture-queue.jsonl")" = sid-A ]
  run stop "$tx" "$PERSONAL"
  [ "$status" -eq 0 ]; ! blocked "$output"
  [ "$(queued)" = 1 ]    # the second Stop of the same turn does not re-queue
}

@test "A12: a dl park stamped with THIS session's id discharges the block" {
  CLAUDE_CODE_SESSION_ID=sid-A "$DL" park --resurface 2026-10-20 --snippet "bring this up" >/dev/null
  run stop "$(mktx "$DEFER")" "$PERSONAL"
  [ "$status" -eq 0 ]; ! blocked "$output"
  [ "$(queued)" = 1 ]    # discharge stops the block, never the queue
}

@test "A12: a dl add from this session discharges; the same add from ANOTHER session does not" {
  CLAUDE_CODE_SESSION_ID=sid-OTHER "$DL" add "Pay the storage balance" --kind soft --lost 2026-10-20 \
    --class money --usd 100 --text "late fee of 100" --source operator --domain money >/dev/null
  run stop "$(mktx "$DEFER")" "$PERSONAL"
  blocked "$output"
  CLAUDE_CODE_SESSION_ID=sid-B "$DL" add "Pay the parking permit" --kind soft --lost 2026-10-21 \
    --class money --usd 100 --text "late fee of 100" --source operator --domain money >/dev/null
  run stop "$(mktx "$DEFER")" "$PERSONAL" sid-B
  ! blocked "$output"
}

@test "A12: an unrelated backlog event does not discharge (dispatch-assert's any-session arm is not used)" {
  "$REPO/bin/cc-backlog" add --title "unrelated chore" --project fixture >/dev/null 2>&1
  [ -s "$CC_BACKLOG_FILE" ]
  run stop "$(mktx "$DEFER")" "$PERSONAL"
  blocked "$output"
}

@test "arm a: a cued date inside 60 days blocks anywhere; a far date only queues" {
  run stop "$(mktx "File the FBAR by Oct 15 or the penalty applies.")" "$ELSEWHERE"
  blocked "$output"
  [[ "$output" == *"FBAR by Oct 15"* ]]
  run stop "$(mktx "The lease renews 2027-08-01, due then.")" "$ELSEWHERE" sid-far
  ! blocked "$output"
  [ "$(queued)" = 2 ]
}

@test "arm b outside a personal cwd blocks only beside life vocabulary" {
  run stop "$(mktx "Let's revisit the retry budget later.")" "$ELSEWHERE"
  ! blocked "$output"
  run stop "$(mktx "Let's revisit the insurance renewal later.")" "$ELSEWHERE" sid-life
  blocked "$output"
}

@test "exempt: kill switch, headless transcript, fired peer — nothing blocks" {
  CC_DEADLINE_CAPTURE=off run stop "$(mktx "$DEFER")" "$PERSONAL" sid-k
  ! blocked "$output"; [ ! -e "$DL_DIR/.state/capture-queue.jsonl" ]
  run stop "$(mktx "$DEFER" sdk-cli)" "$PERSONAL" sid-h
  ! blocked "$output"; [ ! -e "$DL_DIR/.state/capture-queue.jsonl" ]
  jq -nc --arg c "$PERSONAL" '{cwd:$c, marker:"HANDOFF-ENGAGE-fixture"}' > "$CC_FIRED_DIR/pane-fixture.json"
  run stop "$(mktx "$DEFER")" "$PERSONAL" sid-f
  ! blocked "$output"
  [ "$(queued)" = 1 ]    # a fired peer's hit is still queued; only the block is exempt
}

@test "positive control: the same fired-peer stamp for ANOTHER cwd does not exempt" {
  jq -nc --arg c "$ELSEWHERE" '{cwd:$c, marker:"HANDOFF-ENGAGE-fixture"}' > "$CC_FIRED_DIR/pane-fixture.json"
  run stop "$(mktx "$DEFER")" "$PERSONAL" sid-pc
  blocked "$output"
}

@test "NAME_TELL is untouched: a naming tell alone still gets dispatch-assert's block" {
  run stop "$(mktx "The inbox guard deserves its own scoped pass.")" "$ELSEWHERE" sid-n
  [[ "$output" == *"Dispatch-assert"* ]]
  ! blocked "$output"
}

@test "a turn with both: capture blocks first, NAME_TELL fires at the next Stop" {
  tx="$(mktx "We'll bring this up once it's time for the tax filing; the guard deserves its own scoped pass.")"
  run stop "$tx" "$ELSEWHERE" sid-both
  blocked "$output"
  run stop "$tx" "$ELSEWHERE" sid-both
  [[ "$output" == *"Dispatch-assert"* ]]
}
