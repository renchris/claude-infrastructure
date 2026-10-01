#!/usr/bin/env bats
# cc-husk-sweep — WHICH session a husk pane held, or an honest "cannot tell"
# (docs/research/husk-panes-2026-09-30.md, root causes 7 and 8). After the 2026-09-30 reboot the
# sweep named the wrong session for three of seven husks — two teammates resolved to their dead
# lead, an operator shell to a 5 s headless permission-gate transcript — and plain --resume would
# have typed one lead's resume line into three panes. Every case below failed on the pre-fix tool.
#
# The panes are listed by a stub it2 (CC_HUSK_PANES_JSON unset), so the scrollback arm runs in every
# case, exactly as it does live; nothing here reaches a real kitty or a real pane. PATH is pinned to
# the stub dir plus the system dirs, so a tool missing from a bare box fails here first.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # This repo injects these into every pane it launches; a suite must never inherit them.
  unset CC_PANE_CMD CC_PANE_CMD_DIR CC_PANE_CMD_INTERACTIVE
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SWEEP="$REPO/bin/cc-husk-sweep"
  T="$BATS_TEST_TMPDIR"
  mkdir -p "$T/bin"; export PATH="$T/bin:/usr/bin:/bin"
  export CC_REGISTRY_DIR="$T/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export CC_HUSK_CRASH_LOG="$T/crashes.jsonl"; : > "$CC_HUSK_CRASH_LOG"
  export CC_HUSK_LOG="$T/husk-sweep.jsonl"
  export CC_HUSK_STORES="$T/.claude-secondary:$T/.claude-tertiary"
  export CC_HUSK_PS_FILE="$T/ps.txt"
  export CC_HUSK_LIVE_SIDS="$T/live.txt"; : > "$CC_HUSK_LIVE_SIDS"
  export LR_STATE_DIR="$T/lrstate"; mkdir -p "$LR_STATE_DIR/locks"
  export CC_HUSK_WATCHDOG_LOG="$T/watchdog.log"; : > "$CC_HUSK_WATCHDOG_LOG"
  KSTART=$(( $(date +%s) - 3600 )); export CC_HUSK_KITTY_START_EPOCH="$KSTART"
  unset CC_HUSK_PANES_JSON
  export CC_HUSK_SB_PANES="$T/panes.json" CC_HUSK_SB_DIR="$T/sb"; mkdir -p "$CC_HUSK_SB_DIR"
  export CC_HUSK_IT2="$T/bin/it2"; export CC_HUSK_IT2_LOG="$T/it2.log"; : > "$CC_HUSK_IT2_LOG"
  # A stub it2: lists $CC_HUSK_SB_PANES, records every send, and answers a read with what was last
  # sent to that pane (so type_line's echo-verify passes) or else with $CC_HUSK_SB_DIR/<pane>.txt.
  # <pane>.fail makes that pane's read exit 1, and list.fail makes the list exit 1.
  cat > "$CC_HUSK_IT2" <<'IT2'
#!/bin/bash
log="${CC_HUSK_IT2_LOG:?}"
case "$1 $2" in
  "session list") [ -f "$CC_HUSK_SB_DIR/list.fail" ] && exit 1; cat "${CC_HUSK_SB_PANES:?}" ;;
  "session send") printf 'SEND %s %s\n' "$4" "$5" >> "$log" ;;
  "session read")
    [ -f "$CC_HUSK_SB_DIR/$4.fail" ] && exit 1
    if grep -q "^SEND $4 " "$log" 2>/dev/null; then grep "^SEND $4 " "$log" | tail -1 | sed 's/^SEND [^ ]* //'
    elif [ -f "$CC_HUSK_SB_DIR/$4.txt" ]; then cat "$CC_HUSK_SB_DIR/$4.txt"; fi ;;
esac
exit 0
IT2
  chmod +x "$CC_HUSK_IT2"
  CWD_A="$T/wt-a"; CWD_B="$T/wt-b"; mkdir -p "$CWD_A" "$CWD_B"
  # panes 10 and 30: husks (a bare shell) · pane 20: live (a claude under its shell)
  printf '[{"id":"10","pid":100,"cwd":"%s"},{"id":"20","pid":200,"cwd":"%s"},{"id":"30","pid":300,"cwd":"%s"}]\n' "$CWD_A" "$CWD_B" "$CWD_A" > "$CC_HUSK_SB_PANES"
  printf '%s\n' "100 1 login -fp chris" "101 100 -zsh" "200 1 /bin/zsh" "202 200 /x/.bin/claude --resume z" "300 1 /bin/zsh" > "$CC_HUSK_PS_FILE"
  SA=aaaaaaaa-1111-0000-0000-000000000001
  SB=bbbbbbbb-2222-0000-0000-000000000002
}
slug() { printf '%s' "$1" | LC_ALL=C sed 's/[^a-zA-Z0-9]/-/g'; }
jl() { # <store> <cwd> <sid> <record>... — a transcript holding exactly these JSONL records
  local d sid; d="$1/projects/$(slug "$2")"; sid="$3"; mkdir -p "$d"; shift 3
  printf '%s\n' "$@" > "$d/$sid.jsonl"
}
said() { # <yes|no> — an assistant record whose text closes with that verdict
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"done.\\nGood to close: %s — x"}]}}' "$1"
}
wd() { # <epoch> <sid> <pane> — one lead-crash-watchdog.sh SessionStart registration line
  printf '[%s] registered session=%s pid=4242 tty=ttys004 pane=%s\n' \
    "$(date -r "$1" '+%Y-%m-%d %H:%M:%S')" "$2" "$3" >> "$CC_HUSK_WATCHDOG_LOG"
}
sb() { # <pane> <line>... — that pane's scrollback
  printf '%s\n' "${@:2}" > "$CC_HUSK_SB_DIR/$1.txt"
}

