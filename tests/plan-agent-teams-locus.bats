#!/usr/bin/env bats
# plan-agent-teams-default.sh BRANCH 2 — the ACCUMULATING Execution-Locus decision point for
# implementation that never touches a plan file (backlog item 14bcdfee2eb8). Proves:
#   · POSITIVE CONTROL: a progressive replay of the REAL evidence session (fixture distilled from
#     transcript 462e36d1, wt-cc-005159-55873) fires — and fires at slice 3, mid-session
#   · MUTANT CONTROL: the pre-fix hook (the bare `exit 0` on the non-plan path) does NOT fire on that
#     same fixture, so this suite can actually FAIL (MEMORY.md verification-harness-vacuous-pass-traps)
#   · threshold seam is real, not hardcoded: min=2 fires a slice earlier on the same fixture
#   · slice 1 and slice 2 alone never fire; the latch caps it at ONE fire per session
#   · isMeta hook-injected user records (Stop-hook block reasons) mint NO slices — the inflation control
#   · non-source paths (.md, /tmp, node_modules, state dirs) never count
#   · BRANCH 1 REGRESSION: a plan file still gets the untouched PLAN DEFAULTS output
#   · kill-switch, CC_LOCUS_DISABLE, and team-assignee exemption all abstain
#   · transcript resolved from session_id+cwd when the payload carries no transcript_path
#   · every path exits 0 (a PreToolUse hook exiting non-zero BLOCKS the tool call)

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/plan-agent-teams-default.sh"
  FIXTURE="$REPO/tests/fixtures/locus-evidence-session.jsonl"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # hermetic: never touch the live ~/
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$CLAUDE_CONFIG_DIR"
  export CC_LOCUS_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CC_LOCUS_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_LOCUS_SLICE_MIN=3
  SRC="/Users/chrisren/Development/repo/src/thing.tsx"
  TX="$BATS_TEST_TMPDIR/tx.jsonl"
}

# payload <file_path> [transcript_path] [session_id] [cwd]
payload() {
  jq -nc --arg f "${1:-}" --arg tp "${2:-}" --arg sid "${3:-sess-1}" --arg cwd "${4:-/Users/chrisren/Development/repo}" \
    '{session_id:$sid, cwd:$cwd, hook_event_name:"PreToolUse", tool_name:"Edit",
      tool_input:{file_path:$f}} + (if $tp=="" then {} else {transcript_path:$tp} end)'
}

# uturn <iso> → a genuine operator message record
uturn() { jq -nc --arg t "$1" '{type:"user",isSidechain:false,timestamp:$t,message:{role:"user",content:[{type:"text",text:"do the thing"}]}}'; }
# meta <iso> [text] → a hook-injected user record (Stop-hook block reason): isMeta:true
meta() { jq -nc --arg t "$1" --arg x "${2:-Stop hook feedback: loose ends remain}" '{type:"user",isSidechain:false,isMeta:true,timestamp:$t,message:{role:"user",content:[{type:"text",text:$x}]}}'; }
# killturn <iso> → a genuine operator message carrying the kill-switch phrase
killturn() { jq -nc --arg t "$1" '{type:"user",isSidechain:false,timestamp:$t,message:{role:"user",content:[{type:"text",text:"just do this one and stop"}]}}'; }

# Branch 2's fire, discriminated from BRANCH 1's — whose PLAN DEFAULTS text also contains the words
# "EXECUTION LOCUS PER WAVE". Matching on those first made the replay report a fire at the fixture's
# plan-doc edit (record 18) and made the pre-fix mutant look like it fired too: a detector that
# matches a SIBLING's output (MEMORY.md guard-proxy-fails-in-both-directions).
fired() { printf '%s' "$1" | grep -q 'inline implementation slice'; }
# `! cmd` is EXEMPT from set -e, so a negated assertion in a bats test is decorative — it can never
# fail the case. tests/bats-assert-liveness.bats ratchets exactly that and caught three of them here.
# A plain function returning non-zero is a simple command, so it does abort: this is the live form.
refute_fired() { if fired "$1"; then echo "unexpected branch-2 fire: $1"; return 1; fi; }

