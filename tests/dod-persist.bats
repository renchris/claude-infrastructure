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

# ── PER-CAPTURE PROVENANCE (crosstalk prerequisite 1) ─────────────────────────────
# docs/research/dod-crosstalk-2026-08-18.md §4.1: the store is repo-keyed, so N worktrees of one repo
# APPEND to one file — but `persist_dod` recorded the writing cwd only in the file HEADER, i.e. for
# the FIRST writer. "No reader can attribute a capture to a wave, so no read-side rule has an input
# to key on, however clever." These cases pin the missing input: every `## <ts>` block names the
# toplevel that wrote it, and the session id when the caller knows one. Strictly additive — the
# reader-neutrality control below is what keeps it that way.

@test "provenance: a 'set' capture block names the writing git toplevel" {
  local top; top="$(git -C "$CWD" rev-parse --show-toplevel)"
  ( cd "$CWD" && bash "$HOOK" set "provenance via set" >/dev/null )
  local f; f="$(dod_path)"
  # the toplevel rides the capture's own '## ' block header, not just the file header
  grep -E '^## ' "$f" | grep -qF -- "toplevel=$top"
}

@test "provenance: a PreCompact capture block names the toplevel of the writing worktree" {
  local top; top="$(git -C "$CWD" rev-parse --show-toplevel)"
  run run_hook "$(pjson "$(mktx "provenance via PreCompact")")"
  [ "$status" -eq 0 ]
  local f; f="$(dod_path)"
  grep -E '^## ' "$f" | grep -qF -- "toplevel=$top"
}

@test "provenance: the hook JSON's session_id lands on the capture block" {
  local tx; tx="$(mktx "scope with a session")"
  run run_hook "$(jq -nc --arg c "$CWD" --arg t "$tx" \
    '{hook_event_name:"PreCompact",cwd:$c,transcript_path:$t,trigger:"auto",session_id:"sid-ABC123"}')"
  [ "$status" -eq 0 ]
  grep -E '^## ' "$(dod_path)" | grep -qF -- "session=sid-ABC123"
}

@test "provenance: no session id known ⇒ the field is OMITTED, never an empty 'session='" {
  # HERMETIC: the payload carries no session_id AND the env fallback is unset, so this exercises the
  # real omission branch. Without the unset, the live CLAUDE_CODE_SESSION_ID leaks in from the bats
  # environment and the case passes for a reason it does not test.
  local json; json="$(pjson "$(mktx "scope with no session")")"
  run bash -c 'unset CLAUDE_CODE_SESSION_ID; printf "%s" "$1" | bash "$2" 2>/dev/null' _ "$json" "$HOOK"
  [ "$status" -eq 0 ]
  local f; f="$(dod_path)"
  grep -E '^## ' "$f" | grep -qF -- 'toplevel='      # provenance still stamped
  ! grep -E '^## ' "$f" | grep -qF -- 'session='     # the field is absent, not blank
}

@test "provenance: PER-CAPTURE, not per-file — two worktrees sharing one store each name their own" {
  # The exact §4.1 defect: one shared file, two writers, and only the first was attributable.
  local shared="$BATS_TEST_TMPDIR/shared-store.md"
  local other="$BATS_TEST_TMPDIR/wt-b"; mkdir -p "$other"
  git -C "$other" init -q; git -C "$other" config user.email t@t; git -C "$other" config user.name t
  echo y > "$other/f"; git -C "$other" add f; git -C "$other" commit -qm init
  local topA topB; topA="$(git -C "$CWD" rev-parse --show-toplevel)"; topB="$(git -C "$other" rev-parse --show-toplevel)"
  [ -n "$topA" ] && [ -n "$topB" ] && [ "$topA" != "$topB" ] || false # the axis is live, not vacuous
  ( cd "$CWD"   && WRAP_DOD_FILE="$shared" bash "$HOOK" set "wave A scope" >/dev/null )
  ( cd "$other" && WRAP_DOD_FILE="$shared" bash "$HOOK" set "wave B scope" >/dev/null )
  # BOTH captures are attributable — the second writer is not swallowed by the first's file header
  grep -E '^## ' "$shared" | grep -qF -- "toplevel=$topA"
  grep -E '^## ' "$shared" | grep -qF -- "toplevel=$topB"
  [ "$(grep -cE '^## ' "$shared")" -eq 2 ]
}

@test "provenance CONTROL: reader-neutral — no new unchecked box, DOD=present, REMAINDER unchanged" {
  ( cd "$CWD" && bash "$HOOK" set "control scope" >/dev/null )
  local f; f="$(dod_path)"
  # the stamp must not manufacture a frozen-DoD remainder item (wrap-ledger.sh:525 counts '- [ ]')
  run grep -cE '^[[:space:]]*[-*][[:space:]]+\[[[:space:]]\]' "$f"; [ "$output" = "0" ]
  run bash -c 'cd "$1" && WRAP_DOD_DIR="$2" bash "$3" --machine' _ "$CWD" "$WRAP_DOD_DIR" "$REPO/scripts/wrap-ledger.sh"
  printf '%s\n' "$output" | grep -q '^DOD=present'
  printf '%s\n' "$output" | grep -q '^REMAINDER=0'
  # and the scope line itself is untouched, so last_recorded_scope / `get` still resolve it
  run bash -c 'cd "$1" && bash "$2" get' _ "$CWD" "$HOOK"
  printf '%s' "$output" | grep -q 'Scope (frozen): control scope'
}

