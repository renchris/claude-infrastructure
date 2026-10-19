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
  { cancel_rec '~/.claude/hooks/dod-persist.sh'; user_rec; } > "$TP"
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
  { cancel_rec '~/.claude/hooks/mailbox-drain.sh session-start'; user_rec; } > "$TP"
  scan; [ "$(verdict mailbox-drain)" = nothing-owed ]       # cancelled, but it owed nothing
  mkdone mailbox-drain 141 0 120; rm -f "$S/cancels.tsv"
  scan; [ "$(verdict mailbox-drain)" = confirmed ]
  user_rec > "$TP"; rm -f "$S/cancels.tsv"
  scan; [ "$(verdict mailbox-drain)" = cleared ]
}

@test "3.4(d) resume: a cancel past the stored offset is reported, one before it is ignored" {
  TP="$BATS_TEST_TMPDIR/t.jsonl"
  { cancel_rec '~/.claude/hooks/old-hook.sh'; user_rec; } > "$TP"
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
  { cancel_rec '~/.claude/hooks/dod-persist.sh' '2026-10-18T11:59:00.000Z'; user_rec; } > "$TP"
  mksession "$TP"; mkstart dod-persist; mkdone dod-persist 0 1 900
  scan
  [ "$(verdict dod-persist)" = cleared ]
  [ ! -s "$S/cancels.tsv" ]
}

@test "3.4 a resumed epoch (session.start older than the new .start) reads past the first user record" {
  TP="$BATS_TEST_TMPDIR/t.jsonl"
  { user_rec; user_rec; cancel_rec '~/.claude/hooks/dod-persist.sh' '2026-10-18T13:00:06.000Z'; } > "$TP"
  mksession "$TP"; mkstart dod-persist 202610181300.00; mkdone dod-persist 0 5 900
  scan
  [ "$(verdict dod-persist)" = confirmed ]
}

@test "3.4 an own hook cancelled before its sentinel opened is own (confirmed), never foreign" {
  TP="$BATS_TEST_TMPDIR/t.jsonl"
  { cancel_rec '~/.claude/hooks/session-start-dispatch.sh' '' 12004; user_rec; } > "$TP"
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
  { cancel_rec '~/.claude/hooks/desk-brief-inject.sh'; user_rec; } > "$TP"
  bash -c '. "$1"; sh_worker "$2"' _ "$(RLIB)" "$SID"
  [ "$(verdict desk-brief-inject)" = cleared ]                # current epoch: not rescanned
  mkstart desk-brief-inject 202610181205.00; mkdone desk-brief-inject 0 1 0
  { cancel_rec '~/.claude/hooks/desk-brief-inject.sh' '2026-10-18T12:05:06.000Z'; user_rec; } >> "$TP"
  bash -c '. "$1"; sh_worker "$2"' _ "$(RLIB)" "$SID"
  [ "$(verdict desk-brief-inject)" = nothing-owed ]           # the new epoch was scanned
}

@test "3.4 the worker falls back to the payload's transcript path when session.start has none" {
  TP="$BATS_TEST_TMPDIR/t.jsonl"
  { cancel_rec '~/.claude/hooks/dod-persist.sh'; user_rec; } > "$TP"
  mksession ""; mkstart dod-persist; mkdone dod-persist 0 5 900
  bash -c '. "$1"; sh_worker "$2" "$3"' _ "$(RLIB)" "$SID" "$TP"
  [ "$(verdict dod-persist)" = confirmed ]
}

@test "3.4 session-beat's prompt worker writes the verdicts (fixture HOME, no live state)" {
  TP="$BATS_TEST_TMPDIR/t.jsonl"
  { cancel_rec '~/.claude/hooks/dod-persist.sh'; user_rec; } > "$TP"
  mksession "$TP"; mkstart dod-persist; mkdone dod-persist 0 5 900
  export CC_BEAT_DIR="$BATS_TEST_TMPDIR/beats" CC_BEAT_LOG="$BATS_TEST_TMPDIR/beat.log"
  printf '{"session_id":"%s","cwd":"/tmp","prompt":"hi","transcript_path":"%s"}' "$SID" "$TP" \
    | /bin/bash "$REPO/hooks/session-beat.sh" prompt
  for _ in $(seq 1 150); do [ -f "$S/cancels.tsv" ] && break; sleep 0.2; done
  [ "$(verdict dod-persist)" = confirmed ]
}

