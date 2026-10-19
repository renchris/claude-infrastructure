#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329,SC2317
# Startup sentinels (docs/research/startup-hooks-2026-10-18/README.md §5 unit 3.1): every own sync
# SessionStart hook leaves <hook>.start and, on every exit path, <hook>.done with rc, elapsed and the
# bytes it owed — so a harness cancel (which Claude Code renders nowhere) is reportable. Hermetic:
# $HOME and CC_STARTUP_HEALTH_DIR are fixtures; no hook runs against live state.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/hooks/lib/startup-sentinel.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"
  export CC_STARTUP_HEALTH_DIR="$BATS_TEST_TMPDIR/sh"
  export CC_ACCOUNTS_BOARD="$BATS_TEST_TMPDIR/board.txt"   # the accounts-board hook's /tmp default
  SID="aaaaaaaa-1111-2222-3333-444444444444"
  S="$CC_STARTUP_HEALTH_DIR/$SID"
}

probe() { # <body> → a hook script that opens a sentinel then runs body
  printf '#!/bin/bash\n. "%s" && ss_begin probe-hook 5000 "%s" "%s"\n%s\n' "$LIB" "$SID" "${TP:-}" "$1" \
    > "$BATS_TEST_TMPDIR/h.sh"
}
field() { sed -n "s/^$2=//p" "$S/$1"; }

@test "healthy run: start and done, rc 0, owed matches the bytes printed" {
  probe 'out="hello world"; ss_owed $(( ${#out} + 1 )); printf "%s\n" "$out"'
  run bash "$BATS_TEST_TMPDIR/h.sh"
  [ "$status" -eq 0 ]
  [ -f "$S/probe-hook.start" ]
  [ "$(field probe-hook.done rc)" = 0 ]
  [ "$(field probe-hook.done owed)" = "$(( ${#output} + 1 ))" ]    # bats strips the trailing newline
  [ "$(field probe-hook.done timeout_ms)" = 5000 ]
}

@test "an abstain (early exit 0, nothing printed) still leaves done with owed 0" {
  probe 'exit 0'
  run bash "$BATS_TEST_TMPDIR/h.sh"
  [ "$(field probe-hook.done rc)" = 0 ]
  [ "$(field probe-hook.done owed)" = 0 ]
}

@test "a TERM leaves done rc=143" {
  probe 'sleep 5 & wait $!'
  bash "$BATS_TEST_TMPDIR/h.sh" & p=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$S/probe-hook.start" ] && break; sleep 0.2; done
  kill -TERM "$p"; wait "$p" || true
  [ "$(field probe-hook.done rc)" = 143 ]
}

@test "a SIGKILL leaves start without done (still readable as a possible loss)" {
  probe 'sleep 5 & wait $!'
  bash "$BATS_TEST_TMPDIR/h.sh" & p=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$S/probe-hook.start" ] && break; sleep 0.2; done
  kill -KILL "$p"; wait "$p" || true
  [ -f "$S/probe-hook.start" ]
  [ ! -f "$S/probe-hook.done" ]
}

@test "session.start is written once, with the transcript path and its size at start" {
  TP="$BATS_TEST_TMPDIR/t.jsonl"; printf '0123456789' > "$TP"
  probe 'exit 0'
  bash "$BATS_TEST_TMPDIR/h.sh"
  [ "$(field session.start transcript_path)" = "$TP" ]
  [ "$(field session.start size)" = 10 ]
  printf 'more' >> "$TP"
  bash "$BATS_TEST_TMPDIR/h.sh"
  [ "$(field session.start size)" = 10 ]     # the FIRST writer's record stands
}

@test "session.start written with no transcript path is upgraded by the first writer that has one" {
  TP=""; probe 'exit 0'; bash "$BATS_TEST_TMPDIR/h.sh"
  [ -z "$(field session.start transcript_path)" ]
  TP="$BATS_TEST_TMPDIR/t.jsonl"; printf '0123' > "$TP"; probe 'exit 0'; bash "$BATS_TEST_TMPDIR/h.sh"
  [ "$(field session.start transcript_path)" = "$TP" ]
  [ "$(field session.start size)" = 4 ]
  printf 'more' >> "$TP"; TP="$BATS_TEST_TMPDIR/other.jsonl"; probe 'exit 0'; bash "$BATS_TEST_TMPDIR/h.sh"
  [ "$(field session.start transcript_path)" = "$BATS_TEST_TMPDIR/t.jsonl" ]   # a real path is never replaced
  [ "$(field session.start size)" = 4 ]
}

@test "CC_STARTUP_SENTINEL=0 writes nothing; an unsafe sid writes nothing" {
  probe 'exit 0'
  CC_STARTUP_SENTINEL=0 bash "$BATS_TEST_TMPDIR/h.sh"
  [ ! -e "$S" ]
  SID='../escape'; probe 'exit 0'; bash "$BATS_TEST_TMPDIR/h.sh"
  [ ! -e "$CC_STARTUP_HEALTH_DIR/../escape" ]
}

@test "desk-brief-inject leaves start+done on its abstain path (no role file)" {
  run bash -c "printf '{\"session_id\":\"$SID\"}' | DESK_BRIEF_IDL='$BATS_TEST_TMPDIR/idl.jsonl' CC_ROLES_DIR='$BATS_TEST_TMPDIR/roles' DESK_BRIEF_PANE=p1 bash '$REPO/hooks/desk-brief-inject.sh'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -f "$S/desk-brief-inject.start" ]
  [ "$(field desk-brief-inject.done rc)" = 0 ]
  [ "$(field desk-brief-inject.done owed)" = 0 ]
}

@test "desk-brief-inject records the payload's transcript path and size in session.start" {
  TP="$BATS_TEST_TMPDIR/t.jsonl"; printf '0123456789' > "$TP"
  run bash -c "printf '{\"session_id\":\"$SID\",\"transcript_path\":\"$TP\"}' | DESK_BRIEF_IDL='$BATS_TEST_TMPDIR/idl.jsonl' CC_ROLES_DIR='$BATS_TEST_TMPDIR/roles' DESK_BRIEF_PANE=p1 bash '$REPO/hooks/desk-brief-inject.sh'"
  [ "$status" -eq 0 ]
  [ "$(field session.start transcript_path)" = "$TP" ]
  [ "$(field session.start size)" = 10 ]
  [ "$(field desk-brief-inject.done rc)" = 0 ]
}

@test "desk-brief-inject's injected brief is recorded as owed bytes" {
  mkdir -p "$BATS_TEST_TMPDIR/roles"; echo p1 > "$BATS_TEST_TMPDIR/roles/desk"
  printf 'brief body\n' > "$BATS_TEST_TMPDIR/brief.md"
  run bash -c "printf '{\"session_id\":\"$SID\"}' | DESK_BRIEF_IDL='$BATS_TEST_TMPDIR/idl.jsonl' CC_ROLES_DIR='$BATS_TEST_TMPDIR/roles' DESK_BRIEF_PANE=p1 DESK_BRIEF_FILE='$BATS_TEST_TMPDIR/brief.md' bash '$REPO/hooks/desk-brief-inject.sh'"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("brief body")' >/dev/null
  [ "$(field desk-brief-inject.done owed)" = "$(( ${#output} + 1 ))" ]
}

