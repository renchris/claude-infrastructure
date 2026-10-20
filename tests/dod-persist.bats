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
  export CC_STARTUP_HEALTH_DIR="$BATS_TEST_TMPDIR/startup-health"  # startup sentinels: never the live ~/.claude/state/startup-health
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/dod-persist.sh"
  export WRAP_DOD_DIR="$BATS_TEST_TMPDIR/dod"; mkdir -p "$WRAP_DOD_DIR"
  # Lineage-only is the DEFAULT since 2026-09-24. The cases below that pin the older worktree frame
  # run it explicitly at =0; the lineage-only cases pass =1, and "unset is on" is asserted with env -u.
  export CC_DOD_LINEAGE_ONLY=0
  # every SessionStart appends a timing line; keep it in scratch, never the operator's log dir
  export CC_DOD_TIMING_LOG="$BATS_TEST_TMPDIR/dod-timing.jsonl"
  # the 3.5 s checkpoint is wall-clock: at high load it fires mid-suite and swaps the render for its
  # pointer, so every case runs without it except the checkpoint cases, which set it themselves
  export CC_DOD_CHECKPOINT_MS=0
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
# newest-wins semantics the rest of the store already has. The older captures are no longer injected
# at all (docs/research/startup-hooks-2026-10-18/README.md §2 #5): a one-line pointer names how many
# were left out, where they are and how to read them, framed as history, never as binding scope.
# FAILS LOUD on an empty context. Without this an absent additionalContext makes every `! grep`
# below pass vacuously — the empty-compares-equal trap — and a negative assertion that can only
# ever pass is worse than no assertion at all.
ctx_of() {
  local c; c="$(printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
  [ -n "$c" ] && [ "$c" != "null" ] || { echo "ctx_of: EMPTY/absent additionalContext" >&2; return 1; }
  printf '%s' "$c"
}
# The phrase that separates the binding contract from the history. Kept to the WORDING-STABLE
# core: it read 'full INTEGRATE-only history' until the lineage filter landed, at which point the
# injected history stopped being "full" (a concurrent wave's captures are now dropped) and every
# sed-range assertion below silently widened to the whole document — `sed -n '1,/nomatch/p'` prints
# EVERYTHING, so a stale marker does not fail, it inverts. _hist_mark_live is what makes that loud.
# Since the history became a pointer the phrase lives in that one line, still below the contract.
HIST_MARK='INTEGRATE-only history'

# A sed range over an ABSENT marker is vacuous — it selects the whole input, so every "…is NOT above
# the history" assertion below would pass by accident. Assert the marker exists first.
_hist_mark_live() {  # $1 = the injected context
  local n; n="$(printf '%s' "$1" | grep -cF "$HIST_MARK" || true)"
  [ "${n:-0}" -ge 1 ] || { echo "HIST_MARK '$HIST_MARK' absent — every sed-range assertion below is vacuous" >&2; return 1; }
}

