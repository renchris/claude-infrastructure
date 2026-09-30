#!/usr/bin/env bats
# The deadline store's two HUMAN-facing session surfaces (personal/deadlines/DESIGN-2026-09-29.md
# §4.4-4.5), fixtures only:
#   · hooks/accounts-board.sh prepends .state/banner.txt, gated (A3) and latched on (date, hash);
#     with banner.txt absent its output is byte-identical to trunk's hook (A13)
#   · hooks/operator-readout.sh adds `⏰ N due ≤72h — top: <title>` once per session
#   · bin/dl render produces both inputs (.state/banner.txt, .state/due72)

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  BOARD_HOOK="$REPO/hooks/accounts-board.sh"
  OR_HOOK="$REPO/hooks/operator-readout.sh"
  DL="$REPO/bin/dl"
  export D="$BATS_TEST_TMPDIR"
  export HOME="$D/home"; mkdir -p "$HOME"
  export DL_DIR="$D/personal/deadlines"; mkdir -p "$DL_DIR/.state"
  export CC_ACCOUNTS_BOARD="$D/board.txt"
  export CC_FIRED_DIR="$D/fired"; mkdir -p "$CC_FIRED_DIR"
  export CC_PANE_ID="pane-fixture"
  export CLAUDE_CODE_ENTRYPOINT=cli
  unset ITERM_SESSION_ID CC_DEADLINE_LINE
  WORK="$D/work"; mkdir -p "$WORK"
  printf 'Claude Max accounts · cached 12s\nZZBOARDPAYLOADZZ\n' > "$CC_ACCOUNTS_BOARD"
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
}

BANNER="⏰ Pay the fixture bill — tomorrow · Call the fixture clinic — 2d over"
board() { # [cwd] [source] → the hook's systemMessage on stdout
  printf '{"source":"%s","cwd":"%s","hook_event_name":"SessionStart"}' "${2:-startup}" "${1:-$WORK}" \
    | "$BOARD_HOOK" | jq -r '.systemMessage'
}
latch() { cat "$DL_DIR/.state/banner-latch" 2>/dev/null; }

# ── A3: banner gating ─────────────────────────────────────────────────────────────────────────────
@test "A3: sdk-cli emits no banner and leaves the latch untouched" {
  printf '%s\n' "$BANNER" > "$DL_DIR/.state/banner.txt"
  CLAUDE_CODE_ENTRYPOINT=sdk-cli run board
  [ "$status" -eq 0 ]
  [[ "$output" == *ZZBOARDPAYLOADZZ* ]] || false
  [[ "$output" != *"⏰"* ]] || false
  [ -z "$(latch)" ]
}

@test "A3: a fired-peer stamp emits nothing; the same stamp for another cwd does not exempt" {
  printf '%s\n' "$BANNER" > "$DL_DIR/.state/banner.txt"
  jq -nc --arg c "$WORK" '{cwd:$c, marker:"HANDOFF-ENGAGE-fixture"}' > "$CC_FIRED_DIR/pane-fixture.json"
  run board
  [[ "$output" != *"⏰"* ]] || false
  [ -z "$(latch)" ]
  jq -nc --arg c "$D" '{cwd:$c, marker:"HANDOFF-ENGAGE-fixture"}' > "$CC_FIRED_DIR/pane-fixture.json"
  run board
  [[ "$output" == *"⏰ Pay the fixture bill"* ]]
}

@test "A3: cli emits the banner above the board and writes the latch; same content is silent; a change re-emits" {
  printf '%s\n' "$BANNER" > "$DL_DIR/.state/banner.txt"
  run board
  [ "${lines[0]}" = "$BANNER" ]
  [[ "$output" == *ZZBOARDPAYLOADZZ* ]] || false
  [[ "$(latch)" == "$(date +%F) "* ]] || false
  run board
  [[ "$output" != *"⏰"* ]] || false
  [[ "$output" == *ZZBOARDPAYLOADZZ* ]] || false
  printf '%s\n' "⏰ Pay the fixture bill — today" > "$DL_DIR/.state/banner.txt"
  run board
  [ "${lines[0]}" = "⏰ Pay the fixture bill — today" ]
}