# ── INJECTION FRAME: newest-wins, matching the store's own semantics ──────────────
# docs/research/dod-crosstalk-2026-08-18.md §2 measured this as the ACTIVE half: SessionStart cats
# the whole repo-keyed file and frames it "Every 'Scope (frozen):' line below is binding … do NOT
# narrow scope or declare done until ALL of it is met" — so a session in any of 101 worktrees was
# handed 15 waves' contracts as ITS OWN. That framing also contradicted this very script: `get` and
# last_recorded_scope both return the NEWEST line only. These cases pin the injection to the same
# newest-wins semantics the rest of the store already has. LOSSLESS — nothing is dropped, the older
# captures are reframed as history rather than as additional binding scope.
# FAILS LOUD on an empty context. Without this an absent additionalContext makes every `! grep`
# below pass vacuously — the empty-compares-equal trap — and a negative assertion that can only
# ever pass is worse than no assertion at all.
ctx_of() {
  local c; c="$(printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
  [ -n "$c" ] && [ "$c" != "null" ] || { echo "ctx_of: EMPTY/absent additionalContext" >&2; return 1; }
  printf '%s' "$c"
}
HIST_MARK='full INTEGRATE-only history'

@test "injection: the NEWEST frozen line is named as THE current contract, above the history" {
  ( cd "$CWD" && bash "$HOOK" set "wave ONE scope" >/dev/null )
  ( cd "$CWD" && bash "$HOOK" set "wave TWO scope" >/dev/null )
  run run_hook "$(sjson SessionStart)"
  [ "$status" -eq 0 ]
  local ctx; ctx="$(ctx_of "$output")"
  printf '%s' "$ctx" | grep -q 'THE CURRENT CONTRACT'
  # the newest scope is called out ABOVE the history dump; the older one is not
  printf '%s' "$ctx" | sed -n "1,/$HIST_MARK/p" | grep -q 'wave TWO scope'
  ! printf '%s' "$ctx" | sed -n "1,/$HIST_MARK/p" | grep -q 'wave ONE scope'
}

@test "injection: prior captures are NOT framed as binding scope" {
  ( cd "$CWD" && bash "$HOOK" set "wave ONE scope" >/dev/null )
  ( cd "$CWD" && bash "$HOOK" set "wave TWO scope" >/dev/null )
  run run_hook "$(sjson SessionStart)"
  local ctx; ctx="$(ctx_of "$output")"
  # COUNT form, not `! grep`: bash errexit explicitly does NOT fire on a command "whose return value
  # is being inverted with !", so a bare `! cmd` is a live assertion ONLY as a test's FINAL command
  # (where bats takes the body's exit status). As an intermediate line it is DEAD and passes
  # whatever the truth is — measured here, on this very assertion.
  local bind_hits; bind_hits="$(printf '%s' "$ctx" | grep -cF "Every 'Scope (frozen):' line below is binding" || true)"
  [ "$bind_hits" -eq 0 ]
  printf '%s' "$ctx" | grep -qF 'NOT additional binding scope'
}

@test "injection LOSSLESS: every prior capture still reaches the session as history" {
  ( cd "$CWD" && bash "$HOOK" set "wave ONE scope" >/dev/null )
  ( cd "$CWD" && bash "$HOOK" set "wave TWO scope" >/dev/null )
  run run_hook "$(sjson SessionStart)"
  local ctx; ctx="$(ctx_of "$output")"
  printf '%s' "$ctx" | grep -q 'wave ONE scope'      # nothing is dropped …
  printf '%s' "$ctx" | grep -q 'wave TWO scope'      # … and the newest is still there too
}

@test "injection: gate-passed GROWN lines stay binding and pre-authorized (unchanged contract)" {
  ( cd "$CWD" && bash "$HOOK" set "the frozen base" >/dev/null )
  ( cd "$CWD" && bash "$HOOK" set "Scope (grown): +authorized extra" >/dev/null )
  run run_hook "$(sjson SessionStart)"
  local ctx; ctx="$(ctx_of "$output")"
  printf '%s' "$ctx" | grep -q 'Scope (grown)'
  printf '%s' "$ctx" | grep -q 'do NOT re-ask'
}

@test "injection CONTROL: a single-capture store still names that capture as the contract" {
  ( cd "$CWD" && bash "$HOOK" set "the only scope" >/dev/null )
  run run_hook "$(sjson SessionStart)"
  [ "$status" -eq 0 ]
  local ctx; ctx="$(ctx_of "$output")"
  printf '%s' "$ctx" | grep -q 'THE CURRENT CONTRACT'
  printf '%s' "$ctx" | sed -n "1,/$HIST_MARK/p" | grep -q 'the only scope'
}
