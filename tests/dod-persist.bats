#!/usr/bin/env bats
# dod-persist.sh — durable frozen-DoD carrier (a19 §2 HOP A-E). Modes:
#   SessionStart : re-inject the durable DoD file's verbatim content as additionalContext.
#   PreCompact   : mechanical-grep the newest `Scope (frozen):` line from the transcript and APPEND
#                  it (timestamped, INTEGRATE) to the durable file IF ABSENT-or-stale.
#   set "<scope>": CLI freeze; path [cwd]: resolve the durable path.
# PATH CONTRACT: identical to scripts/wrap-ledger.sh (WRAP_DOD_FILE / WRAP_DOD_DIR + toplevel hash),
# so producer (this) and consumer (wrap-ledger/completion-assert) resolve the SAME file — proven end
# to end below (dod-persist writes → wrap-ledger reports DOD=present).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/dod-persist.sh"
  export WRAP_DOD_DIR="$BATS_TEST_TMPDIR/dod"; mkdir -p "$WRAP_DOD_DIR"
  CWD="$BATS_TEST_TMPDIR/wt"; mkdir -p "$CWD"
  git -C "$CWD" init -q; git -C "$CWD" config user.email t@t; git -C "$CWD" config user.name t
  echo x > "$CWD/f"; git -C "$CWD" add f; git -C "$CWD" commit -qm init
}

dod_path() { bash "$HOOK" path "$CWD" | tr -d '\n'; }   # resolved durable-DoD file for $CWD
run_hook() { printf '%s' "$1" | bash "$HOOK" 2>/dev/null; }   # $1 = stdin JSON
# transcript whose newest assistant text carries "Scope (frozen): $1"
mktx() {
  local path="$BATS_TEST_TMPDIR/tx-${BATS_TEST_NUMBER}-$RANDOM.jsonl"
  {
    jq -nc '{type:"user",message:{content:"do the task"}}'
    jq -nc --arg s "$1" '{type:"assistant",message:{content:[{type:"text",text:("Scope (frozen): " + $s)}]}}'
    jq -nc '{type:"assistant",message:{content:[{type:"text",text:"working..."}]}}'
  } > "$path"
  printf '%s' "$path"
}
sjson() { jq -nc --arg c "$CWD" --arg e "$1" '{hook_event_name:$e,cwd:$c}'; }         # SessionStart/other
pjson() { jq -nc --arg c "$CWD" --arg t "$1" '{hook_event_name:"PreCompact",cwd:$c,transcript_path:$t,trigger:"auto"}'; }

# ── SessionStart re-injection ─────────────────────────────────────────────────────
@test "SessionStart: existing DoD file ⇒ additionalContext carrying its verbatim scope" {
  local f; f="$(dod_path)"; mkdir -p "$(dirname "$f")"
  printf '# Durable frozen DoD\nScope (frozen): ship the widget with tests\n' > "$f"
  run run_hook "$(sjson SessionStart)"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'hookSpecificOutput'
  printf '%s' "$output" | grep -q 'additionalContext'
  printf '%s' "$output" | grep -q 'ship the widget with tests'
}

