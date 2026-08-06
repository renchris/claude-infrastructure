#!/usr/bin/env bats
# memory-nudge.sh — UserPromptSubmit hook: periodic crystallization nudge + the
# APPEND-TIME BUDGET that keeps MEMORY.md under the harness read limit.
#
# The defect this pins: the index is loaded with a hard limit (24985 B) past which
# the loader SILENTLY DROPS THE TAIL — the newest entries. Three manual compaction
# passes each re-inflated within days because nothing measured the budget at the
# moment of APPEND. Measured 2026-07-31: 27796 B / 96 entries, ~2811 B over.
#
# RED-proof coverage: the over-limit gate fires on the FIRST prompt (not the
# periodic slot); each of the three diagnoses (hook-length / both / cardinality)
# is selected by the arithmetic, not asserted; a HEALTHY index never raises the
# alarm (polarity control) and never blocks; every fail-safe path exits 0 with no
# output; output is always valid JSON; the counter is sandboxed per config dir.
#
# Assertions are simple commands only. bash exempts `[[ ]]` from errexit, so a
# non-final `[[ ]]` in a bats body evaluates and DISCARDS its result — the test
# passes vacuously (scripts/bats-assert-liveness.py; this file was written that
# way first and the ratchet caught 17 of them).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/memory-nudge.sh"
  # Fixture $HOME: the hook falls back to $HOME/.claude for both the config dir and
  # the counter, so an unfixtured suite would read and write the operator's live ~/.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export MEMORY_NUDGE_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"
  LIMIT=24985
}

# ── errexit-live assertion helpers (function calls are ordinary simple commands) ──
has()    { printf '%s' "$1" | grep -qF -- "$2"; }
hasnt()  { if printf '%s' "$1" | grep -qF -- "$2"; then return 1; fi; }
starts() { case "$1" in "$2"*) return 0 ;; *) return 1 ;; esac; }

# Build an index fixture: $1 entries, each with a $2-byte hook.
mkindex() {
  local n="$1" hooklen="$2" dir f i pad
  dir="$BATS_TEST_TMPDIR/idx-$n-$hooklen"; mkdir -p "$dir"; f="$dir/MEMORY.md"
  pad="$(head -c "$hooklen" /dev/zero | tr '\0' x)"
  : >"$f"
  for ((i=0; i<n; i++)); do printf -- '- [T%s](t%s.md) — %s\n' "$i" "$i" "$pad" >>"$f"; done
  printf '%s' "$f"
}

# Invoke the hook once as prompt #N for a given session id.
fire() {  # fire <sid> <index-path> [cwd]
  printf '{"session_id":"%s","cwd":"%s"}' "$1" "${3:-/nonexistent-cwd-xyz}" \
    | MEMORY_INDEX_PATH="$2" bash "$HOOK"
}
ctx() { jq -r '.hookSpecificOutput.additionalContext'; }

# ── the gate fires, and fires EARLY ───────────────────────────────────────────

@test "over-limit index raises the alarm on the FIRST prompt, not the periodic slot" {
  idx="$(mkindex 100 250)"
  [ "$(wc -c <"$idx")" -gt "$LIMIT" ]           # fixture really is over
  run fire s-first "$idx"
  [ "$status" -eq 0 ]
  starts "$(printf '%s' "$output" | ctx)" '🚨'
}

@test "alarm reports the true overage and that the NEWEST entries were dropped" {
  idx="$(mkindex 100 250)"; total="$(wc -c <"$idx" | tr -d ' ')"
  run fire s-num "$idx"
  out="$(printf '%s' "$output" | ctx)"
  has "$out" "$total B vs the $LIMIT B loader limit"
  has "$out" "over by $((total - LIMIT)) B"
  has "$out" "NEWEST"
  has "$out" "no reader can tell"
}

# ── the three diagnoses are SELECTED by arithmetic, not asserted ──────────────