@test "A3: a cwd under /tmp, or unset entrypoint with -p in the parent's argv, emits nothing" {
  printf '%s\n' "$BANNER" > "$DL_DIR/.state/banner.txt"
  run board /tmp/some-fire
  [[ "$output" != *"⏰"* ]] || false
  [ -z "$(latch)" ]
  # the fallback discriminator: CLAUDE_CODE_ENTRYPOINT unset, parent argv carries -p
  run env -u CLAUDE_CODE_ENTRYPOINT bash -c 'printf "{\"source\":\"startup\",\"cwd\":\"%s\"}" "$1" | "$2" | jq -r .systemMessage; true' -p "$WORK" "$BOARD_HOOK"
  [[ "$output" != *"⏰"* ]]; [ -z "$(latch)" ]
}

@test "compact never shows the banner and never spends the latch" {
  printf '%s\n' "$BANNER" > "$DL_DIR/.state/banner.txt"
  run board "$WORK" compact
  [ -z "$output" ]; [ -z "$(latch)" ]
}

# ── A13: byte-identical without banner.txt ────────────────────────────────────────────────────────
@test "A13: with banner.txt absent the hook's stdout is byte-identical to the pre-change hook" {
  # The pre-change hook, replayed from a LITERAL sha (W1's last commit before this wave), and
  # proven to be pre-change by the marker the change introduced.
  git -C "$REPO" show 2792a2911:hooks/accounts-board.sh > "$D/before.sh"
  chmod +x "$D/before.sh"
  ! grep -q 'dl_banner' "$D/before.sh" || false
  for src in startup resume clear compact; do
    for state in fresh empty; do
      if [ "$state" = empty ]; then : > "$CC_ACCOUNTS_BOARD"; else printf 'board\nZZ\n' > "$CC_ACCOUNTS_BOARD"; fi
      in="$(printf '{"source":"%s","cwd":"%s"}' "$src" "$WORK")"
      a="$(printf '%s' "$in" | "$D/before.sh" | od -c)"
      b="$(printf '%s' "$in" | "$BOARD_HOOK" | od -c)"
      [ "$a" = "$b" ] || { echo "differs: $src/$state"; false; }
    done
  done
  rm -f "$CC_ACCOUNTS_BOARD"
  in="$(printf '{"source":"startup","cwd":"%s"}' "$WORK")"
  [ "$(printf '%s' "$in" | "$D/before.sh" | od -c)" = "$(printf '%s' "$in" | "$BOARD_HOOK" | od -c)" ]
}

# ── bin/dl render feeds both surfaces ────────────────────────────────────────────────────────────
@test "dl render writes banner.txt and due72 for a hot item, and removes both when nothing is hot" {
  export DL_TODAY=2020-09-29 DL_RULES_FILE="$D/rules.md"
  "$DL" add "Pay the fixture bill" --kind soft --lost 2020-09-30 --class money --usd 100 \
    --text "late fee of 100" --source operator --domain money >/dev/null
  "$DL" render >/dev/null
  [ "$(cat "$DL_DIR/.state/due72")" = "$(printf '1\tPay the fixture bill')" ]
  grep -q 'Pay the fixture bill' "$DL_DIR/.state/banner.txt"
  DL_TODAY=2020-09-01 "$DL" render >/dev/null
  [ ! -e "$DL_DIR/.state/due72" ]; [ ! -e "$DL_DIR/.state/banner.txt" ]
}