# ── POSITIVE CONTROL: progressive replay of the real evidence session ────────────────────────────
# Truncate the real fixture at every source-edit moment and invoke the hook there, exactly as it
# would have been invoked live. Asserts WHERE the fire lands, not merely that one happens.
# Echoes: MEMORY.md control-must-replay-the-real-artifact.
replay() { # replay <max_records> → last stdout of the hook
  local n="$1" i=0 out="" line p
  : > "$TX"
  while IFS= read -r line; do
    i=$((i+1)); [ "$i" -gt "$n" ] && break
    printf '%s\n' "$line" >> "$TX"
    [ "$(printf '%s' "$line" | jq -r '.type')" = "assistant" ] || continue
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      out="$(payload "$p" "$TX" | bash "$HOOK" 2>/dev/null || true)"
      REPLAY_LAST_IDX="$i"
      fired "$out" && { REPLAY_OUT="$out"; return 0; }
    done < <(printf '%s' "$line" | jq -r '.message.content[]?.input.file_path // empty')
  done < "$FIXTURE"
  REPLAY_OUT="$out"; return 1
}

@test "fixture: the distilled evidence session exists and carries the real slice structure" {
  [ -s "$FIXTURE" ]
  run jq -r '.type' "$FIXTURE"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q user
  printf '%s' "$output" | grep -q assistant
}

@test "POSITIVE CONTROL: replaying the real evidence session FIRES" {
  replay 65   # rc 0 == fired; replay stores the payload in REPLAY_OUT, so do not wrap it in `run`
  fired "$REPLAY_OUT"
}

@test "POSITIVE CONTROL: it fires at the 3rd slice, mid-session (not at the end)" {
  replay 65
  # the brief's session is 65 records; the fire must arrive with real work still ahead
  [ "$REPLAY_LAST_IDX" -lt 60 ]
  printf '%s' "$REPLAY_OUT" | grep -q 'slice #3'
}

@test "MUTANT CONTROL: the pre-fix hook does NOT fire on the same fixture" {
  # Anchor-checked mutant: restore the exact pre-fix behaviour (bare `exit 0` on the non-plan path).
  # Built with python, not sed: in a BRE the anchor's leading `[ "` opens a BRACKET EXPRESSION, so the
  # sed form silently matched nothing and the "mutant" was a byte-identical copy that fired like the
  # real hook — a control that could not fail (MEMORY.md verification-harness-vacuous-pass-traps).
  local mut="$BATS_TEST_TMPDIR/prefix.sh"
  grep -q '\[ "$IS_PLAN" = false \] && { _locus_source_branch; exit 0; }' "$HOOK"   # anchor must exist
  python3 - "$HOOK" "$mut" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src).read()
old = '[ "$IS_PLAN" = false ] && { _locus_source_branch; exit 0; }'
new = '[ "$IS_PLAN" = false ] && exit 0'
assert s.count(old) == 1, "anchor not found exactly once"
open(dst, 'w').write(s.replace(old, new))
PY
  run cmp -s "$HOOK" "$mut"
  [ "$status" -ne 0 ]        # the mutation MUST have changed the file
  bash -n "$mut"
  local mrc=0
  HOOK="$mut" replay 65 || mrc=$?
  [ "$mrc" -ne 0 ]           # rc != 0 == never fired
  refute_fired "$REPLAY_OUT"
}

@test "threshold seam is real: min=2 fires one slice earlier on the same fixture" {
  CC_LOCUS_SLICE_MIN=3 replay 65 || true; local at3="$REPLAY_LAST_IDX"
  rm -rf "$CC_LOCUS_STATE_DIR"
  CC_LOCUS_SLICE_MIN=2 replay 65 || true; local at2="$REPLAY_LAST_IDX"
  [ "$at2" -lt "$at3" ]
}