@test "diagnosis: long hooks over a small overage ⇒ shortening is the lever" {
  run fire s-lev1 "$(mkindex 100 250)"
  out="$(printf '%s' "$output" | ctx)"
  has "$out" 'hook LENGTH is the binding lever'
  has "$out" 'more than the'                    # recovery >= overage, checked not claimed
  hasnt "$out" 'CARDINALITY'
}

@test "diagnosis: hooks already at target ⇒ CARDINALITY, shortening cannot reach it" {
  run fire s-lev2 "$(mkindex 600 40)"
  out="$(printf '%s' "$output" | ctx)"
  has "$out" 'CARDINALITY'
  has "$out" 'shortening CANNOT reach the limit'
  has "$out" 'DURABILITY criterion'
  hasnt "$out" 'binding lever'
}

@test "diagnosis: partial recovery ⇒ BOTH levers, never a false 'enough'" {
  # 190 entries x 130 B hooks: over the limit, but shortening to 115 B recovers
  # far less than the overage — the message must not claim shortening suffices.
  run fire s-lev3 "$(mkindex 190 130)"
  out="$(printf '%s' "$output" | ctx)"
  has "$out" 'BOTH levers are needed'
  has "$out" 'recovers only'
  hasnt "$out" 'more than the'
}

@test "alarm carries the one-in-one-out rule and keeps the lossy half human-gated" {
  run fire s-rule "$(mkindex 100 250)"
  out="$(printf '%s' "$output" | ctx)"
  has "$out" 'ONE-IN-ONE-OUT'
  has "$out" 'PROPOSE-ONLY'
}

# ── polarity control: a healthy index must NOT raise the alarm ────────────────

@test "healthy index is silent off the periodic slot (no always-on alarm)" {
  run fire s-quiet "$(mkindex 40 100)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "healthy index at the periodic slot reports budget, never the alarm" {
  idx="$(mkindex 40 100)"; out=""
  for _ in $(seq 1 12); do out="$(fire s-periodic "$idx" || true)"; done
  ctxout="$(printf '%s' "$out" | ctx)"
  has "$ctxout" 'MEMORY INDEX BUDGET (live)'
  has "$ctxout" 'headroom'
  has "$ctxout" 'entry slots left'
  hasnt "$ctxout" '🚨'                          # polarity: no alarm when healthy
  has "$ctxout" 'MEMORY CHECK (periodic)'
}

@test "budget names a per-append hard cap the model can actually apply" {
  idx="$(mkindex 40 100)"; out=""
  for _ in $(seq 1 12); do out="$(fire s-cap "$idx" || true)"; done
  has "$(printf '%s' "$out" | ctx)" 'hard cap this append:'
}

@test "runway is counted at the OBSERVED density, not the target-length ceiling" {
  # 40 entries x 250 B hooks: healthy (10820 B), but written 2.2x longer than the
  # 115 B target. The target-based ceiling leaves 145 slots; only 52 lines of the
  # length this index is actually written at fit in the headroom. Leading with 145
  # tells a caller it has 2.8x the room it has. Measured live 2026-08-06 as 37 vs
  # 11, and that inflated figure had already reached a backlog item's premise as
  # "37 free cardinality slots" — framing a cardinality-bound index as length-bound.
  idx="$(mkindex 40 250)"; out=""
  [ "$(wc -c <"$idx")" -lt "$LIMIT" ]            # fixture is healthy, not over
  for _ in $(seq 1 12); do out="$(fire s-runway "$idx" || true)"; done
  ctxout="$(printf '%s' "$out" | ctx)"
  has "$ctxout" '~52 entry slots left'           # observed 271 B/line
  has "$ctxout" 'ACTUALLY written at'
  has "$ctxout" '(145 only if'                   # ceiling kept, marked conditional
  hasnt "$ctxout" '~145 entry slots left'        # the pre-fix wording this pins
}

# ── fail-safe: a side-car must fail no wider than itself ──────────────────────