@test "SessionStart: no DoD file ⇒ silent exit 0 (nothing to re-inject)" {
  run run_hook "$(sjson SessionStart)"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── PreCompact extraction ─────────────────────────────────────────────────────────
@test "PreCompact: extracts newest 'Scope (frozen):' from the transcript → writes durable file" {
  run run_hook "$(pjson "$(mktx "build A, migrate B, verify C")")"
  [ "$status" -eq 0 ]
  local f; f="$(dod_path)"; [ -f "$f" ]
  grep -q 'Scope (frozen): build A, migrate B, verify C' "$f"
}

@test "PreCompact: no 'Scope (frozen):' in transcript ⇒ no file written (no-op)" {
  local tx="$BATS_TEST_TMPDIR/notx.jsonl"
  jq -nc '{type:"assistant",message:{content:[{type:"text",text:"just chatting, no scope"}]}}' > "$tx"
  run run_hook "$(pjson "$tx")"
  [ "$status" -eq 0 ]; [ ! -f "$(dod_path)" ]
}

@test "PreCompact: newest of multiple 'Scope (frozen):' lines wins (tail-most)" {
  local tx="$BATS_TEST_TMPDIR/multitx.jsonl"
  {
    jq -nc '{type:"assistant",message:{content:[{type:"text",text:"Scope (frozen): OLD scope"}]}}'
    jq -nc '{type:"assistant",message:{content:[{type:"text",text:"Scope (frozen): NEW scope"}]}}'
  } > "$tx"
  run run_hook "$(pjson "$tx")"
  local f; f="$(dod_path)"
  grep -q 'Scope (frozen): NEW scope' "$f"
  run grep -c 'OLD scope' "$f"; [ "$output" = "0" ]      # only the newest is captured
}

# ── set CLI ───────────────────────────────────────────────────────────────────────
@test "set: writes the durable file, normalizing a bare scope to a 'Scope (frozen):' line" {
  ( cd "$CWD" && bash "$HOOK" set "ship X and Y" >/dev/null )
  grep -q 'Scope (frozen): ship X and Y' "$(dod_path)"
}

@test "set: a line already carrying 'Scope (frozen):' is not double-prefixed" {
  ( cd "$CWD" && bash "$HOOK" set "Scope (frozen): already framed" >/dev/null )
  run grep -c 'Scope (frozen): Scope' "$(dod_path)"; [ "$output" = "0" ]
  grep -q 'Scope (frozen): already framed' "$(dod_path)"
}

@test "set: no arg ⇒ usage + exit 2" {
  run bash -c 'cd "$1" && bash "$2" set' _ "$CWD" "$HOOK"
  [ "$status" -eq 2 ]
}

# ── append-not-overwrite (INTEGRATE + dedup) ──────────────────────────────────────
@test "append: distinct scopes both persist (history kept); an identical re-capture dedups" {
  local f; f="$(dod_path)"
  ( cd "$CWD" && bash "$HOOK" set "scope ONE" >/dev/null )
  ( cd "$CWD" && bash "$HOOK" set "scope TWO" >/dev/null )
  grep -q 'scope ONE' "$f"                                # earlier capture NOT overwritten
  grep -q 'scope TWO' "$f"
  run grep -c 'Scope (frozen):' "$f"; [ "$output" -ge 2 ]
  local before after
  before="$(grep -c 'Scope (frozen):' "$f")"
  ( cd "$CWD" && bash "$HOOK" set "scope TWO" >/dev/null )   # identical to last ⇒ no duplicate
  after="$(grep -c 'Scope (frozen):' "$f")"
  [ "$before" = "$after" ]
}

@test "append: PreCompact with an unchanged scope does NOT duplicate the entry" {
  local tx; tx="$(mktx "steady scope")"
  run_hook "$(pjson "$tx")" >/dev/null                   # first capture
  local before; before="$(grep -c 'Scope (frozen):' "$(dod_path)")"
  run_hook "$(pjson "$tx")" >/dev/null                   # same scope again
  local after; after="$(grep -c 'Scope (frozen):' "$(dod_path)")"
  [ "$before" = "$after" ]
}

# ── PATH CONTRACT with wrap-ledger (producer↔consumer resolve the SAME file) ───────
@test "contract: dod-persist writes the SAME file wrap-ledger reads (DOD=present)" {
  ( cd "$CWD" && bash "$HOOK" set "the frozen scope" >/dev/null )
  run bash -c 'cd "$1" && WRAP_DOD_DIR="$2" bash "$3" --machine' _ "$CWD" "$WRAP_DOD_DIR" "$REPO/scripts/wrap-ledger.sh"
  printf '%s\n' "$output" | grep -q '^DOD=present'
}

# ── FAIL-SAFE (a SessionStart/PreCompact hook must never cost a session) ───────────
@test "fail-safe: PreCompact with a missing transcript ⇒ exit 0, no file" {
  run run_hook "$(jq -nc --arg c "$CWD" '{hook_event_name:"PreCompact",cwd:$c,transcript_path:"/no/such.jsonl"}')"
  [ "$status" -eq 0 ]; [ ! -f "$(dod_path)" ]
}
@test "fail-safe: garbage stdin ⇒ exit 0" {
  run bash -c 'printf "not json" | bash "$1" 2>/dev/null' _ "$HOOK"
  [ "$status" -eq 0 ]
}
@test "fail-safe: unknown hook_event_name ⇒ exit 0, no output" {
  run run_hook "$(sjson PostToolUse)"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── Follow-On Gate growth: Scope (grown) lines survive compaction like the baseline ──
mktx_grown() {  # $1 frozen  $2 grown1  [$3 grown2]
  local path="$BATS_TEST_TMPDIR/txg-${BATS_TEST_NUMBER}-$RANDOM.jsonl"
  {
    jq -nc --arg s "$1" '{type:"assistant",message:{content:[{type:"text",text:("Scope (frozen): " + $s)}]}}'
    jq -nc --arg g "$2" '{type:"assistant",message:{content:[{type:"text",text:("Scope (grown): " + $g)}]}}'
    if [ -n "${3:-}" ]; then
      jq -nc --arg g "$3" '{type:"assistant",message:{content:[{type:"text",text:("Scope (grown): " + $g)}]}}'
    fi
  } > "$path"
  printf '%s' "$path"
}

@test "PreCompact: grown lines captured alongside frozen (gate-passed growth survives compaction)" {
  local tx; tx="$(mktx_grown 'base task' '+ghost-pointer sweep' '+policy encode')"
  run run_hook "$(pjson "$tx")"
  [ "$status" -eq 0 ]
  local f; f="$(dod_path)"
  grep -q 'Scope (frozen): base task' "$f"
  grep -q 'Scope (grown): +ghost-pointer sweep' "$f"
  grep -q 'Scope (grown): +policy encode' "$f"
}

@test "PreCompact: grown dedup — re-compaction appends nothing; a NEW grown item still lands" {
  local tx; tx="$(mktx_grown 'base task' '+itemA')"
  run_hook "$(pjson "$tx")" >/dev/null
  local f n1; f="$(dod_path)"; n1=$(grep -c 'Scope (grown): +itemA' "$f")
  [ "$n1" -eq 1 ]
  run_hook "$(pjson "$tx")" >/dev/null
  [ "$(grep -c 'Scope (grown): +itemA' "$f")" -eq "$n1" ]
  local tx2; tx2="$(mktx_grown 'base task' '+itemA' '+itemB')"
  run_hook "$(pjson "$tx2")" >/dev/null
  [ "$(grep -c 'Scope (grown): +itemA' "$f")" -eq "$n1" ]
  grep -q 'Scope (grown): +itemB' "$f"
}

@test "PreCompact: grown-only transcript (no frozen line) still persists the growth" {
  local path="$BATS_TEST_TMPDIR/txg-only-$RANDOM.jsonl"
  jq -nc '{type:"assistant",message:{content:[{type:"text",text:"Scope (grown): +solo growth"}]}}' > "$path"
  run run_hook "$(pjson "$path")"
  [ "$status" -eq 0 ]
  grep -q 'Scope (grown): +solo growth' "$(dod_path)"
}

@test "set: a grown line is accepted verbatim, never double-prefixed as frozen" {
  ( cd "$CWD" && bash "$HOOK" set "Scope (grown): +extra thing" )
  local f; f="$(dod_path)"
  grep -q '^Scope (grown): +extra thing' "$f"
  ! grep -q 'Scope (frozen): Scope (grown)' "$f"
}

@test "SessionStart: framing declares grown lines binding + pre-authorized" {
  local f; f="$(dod_path)"; mkdir -p "$(dirname "$f")"
  printf 'Scope (frozen): base\nScope (grown): +x\n' > "$f"
  run run_hook "$(sjson SessionStart)"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "Scope (grown)"
  printf '%s' "$output" | grep -q 'do NOT re-ask'
}