@test "C1: the watchdog's registration names the session and outranks the scrollback; a line from before this kitty started does not" {
  jl "$T/.claude-tertiary"  "$CWD_A" "$SA" "$(said no)"
  jl "$T/.claude-secondary" "$CWD_A" "$SB" "$(said no)"
  sb 10 '$ claude2 --strict-mcp-config' 'Resume this session with:' "claude --resume $SB"
  wd $((KSTART + 60)) "$SA" 10
  wd $((KSTART + 90)) cccccccc-3333-0000-0000-000000000003 100   # pane=100 is not pane=10
  run "$SWEEP" --json --pane 10
  [ "$status" -eq 0 ]
  [[ "$output" == *"\"sid\":\"$SA\""* ]] || { echo "$output"; false; }
  [[ "$output" == *'"source":"watchdog"'* ]] || { echo "$output"; false; }
  [[ "$output" == *'"launcher":"claude3"'* ]] || { echo "$output"; false; }
  # the same registration, but written by a PREVIOUS kitty (window ids restart at 1 per kitty)
  : > "$CC_HUSK_WATCHDOG_LOG"; wd $((KSTART - 60)) "$SA" 10
  run "$SWEEP" --json --pane 10
  [[ "$output" == *"\"sid\":\"$SB\""* ]] || { echo "an old kitty's pane 10 named today's: $output"; false; }
  [[ "$output" == *'"source":"scrollback"'* ]] || { echo "$output"; false; }
  # an unreadable kitty start: the arm abstains rather than trust an unfiltered log
  : > "$CC_HUSK_WATCHDOG_LOG"; wd $((KSTART + 60)) "$SA" 10
  run env CC_HUSK_KITTY_START_EPOCH= "$SWEEP" --json --pane 10
  [[ "$output" == *'"source":"scrollback"'* ]] || { echo "$output"; false; }
}

@test "C2: it2-kitty 'session read -n N' reads the WHOLE scrollback and keeps its last N lines" {
  unset CC_PANE_CMD CC_PANE_CMD_DIR CC_PANE_CMD_INTERACTIVE
  export CC_TERM_KITTY_TO="unix:$T/sock" CC_TERM_KITTY="$T/fake-kitty" KARGV="$T/kitty-argv"
  cat > "$CC_TERM_KITTY" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "${KARGV:?}"
for i in 1 2 3 4 5 6 7 8 9 10; do echo "line$i"; done
SH
  chmod +x "$CC_TERM_KITTY"
  run "$REPO/bin/it2-kitty" session read -s 5 -n 3
  [ "$status" -eq 0 ]
  [ "$output" = "line8
line9
line10" ] || { echo "$output"; false; }
  grep -q -- 'get-text --match id:5 --extent all' "$KARGV" || { cat "$KARGV"; false; }
  # without -n: the visible screen, unchanged
  : > "$KARGV"
  run "$REPO/bin/it2-kitty" session read -s 5
  [ "$status" -eq 0 ]
  if grep -q -- '--extent' "$KARGV"; then cat "$KARGV"; false; fi
}

@test "C3: a failed scrollback read is UNKNOWN (read-failed), never a fall-through to a guess" {
  : > "$CC_HUSK_SB_DIR/10.fail"
  jl "$T/.claude-tertiary" "$CWD_A" "$SA" "$(said no)"
  run "$SWEEP" --json --pane 10
  [ "$status" -eq 0 ]
  [[ "$output" == *'"sid":"-"'* ]] || { echo "$output"; false; }
  [[ "$output" == *'"verdict":"UNKNOWN"'* ]] || { echo "$output"; false; }
  [[ "$output" == *'"source":"read-failed"'* ]] || { echo "$output"; false; }
}

@test "C4: a transcript in the pane's cwd names no session — unresolved is UNKNOWN, and nothing is typed" {
  jl "$T/.claude-tertiary" "$CWD_A" "$SA" "$(said no)"
  run "$SWEEP" --json --pane 10
  [ "$status" -eq 0 ]
  [[ "$output" == *'"sid":"-"'* ]] || { echo "$output"; false; }
  [[ "$output" == *'"verdict":"UNKNOWN"'* ]] || { echo "$output"; false; }
  run "$SWEEP" --resume --all --yes --pane 10
  [ ! -s "$CC_HUSK_IT2_LOG" ] || { cat "$CC_HUSK_IT2_LOG"; false; }
}

@test "C5: the launcher comes from the store that HOLDS the transcript, not from the registry's label" {
  printf '{"paneUUID":"10","session_id":"%s","account":"claude-secondary","cwd":"%s"}\n' "$SA" "$CWD_A" > "$CC_REGISTRY_DIR/10.json"
  jl "$T/.claude-tertiary" "$CWD_A" "$SA" "$(said no)"
  run "$SWEEP" --json --pane 10
  [ "$status" -eq 0 ]
  [[ "$output" == *'"launcher":"claude3"'* ]] || { echo "$output"; false; }
}

@test "C6: the cwd is the one the session recorded, not the shell's" {
  sb 10 'Resume this session with:' "claude --resume $SA"
  jl "$T/.claude-tertiary" "$CWD_B" "$SA" \
    "{\"type\":\"user\",\"cwd\":\"$CWD_B\",\"message\":{\"role\":\"user\",\"content\":\"go\"}}" "$(said no)"
  run "$SWEEP" --json --pane 10
  [ "$status" -eq 0 ]
  [[ "$output" == *"\"cwd\":\"$CWD_B\""* ]] || { echo "$output"; false; }
}

@test "C7: two panes resolving to ONE sid are both DUPLICATE, and --resume types nothing into either" {
  sb 10 "\$ nocorrect CC_ACCOUNT_PINNED=1 claude3 --resume $SA"
  sb 30 "\$ nocorrect CC_ACCOUNT_PINNED=1 claude3 --resume $SA"
  jl "$T/.claude-tertiary" "$CWD_A" "$SA" "$(said no)"
  run "$SWEEP" --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '"verdict":"DUPLICATE"')" -eq 2 ] || { echo "$output"; false; }
  run "$SWEEP" --json --pane 10          # --pane narrows the output, never the comparison
  [[ "$output" == *'"verdict":"DUPLICATE"'* ]] || { echo "$output"; false; }
  run "$SWEEP" --resume --all --yes
  [ ! -s "$CC_HUSK_IT2_LOG" ] || { cat "$CC_HUSK_IT2_LOG"; false; }
}