# ── SYNTHETIC PREDICATE CASES ────────────────────────────────────────────────────────────────────
@test "slice 1 alone does not fire" {
  uturn "2026-08-11T10:00:00.000Z" > "$TX"
  run bash -c 'payload_out=$(jq -nc --arg f "'"$SRC"'" --arg tp "'"$TX"'" "{session_id:\"s\",cwd:\"/c\",tool_input:{file_path:\$f},transcript_path:\$tp}"); printf "%s" "$payload_out" | bash "'"$HOOK"'"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "two slices do not fire; the third does; then the latch holds" {
  uturn "2026-08-11T10:00:00.000Z" > "$TX"
  run bash -c "$(declare -f payload); payload '$SRC' '$TX' | bash '$HOOK'"
  [ "$status" -eq 0 ]; [ -z "$output" ]

  uturn "2026-08-11T11:00:00.000Z" >> "$TX"
  run bash -c "$(declare -f payload); payload '$SRC' '$TX' | bash '$HOOK'"
  [ "$status" -eq 0 ]; [ -z "$output" ]

  uturn "2026-08-11T12:00:00.000Z" >> "$TX"
  run bash -c "$(declare -f payload); payload '$SRC' '$TX' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'EXECUTION LOCUS'
  printf '%s' "$output" | jq -e '.hookSpecificOutput.hookEventName=="PreToolUse"'
  # branch 2 must NOT carry permissionDecision: it must not widen auto-approval to source files
  run bash -c "printf '%s' '$output' | jq -e '.hookSpecificOutput.permissionDecision'"
  [ "$status" -ne 0 ]

  # LATCH: a 4th slice on the same session stays silent
  uturn "2026-08-11T13:00:00.000Z" >> "$TX"
  run bash -c "$(declare -f payload); payload '$SRC' '$TX' | bash '$HOOK'"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "INFLATION CONTROL: isMeta hook-injected records mint no slices" {
  # 2 genuine turns + 3 injected block reasons. Under min=3 a naive counter would fire; this must not.
  { uturn "2026-08-11T10:00:00.000Z"; meta "2026-08-11T10:05:00.000Z"; } > "$TX"
  run bash -c "$(declare -f payload); payload '$SRC' '$TX' | bash '$HOOK'"
  [ -z "$output" ]
  meta "2026-08-11T10:10:00.000Z" >> "$TX"
  run bash -c "$(declare -f payload); payload '$SRC' '$TX' | bash '$HOOK'"
  [ -z "$output" ]
  meta "2026-08-11T10:15:00.000Z" >> "$TX"
  run bash -c "$(declare -f payload); payload '$SRC' '$TX' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  uturn "2026-08-11T11:00:00.000Z" >> "$TX"
  run bash -c "$(declare -f payload); payload '$SRC' '$TX' | bash '$HOOK'"
  [ -z "$output" ]   # only 2 real slices so far
}

# ── EVERY GATE BELOW RUNS AT min=1 WITH ITS OWN A/B CONTROL ──────────────────────────────────────
# At min=3 a single invocation records ONE slice and stays silent no matter what the gate does, so
# every one of these tests passed VACUOUSLY on first run (MEMORY.md sibling-guard-makes-the-fixture-
# vacuous). min=1 makes the named gate the ONLY thing that can explain the silence, and the control
# leg proves the same fixture fires without it.
hook_once() { printf '%s' "$(payload "$1" "$TX")" | bash "$HOOK" 2>/dev/null || true; }

@test "non-source paths never count toward a slice (control: the same turn DOES fire for source)" {
  export CC_LOCUS_SLICE_MIN=1
  uturn "2026-08-11T10:00:00.000Z" > "$TX"
  # control leg: at min=1 one source edit in one turn fires — so silence below is the path filter
  run hook_once "$SRC"
  printf '%s' "$output" | grep -q 'EXECUTION LOCUS'
  for p in /Users/x/repo/docs/notes.md /tmp/fire-brief.txt /Users/x/repo/node_modules/a/i.js \
           /Users/x/.claude/state/s.json /Users/x/.claude/autonomy/backlog.jsonl \
           /Users/x/repo/README.md /Users/x/repo/.next/build/a.js; do
    rm -rf "$CC_LOCUS_STATE_DIR"
    run hook_once "$p"
    [ "$status" -eq 0 ]
    [ -z "$output" ] || { echo "unexpected fire for $p: $output"; false; }
  done
}

@test "BRANCH 1 REGRESSION: a plan file still gets the untouched PLAN DEFAULTS output" {
  export CC_LOCUS_SLICE_MIN=1
  uturn "2026-08-11T10:00:00.000Z" > "$TX"
  run bash -c "$(declare -f payload); payload '/Users/x/repo/docs/plans/THING_PLAN.md' '$TX' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'PLAN DEFAULTS'
  printf '%s' "$output" | jq -e '.hookSpecificOutput.permissionDecision=="allow"'
  # branch 1's own text says "EXECUTION LOCUS PER WAVE", so assert on branch 2's distinctive phrase
  refute_fired "$output"
}

@test "kill-switch on the last operator message abstains" {
  export CC_LOCUS_SLICE_MIN=1
  uturn "2026-08-11T10:00:00.000Z" > "$TX"
  run hook_once "$SRC"
  printf '%s' "$output" | grep -q 'EXECUTION LOCUS'   # control
  rm -rf "$CC_LOCUS_STATE_DIR"
  killturn "2026-08-11T10:00:00.000Z" > "$TX"
  run hook_once "$SRC"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "CC_LOCUS_DISABLE=1 abstains" {
  export CC_LOCUS_SLICE_MIN=1
  uturn "2026-08-11T10:00:00.000Z" > "$TX"
  run hook_once "$SRC"
  printf '%s' "$output" | grep -q 'EXECUTION LOCUS'   # control
  rm -rf "$CC_LOCUS_STATE_DIR"
  export CC_LOCUS_DISABLE=1
  run hook_once "$SRC"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "team assignee is exempt (fired peers are NOT — see the hook header)" {
  export CC_LOCUS_SLICE_MIN=1
  uturn "2026-08-11T10:00:00.000Z" > "$TX"
  run hook_once "$SRC"
  printf '%s' "$output" | grep -q 'EXECUTION LOCUS'   # control: no assignee stub yet
  rm -rf "$CC_LOCUS_STATE_DIR"
  mkdir -p "$CLAUDE_CONFIG_DIR/hooks/lib"
  printf 'agent_is_assignee() { printf "%%s" "tm-1"; }\n' > "$CLAUDE_CONFIG_DIR/hooks/lib/agent-identity.sh"
  run hook_once "$SRC"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "transcript resolves from session_id+cwd when the payload carries no transcript_path" {
  export CC_LOCUS_SLICE_MIN=1
  local cwd="/Users/chrisren/Development/.worktrees/wt-demo" sid="sess-xyz" slug
  slug="$(printf '%s' "$cwd" | tr '/.' '--')"
  mkdir -p "$CLAUDE_CONFIG_DIR/projects/$slug"
  uturn "2026-08-11T10:00:00.000Z" > "$CLAUDE_CONFIG_DIR/projects/$slug/$sid.jsonl"
  run bash -c "$(declare -f payload); payload '$SRC' '' '$sid' '$cwd' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'EXECUTION LOCUS'
  # and it stays silent when no transcript can be resolved either way
  rm -rf "$CC_LOCUS_STATE_DIR" "$CLAUDE_CONFIG_DIR/projects/$slug"
  run bash -c "$(declare -f payload); payload '$SRC' '' '$sid' '$cwd' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "every failure path exits 0 and stays silent (a PreToolUse non-zero BLOCKS the tool)" {
  # no file_path · missing transcript · unparseable transcript · empty payload
  for p in '{}' '{"tool_input":{}}' '{"tool_input":{"file_path":"'"$SRC"'"},"session_id":"s","cwd":"/nope"}'; do
    run bash -c "printf '%s' '$p' | bash '$HOOK'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
  printf 'not json at all\n' > "$TX"
  run bash -c "$(declare -f payload); payload '$SRC' '$TX' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the fire writes exactly one auditable IDL line (rate is measurable, threshold tunable)" {
  # three separate invocations, one per turn — slices accumulate ACROSS turns, never within one
  uturn "2026-08-11T10:00:00.000Z" > "$TX"
  hook_once "$SRC" >/dev/null
  uturn "2026-08-11T11:00:00.000Z" >> "$TX"
  hook_once "$SRC" >/dev/null
  uturn "2026-08-11T12:00:00.000Z" >> "$TX"
  hook_once "$SRC" >/dev/null
  [ -s "$CC_LOCUS_IDL" ]
  run bash -c "wc -l < '$CC_LOCUS_IDL' | tr -d ' '"
  [ "$output" = "1" ]
  run jq -e '.disposition=="fired" and .reason=="inline-slice-accumulation" and .slices==3 and .threshold==3' "$CC_LOCUS_IDL"
  [ "$status" -eq 0 ]
}