# ── the ⏰ close-block line (operator-readout) ───────────────────────────────────────────────────
or_env() {
  export CC_OPREADOUT_STATE_DIR="$D/orstate" CC_IDL="$D/idl.jsonl"
  export CC_ACTIVATION_DIR="$D/activation" CC_DECISIONS_DIR="$D/decisions"
  export CC_BACKLOG_FILE="$D/backlog.jsonl" CC_BACKLOG_BIN="$REPO/bin/cc-backlog"
  export CC_ORB_BLG_CACHE_DIR="$D/blg-cache" WRAP_LEDGER_BIN="$REPO/scripts/wrap-ledger.sh"
  export CC_SHARED_CHECKOUT="$D/no-such-checkout" CC_OPREADOUT_NOW=1000000 CC_OPREADOUT_TTL_S=900
  export CC_BACKLOG_KICK=off CC_BACKLOG_KICK_BIN="$D/no-such-dispatch"
  export CC_HANDOFF_ALARM_DIR="$D/ha" CC_ANNOUNCE_ALARM_DIR="$D/aa" CC_COMPLETION_RECORDS_DIR="$D/cp"
  export CC_PAGES_DIR="$D/pages" CC_MAILBOX_DIR="$D/mailbox" CC_SWEEP_SEEN_DIR="$D/seen"
  export CC_RESUME_DEBT_BIN=none LR_STATE_DIR="$D/lr" LR_RECON_ROOT="$D/lr/recon"
  mkdir -p "$CC_ACTIVATION_DIR" "$CC_DECISIONS_DIR" "$CC_HANDOFF_ALARM_DIR" "$CC_ANNOUNCE_ALARM_DIR" \
    "$CC_COMPLETION_RECORDS_DIR" "$CC_PAGES_DIR" "$CC_MAILBOX_DIR/dead-letter" "$CC_SWEEP_SEEN_DIR"
  : > "$CC_BACKLOG_FILE"
}
mk_or_tx() { # [entrypoint] → a transcript whose last record carries that entrypoint
  local p="$D/tx-$RANDOM.jsonl"
  jq -nc --arg ep "${1:-cli}" '{type:"assistant",entrypoint:$ep,message:{content:[{type:"text",text:"done"}]}}' > "$p"
  printf '%s' "$p"
}
or_stop() { # <sid> <transcript>
  printf '{"session_id":"%s","cwd":"","transcript_path":"%s"}' "$1" "$2" | "$OR_HOOK"
}

@test "⏰ line: once per session, alone where the hook had nothing else to say" {
  or_env
  printf '2\tPay the fixture bill\n' > "$DL_DIR/.state/due72"
  tx="$(mk_or_tx)"
  run or_stop s1 "$tx"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r .systemMessage)" = "⏰ 2 due ≤72h — top: Pay the fixture bill" ]
  ! printf '%s' "$output" | grep -q '"decision"' || false
  run or_stop s1 "$tx"
  [[ "$output" != *"⏰"* ]] || false
  run or_stop s2 "$tx"
  [[ "$output" == *"⏰ 2 due"* ]]
}

@test "⏰ line: appended to a rendered block rather than replacing it" {
  or_env
  printf '2\tPay the fixture bill\n' > "$DL_DIR/.state/due72"
  printf '#!/bin/sh\necho hi\n' > "$CC_ACTIVATION_DIR/01-fixture-activate.sh"
  run or_stop s3 "$(mk_or_tx)"
  msg="$(printf '%s' "$output" | jq -r .systemMessage)"
  [[ "$msg" == *"01-fixture-activate"* ]] || false
  [ "$(printf '%s\n' "$msg" | tail -1)" = "⏰ 2 due ≤72h — top: Pay the fixture bill" ]
}

@test "⏰ line: silent for a headless transcript, a payload with no transcript, the kill switch, or no due72" {
  or_env
  printf '2\tPay the fixture bill\n' > "$DL_DIR/.state/due72"
  run or_stop h1 "$(mk_or_tx sdk-cli)"
  [[ "$output" != *"⏰"* ]] || false
  run or_stop h2 "$D/no-such-transcript.jsonl"
  [[ "$output" != *"⏰"* ]] || false
  CC_DEADLINE_LINE=off run or_stop h3 "$(mk_or_tx)"
  [[ "$output" != *"⏰"* ]] || false
  tx="$(mk_or_tx)"
  base="$(CC_DEADLINE_LINE=off or_stop h4 "$tx")"
  rm -f "$DL_DIR/.state/due72" "$CC_OPREADOUT_STATE_DIR"/*
  [ "$(or_stop h4 "$tx")" = "$base" ]
}