# ── 3.4 transcript worker (hooks/lib/startup-health.sh) ──────────────────────────────────────────
# Fixtures only: a static transcript plus a sentinel dir; no hook runs. Every .start is stamped at
# 2026-10-18T12:00:00Z so record timestamps can sit on either side of the epoch floor (30 s).
RLIB() { printf '%s' "$REPO/hooks/lib/startup-health.sh"; }
T0=202610181200.00
# The literal ~ is the harness's own command text in a hook_cancelled record, never a path to expand.
# shellcheck disable=SC2088
HK='~/.claude/hooks'
mkstart() { mkdir -p "$S"; : > "$S/$1.start"; TZ=UTC touch -t "${2:-$T0}" "$S/$1.start"; }
mkdone() { # <hook> <rc> <elapsed_s> <owed> [timeout_ms]
  printf 'rc=%s\nelapsed_s=%s\nowed=%s\ntimeout_ms=%s\n' "$2" "$3" "$4" "${5:-5000}" > "$S/$1.done"
}
mksession() { # <transcript> [size]
  mkdir -p "$S"; printf 'transcript_path=%s\nsize=%s\n' "$1" "${2:-0}" > "$S/session.start"
  TZ=UTC touch -t "$T0" "$S/session.start"
}
cancel_rec() { # <command> [ts] [durationMs] — one SessionStart hook_cancelled transcript line
  jq -nc --arg c "$1" --arg ts "${2:-2026-10-18T12:00:06.169Z}" --argjson d "${3:-5472}" \
    '{parentUuid:null,attachment:{type:"hook_cancelled",hookName:"SessionStart:startup",hookEvent:"SessionStart",command:$c,durationMs:$d,timedOut:true,timeoutMs:5000},type:"attachment",timestamp:$ts}'
}
user_rec() { printf '{"type":"user","message":{"role":"user","content":"hi"},"timestamp":"2026-10-18T12:00:09.000Z"}\n'; }
scan() { bash -c '. "$1"; sh_write "$2" "${3:-}"' _ "$(RLIB)" "$S" "${1:-}"; }
verdict() { cat "$S/$1.verdict"; }
possible() { bash -c '. "$1"; sh_possible "$2" "$3"; printf "%s" "$SH_REASON"' _ "$(RLIB)" "$S" "$1"; }

@test "3.4(a) a project-hook cancel with no sentinel is one confirmed foreign row naming the command" {
  TP="$BATS_TEST_TMPDIR/t.jsonl"
  { cancel_rec 'pnpm exec tsx scripts/unblock-sweep.ts' '' 23100; user_rec; } > "$TP"
  mksession "$TP"; mkstart desk-brief-inject; mkdone desk-brief-inject 0 1 0
  scan
  [ "$(wc -l < "$S/cancels.tsv" | tr -d ' ')" = 1 ]
  [ "$(cut -f1,3 "$S/cancels.tsv")" = "$(printf 'pnpm exec tsx scripts/unblock-sweep.ts\t23100')" ]
  [ "$(verdict foreign-1)" = "confirmed pnpm exec tsx scripts/unblock-sweep.ts" ]
  [ "$(verdict desk-brief-inject)" = cleared ]
}

@test "3.4(b) rc 0 at 5 s with output owed: possible; a record confirms it, no record clears it" {
  TP="$BATS_TEST_TMPDIR/t.jsonl"
  mksession "$TP"; mkstart dod-persist; mkdone dod-persist 0 5 900
  [ -n "$(possible dod-persist)" ]
  { cancel_rec "$HK/dod-persist.sh"; user_rec; } > "$TP"
  scan
  [ "$(verdict dod-persist)" = confirmed ]
  user_rec > "$TP"; rm -f "$S/cancels.tsv"
  scan
  [ "$(verdict dod-persist)" = cleared ]
  [ -f "$S/cancels.tsv" ] && [ ! -s "$S/cancels.tsv" ]     # scanned, none
}

@test "3.4(c) rc 141 is a possible loss, then confirmed or cleared by the transcript" {
  TP="$BATS_TEST_TMPDIR/t.jsonl"
  mksession "$TP"; mkstart mailbox-drain; mkdone mailbox-drain 141 0 0
  [ "$(possible mailbox-drain)" = "exit 141" ]
  { cancel_rec "$HK/mailbox-drain.sh session-start"; user_rec; } > "$TP"
  scan; [ "$(verdict mailbox-drain)" = nothing-owed ]       # cancelled, but it owed nothing
  mkdone mailbox-drain 141 0 120; rm -f "$S/cancels.tsv"
  scan; [ "$(verdict mailbox-drain)" = confirmed ]
  user_rec > "$TP"; rm -f "$S/cancels.tsv"
  scan; [ "$(verdict mailbox-drain)" = cleared ]
}

@test "3.4(d) resume: a cancel past the stored offset is reported, one before it is ignored" {
  TP="$BATS_TEST_TMPDIR/t.jsonl"
  { cancel_rec "$HK/old-hook.sh"; user_rec; } > "$TP"
  mksession "$TP" "$(wc -c < "$TP" | tr -d ' ')"
  mkstart desk-brief-inject; mkdone desk-brief-inject 0 1 0
  { cancel_rec 'bash .claude/hooks/mcp-auth-guard.sh'; user_rec; } >> "$TP"
  scan
  [ "$(wc -l < "$S/cancels.tsv" | tr -d ' ')" = 1 ]
  [ "$(verdict foreign-1)" = "confirmed bash .claude/hooks/mcp-auth-guard.sh" ]
}

@test "3.4(e) transcript absent: the worker polls to its cap and writes nothing" {
  mksession "$BATS_TEST_TMPDIR/never.jsonl"; mkstart dod-persist; mkdone dod-persist 143 5 0
  run bash -c '. "$1"; CC_STARTUP_HEALTH_POLL_S=1 sh_worker "$2"' _ "$(RLIB)" "$SID"
  [ "$status" -eq 0 ]
  [ ! -e "$S/cancels.tsv" ]
  [ ! -e "$S/dod-persist.verdict" ]
}

@test "3.4 a record older than the start epoch (a fork's copied history, a resume) is ignored" {
  TP="$BATS_TEST_TMPDIR/t.jsonl"
  { cancel_rec "$HK/dod-persist.sh" '2026-10-18T11:59:00.000Z'; user_rec; } > "$TP"
  mksession "$TP"; mkstart dod-persist; mkdone dod-persist 0 1 900
  scan
  [ "$(verdict dod-persist)" = cleared ]
  [ ! -s "$S/cancels.tsv" ]
}

@test "3.4 a resumed epoch (session.start older than the new .start) reads past the first user record" {
  TP="$BATS_TEST_TMPDIR/t.jsonl"
  { user_rec; user_rec; cancel_rec "$HK/dod-persist.sh" '2026-10-18T13:00:06.000Z'; } > "$TP"
  mksession "$TP"; mkstart dod-persist 202610181300.00; mkdone dod-persist 0 5 900
  scan
  [ "$(verdict dod-persist)" = confirmed ]
}

@test "3.4 an own hook cancelled before its sentinel opened is own (confirmed), never foreign" {
  TP="$BATS_TEST_TMPDIR/t.jsonl"
  { cancel_rec "$HK/session-start-dispatch.sh" '' 12004; user_rec; } > "$TP"
  mksession "$TP"; mkstart desk-brief-inject; mkdone desk-brief-inject 0 1 0
  scan
  [ "$(verdict session-start-dispatch)" = confirmed ]
  [ ! -e "$S/foreign-1.verdict" ]
}