@test "missing index still emits the plain nudge at the periodic slot" {
  out=""
  for _ in $(seq 1 12); do out="$(fire s-none "$BATS_TEST_TMPDIR/absent/MEMORY.md" || true)"; done
  starts "$(printf '%s' "$out" | ctx)" 'MEMORY CHECK (periodic)'
}

@test "unreadable and empty indexes degrade to the plain nudge, never a crash" {
  empty="$BATS_TEST_TMPDIR/empty.md"; : >"$empty"
  noent="$BATS_TEST_TMPDIR/nope.md"
  n=0
  for f in "$empty" "$noent"; do
    out=""; n=$((n + 1))   # sid must stay [A-Za-z0-9_-]: the hook rejects a dot
    for _ in $(seq 1 12); do out="$(fire "s-degrade-$n" "$f" || true)"; done
    printf '%s' "$out" | jq -e . >/dev/null
    hasnt "$(printf '%s' "$out" | ctx)" '🚨'
  done
}

@test "malformed stdin and a missing session_id exit 0 silently" {
  run bash -c "printf 'not json' | bash '$HOOK'"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  run bash -c "printf '{}' | bash '$HOOK'"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "INTERVAL=0 is a total kill switch even with an over-limit index" {
  run bash -c "printf '{\"session_id\":\"s-off\",\"cwd\":\"/x\"}' \
    | MEMORY_NUDGE_INTERVAL=0 MEMORY_INDEX_PATH='$(mkindex 100 250)' bash '$HOOK'"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── contract: the payload is always valid JSON ────────────────────────────────

@test "every firing path emits valid single-line JSON with the right event name" {
  i=0
  for idx in "$(mkindex 100 250)" "$(mkindex 600 40)" "$(mkindex 190 130)"; do
    i=$((i + 1))
    run fire "s-json-$i" "$idx"
    printf '%s' "$output" | jq -e '.hookSpecificOutput.hookEventName == "UserPromptSubmit"' >/dev/null
    # bats strips the trailing newline, so a compact one-line payload has 0 embedded ones
    [ "$(printf '%s' "$output" | wc -l | tr -d ' ')" -eq 0 ]
  done
}

# ── resolution: a linked worktree keys on the MAIN worktree, like the harness ──

@test "index is resolved through the git COMMON dir, not the linked worktree path" {
  main="$BATS_TEST_TMPDIR/proj"; mkdir -p "$main"
  git init -q "$main"
  ( cd "$main" || exit 1; git config user.email t@e.com; git config user.name t
    echo x > a.txt; git add a.txt; git commit -q -m base ) >/dev/null 2>&1
  wt="$BATS_TEST_TMPDIR/wt-linked"
  ( cd "$main"; git worktree add -q -b wtb "$wt" ) >/dev/null 2>&1
  # Key the fixture on the PHYSICAL main path: git reports a resolved path, and in
  # production the harness slug is a real path (no /var -> /private/var confound).
  main_phys="$(cd "$main" && pwd -P)"
  slug="$(printf '%s' "$main_phys" | tr '/.' '--')"
  memdir="$CLAUDE_CONFIG_DIR/projects/$slug/memory"; mkdir -p "$memdir"
  cp "$(mkindex 100 250)" "$memdir/MEMORY.md"
  # Fire FROM the linked worktree with no MEMORY_INDEX_PATH override.
  run bash -c "printf '{\"session_id\":\"s-wt\",\"cwd\":\"$wt\"}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  starts "$(printf '%s' "$output" | ctx)" '🚨'
}

# ── the counter follows the config dir in play ────────────────────────────────

@test "counter is written under the configured state dir, not a hardcoded ~/.claude" {
  fire s-count "$(mkindex 40 100)" >/dev/null || true
  [ -f "$MEMORY_NUDGE_STATE_DIR/nudge-s-count.count" ]
  [ "$(cat "$MEMORY_NUDGE_STATE_DIR/nudge-s-count.count")" = "1" ]
}