@test "C8: a teammate's transcript is TEAMMATE and is never resumed, not even with --all" {
  printf '{"paneUUID":"10","session_id":"%s","account":"claude-tertiary","cwd":"%s"}\n' "$SA" "$CWD_A" > "$CC_REGISTRY_DIR/10.json"
  jl "$T/.claude-tertiary" "$CWD_A" "$SA" \
    '{"type":"user","teamName":"session-c82dd5b9","agentName":"heat-rebase","message":{"role":"user","content":"go"}}' "$(said no)"
  run "$SWEEP" --json --pane 10
  [ "$status" -eq 0 ]
  [[ "$output" == *'"verdict":"TEAMMATE"'* ]] || { echo "$output"; false; }
  run "$SWEEP" --resume --all --yes --pane 10
  [ ! -s "$CC_HUSK_IT2_LOG" ] || { cat "$CC_HUSK_IT2_LOG"; false; }
}

@test "C9: a pane list that fails or is not JSON exits 2 — never 'no husk panes'" {
  printf 'not json\n' > "$T/bad.json"
  run env CC_HUSK_PANES_JSON="$T/bad.json" "$SWEEP" --json
  [ "$status" -eq 2 ] || { echo "rc=$status $output"; false; }
  [[ "$output" != *"no husk panes"* ]] || { echo "$output"; false; }
  : > "$CC_HUSK_SB_DIR/list.fail"
  run "$SWEEP" --json
  [ "$status" -eq 2 ] || { echo "rc=$status $output"; false; }
}

@test "C10: the close is read from ASSISTANT text only — the CLAUDE.md attachment's example is not the session's word" {
  printf '{"paneUUID":"10","session_id":"%s","account":"claude-tertiary","cwd":"%s"}\n' "$SA" "$CWD_A" > "$CC_REGISTRY_DIR/10.json"
  jl "$T/.claude-tertiary" "$CWD_A" "$SA" "$(said yes)" \
    '{"type":"attachment","attachment":{"type":"nested_memory","content":"An honest Good to close: no — <what remains> also satisfies"}}' \
    '{"type":"user","message":{"role":"user","content":"Good to close: no?"}}'
  run "$SWEEP" --json --pane 10
  [ "$status" -eq 0 ]
  [[ "$output" == *'"close":"yes"'* ]] || { echo "$output"; false; }
}

@test "the scrollback accepts the pinned 'nocorrect CC_ACCOUNT_PINNED=1 claude3 --resume <sid>' line" {
  sb 10 "\$ nocorrect CC_ACCOUNT_PINNED=1 claude3 --resume $SA" '  ...' '$ '
  jl "$T/.claude-tertiary" "$CWD_B" "$SA" "$(said no)"
  run "$SWEEP" --json --pane 10
  [ "$status" -eq 0 ]
  [[ "$output" == *"\"sid\":\"$SA\""* ]] || { echo "$output"; false; }
  [[ "$output" == *'"source":"scrollback"'* ]] || { echo "$output"; false; }
  [[ "$output" == *'"launcher":"claude3"'* ]] || { echo "$output"; false; }
}