@test "3.4 the worker scans once per start epoch, and again after a newer .start" {
  TP="$BATS_TEST_TMPDIR/t.jsonl"; user_rec > "$TP"
  mksession "$TP"; mkstart desk-brief-inject; mkdone desk-brief-inject 0 1 0
  bash -c '. "$1"; sh_worker "$2"' _ "$(RLIB)" "$SID"
  [ -f "$S/cancels.tsv" ]
  TZ=UTC touch -t 202610181201.00 "$S/cancels.tsv"
  { cancel_rec "$HK/desk-brief-inject.sh"; user_rec; } > "$TP"
  bash -c '. "$1"; sh_worker "$2"' _ "$(RLIB)" "$SID"
  [ "$(verdict desk-brief-inject)" = cleared ]                # current epoch: not rescanned
  mkstart desk-brief-inject 202610181205.00; mkdone desk-brief-inject 0 1 0
  { cancel_rec "$HK/desk-brief-inject.sh" '2026-10-18T12:05:06.000Z'; user_rec; } >> "$TP"
  bash -c '. "$1"; sh_worker "$2"' _ "$(RLIB)" "$SID"
  [ "$(verdict desk-brief-inject)" = nothing-owed ]           # the new epoch was scanned
}

@test "3.4 the worker falls back to the payload's transcript path when session.start has none" {
  TP="$BATS_TEST_TMPDIR/t.jsonl"
  { cancel_rec "$HK/dod-persist.sh"; user_rec; } > "$TP"
  mksession ""; mkstart dod-persist; mkdone dod-persist 0 5 900
  bash -c '. "$1"; sh_worker "$2" "$3"' _ "$(RLIB)" "$SID" "$TP"
  [ "$(verdict dod-persist)" = confirmed ]
}

@test "3.4 session-beat's prompt worker writes the verdicts (fixture HOME, no live state)" {
  TP="$BATS_TEST_TMPDIR/t.jsonl"
  { cancel_rec "$HK/dod-persist.sh"; user_rec; } > "$TP"
  mksession "$TP"; mkstart dod-persist; mkdone dod-persist 0 5 900
  export CC_BEAT_DIR="$BATS_TEST_TMPDIR/beats" CC_BEAT_LOG="$BATS_TEST_TMPDIR/beat.log"
  printf '{"session_id":"%s","cwd":"/tmp","prompt":"hi","transcript_path":"%s"}' "$SID" "$TP" \
    | /bin/bash "$REPO/hooks/session-beat.sh" prompt
  for _ in $(seq 1 150); do [ -f "$S/cancels.tsv" ] && break; sleep 0.2; done
  [ "$(verdict dod-persist)" = confirmed ]
}

# ── 3.2 prompt front (sh_front_emit, under /bin/bash 3.2 like session-beat) ───────────────────────
front() { /bin/bash -c '. "$1"; sh_front_emit "$2" UserPromptSubmit' _ "$(RLIB)" "$SID"; }
sys() { printf '%s' "$1" | jq -r '.systemMessage // empty'; }
ctx() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // empty'; }
idl_count() { grep -c "\"reason\":\"$1\"" "$HOME/.claude/autonomy/idl.jsonl" 2>/dev/null || true; }

@test "3.2 healthy: no output on prompt 1, nothing after the scan, then the resolved fast exit" {
  TP="$BATS_TEST_TMPDIR/t.jsonl"
  mksession "$TP"; mkstart dod-persist; mkdone dod-persist 0 1 900
  run front; [ "$status" -eq 0 ]; [ -z "$output" ]
  user_rec > "$TP"; scan
  run front; [ -z "$output" ]
  [ -f "$S/resolved" ]
  run front; [ -z "$output" ]
  [ ! -e "$HOME/.claude/autonomy/idl.jsonl" ]           # a healthy session writes no IDL row
}

@test "3.2 a possible loss prints the fixed line once (plus the DoD pointer); then the confirmed line once" {
  TP="$BATS_TEST_TMPDIR/t.jsonl"
  mksession "$TP"; mkstart dod-persist; mkdone dod-persist 143 5 900
  run front
  [ "$(sys "$output")" = "⚠ startup: dod-persist may not have delivered (exit 143) — confirming" ]
  ctx "$output" | grep -qF "$HK/dod-persist.sh get"
  [ -f "$S/pending" ]
  run front; [ -z "$output" ]                            # no verdict yet: no repeat
  { cancel_rec "$HK/dod-persist.sh" '' 5472; user_rec; } > "$TP"; scan
  run front
  [ "$(sys "$output")" = "⚠ startup: dod-persist did not finish (cancelled after 5.4 s) — the frozen DoD contract · ~/.claude/hooks/dod-persist.sh get" ]
  [ -z "$(ctx "$output")" ]                              # the pointer was already given
  [ "$(idl_count 'startup-drop:confirmed:dod-persist')" = 1 ]
  run front; [ -z "$output" ]                            # latched
}

@test "3.2 an rc-0 cancel never flagged on prompt 1 is reported confirmed, with the pointer, from prompt 2" {
  TP="$BATS_TEST_TMPDIR/t.jsonl"
  mksession "$TP"; mkstart dod-persist; mkdone dod-persist 0 2 900
  run front; [ -z "$output" ]
  { cancel_rec "$HK/dod-persist.sh"; user_rec; } > "$TP"; scan
  run front
  sys "$output" | grep -qF 'dod-persist did not finish'
  ctx "$output" | grep -qF 'dod-persist.sh get'
}

@test "3.2 a foreign project-hook cancel is named once, never run, and the JSON survives quotes" {
  TP="$BATS_TEST_TMPDIR/t.jsonl"
  cmd='bash -c "echo \"hi\" \\ x"'
  { cancel_rec "$cmd" '' 23100; user_rec; } > "$TP"
  mksession "$TP"; mkstart desk-brief-inject; mkdone desk-brief-inject 0 1 0
  scan
  run front
  [ "$(sys "$output")" = "⚠ startup: project hook $cmd was cancelled after 23.1 s — not re-run · re-run it by hand" ]
  [ "$(idl_count 'startup-drop:confirmed:foreign')" = 1 ]
  run front; [ -z "$output" ]
}

@test "3.2 a possible loss the transcript clears prints nothing more and leaves one cleared IDL row" {
  TP="$BATS_TEST_TMPDIR/t.jsonl"
  mksession "$TP"; mkstart mailbox-drain; mkdone mailbox-drain 141 0 300
  run front; sys "$output" | grep -qF 'mailbox-drain may not have delivered (exit 141)'
  [ -z "$(ctx "$output")" ]                              # the pointer is for dod-persist only
  user_rec > "$TP"; scan
  run front; [ -z "$output" ]
  [ "$(idl_count 'startup-drop:cleared:mailbox-drain')" = 1 ]
  [ -f "$S/resolved" ]
}

@test "3.2 no transcript ever: at most 3 tries, one possible line, then resolved" {
  mksession "$BATS_TEST_TMPDIR/never.jsonl"; mkstart session-start-dispatch; : # no .done: never finished
  run front; sys "$output" | grep -qF 'session-start-dispatch may not have delivered (it never finished)'
  run front; [ -z "$output" ]
  run front; [ -z "$output" ]
  [ -f "$S/resolved" ]
  run front; [ -z "$output" ]
}