@test "injection: the NEWEST frozen line is named as THE current contract, above the history" {
  ( cd "$CWD" && bash "$HOOK" set "wave ONE scope" >/dev/null )
  ( cd "$CWD" && bash "$HOOK" set "wave TWO scope" >/dev/null )
  run run_hook "$(sjson SessionStart)"
  [ "$status" -eq 0 ]
  local ctx; ctx="$(ctx_of "$output")"
  printf '%s' "$ctx" | grep -q 'THE CURRENT CONTRACT'
  _hist_mark_live "$ctx"
  # the newest scope is called out ABOVE the history dump; the older one is not
  printf '%s' "$ctx" | sed -n "1,/$HIST_MARK/p" | grep -q 'wave TWO scope'
  # a COUNT, not `! … | grep -q`: bash errexit explicitly does not fire on an inverted return
  # value, so a bare `! cmd` is a live assertion ONLY as a test's final command — as an
  # intermediate line it passes whatever the truth is (memory: negated-assertion-dead-unless-final)
  local n1
  n1="$(printf '%s' "$ctx" | sed -n "1,/$HIST_MARK/p" | grep -cF 'wave ONE scope' || true)"
  [ "${n1:-0}" -eq 0 ]
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

@test "injection POINTER: the older captures become one line naming their count, the store and the read command" {
  ( cd "$CWD" && bash "$HOOK" set "wave ONE scope" >/dev/null )
  ( cd "$CWD" && bash "$HOOK" set "wave TWO scope" >/dev/null )
  ( cd "$CWD" && bash "$HOOK" set "wave THREE scope" >/dev/null )
  run run_hook "$(sjson SessionStart)"
  local ctx; ctx="$(ctx_of "$output")"
  printf '%s' "$ctx" | grep -qF '    Scope (frozen): wave THREE scope'   # the contract is still quoted
  # the older two are named by count, not injected: no capture body and no '## ' block reaches the session
  printf '%s' "$ctx" | grep -qF 'History: 2 other capture(s)'
  local n; n="$(printf '%s' "$ctx" | grep -cE 'wave (ONE|TWO) scope|^## ' || true)"
  [ "${n:-0}" -eq 0 ]
  printf '%s' "$ctx" | grep -qF "Read them in the store: $(dod_path)"
  printf '%s' "$ctx" | grep -qF '`~/.claude/hooks/dod-persist.sh get`'
  # … and the store still holds every one of them (only the injection shrank)
  [ "$(grep -c '^Scope (frozen): wave' "$(dod_path)")" -eq 3 ]
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

# ── CC_DOD_LINEAGE_ONLY=1 — only this session's lineage is injected ──────────────────────────────
# docs/research/token-efficiency-2026-09-23/measure/hooks.md §4 "Frozen DoD", §5 row 8: the default
# frame shows the newest capture of ANY session in this worktree (and every unattributed one) as
# THE CURRENT CONTRACT; 7 of 8 sampled sessions were working on something unrelated. Under the flag
# a capture is injected only if it names this session, or a toplevel recorded as this worktree's
# predecessor in lineage.tsv; otherwise the session gets a one-line pointer to the store.
lo_setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  lo_pane_env
  TOP="$(git -C "$CWD" rev-parse --show-toplevel)"
  STORE="$(dod_path)"; mkdir -p "$(dirname "$STORE")"
  {
    printf '# Durable frozen DoD — %s\n\n' "$TOP"
    printf '## 2026-09-01T00:00:00Z (PreCompact:auto)\nScope (frozen): unattributed contract\n\n'
    printf '## 2026-09-02T00:00:00Z (PreCompact:auto) · toplevel=/pred/wt · session=PREDSID\nScope (frozen): predecessor contract\n\n'
    printf '## 2026-09-03T00:00:00Z (manual-set) · toplevel=%s · session=MESID\nScope (frozen): my contract\n\n' "$TOP"
    printf '## 2026-09-04T00:00:00Z (PreCompact:auto) · toplevel=%s · session=OTHERSID\nScope (frozen): other session contract\n\n' "$TOP"
  } > "$STORE"
}
# The session lineage includes the sessions that held this pane before (mailbox alias trail), so the
# pane and the mailbox dir are pinned to scratch: the operator's shell exports both.
lo_pane_env() {
  unset ITERM_SESSION_ID CC_PANE_ID
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mailbox"; mkdir -p "$CC_MAILBOX_DIR/.alias"
}
lo_trail() {  # $1=pane  $2...=sessions, OLDEST first (the trail file is append-only)
  local pane="$1" s; shift
  for s in "$@"; do printf '2026-09-20T00:00:00+0000 %s\n' "$s" >> "$CC_MAILBOX_DIR/.alias/$pane"; done
}
lo_json() { jq -nc --arg c "$CWD" --arg s "$1" '{hook_event_name:"SessionStart",cwd:$c} + (if $s == "" then {} else {session_id:$s} end)'; }
lo_ctx() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext'; }
lo_lacks() { ! printf '%s' "$1" | grep -qF -- "$2"; }

@test "lineage-only: own-session capture is the contract; other sessions and unattributed ones are left out" {
  lo_setup
  run bash -c 'printf "%s" "$1" | CC_DOD_LINEAGE_ONLY=1 bash "$0" 2>/dev/null' "$HOOK" "$(lo_json MESID)"
  [ "$status" -eq 0 ]
  local c; c="$(lo_ctx "$output")"
  printf '%s' "$c" | grep -qF 'THE CURRENT CONTRACT'
  printf '%s' "$c" | grep -qF '    Scope (frozen): my contract'
  printf '%s' "$c" | grep -qF 'History: 0 other capture(s) of this lineage (this session, a session that held this pane before it, or a recorded predecessor worktree) are not shown'
  printf '%s' "$c" | grep -qF 'and 2 from this worktree'"'"'s other sessions or with no provenance are left out'
  lo_lacks "$c" 'other session contract'
  lo_lacks "$c" 'unattributed contract'
  lo_lacks "$c" 'predecessor contract'
}

# PREDECESSOR CAPTURES NEVER BIND (docs/research/startup-hooks-2026-10-18/README.md §2 #5 interim
# fix): the predecessor rule is transitive, and the newest contract it admitted was an unrelated
# wave's in >=120 of 205 measured injections, shown under "this is what binds you".
@test "lineage-only: a predecessor-only capture is prior context, never under the binds-you head" {
  lo_setup
  printf '2026-09-02T12:00:00Z\t/pred/wt\t%s\tfire\n' "$TOP" > "$WRAP_DOD_DIR/lineage.tsv"
  run bash -c 'printf "%s" "$1" | CC_DOD_LINEAGE_ONLY=1 bash "$0" 2>/dev/null' "$HOOK" "$(lo_json NEWSID)"
  [ "$status" -eq 0 ]
  local c; c="$(lo_ctx "$output")"
  # still inherited, as context: the fired child sees what its parent was doing …
  printf '%s' "$c" | grep -qF 'Prior context only, NOT binding — the newest contract of a recorded predecessor worktree'
  printf '%s' "$c" | grep -qF 'Scope (frozen): predecessor contract'
  # … but nothing binds: no binds-you head, and not the head's 4-space quote of a contract
  printf '%s' "$c" | grep -qF 'THE CURRENT CONTRACT is not recorded'
  [ "$(printf '%s' "$c" | grep -cF 'this is what binds you' || true)" -eq 0 ]
  [ "$(printf '%s' "$c" | grep -cF '    Scope (frozen): predecessor contract' || true)" -eq 0 ]
  lo_lacks "$c" 'my contract'
  lo_lacks "$c" 'other session contract'
}

@test "lineage-only: a predecessor's NEWER contract never displaces this lineage's own as the head" {
  lo_setup
  printf '## 2026-09-05T00:00:00Z (PreCompact:auto) · toplevel=/pred/wt · session=PREDSID\nScope (frozen): newer predecessor contract\n\n' >> "$STORE"
  printf '2026-09-02T12:00:00Z\t/pred/wt\t%s\tfire\n' "$TOP" > "$WRAP_DOD_DIR/lineage.tsv"
  run bash -c 'printf "%s" "$1" | CC_DOD_LINEAGE_ONLY=1 bash "$0" 2>/dev/null' "$HOOK" "$(lo_json MESID)"
  [ "$status" -eq 0 ]
  local c; c="$(lo_ctx "$output")"
  printf '%s' "$c" | grep -qF 'this is what binds you'
  printf '%s' "$c" | grep -qF '    Scope (frozen): my contract'
  # both predecessor captures are counted in the pointer, never shown: 3 admitted − 1 quoted
  printf '%s' "$c" | grep -qF 'History: 2 other capture(s) of this lineage'
  lo_lacks "$c" 'predecessor contract'
}

@test "lineage-only: no lineage in the store ⇒ a one-line pointer to the store, no contract text" {
  lo_setup
  run bash -c 'printf "%s" "$1" | CC_DOD_LINEAGE_ONLY=1 bash "$0" 2>/dev/null' "$HOOK" "$(lo_json NEWSID)"
  [ "$status" -eq 0 ]
  local c; c="$(lo_ctx "$output")"
  [ "$(printf '%s\n' "$c" | grep -c '')" -eq 1 ]
  [ "$c" = "No DoD of this lineage; 3 other capture(s) in $STORE" ]
  lo_lacks "$c" 'Scope (frozen)'
  lo_lacks "$c" 'THE CURRENT CONTRACT'
}

@test "lineage-only: the nothing-to-inject notice is ≤100 chars on the live store path shape" {
  # live shape: the store under $HOME/.claude/autonomy/dod with a repo key, rendered as '~/…'
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export WRAP_DOD_DIR="$HOME/.claude/autonomy/dod"
  git -C "$CWD" remote add origin https://example.invalid/notice-len.git
  lo_setup
  case "$STORE" in "$WRAP_DOD_DIR"/repo-*.md) ;; *) echo "not the live repo-key shape: $STORE" >&2; false ;; esac
  run bash -c 'printf "%s" "$1" | CC_DOD_LINEAGE_ONLY=1 bash "$0" 2>/dev/null' "$HOOK" "$(lo_json NEWSID)"
  [ "$status" -eq 0 ]
  local c; c="$(lo_ctx "$output")"
  [ "$c" = "No DoD of this lineage; 3 other capture(s) in ~/.claude/autonomy/dod/${STORE##*/}" ]
  # +2: a three-digit count (the live store holds dozens) must still fit
  [ $(( ${#c} + 2 )) -le 100 ] || { echo "notice is ${#c} chars: $c" >&2; false; }
}

@test "lineage-only: no session id at all ⇒ the pointer, never another session's contract" {
  lo_setup
  run bash -c 'printf "%s" "$1" | env -u CLAUDE_CODE_SESSION_ID CC_DOD_LINEAGE_ONLY=1 bash "$0" 2>/dev/null' "$HOOK" "$(lo_json '')"
  [ "$status" -eq 0 ]
  local c; c="$(lo_ctx "$output")"
  printf '%s' "$c" | grep -qF 'No DoD of this lineage; '
  lo_lacks "$c" 'Scope (frozen)'
}

@test "lineage-only: a PreCompact capture comes back to the same session after compaction" {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  lo_pane_env
  local tx; tx="$(mktx "finish the compaction round trip")"
  jq -nc --arg c "$CWD" --arg t "$tx" '{hook_event_name:"PreCompact",cwd:$c,transcript_path:$t,trigger:"auto",session_id:"CMPSID"}' \
    | bash "$HOOK" >/dev/null 2>&1
  run bash -c 'printf "%s" "$1" | CC_DOD_LINEAGE_ONLY=1 bash "$0" 2>/dev/null' "$HOOK" "$(lo_json CMPSID)"
  [ "$status" -eq 0 ]
  lo_ctx "$output" | grep -qF '    Scope (frozen): finish the compaction round trip'
}

@test "lineage-only =0: output is byte-identical to the hook without the lineage-only branch; UNSET is on" {
  lo_setup
  # Reference: the subject with its 4-line flag branch removed. Preconditions asserted, so a moved
  # anchor fails here instead of silently comparing the subject with itself.
  local ref="$BATS_TEST_TMPDIR/ref/hooks"; mkdir -p "$ref"
  ln -sfn "$REPO/hooks/lib" "$ref/lib"
  [ "$(grep -c 'if \[ "${CC_DOD_LINEAGE_ONLY:-1}" = 1 \]; then' "$HOOK")" -eq 1 ]
  awk '/if \[ "\$\{CC_DOD_LINEAGE_ONLY:-1\}" = 1 \]; then/ {skip=4} skip>0 {skip--; next} {print}' "$HOOK" > "$ref/dod-persist.sh"
  # the SessionStart branch is gone; the write-side dedup reads the flag too and stays
  [ "$(grep -c 'CC_DOD_LINEAGE_ONLY:-1' "$ref/dod-persist.sh")" -eq $(( $(grep -c 'CC_DOD_LINEAGE_ONLY:-1' "$HOOK") - 1 )) ]
  [ "$(grep -c '_dod_inject_lineage_only "\$cwd"' "$ref/dod-persist.sh")" -eq 0 ]
  local j; j="$(lo_json MESID)"
  local want got on
  want="$(printf '%s' "$j" | CC_DOD_LINEAGE_ONLY=0 bash "$ref/dod-persist.sh" 2>/dev/null)"
  got="$(printf '%s' "$j" | CC_DOD_LINEAGE_ONLY=0 bash "$HOOK" 2>/dev/null)"
  [ -n "$want" ]
  [ "$got" = "$want" ]
  # power: the flag does change the output on this store, and unset now means ON (2026-09-24)
  on="$(printf '%s' "$j" | CC_DOD_LINEAGE_ONLY=1 bash "$HOOK" 2>/dev/null)"
  [ "$on" != "$want" ]
  got="$(printf '%s' "$j" | env -u CC_DOD_LINEAGE_ONLY bash "$HOOK" 2>/dev/null)"
  [ "$got" = "$on" ] || { echo "unset did not behave as on"; false; }
}

@test "lineage-only: the /handoff carry — a same-pane successor inherits the predecessor's set" {
  # commands/handoff.md T-P4-4: the predecessor runs `set`, stamped with ITS session id; the recycle
  # successor is a new session on the same pane. The pane's alias trail links the two.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  lo_pane_env
  (cd "$CWD" && CLAUDE_CODE_SESSION_ID=SIDA CC_DOD_LINEAGE_ONLY=1 bash "$HOOK" set "Scope (frozen): ship X") >/dev/null
  lo_trail PANE1 SIDA SIDB
  run bash -c 'printf "%s" "$1" | CC_PANE_ID=PANE1 CC_DOD_LINEAGE_ONLY=1 bash "$0" 2>/dev/null' "$HOOK" "$(lo_json SIDB)"
  [ "$status" -eq 0 ]
  lo_ctx "$output" | grep -qF '    Scope (frozen): ship X'
  # control: the same session on a pane whose trail does not hold SIDA gets the pointer
  run bash -c 'printf "%s" "$1" | CC_PANE_ID=PANE2 CC_DOD_LINEAGE_ONLY=1 bash "$0" 2>/dev/null' "$HOOK" "$(lo_json SIDB)"
  [ "$status" -eq 0 ]
  lo_ctx "$output" | grep -qF 'No DoD of this lineage; '
  lo_lacks "$(lo_ctx "$output")" 'ship X'
}

@test "lineage-only: a sibling session restating the same scope gets its own capture, and keeps it across compaction" {
  # Write-side dedup under the flag compares with THIS session's captures. Against the worktree
  # stream, B's PreCompact would read A's identical line as already recorded and write nothing.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  lo_pane_env
  (cd "$CWD" && CLAUDE_CODE_SESSION_ID=SIDA CC_DOD_LINEAGE_ONLY=1 bash "$HOOK" set "Scope (frozen): ship X") >/dev/null
  local f; f="$(dod_path)"
  local tx; tx="$(mktx "ship X")"
  local pc; pc="$(jq -nc --arg c "$CWD" --arg t "$tx" '{hook_event_name:"PreCompact",cwd:$c,transcript_path:$t,trigger:"auto",session_id:"SIDB"}')"
  # flag off (=0): today's dedup, no capture for B
  printf '%s' "$pc" | CC_DOD_LINEAGE_ONLY=0 bash "$HOOK" >/dev/null 2>&1
  [ "$(grep -c 'session=SIDB' "$f")" -eq 0 ]
  # flag on: B gets its own capture, once
  printf '%s' "$pc" | CC_DOD_LINEAGE_ONLY=1 bash "$HOOK" >/dev/null 2>&1
  printf '%s' "$pc" | CC_DOD_LINEAGE_ONLY=1 bash "$HOOK" >/dev/null 2>&1
  [ "$(grep -c 'session=SIDB' "$f")" -eq 1 ]
  run bash -c 'printf "%s" "$1" | CC_DOD_LINEAGE_ONLY=1 bash "$0" 2>/dev/null' "$HOOK" "$(lo_json SIDB)"
  [ "$status" -eq 0 ]
  lo_ctx "$output" | grep -qF '    Scope (frozen): ship X'
  # `set` under the flag dedups the same way: A restating is a no-op, B restating is not
  run bash -c 'cd "$1" && CLAUDE_CODE_SESSION_ID=SIDA CC_DOD_LINEAGE_ONLY=1 bash "$0" set "Scope (frozen): ship X"' "$HOOK" "$CWD"
  [[ "$output" == unchanged* ]] || false
  run bash -c 'cd "$1" && CLAUDE_CODE_SESSION_ID=SIDC CC_DOD_LINEAGE_ONLY=1 bash "$0" set "Scope (frozen): ship X"' "$HOOK" "$CWD"
  [[ "$output" == captured* ]] || false
  run bash -c 'cd "$1" && CLAUDE_CODE_SESSION_ID=SIDD CC_DOD_LINEAGE_ONLY=0 bash "$0" set "Scope (frozen): ship X"' "$HOOK" "$CWD"
  [[ "$output" == unchanged* ]] || false   # flag off: today's worktree-wide dedup
}

@test "lineage-only: the pane trail is bounded to the newest 3 predecessors" {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  lo_pane_env
  local f; f="$(dod_path)"; mkdir -p "$(dirname "$f")"
  local top; top="$(git -C "$CWD" rev-parse --show-toplevel)"
  printf '## 2026-09-01T00:00:00Z (manual-set) · toplevel=%s · session=OLD1\nScope (frozen): oldest tenant\n\n' "$top" > "$f"
  lo_trail PANE3 OLD1 P2 P3 P4 ME
  run bash -c 'printf "%s" "$1" | CC_PANE_ID=PANE3 CC_DOD_LINEAGE_ONLY=1 bash "$0" 2>/dev/null' "$HOOK" "$(lo_json ME)"
  lo_ctx "$output" | grep -qF 'No DoD of this lineage; '
  lo_lacks "$(lo_ctx "$output")" 'oldest tenant'
  run bash -c 'printf "%s" "$1" | CC_PANE_ID=PANE3 CC_DOD_LINEAGE_PANE_MAX=4 CC_DOD_LINEAGE_ONLY=1 bash "$0" 2>/dev/null' "$HOOK" "$(lo_json ME)"
  lo_ctx "$output" | grep -qF '    Scope (frozen): oldest tenant'
}

@test "lineage-only: lines outside any capture block are counted in the pointer, not dropped silently" {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  lo_pane_env
  local f; f="$(dod_path)"; mkdir -p "$(dirname "$f")"
  printf '# Durable frozen DoD — legacy\n\n- [ ] legacy box one\n- [x] legacy box two\n' > "$f"
  run bash -c 'printf "%s" "$1" | CC_DOD_LINEAGE_ONLY=1 bash "$0" 2>/dev/null' "$HOOK" "$(lo_json NEWSID)"
  [ "$status" -eq 0 ]
  local c; c="$(lo_ctx "$output")"
  # the short notice counts them as one more capture (the unit _dod_newest_within makes of them)
  [ "$c" = "No DoD of this lineage; 1 other capture(s) in $f" ]
  lo_lacks "$c" 'legacy box one'
}

# ── INJECTION SIZE: the always-kept captures in full, the rest a pointer ─────────────────────────
# Past Claude Code's 10,000-char cap the injection is swapped for a 2,000-char preview of its head;
# rendered oldest-first, that head never reached the newest captures (26 of 26 lineage injections
# 2026-10-02..04 were over the cap). The budgeted history that fixed it is now a one-line pointer
# (docs/research/startup-hooks-2026-10-18/README.md §2 #5): only every capture AFTER the newest
# frozen one is injected, newest first, because 'Scope (grown)' extends the contract. The newest
# frozen capture itself is the quoted contract and is not repeated. Order assertions key on the
# '## <ts>' headers, because the newest frozen line is also quoted in the contract lead.
bud_pad() { printf "%${1}s" '' | tr ' ' p; }
bud_store() {  # $1=store  $2=session  $3...="frozen:<label>"|"grown:<label>", OLDEST first, ~1.5 KB each
  local store="$1" sid="$2" top i=0 c; shift 2
  top="$(git -C "$CWD" rev-parse --show-toplevel)"
  mkdir -p "$(dirname "$store")"
  printf '# Durable frozen DoD — %s\n\n' "$top" > "$store"
  for c in "$@"; do
    i=$((i + 1))
    printf '## 2026-09-%02dT00:00:00Z (manual-set) · toplevel=%s · session=%s\nScope (%s): %s %s\n\n' \
      "$i" "$top" "$sid" "${c%%:*}" "${c#*:}" "$(bud_pad 1500)" >> "$store"
  done
}
bud_line() { printf '%s\n' "$1" | grep -nF -- "$2" | head -1 | cut -d: -f1; }   # first line holding $2

@test "pointer: six large frozen captures ⇒ the newest is the contract, the other five one line" {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  lo_pane_env
  bud_store "$(dod_path)" MESID frozen:CAP1 frozen:CAP2 frozen:CAP3 frozen:CAP4 frozen:CAP5 frozen:CAP6
  run bash -c 'printf "%s" "$1" | CC_DOD_LINEAGE_ONLY=1 bash "$0" 2>/dev/null' "$HOOK" "$(lo_json MESID)"
  [ "$status" -eq 0 ]
  local c; c="$(lo_ctx "$output")"
  [ "${#c}" -lt 10000 ]
  printf '%s' "$c" | grep -qF '    Scope (frozen): CAP6 p'
  # no capture block at all: the newest frozen is the quoted contract and is not repeated below it
  [ "$(printf '%s\n' "$c" | grep -c '^## ' || true)" -eq 0 ]
  local cap; for cap in CAP1 CAP2 CAP3 CAP4 CAP5; do lo_lacks "$c" "$cap p"; done
  printf '%s' "$c" | grep -qF 'History: 5 other capture(s) of this lineage'
  printf '%s' "$c" | grep -qF '`~/.claude/hooks/dod-persist.sh get`'
  # the whole injection is the frame, the ~1.5 KB contract and the pointer
  [ "${#c}" -lt 2600 ] || { echo "injection is ${#c} chars" >&2; false; }
}

@test "budget: every capture after the newest frozen one is kept, even past the budget" {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  lo_pane_env
  bud_store "$(dod_path)" MESID frozen:OLDBASE grown:+G1 frozen:BASE grown:+G2 grown:+G3 grown:+G4 grown:+G5
  local cap c g
  # CC_DOD_INJECT_MAX_CHARS no longer sizes anything; the always-kept set is the same at any value
  for cap in 6000 0; do
    run bash -c 'printf "%s" "$1" | CC_DOD_INJECT_MAX_CHARS="$2" CC_DOD_LINEAGE_ONLY=1 bash "$0" 2>/dev/null' \
      "$HOOK" "$(lo_json MESID)" "$cap"
    [ "$status" -eq 0 ]
    c="$(lo_ctx "$output")"
    for g in G2 G3 G4 G5; do printf '%s' "$c" | grep -qF "Scope (grown): +$g p"; done
    printf '%s' "$c" | grep -qF '    Scope (frozen): BASE p'          # the contract lead still names it
    printf '%s' "$c" | grep -qF 'Below, newest first, in full: 4 capture(s)'
    printf '%s' "$c" | grep -qF 'History: 2 other capture(s)'     # OLDBASE and +G1, by count only
    lo_lacks "$c" 'OLDBASE'
    lo_lacks "$c" '+G1 p'
  done
  # power: four ~1.5 KB grown captures are past the old 6000 budget, so a budget would have cut one
  [ "${#c}" -gt 6000 ]
}

@test "always-kept: post-frozen captures arrive in full, newest first, one blank line between blocks" {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  lo_pane_env
  local f; f="$(dod_path)"; mkdir -p "$(dirname "$f")"
  local top; top="$(git -C "$CWD" rev-parse --show-toplevel)"
  {
    printf '## 2026-09-01T00:00:00Z (manual-set) · toplevel=%s · session=MESID\nScope (frozen): first small\n\n' "$top"
    printf '## 2026-09-02T00:00:00Z (manual-set) · toplevel=%s · session=MESID\nScope (grown): +second small\n\n' "$top"
    printf '## 2026-09-03T00:00:00Z (manual-set) · toplevel=%s · session=MESID\nScope (grown): +third small\n\n' "$top"
  } > "$f"
  run bash -c 'printf "%s" "$1" | CC_DOD_LINEAGE_ONLY=1 bash "$0" 2>/dev/null' "$HOOK" "$(lo_json MESID)"
  [ "$status" -eq 0 ]
  local c; c="$(lo_ctx "$output")"
  printf '%s' "$c" | grep -qF '    Scope (frozen): first small'
  printf '%s' "$c" | grep -qF 'Below, newest first, in full: 2 capture(s)'
  printf '%s' "$c" | grep -qF 'History: 0 other capture(s)'
  local l1 l2 l3; l1="$(bud_line "$c" '## 2026-09-01T')"; l2="$(bud_line "$c" '## 2026-09-02T')"; l3="$(bud_line "$c" '## 2026-09-03T')"
  [ -z "$l1" ] && [ -n "$l2" ] && [ -n "$l3" ] || false
  [ "$l3" -lt "$l2" ] || false
  [ -z "$(printf '%s\n' "$c" | sed -n "$((l2 - 1))p")" ]
  [ -z "$(printf '%s\n' "$c" | sed -n "$((l3 - 1))p")" ]
}

@test "pointer =0 frame: six large frozen captures ⇒ the contract and one line, under the cap" {
  bud_store "$(dod_path)" MESID frozen:CAP1 frozen:CAP2 frozen:CAP3 frozen:CAP4 frozen:CAP5 frozen:CAP6
  run run_hook "$(sjson SessionStart)"
  [ "$status" -eq 0 ]
  local c; c="$(ctx_of "$output")"
  [ "${#c}" -lt 10000 ]
  _hist_mark_live "$c"
  printf '%s' "$c" | grep -qF '    Scope (frozen): CAP6 p'
  [ "$(printf '%s\n' "$c" | grep -c '^## ' || true)" -eq 0 ]
  lo_lacks "$c" 'CAP5 p'
  printf '%s' "$c" | grep -qF "History: 5 other capture(s) of this wave's INTEGRATE-only history"
  [ "${#c}" -lt 2600 ] || { echo "injection is ${#c} chars" >&2; false; }
}

@test "always-kept =0 frame: newest is by timestamp across both stores, not by stream position" {
  # dod_read_content emits the repo-key store BEFORE this toplevel's legacy file, so reversing the
  # stream would rank the legacy store's older FROZEN capture newest, and the strict always-kept set
  # after it would then be empty instead of the two repo-store growths.
  local legacy repo top; legacy="$(dod_path)"
  git -C "$CWD" remote add origin https://example.invalid/budget-order.git
  repo="$(dod_path)"; [ "$repo" != "$legacy" ]
  top="$(git -C "$CWD" rev-parse --show-toplevel)"; mkdir -p "$(dirname "$repo")"
  printf '## 2026-09-01T00:00:00Z (manual-set) · toplevel=%s\nScope (frozen): legacy older base\n\n' "$top" > "$legacy"
  {
    printf '## 2026-09-03T00:00:00Z (manual-set) · toplevel=%s\nScope (grown): +repo middle\n\n' "$top"
    printf '## 2026-09-05T00:00:00Z (manual-set) · toplevel=%s\nScope (grown): +repo newest\n\n' "$top"
  } > "$repo"
  run run_hook "$(sjson SessionStart)"
  [ "$status" -eq 0 ]
  local c; c="$(ctx_of "$output")"
  printf '%s' "$c" | grep -qF '    Scope (frozen): legacy older base'
  local l1 l3 l5; l1="$(bud_line "$c" '## 2026-09-01T')"; l3="$(bud_line "$c" '## 2026-09-03T')"; l5="$(bud_line "$c" '## 2026-09-05T')"
  [ -z "$l1" ] && [ -n "$l3" ] && [ -n "$l5" ] || false
  [ "$l5" -lt "$l3" ] || false
}

# ── cost (startup-hooks README §2 #17): one payload parse, one rev-parse, phase timing, checkpoint ──
# A git shim that counts its own calls, then execs the real git: the memo's whole claim is a number.
git_counter() {
  local real; real="$(command -v git)"
  mkdir -p "$BATS_TEST_TMPDIR/gshim"
  printf '#!/bin/bash\necho x >> "%s"\nexec "%s" "$@"\n' "$BATS_TEST_TMPDIR/git-calls" "$real" > "$BATS_TEST_TMPDIR/gshim/git"
  chmod +x "$BATS_TEST_TMPDIR/gshim/git"; : > "$BATS_TEST_TMPDIR/git-calls"
}

@test "cost: a lineage SessionStart asks git at most twice (one rev-parse, one config read)" {
  git -C "$CWD" remote add origin https://example.invalid/cost.git   # the repo-key path: one config read
  lo_setup
  git_counter
  run bash -c "printf '%s' '$(lo_json MESID)' | PATH='$BATS_TEST_TMPDIR/gshim':\"\$PATH\" CC_DOD_LINEAGE_ONLY=1 bash '$HOOK' 2>/dev/null"
  [ "$status" -eq 0 ]
  ctx_of "$output" | grep -qF '    Scope (frozen): my contract'
  [ "$(wc -l < "$BATS_TEST_TMPDIR/git-calls" | tr -d ' ')" -le 2 ] || { echo "git calls: $(wc -l < "$BATS_TEST_TMPDIR/git-calls")" >&2; false; }
}

@test "cost: the memo answers only for the cwd it was primed with" {
  local other="$BATS_TEST_TMPDIR/other"; git init -q "$other"
  git -C "$other" remote add origin https://example.invalid/other.git
  run bash -c ". '$REPO/hooks/lib/dod-path.sh'; dod_prime '$CWD'; dod_toplevel '$other'; echo; dod_path_for '$other'; echo; dod_toplevel '$CWD'"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$(git -C "$other" rev-parse --show-toplevel)" ]
  [ "${lines[1]}" = "$(bash -c ". '$REPO/hooks/lib/dod-path.sh'; dod_path_for '$other'")" ]
  [ "${lines[2]}" = "$(git -C "$CWD" rev-parse --show-toplevel)" ]
}

@test "cost: an empty payload field between two others does not shift the fields after it" {
  lo_setup
  local j; j="$(jq -nc --arg c "$CWD" '{hook_event_name:"SessionStart",session_id:"",cwd:$c}')"
  run bash -c "printf '%s' '$j' | CLAUDE_CODE_SESSION_ID=MESID CC_DOD_LINEAGE_ONLY=1 bash '$HOOK' 2>/dev/null"
  [ "$status" -eq 0 ]
  ctx_of "$output" | grep -qF '    Scope (frozen): my contract'   # cwd intact; sid fell back to the env
}

@test "timing: a SessionStart appends one line of per-phase milliseconds; an empty CC_DOD_TIMING_LOG writes none" {
  lo_setup
  run bash -c "printf '%s' '$(lo_json MESID)' | CC_DOD_LINEAGE_ONLY=1 bash '$HOOK' 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CC_DOD_TIMING_LOG" | tr -d ' ')" -eq 1 ]
  jq -e '.outcome == "ok" and .sid == "MESID" and (.total_ms|type) == "number"
         and (.phases|keys) == ["lineage","parse","prime","read","render","scope"]' "$CC_DOD_TIMING_LOG"
  run bash -c "printf '%s' '$(lo_json MESID)' | CC_DOD_TIMING_LOG= CC_DOD_LINEAGE_ONLY=1 bash '$HOOK' 2>/dev/null"
  [ "$(wc -l < "$CC_DOD_TIMING_LOG" | tr -d ' ')" -eq 1 ]
}

@test "checkpoint: past its budget the hook emits a labelled pointer to the store instead of the render" {
  lo_setup
  run bash -c "printf '%s' '$(lo_json MESID)' | CC_DOD_CHECKPOINT_MS=1 CC_DOD_LINEAGE_ONLY=1 bash '$HOOK' 2>/dev/null"
  [ "$status" -eq 0 ]
  local c; c="$(ctx_of "$output")"
  printf '%s' "$c" | grep -qF 'DoD not injected: dod-persist stopped at its 1 ms checkpoint (prime,'
  printf '%s' "$c" | grep -qF "$STORE"
  printf '%s' "$c" | grep -qF 'dod-persist.sh get'
  lo_lacks "$c" 'my contract'
  [ "${#c}" -lt 400 ]
  jq -e '.outcome == "checkpoint"' "$CC_DOD_TIMING_LOG"
  # CONTROL: with the checkpoint off the same start renders the contract
  run bash -c "printf '%s' '$(lo_json MESID)' | CC_DOD_LINEAGE_ONLY=1 bash '$HOOK' 2>/dev/null"
  ctx_of "$output" | grep -qF '    Scope (frozen): my contract'
}

@test "checkpoint: no store ⇒ still silent past the budget (nothing to point at)" {
  run bash -c "printf '%s' '$(sjson SessionStart)' | CC_DOD_CHECKPOINT_MS=1 bash '$HOOK' 2>/dev/null"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