@test "3.2 a resume (a .start newer than resolved) re-opens the session" {
  TP="$BATS_TEST_TMPDIR/t.jsonl"; user_rec > "$TP"
  mksession "$TP"; mkstart dod-persist; mkdone dod-persist 0 1 900
  scan; run front; [ -z "$output" ]; [ -f "$S/resolved" ]
  TZ=UTC touch -t 202610181201.00 "$S/resolved" "$S/cancels.tsv" "$S"/*.verdict "$S"/*.reported
  mkstart dod-persist 202610181300.00; mkdone dod-persist 143 5 900
  run front
  sys "$output" | grep -qF 'dod-persist may not have delivered (exit 143)'
}

@test "3.2 CC_STARTUP_HEALTH=0 and an unsafe sid print nothing" {
  mksession "$BATS_TEST_TMPDIR/x"; mkstart dod-persist; mkdone dod-persist 143 5 900
  run /bin/bash -c '. "$1"; CC_STARTUP_HEALTH=0 sh_front_emit "$2" UserPromptSubmit' _ "$(RLIB)" "$SID"
  [ -z "$output" ]
  run /bin/bash -c '. "$1"; sh_front_emit "../x" UserPromptSubmit' _ "$(RLIB)"
  [ -z "$output" ]
}

@test "3.2 session-beat prints the front's JSON on stdout, and 0 bytes on a healthy prompt" {
  export CC_BEAT_DIR="$BATS_TEST_TMPDIR/beats" CC_BEAT_LOG="$BATS_TEST_TMPDIR/beat.log"
  mksession "$BATS_TEST_TMPDIR/never.jsonl"; mkstart dod-persist; mkdone dod-persist 143 5 900
  run /bin/bash -c "printf '{\"session_id\":\"$SID\",\"hook_event_name\":\"UserPromptSubmit\",\"cwd\":\"/tmp\",\"prompt\":\"hi\"}' | CC_STARTUP_HEALTH_POLL_S=0 /bin/bash '$REPO/hooks/session-beat.sh' prompt"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.hookSpecificOutput.hookEventName == "UserPromptSubmit"' >/dev/null
  sys "$output" | grep -qF 'dod-persist may not have delivered'
  run /bin/bash -c "printf '{\"session_id\":\"bbbb-2\",\"cwd\":\"/tmp\",\"prompt\":\"hi\"}' | /bin/bash '$REPO/hooks/session-beat.sh' prompt"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── 3.3 cc-startup-health [sid] (read-only report) ────────────────────────────────────────────────
CSH() { "$REPO/bin/cc-startup-health" "$@"; }

@test "3.3 report: a confirmed DoD loss with its recovery, a foreign hook named and never run, the outbox" {
  TP="$BATS_TEST_TMPDIR/t.jsonl"
  { cancel_rec "$HK/dod-persist.sh"; cancel_rec 'pnpm exec tsx scripts/unblock-sweep.ts' '' 23100; user_rec; } > "$TP"
  mksession "$TP"; mkstart dod-persist; mkdone dod-persist 0 5 900
  mkstart desk-brief-inject; mkdone desk-brief-inject 0 1 0
  printf 'BOARD-LINE-ZZ\n' > "$S/outbox.txt"
  run CSH "$SID"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'dod-persist'
  printf '%s\n' "$output" | grep -F 'dod-persist' | grep -qF 'LOST — the frozen DoD contract · recover: ~/.claude/hooks/dod-persist.sh get'
  printf '%s\n' "$output" | grep -F 'desk-brief-inject' | grep -qF 'delivered'
  printf '%s\n' "$output" | grep -qF 'project hook cancelled — not re-run · re-run it by hand: pnpm exec tsx scripts/unblock-sweep.ts'
  printf '%s\n' "$output" | grep -qF 'BOARD-LINE-ZZ'
}

@test "3.3 report is read-only: an unscanned session is judged in memory and its dir is untouched" {
  TP="$BATS_TEST_TMPDIR/t.jsonl"
  { cancel_rec "$HK/dod-persist.sh"; user_rec; } > "$TP"
  mksession "$TP"; mkstart dod-persist; mkdone dod-persist 0 5 900
  before="$(ls -la "$S")"
  run CSH "$SID"
  printf '%s\n' "$output" | grep -F 'dod-persist' | grep -qF 'LOST'
  [ "$(ls -la "$S")" = "$before" ]
}

@test "3.3 report without a transcript shows a possible loss as unconfirmed" {
  mksession "$BATS_TEST_TMPDIR/never.jsonl"; mkstart dod-persist; mkdone dod-persist 143 5 900
  run CSH "$SID"
  printf '%s\n' "$output" | grep -qF 'no transcript yet'
  printf '%s\n' "$output" | grep -F 'dod-persist' | grep -qF 'possible loss, unconfirmed (exit 143)'
}

@test "3.3 no sid lists the sessions with confirmed losses; an unknown sid says so" {
  TP="$BATS_TEST_TMPDIR/t.jsonl"
  { cancel_rec "$HK/dod-persist.sh"; user_rec; } > "$TP"
  mksession "$TP"; mkstart dod-persist; mkdone dod-persist 0 5 900
  run CSH
  printf '%s\n' "$output" | grep -qF "$SID  1 lost"
  run CSH cccccccc-0000
  printf '%s\n' "$output" | grep -qF 'no startup sentinels for cccccccc-0000'
}

# ── 3.5 fleet line: cc-startup-health --fleet / --ack and the accounts-board line ─────────────────
mksid() { # <sid> <hook> <rc> <owed> <transcript-records...> — one settled session, scanned or not
  local sid="$1" h="$2" rc="$3" owed="$4" tp; shift 4
  S="$CC_STARTUP_HEALTH_DIR/$sid"; tp="$BATS_TEST_TMPDIR/$sid.jsonl"
  { for c in "$@"; do cancel_rec "$c"; done; user_rec; } > "$tp"
  mksession "$tp"; mkstart "$h"; mkdone "$h" "$rc" 5 "$owed"
  S="$CC_STARTUP_HEALTH_DIR/$SID"
}
LINE() { cat "$CC_STARTUP_HEALTH_DIR/fleet-line.txt"; }

@test "3.5 the fold counts losses under ⚠ and deferrals in the plain suffix" {
  mksid aaaa-1 dod-persist 0 900 "$HK/dod-persist.sh"
  mksid aaaa-2 mailbox-drain 0 300 "$HK/mailbox-drain.sh session-start"
  mksid aaaa-3 desk-brief-inject 0 0
  run CSH --fleet; [ "$status" -eq 0 ]
  LINE | grep -qE '^⚠ startup losses since ack never \(oldest [0-9]+[mhd]\): 1 — dod-persist 1 · deferred: mailbox-drain 1 · cc-startup-health --ack$'
  [ -f "$CC_STARTUP_HEALTH_DIR/fleet.stamp" ]
  [ -f "$CC_STARTUP_HEALTH_DIR/aaaa-1/cancels.tsv" ]          # the fold scanned the unscanned epoch
}

@test "3.5 a deferral-only state shows no ⚠ line" {
  mksid aaaa-2 mailbox-drain 0 300 "$HK/mailbox-drain.sh session-start"
  CSH --fleet
  [ ! -s "$CC_STARTUP_HEALTH_DIR/fleet-line.txt" ]
}

@test "3.5 --ack clears only the shown occurrences; a later occurrence raises the line again" {
  mksid aaaa-1 dod-persist 0 900 "$HK/dod-persist.sh"
  CSH --fleet; [ -s "$CC_STARTUP_HEALTH_DIR/fleet-line.txt" ]
  run CSH --ack
  printf '%s\n' "$output" | grep -qF 'acknowledged 1 occurrence'
  [ ! -s "$CC_STARTUP_HEALTH_DIR/fleet-line.txt" ]
  CSH --fleet; [ ! -s "$CC_STARTUP_HEALTH_DIR/fleet-line.txt" ]   # no timer re-raises it
  mksid aaaa-9 session-start-dispatch 0 400 "$HK/session-start-dispatch.sh"
  CSH --fleet
  LINE | grep -qE ': 1 — session-start-dispatch 1 · cc-startup-health --ack$'
  LINE | grep -qvF 'since ack never'
}

@test "3.5 an idle pane (no transcript) counts a possible loss from its sentinel; a young start waits" {
  S="$CC_STARTUP_HEALTH_DIR/aaaa-5"; mksession "$BATS_TEST_TMPDIR/never.jsonl"; mkstart dod-persist; mkdone dod-persist 143 5 900
  S="$CC_STARTUP_HEALTH_DIR/aaaa-6"; mkdir -p "$S"; : > "$S/dod-persist.start"   # started just now
  CSH --fleet
  LINE | grep -qF ': 1 — dod-persist 1 ·'
}

@test "3.5 retention deletes session dirs older than 7 days" {
  mksid aaaa-1 dod-persist 0 900 "$HK/dod-persist.sh"
  TZ=UTC touch -t 202609010000.00 "$CC_STARTUP_HEALTH_DIR/aaaa-1"
  CSH --fleet
  [ ! -e "$CC_STARTUP_HEALTH_DIR/aaaa-1" ]
  [ ! -s "$CC_STARTUP_HEALTH_DIR/fleet-line.txt" ]
}

board() { # → the accounts-board systemMessage for a fixture board
  printf 'BOARDBODY\n' > "$BATS_TEST_TMPDIR/board.txt"
  printf '{"source":"startup","hook_event_name":"SessionStart"}' \
    | CC_ACCOUNTS_BOARD="$BATS_TEST_TMPDIR/board.txt" "$REPO/hooks/accounts-board.sh" | jq -r '.systemMessage'
}

@test "3.5 the board: unchanged with no fold files; the line sits above the body; a stale fold is loud" {
  plain="$(board)"
  [ "$plain" = BOARDBODY ]
  mkdir -p "$CC_STARTUP_HEALTH_DIR"; printf '⚠ startup losses since ack never (oldest 2h): 1 — dod-persist 1 · cc-startup-health --ack\n' > "$CC_STARTUP_HEALTH_DIR/fleet-line.txt"
  : > "$CC_STARTUP_HEALTH_DIR/fleet.stamp"
  [ "$(board)" = "$(printf '⚠ startup losses since ack never (oldest 2h): 1 — dod-persist 1 · cc-startup-health --ack\nBOARDBODY')" ]
  : > "$CC_STARTUP_HEALTH_DIR/fleet-line.txt"
  [ "$(board)" = BOARDBODY ]                                   # nothing unacked: no line
  TZ=UTC touch -t 202610180000.00 "$CC_STARTUP_HEALTH_DIR/fleet.stamp"
  board | head -1 | grep -qE '^startup-health fold stale since [0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$'
}

@test "3.5 the keepwarm tick runs the fold, bounded, and survives a broken one" {
  grep -q '_startup_health_fold()' "$REPO/bin/claude-accounts"
  run python3 - "$REPO/bin/claude-accounts" <<'PY'
import importlib.machinery, importlib.util, os, sys, types
src = open(sys.argv[1]).read()
start = src.index("def _startup_health_fold():")
end = src.index("\ndef ", start + 10)
ns = {"os": os, "sys": sys, "subprocess": __import__("subprocess"), "__file__": os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts")}
exec(src[start:end], ns)
tool = os.path.join(os.environ["BATS_TEST_TMPDIR"], "cc-startup-health")
open(tool, "w").write("#!/bin/sh\necho \"$1\" > \"$BATS_TEST_TMPDIR/fold-called\"\nexit 3\n"); os.chmod(tool, 0o755)
ns["_startup_health_fold"]()
print(open(os.path.join(os.environ["BATS_TEST_TMPDIR"], "fold-called")).read().strip())
ns2 = {"os": os, "sys": sys, "subprocess": __import__("subprocess")}   # exec'd as `python3 -c`: no __file__
exec(src[start:end], ns2); ns2["_startup_health_fold"](); print("no-file-ok")
PY
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf -- '--fleet\nno-file-ok')" ]
}

# ── 3.6 alert writers (hooks/lib/startup-alert.sh) ───────────────────────────────────────────────
ALERTS() { printf '%s' "$CC_STARTUP_HEALTH_DIR/alerts/$SID"; }

@test "3.6 a TERMed sentinel leaves its possible-loss line in the rolling alert file" {
  probe 'sleep 5 & wait $!'
  bash "$BATS_TEST_TMPDIR/h.sh" & p=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$S/probe-hook.start" ] && break; sleep 0.2; done
  kill -TERM "$p"; wait "$p" || true
  [ "$(cat "$(ALERTS)")" = "⚠ startup: probe-hook may not have delivered (exit 143) — confirming" ]
}

@test "3.6 two faults make one file with two lines; a repeat is not added; a clean exit adds nothing" {
  probe 'exit 0'; bash "$BATS_TEST_TMPDIR/h.sh"
  [ ! -e "$(ALERTS)" ]
  bash -c '. "$1"; sa_alert "$2" "line one"; sa_alert "$2" "line two"; sa_alert "$2" "line one"' \
    _ "$REPO/hooks/lib/startup-alert.sh" "$SID"
  [ "$(cat "$(ALERTS)")" = "$(printf 'line one\nline two')" ]
  [ "$(ls -A "$CC_STARTUP_HEALTH_DIR/alerts")" = "$SID" ]     # no temp or lock left behind
}

@test "3.6 the front empties the alert file once the session's startup is resolved" {
  TP="$BATS_TEST_TMPDIR/t.jsonl"; user_rec > "$TP"
  mksession "$TP"; mkstart mailbox-drain; mkdone mailbox-drain 141 0 0
  bash -c '. "$1"; sa_alert "$2" "pending line"' _ "$REPO/hooks/lib/startup-alert.sh" "$SID"
  scan; run front
  [ -f "$S/resolved" ]
  [ ! -s "$(ALERTS)" ]
}

@test "3.6 the report shows pending alerts; the fold drops alert files whose session is gone" {
  mksession "$BATS_TEST_TMPDIR/never.jsonl"; mkstart dod-persist; mkdone dod-persist 143 5 900
  bash -c '. "$1"; sa_alert "$2" "pending line"; sa_alert dddd-0 "orphan"' _ "$REPO/hooks/lib/startup-alert.sh" "$SID"
  run CSH "$SID"
  printf '%s\n' "$output" | grep -qF 'pending line'
  CSH --fleet
  [ -s "$(ALERTS)" ]
  [ ! -e "$CC_STARTUP_HEALTH_DIR/alerts/dddd-0" ]
}

# ── sentinel wiring: mailbox-drain (session-start mode only), fixture mailbox ─────────────────────
drain() { # <mode> — mailbox-drain against a fixture mailbox, payload naming $SID
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"; mkdir -p "$CC_MAILBOX_DIR"
  printf '{"session_id":"%s","transcript_path":"%s","hook_event_name":"SessionStart"}' "$SID" "${TP:-}" \
    | ITERM_SESSION_ID="w0t0p0:AAAAAAAA-1111-2222-3333-444444444444" bash "$REPO/hooks/mailbox-drain.sh" "$1"
}

@test "mailbox-drain session-start leaves start+done, owing the bytes it printed" {
  mkdir -p "$BATS_TEST_TMPDIR/mbox"
  printf 'peer line for the start\n' > "$BATS_TEST_TMPDIR/mbox/AAAAAAAA-1111-2222-3333-444444444444.md"
  run drain session-start
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qF 'peer line for the start'
  [ -f "$S/mailbox-drain.start" ]
  [ "$(field mailbox-drain.done rc)" = 0 ]
  [ "$(field mailbox-drain.done owed)" -gt 0 ]
  [ "$(field mailbox-drain.done timeout_ms)" = 5000 ]
}

@test "mailbox-drain writes no sentinel outside session-start mode" {
  run drain prompt
  [ "$status" -eq 0 ]
  [ ! -e "$S/mailbox-drain.start" ]
}

# ── sentinel wiring: dod-persist (SessionStart branch), fixture DoD store ─────────────────────────
dodrepo() {
  export WRAP_DOD_DIR="$BATS_TEST_TMPDIR/dod" CC_DOD_LINEAGE_ONLY=0; mkdir -p "$WRAP_DOD_DIR"
  CWD="$BATS_TEST_TMPDIR/wt"; mkdir -p "$CWD"
  git -C "$CWD" init -q; git -C "$CWD" config user.email t@t; git -C "$CWD" config user.name t
  echo x > "$CWD/f"; git -C "$CWD" add f; git -C "$CWD" commit -qm init
}

@test "dod-persist SessionStart leaves start+done, owing the context it injected" {
  dodrepo
  f="$(bash "$REPO/hooks/dod-persist.sh" path "$CWD" | tr -d '\n')"; mkdir -p "$(dirname "$f")"
  printf '# Durable frozen DoD\nScope (frozen): ship the widget\n' > "$f"
  run bash -c "jq -nc --arg c '$CWD' --arg s '$SID' '{hook_event_name:\"SessionStart\",cwd:\$c,session_id:\$s}' | bash '$REPO/hooks/dod-persist.sh'"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qF 'ship the widget'
  [ "$(field dod-persist.done rc)" = 0 ]
  [ "$(field dod-persist.done owed)" -gt 0 ]
}

@test "dod-persist with no DoD owes nothing; with no payload session id it writes no sentinel" {
  dodrepo
  run bash -c "jq -nc --arg c '$CWD' --arg s '$SID' '{hook_event_name:\"SessionStart\",cwd:\$c,session_id:\$s}' | bash '$REPO/hooks/dod-persist.sh'"
  [ "$(field dod-persist.done owed)" = 0 ]
  rm -rf "$S"
  run bash -c "jq -nc --arg c '$CWD' '{hook_event_name:\"SessionStart\",cwd:\$c}' | CLAUDE_CODE_SESSION_ID='$SID' bash '$REPO/hooks/dod-persist.sh'"
  [ ! -e "$S" ]                                  # the env fallback never names a sentinel
}

# ── sentinel wiring + 3.6 alert seam: session-start-dispatch, fixture children ────────────────────
ssd_setup() {
  H="$BATS_TEST_TMPDIR/children"; mkdir -p "$H"
  export CC_SSD_HOOK_DIR="$H" CC_SSD_LEDGER="$BATS_TEST_TMPDIR/ledger.jsonl" CC_SSD_SPOOL="$BATS_TEST_TMPDIR/spool"
  printf '{"session_id":"%s","hook_event_name":"SessionStart","source":"startup","transcript_path":"%s"}' \
    "$SID" "$BATS_TEST_TMPDIR/t.jsonl" > "$BATS_TEST_TMPDIR/p"
}
ssd_child() { printf '#!/bin/bash\n%s\n' "$2" > "$H/$1"; chmod +x "$H/$1"; }

@test "the dispatcher leaves start+done owing its board, and links its outbox for cc-startup-health" {
  ssd_setup; ssd_child a.sh 'echo BOARD-FROM-CHILD'
  run env CC_SSD_CHILDREN=a.sh /bin/bash "$REPO/hooks/session-start-dispatch.sh" < "$BATS_TEST_TMPDIR/p" 3>&-
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qF 'BOARD-FROM-CHILD'
  [ "$(field session-start-dispatch.done rc)" = 0 ]
  [ "$(field session-start-dispatch.done owed)" = "$(( ${#output} + 1 ))" ]
  [ "$(field session-start-dispatch.done timeout_ms)" = 12000 ]
  [ "$(field session.start transcript_path)" = "$BATS_TEST_TMPDIR/t.jsonl" ]
  [ -L "$S/outbox.txt" ]
  [ -s "$S/outbox.txt" ]
  run CSH "$SID"
  printf '%s\n' "$output" | grep -qF '    BOARD-FROM-CHILD'
}

@test "3.6 a harness TERM of the dispatcher: done rc 143, one alert line naming what was running" {
  ssd_setup; ssd_child fast.sh 'echo FAST'
  ssd_child hang.sh "echo \$\$ >> '$BATS_TEST_TMPDIR/pids'; exec sleep 60"
  CC_SSD_CHILDREN="fast.sh hang.sh" CC_SSD_EMIT_S=20 CC_SSD_LATE_S=21 \
    /bin/bash "$REPO/hooks/session-start-dispatch.sh" < "$BATS_TEST_TMPDIR/p" > "$BATS_TEST_TMPDIR/out" 3>&- &
  dp=$!
  for _ in $(seq 1 150); do [ -s "$BATS_TEST_TMPDIR/pids" ] && [ -e "$S/session-start-dispatch.start" ] && break; sleep 0.1; done
  kill -TERM "$dp"; wait "$dp" || true
  while read -r p; do kill -KILL "$p" 2>/dev/null || true; done < "$BATS_TEST_TMPDIR/pids"
  [ "$(field session-start-dispatch.done rc)" = 143 ]
  grep -qF '⚠ startup: session-start-dispatch may not have delivered (cancelled by Claude Code; still running: hang.sh) — confirming' "$(ALERTS)"
  [ -L "$S/outbox.txt" ]
}

# ── 5.4 stamp only after proof of delivery (hooks/lib/startup-proof.sh + sh_settle) ───────────────
# A delivered-hook record in the transcript, the shape Claude Code writes for SessionStart output.
delivered_rec() { # <attachment type> <text>
  jq -nc --arg t "$1" --arg c "$2" '{type:"attachment",attachment:{type:$t,hookName:"SessionStart:startup",hookEvent:"SessionStart",content:$c},timestamp:"2026-10-18T12:00:07.000Z"}'
}
settle() { bash -c '. "$1"; sh_settle "$2"' _ "$(RLIB)" "$S"; }
scanned() { mkdir -p "$S"; : > "$S/cancels.tsv"; }        # this start epoch is scanned (no .start yet)

rcy_packet() {
  export CC_RECYCLE_FAILED_DIR="$BATS_TEST_TMPDIR/recycle-failed"; mkdir -p "$CC_RECYCLE_FAILED_DIR"
  TOK="recycle-recovery:$SID:1791000000"; PKT="$CC_RECYCLE_FAILED_DIR/$SID.json"
  jq -n --arg tok "$TOK" '{failed_at:"2026-10-09T05:31:00Z", token:$tok}' > "$PKT"
  printf 'Your self-recycle FAILED. token %s\n' "$TOK" > "$CC_RECYCLE_FAILED_DIR/$SID.prompt.md"
}
rcy_hook() {
  printf '{"session_id":"%s","hook_event_name":"SessionStart","source":"resume"}' "$SID" \
    | /bin/bash "$REPO/hooks/recycle-failed-inject.sh"
}

@test "5.4 recycle order: printed, NOT stamped at print; the transcript's record of it stamps injected_at" {
  rcy_packet
  run rcy_hook
  printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext' | grep -qF "$TOK"
  [ -z "$(jq -r '.injected_at // empty' "$PKT")" ]
  [ -f "$S/proof.recycle-order" ]
  TP="$BATS_TEST_TMPDIR/t.jsonl"; mksession "$TP"
  { delivered_rec hook_additional_context "RECYCLE FAILED … recovery token $TOK"; user_rec; } > "$TP"
  scanned; settle
  [ -n "$(jq -r '.injected_at // empty' "$PKT")" ]
  [ -f "$S/settled.recycle-order" ]
}

@test "5.4 recycle order lost at startup: the front injects it ONCE, and that turn's record proves it" {
  rcy_packet; rcy_hook >/dev/null
  TP="$BATS_TEST_TMPDIR/t.jsonl"; mksession "$TP"; user_rec > "$TP"
  scanned; settle
  [ -f "$S/fallback.recycle-order" ]
  [ -z "$(jq -r '.injected_at // empty' "$PKT")" ]
  run front
  ctx "$output" | grep -qF "$TOK"
  sys "$output" | grep -qF 'recycle-order did not reach this session at startup — delivered now'
  [ -f "$S/fallback.recycle-order.sent" ]
  run front; [ -z "$(ctx "$output")" ]                         # once
  jq -nc --arg c "$(cat "$S/fallback.recycle-order.sent")" \
    '{type:"attachment",attachment:{type:"hook_additional_context",hookEvent:"UserPromptSubmit",content:$c}}' >> "$TP"
  settle
  [ -n "$(jq -r '.injected_at // empty' "$PKT")" ]
}

@test "5.4 a request whose start ended without proof (no fallback) runs no action and is unproven" {
  TP="$BATS_TEST_TMPDIR/t.jsonl"; mksession "$TP"; user_rec > "$TP"
  bash -c '. "$1"; sp_request "$2" probe "NEEDLE-ZZ" touch "$3"' _ "$REPO/hooks/lib/startup-proof.sh" "$SID" "$BATS_TEST_TMPDIR/latch"
  settle; [ -f "$S/proof.probe" ]                              # not scanned yet: undecided
  scanned; settle
  [ -f "$S/unproven.probe" ]
  [ ! -e "$BATS_TEST_TMPDIR/latch" ]
}

@test "5.4 CC_STARTUP_PROOF=0 restores print-then-stamp" {
  rcy_packet
  run env CC_STARTUP_PROOF=0 /bin/bash -c "printf '{\"session_id\":\"$SID\"}' | /bin/bash '$REPO/hooks/recycle-failed-inject.sh'"
  [ -n "$(jq -r '.injected_at // empty' "$PKT")" ]
  [ ! -e "$S/proof.recycle-order" ]
}

@test "5.4 desk brief: the fired row waits for proof; unproven writes failed/not-delivered instead" {
  mkdir -p "$BATS_TEST_TMPDIR/roles"; echo p1 > "$BATS_TEST_TMPDIR/roles/desk"
  printf 'brief body\n' > "$BATS_TEST_TMPDIR/brief.md"
  IDLF="$BATS_TEST_TMPDIR/idl.jsonl"
  run bash -c "printf '{\"session_id\":\"$SID\"}' | DESK_BRIEF_IDL='$IDLF' CC_ROLES_DIR='$BATS_TEST_TMPDIR/roles' DESK_BRIEF_PANE=p1 DESK_BRIEF_FILE='$BATS_TEST_TMPDIR/brief.md' bash '$REPO/hooks/desk-brief-inject.sh'"
  [ "$status" -eq 0 ]
  # shellcheck disable=SC2143  # deliberate: a bare `! grep -q` never fails a bats test
  [ -z "$(grep '"fired"' "$IDLF" 2>/dev/null)" ]                # no fired row at print
  TP="$BATS_TEST_TMPDIR/t.jsonl"; mksession "$TP"
  { delivered_rec hook_additional_context "You hold the machine-wide DESK role (…)"; user_rec; } > "$TP"
  scanned; settle
  [ "$(jq -r 'select(.disposition == "fired") | .reason + " " + .pane + " " + .hook' "$IDLF")" = "injected p1 desk-brief-inject" ]
}

@test "5.4 deadline banner: the latch is written on proof, not at print" {
  export DL_DIR="$BATS_TEST_TMPDIR/deadlines"; mkdir -p "$DL_DIR/.state" "$BATS_TEST_TMPDIR/work"
  export CLAUDE_CODE_ENTRYPOINT=cli CC_PANE_ID=pane-fixture CC_FIRED_DIR="$BATS_TEST_TMPDIR/fired"
  printf '⏰ Pay the fixture bill — tomorrow\n' > "$DL_DIR/.state/banner.txt"
  printf 'BOARDBODY\n' > "$CC_ACCOUNTS_BOARD"
  run bash -c "printf '{\"source\":\"startup\",\"cwd\":\"$BATS_TEST_TMPDIR/work\",\"session_id\":\"$SID\"}' | '$REPO/hooks/accounts-board.sh'"
  printf '%s' "$output" | jq -r .systemMessage | grep -qF 'Pay the fixture bill'
  [ ! -e "$DL_DIR/.state/banner-latch" ]
  TP="$BATS_TEST_TMPDIR/t.jsonl"; mksession "$TP"
  { delivered_rec hook_system_message "⏰ Pay the fixture bill — tomorrow
BOARDBODY"; user_rec; } > "$TP"
  scanned; settle
  [[ "$(cat "$DL_DIR/.state/banner-latch")" == "$(date +%F) "* ]]
}

@test "5.4 goal nudge at SessionStart: the once-marker waits for proof" {
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"; mkdir -p "$CC_MAILBOX_DIR"
  GT="$BATS_TEST_TMPDIR/goal.jsonl"
  printf '{"type":"attachment","attachment":{"type":"goal_status","met":false,"sentinel":true,"condition":"finish"}}\n' > "$GT"
  gd() { printf '{"transcript_path":"%s","session_id":"%s"}' "$GT" "$SID" | ITERM_SESSION_ID="w0t0p0:AAAAAAAA-1111-2222-3333-444444444444" bash "$REPO/hooks/mailbox-drain.sh" session-start; }
  run gd; printf '%s' "$output" | grep -qF 'do NOT park the ordinary 4-hour watcher'
  [ -z "$(ls -A "$CC_MAILBOX_DIR/.goalnudge" 2>/dev/null)" ]
  run gd; printf '%s' "$output" | grep -qF 'do NOT park'      # unproven: said again
  TP="$BATS_TEST_TMPDIR/t.jsonl"; mksession "$TP"
  { delivered_rec hook_additional_context "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"; user_rec; } > "$TP"
  scanned; settle
  [ -n "$(ls -A "$CC_MAILBOX_DIR/.goalnudge" 2>/dev/null)" ]
}

@test "5.4 an idl request whose start ended without proof writes failed / not-delivered, never fired" {
  IDLF="$BATS_TEST_TMPDIR/idl.jsonl"
  TP="$BATS_TEST_TMPDIR/t.jsonl"; mksession "$TP"; user_rec > "$TP"
  bash -c '. "$1"; sp_request "$2" desk-brief "You hold the machine-wide DESK role" idl "$3" desk-brief-inject "{\"pane\":\"p1\"}"' \
    _ "$REPO/hooks/lib/startup-proof.sh" "$SID" "$IDLF"
  scanned; settle
  [ "$(jq -r '.disposition + " " + .reason + " " + .pane' "$IDLF")" = "failed not-delivered p1" ]
  [ -f "$S/unproven.desk-brief" ]
}

@test "3.5 the fold folds a settled session once (cache), and refolds it when a file in it changes" {
  mksid aaaa-1 dod-persist 0 900 "$HK/dod-persist.sh"
  CSH --fleet
  C="$CC_STARTUP_HEALTH_DIR/aaaa-1/fold.cache"
  [ -f "$C" ]
  rm -f "$BATS_TEST_TMPDIR/aaaa-1.jsonl"                       # cached: the transcript is no longer read
  CSH --fleet
  LINE | grep -qF ': 1 — dod-persist 1 ·'
  TZ=UTC touch -t 202601010000.00 "$C"                         # any file in the dir now newer ⇒ refold
  CSH --fleet
  [ "$C" -nt "$CC_STARTUP_HEALTH_DIR/aaaa-1/dod-persist.done" ]
  LINE | grep -qF ': 1 — dod-persist 1 ·'                      # the stored verdicts still count it
}

@test "3.5 --ack records occurrences only, never the start rows the detector counts" {
  mksid aaaa-1 dod-persist 0 900 "$HK/dod-persist.sh"
  CSH --ack
  [ "$(cat "$CC_STARTUP_HEALTH_DIR/fleet-ack.txt")" = "$(grep -o 'aaaa-1:dod-persist:[0-9]*' "$CC_STARTUP_HEALTH_DIR/aaaa-1/fold.cache" | head -1)" ]
}

# ── #25 load-banded startup span guard (fixture dispatcher ledger + capacity log) ─────────────────
span_fixture() { # <load_1m> <total_ms>... — one start per ms, a minute apart, each with a load sample
  local load="$1" i=0 now t ms; shift
  export CC_SSD_LEDGER="$BATS_TEST_TMPDIR/ssd.jsonl" CC_CAPACITY_LOG="$BATS_TEST_TMPDIR/cap.jsonl"
  now="$(date +%s)"
  for ms in "$@"; do
    i=$(( i + 1 )); t="$(date -u -r $(( now - i * 60 )) +%FT%TZ)"
    printf '{"ts":"%s","load_1m":%s}\n' "$(date -u -r $(( now - i * 60 - 30 )) +%FT%TZ)" "$load" >> "$CC_CAPACITY_LOG"
    printf '{"v":1,"ts":"%s","sid":"s%s","total_ms":%s}\n' "$t" "$i" "$ms" >> "$CC_SSD_LEDGER"
  done
  mkdir -p "$CC_STARTUP_HEALTH_DIR"
}
SPANLINE() { cat "$CC_STARTUP_HEALTH_DIR/span-line.txt"; }

@test "#25 a load band whose 24 h p90 is over 10.1 s puts one line on the board" {
  span_fixture 420 12000 12500 13000 13500 14000 9000
  CSH --fleet
  [ "$(SPANLINE)" = "⚠ startup span p90 13.5 s at load 300+ over 24 h (n 6; target 10.1 s) · cc-startup-health --span" ]
  board | grep -qF '⚠ startup span p90 13.5 s at load 300+'
}

@test "#25 inside the target, or too few starts, the guard adds no line" {
  span_fixture 40 2000 2500 3000 3500 4000 4500
  CSH --fleet; [ ! -s "$CC_STARTUP_HEALTH_DIR/span-line.txt" ]
  [ "$(board)" = BOARDBODY ]
  rm -f "$CC_SSD_LEDGER" "$CC_CAPACITY_LOG" "$CC_STARTUP_HEALTH_DIR/span.stamp"
  span_fixture 420 15000 15000 15000
  CSH --fleet; [ ! -s "$CC_STARTUP_HEALTH_DIR/span-line.txt" ]   # n 3 < 5
}

@test "#25 the guard recomputes at most hourly; --span prints both windows by band" {
  span_fixture 120 3000 3000 3000 3000 3000
  CSH --fleet; [ ! -s "$CC_STARTUP_HEALTH_DIR/span-line.txt" ]
  span_fixture 120 20000 20000 20000 20000 20000 20000 20000 20000 20000 20000 20000
  CSH --fleet; [ ! -s "$CC_STARTUP_HEALTH_DIR/span-line.txt" ]    # within the hour: not re-read
  CC_STARTUP_SPAN_EVERY_S=0 CSH --fleet
  SPANLINE | grep -qF 'at load 50-150 over 24 h (n 16;'
  run CSH --span
  printf '%s\n' "$output" | grep -qE '^  50-150 +16 '
  printf '%s\n' "$output" | grep -qF 'last 7 d:'
}

# ── #26 fleet drop detector, shadow mode ───────────────────────────────────────────────────────────
# Sentinel-only sessions (no transcript): a dod-persist .done rc 143 is a loss, rc 0 a clean start.
det_sid() { # <sid> <rc> <age-s>
  local d="$CC_STARTUP_HEALTH_DIR/$1" t
  mkdir -p "$d"; printf 'transcript_path=%s\nsize=0\n' "$BATS_TEST_TMPDIR/none.jsonl" > "$d/session.start"
  : > "$d/dod-persist.start"; printf 'rc=%s\nelapsed_s=1\nowed=900\ntimeout_ms=5000\n' "$2" > "$d/dod-persist.done"
  t="$(date -r $(( $(date +%s) - $3 )) +%Y%m%d%H%M.%S)"; touch -t "$t" "$d/dod-persist.start" "$d/session.start"
}
DLOG() { cat "$BATS_TEST_TMPDIR/detector.jsonl" 2>/dev/null; }

@test "#26 the floor and never-seen rules trip in SHADOW: logged, never on the board; ack clears per occurrence" {
  export CC_STARTUP_DETECT_LOG="$BATS_TEST_TMPDIR/detector.jsonl"
  det_sid dddd-1 143 3600; det_sid dddd-2 143 3600; det_sid dddd-3 143 3600
  CSH --fleet
  [ "$(DLOG | jq -r 'select(.event == "trip") | .rule + " " + .hook + " " + (.losses_6h | tostring)' | sort | tr '\n' ',')" = "floor dod-persist 3,new dod-persist 3," ]
  DLOG | jq -e 'select(.event == "trip") | .shadow == true' >/dev/null
  [ "$(board | grep -ciE 'detector|trip|relative')" = 0 ]      # shadow: nothing of it on the board
  CSH --fleet
  [ "$(DLOG | jq -r 'select(.event == "trip")' | grep -c '"trip"')" = 2 ]   # a held trip is logged once
  CSH --ack
  [ "$(DLOG | jq -r 'select(.event == "clear") | .rule' | sort | tr '\n' ',')" = "floor,new," ]
  [ ! -s "$CC_STARTUP_HEALTH_DIR/detector.state" ]
}

@test "#26 a trip is held until its own occurrences are acked, not cleared by a later quiet window" {
  export CC_STARTUP_DETECT_LOG="$BATS_TEST_TMPDIR/detector.jsonl"
  det_sid dddd-1 143 3600; det_sid dddd-2 143 3600; det_sid dddd-3 143 3600
  CSH --fleet
  for s in dddd-1 dddd-2 dddd-3; do touch -t "$(date -r $(( $(date +%s) - 30000 )) +%Y%m%d%H%M.%S)" "$CC_STARTUP_HEALTH_DIR/$s/dod-persist.start"; done
  CSH --fleet                                                  # all three now older than 6 h
  grep -q '^floor' "$CC_STARTUP_HEALTH_DIR/detector.state"
  [ -z "$(DLOG | jq -r 'select(.event == "clear")')" ]
}

@test "#26 the relative rule: a 6 h share at least twice the 7 d share, >= 5 %, n >= 20 — below the floor" {
  export CC_STARTUP_DETECT_LOG="$BATS_TEST_TMPDIR/detector.jsonl"
  for i in $(seq 1 40); do det_sid "old-$i" 0 172800; done
  det_sid old-41 143 172800                                    # a prior loss: dod-persist is not "new"
  for i in $(seq 1 18); do det_sid "new-$i" 0 3600; done
  det_sid new-19 143 3600; det_sid new-20 143 3600             # 2 of 20 in 6 h (10 %) vs 3 of 61 in 7 d
  CSH --fleet
  [ "$(DLOG | jq -r 'select(.event == "trip") | .rule' | tr '\n' ',')" = "relative," ]
  run CSH --detector
  printf '%s\n' "$output" | grep -qE 'relative +dod-persist +2 occurrence'
}
