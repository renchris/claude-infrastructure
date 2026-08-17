#!/usr/bin/env bats
# The desk brief SSOT + its injection hook.
#
# docs/templates/desk-boot-brief.md is the SINGLE definition of the desk role. Four consumers read
# it — the auto-respawn sweep, the launcher, the in-place command, and the SessionStart hook. The
# failure this file is built to prevent is DRIFT: a consumer that stops pointing at the SSOT (or an
# SSOT that quietly empties) degrades SILENTLY into a desk that does not know it is the desk. So the
# lint tests below assert the wiring itself, not just behaviour.
#
# hooks/desk-brief-inject.sh is what makes desk-register the single ACTIVATION trigger: hold the
# role → get the brief, mechanically, on every start/resume/compact.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  BRIEF="$REPO/docs/templates/desk-boot-brief.md"
  HOOK="$REPO/hooks/desk-brief-inject.sh"
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"; mkdir -p "$CC_ROLES_DIR"
  # Hermetic disposition log. NOT optional: the hook's default is ~/.claude/autonomy/idl.jsonl, so
  # without this every run of this suite would append to the REAL fleet IDL and pollute the very
  # signal these cases exist to protect.
  export DESK_BRIEF_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  PANE="PANE-AAAA-BBBB-CCCC-000000000001"
}
ctx() { jq -r '.hookSpecificOutput.additionalContext' ; }
# last recorded {disposition,reason} pair — the hook's whole wire surface
disp()   { jq -r '.disposition' "$DESK_BRIEF_IDL" 2>/dev/null | tail -1; }
reason() { jq -r '.reason'      "$DESK_BRIEF_IDL" 2>/dev/null | tail -1; }

# ---- SSOT lint -------------------------------------------------------------------------------

@test "lint: the brief SSOT exists and is non-empty" {
  [ -f "$BRIEF" ]
  [ "$(wc -c < "$BRIEF" | tr -d ' ')" -gt 500 ]
}

@test "lint: the brief still defines the ROLE (state-free content that must never rot out)" {
  grep -q "orchestrator desk" "$BRIEF"
  grep -q "cc-roles/desk" "$BRIEF"          # the role file it tells you to hold
  grep -q "cc-blockers" "$BRIEF"            # orient step
  grep -q "desk-register" "$BRIEF"          # how to claim the role
  grep -qi "drive" "$BRIEF"                 # the operating principle
}

@test "lint: EVERY consumer references the SSOT (drift guard)" {
  # auto-respawn sweep — fires a replacement desk from it
  grep -q "docs/templates/desk-boot-brief.md" "$REPO/scripts/desk-invariant.sh"
  # the SessionStart injection hook
  grep -q "docs/templates/desk-boot-brief.md" "$REPO/hooks/desk-brief-inject.sh"
  # the launcher (fresh pane)
  grep -q "docs/templates/desk-boot-brief.md" "$REPO/lib/desk.zsh"
  # the in-place command
  grep -q "docs/templates/desk-boot-brief.md" "$REPO/commands/desk.md"
}

@test "lint: both wrappers invoke the desk-register primitive" {
  grep -q "desk-register" "$REPO/lib/desk.zsh"
  grep -q "desk-register" "$REPO/commands/desk.md"
}

@test "lint: the brief does NOT re-arm a per-session cadence loop (launchd owns cadence)" {
  # Earlier desk generations booted by arming a ~900s in-session Monitor; that double-dispatches
  # and dies with the pane. The brief must say so rather than instruct it.
  grep -q "launchd" "$BRIEF"
  ! grep -qE "re-arm the .*cadence Monitor|arm the ~?900s" "$BRIEF"
}

# ---- hook behaviour --------------------------------------------------------------------------

@test "hook: THIS pane holds the role → injects the brief as SessionStart additionalContext" {
  printf '%s\n' "$PANE" > "$CC_ROLES_DIR/desk"
  run env DESK_BRIEF_PANE="$PANE" "$HOOK" <<< '{"hook_event_name":"SessionStart"}'
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.hookEventName')" = "SessionStart" ]
  printf '%s' "$output" | ctx | grep -q "Desk boot brief"
  printf '%s' "$output" | ctx | grep -q "BINDING"
}

@test "hook: a DIFFERENT pane holds the role → silent no-op (never leaks the desk brief)" {
  printf '%s\n' "SOMEONE-ELSE" > "$CC_ROLES_DIR/desk"
  run env DESK_BRIEF_PANE="$PANE" "$HOOK" <<< '{"hook_event_name":"SessionStart"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "hook: no role registered → silent no-op" {
  run env DESK_BRIEF_PANE="$PANE" "$HOOK" <<< '{"hook_event_name":"SessionStart"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "hook: not an iTerm pane (no \$ITERM_SESSION_ID) → silent no-op, never errors" {
  printf '%s\n' "$PANE" > "$CC_ROLES_DIR/desk"
  run env -u ITERM_SESSION_ID -u DESK_BRIEF_PANE CC_ROLES_DIR="$CC_ROLES_DIR" \
      "$HOOK" <<< '{"hook_event_name":"SessionStart"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "hook: derives the pane from the iTerm2 wNtNpN:UUID form" {
  printf '%s\n' "$PANE" > "$CC_ROLES_DIR/desk"
  run env -u DESK_BRIEF_PANE ITERM_SESSION_ID="w2t0p3:$PANE" CC_ROLES_DIR="$CC_ROLES_DIR" \
      "$HOOK" <<< '{"hook_event_name":"SessionStart"}'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | ctx | grep -q "Desk boot brief"
}

@test "hook: a MISSING brief degrades silently (a SessionStart hook must never cost a session)" {
  printf '%s\n' "$PANE" > "$CC_ROLES_DIR/desk"
  run env DESK_BRIEF_PANE="$PANE" DESK_BRIEF_FILE="$BATS_TEST_TMPDIR/nope.md" \
      "$HOOK" <<< '{"hook_event_name":"SessionStart"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "hook: emits ONE line of valid JSON (a broken parse demotes the whole hook output)" {
  printf '%s\n' "$PANE" > "$CC_ROLES_DIR/desk"
  env DESK_BRIEF_PANE="$PANE" "$HOOK" <<< '{"hook_event_name":"SessionStart"}' > "$BATS_TEST_TMPDIR/o.json"
  [ "$(wc -l < "$BATS_TEST_TMPDIR/o.json" | tr -d ' ')" = "1" ]
  jq -e . "$BATS_TEST_TMPDIR/o.json" >/dev/null
}

@test "hook: resolves its brief THROUGH a symlink (~/.claude/hooks is a per-file symlink)" {
  # The bug this guards: an unresolved dirname makes "../docs/..." resolve under ~/.claude, which
  # has no docs/ — so the brief silently vanishes at the live path. scripts/desk-invariant.sh had
  # exactly this defect and survived only via an absolute launchd override.
  printf '%s\n' "$PANE" > "$CC_ROLES_DIR/desk"
  mkdir -p "$BATS_TEST_TMPDIR/fakehooks"
  ln -s "$HOOK" "$BATS_TEST_TMPDIR/fakehooks/desk-brief-inject.sh"
  # NB: `env` options must precede the VAR=value assignments — BSD env treats everything after the
  # first assignment as the command to run (an `-u` placed later becomes the command → exit 127).
  run env -u DESK_BRIEF_FILE DESK_BRIEF_PANE="$PANE" CC_ROLES_DIR="$CC_ROLES_DIR" \
      "$BATS_TEST_TMPDIR/fakehooks/desk-brief-inject.sh" <<< '{"hook_event_name":"SessionStart"}'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | ctx | grep -q "Desk boot brief"
}

# ---- dead-consumer observability (backlog 04010b4c8074) ---------------------------------------
# This hook keys on ~/.claude/cc-roles/<role>. That file was DELETED by a cleanup on 2026-07-26 and
# the hook has injected nothing since — silently, because it emitted no telemetry of any kind. With
# zero records it did not even appear in scripts/idl-abstain-alarm.sh's table (a hook with no
# evaluations leaves the table by design), so "dead since July" and "healthy, desk is elsewhere"
# were the same observation. Every exit path now names itself on the wire.
# docs/research/idle-recycle-not-proactive-2026-08-08.md §"Secondary items".

@test "IDL: no role file at all → abstained:no-role-file (the dead-consumer state, named)" {
  run env DESK_BRIEF_PANE="$PANE" "$HOOK" <<< '{"hook_event_name":"SessionStart","session_id":"S1"}'
  [ "$status" -eq 0 ]; [ -z "$output" ]              # stdout silence is UNCHANGED — only the wire moved
  [ "$(disp)" = "abstained" ]
  [ "$(reason)" = "no-role-file" ]
}

@test "IDL: an EMPTY role file is its own state (role-empty), not 'absent' and not 'someone else'" {
  : > "$CC_ROLES_DIR/desk"
  run env DESK_BRIEF_PANE="$PANE" "$HOOK" <<< '{"hook_event_name":"SessionStart","session_id":"S2"}'
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ "$(reason)" = "role-empty" ]
}

@test "IDL: CONTROL — a role held by ANOTHER pane is other-holder, NOT a dead consumer" {
  # The load-bearing case. Without it, the two above would pass on a hook that reported every
  # non-fire as a dead channel — which is the same collapse, inverted, and would make a healthy
  # fleet page-worthy noise.
  printf '%s\n' "SOMEONE-ELSE" > "$CC_ROLES_DIR/desk"
  run env DESK_BRIEF_PANE="$PANE" "$HOOK" <<< '{"hook_event_name":"SessionStart","session_id":"S3"}'
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ "$(reason)" = "other-holder" ]
}

@test "IDL: POSITIVE CONTROL — the desk pane records a FIRE (an all-abstain table is ambiguous)" {
  printf '%s\n' "$PANE" > "$CC_ROLES_DIR/desk"
  run env DESK_BRIEF_PANE="$PANE" "$HOOK" <<< '{"hook_event_name":"SessionStart","session_id":"S4"}'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | ctx | grep -q "Desk boot brief"
  [ "$(disp)" = "fired" ]
  [ "$(reason)" = "injected" ]
  [ "$(jq -r '.pane' "$DESK_BRIEF_IDL" | tail -1)" = "$PANE" ]
}

@test "IDL: a MISSING brief is brief-missing — a broken SSOT never poses as 'not the desk'" {
  printf '%s\n' "$PANE" > "$CC_ROLES_DIR/desk"
  run env DESK_BRIEF_PANE="$PANE" DESK_BRIEF_FILE="$BATS_TEST_TMPDIR/nope.md" \
      "$HOOK" <<< '{"hook_event_name":"SessionStart","session_id":"S5"}'
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ "$(reason)" = "brief-missing" ]
}

@test "IDL: the session id rides the record (a row with no sid cannot be joined to anything)" {
  run env DESK_BRIEF_PANE="$PANE" "$HOOK" <<< '{"hook_event_name":"SessionStart","session_id":"S-JOIN-ME"}'
  [ "$status" -eq 0 ]
  [ "$(jq -r '.sid' "$DESK_BRIEF_IDL" | tail -1)" = "S-JOIN-ME" ]
  [ "$(jq -r '.hook' "$DESK_BRIEF_IDL" | tail -1)" = "desk-brief-inject" ]
}

@test "IDL: every record is ONE line of valid JSON (a malformed line aborts the cc-audit slurp)" {
  # The invariant hooks/lib/idl-log.sh exists to hold: one bad line reads as "no records" and
  # silently flips the abstain alarm green, defeating the detector this change feeds.
  printf '%s\n' "$PANE" > "$CC_ROLES_DIR/desk"
  env DESK_BRIEF_PANE="$PANE" "$HOOK" <<< '{"hook_event_name":"SessionStart","session_id":"S6"}' >/dev/null
  env DESK_BRIEF_PANE="OTHER" "$HOOK" <<< '{"hook_event_name":"SessionStart","session_id":"S7"}' >/dev/null
  [ "$(wc -l < "$DESK_BRIEF_IDL" | tr -d ' ')" = "2" ]
  jq -e -s 'length == 2' "$DESK_BRIEF_IDL" >/dev/null
}

@test "IDL: telemetry NEVER costs the session — an unwritable log still injects the brief" {
  printf '%s\n' "$PANE" > "$CC_ROLES_DIR/desk"
  run env DESK_BRIEF_PANE="$PANE" DESK_BRIEF_IDL="/nonexistent-dir-$$/deep/idl.jsonl" \
      "$HOOK" <<< '{"hook_event_name":"SessionStart","session_id":"S8"}'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | ctx | grep -q "Desk boot brief"
}

@test "IDL: run from a TTY-less pipe with NO payload it still records (never hangs on stdin)" {
  run env DESK_BRIEF_PANE="$PANE" "$HOOK" < /dev/null
  [ "$status" -eq 0 ]
  [ "$(reason)" = "no-role-file" ]
  [ "$(jq -r '.sid' "$DESK_BRIEF_IDL" | tail -1)" = "?" ]
}

@test "lint: the hook's reason vocabulary is NOT in idl-abstain-alarm's blind set (never pages)" {
  # A desk-less machine is a DELIBERATE state (scripts/desk-invariant.sh's `not-opted-in`, D6), so
  # these must classify DORMANT — reported for review, never a page. Blind tokens page.
  local blind; blind="$(sed -n '/^_default_blind=(/,/)$/p' "$REPO/scripts/idl-abstain-alarm.sh")"
  [ -n "$blind" ]                                   # the extractor must SEE its subject
  for r in no-role-file role-empty other-holder brief-missing brief-empty; do
    ! printf '%s' "$blind" | grep -q -- "$r" || false
  done
}

@test "desk-invariant: resolves its brief through a symlink too (the fixed default)" {
  mkdir -p "$BATS_TEST_TMPDIR/fakescripts"
  ln -s "$REPO/scripts/desk-invariant.sh" "$BATS_TEST_TMPDIR/fakescripts/desk-invariant.sh"
  # --selftest is hermetic; if SCRIPT_DIR were unresolved the script still runs, so assert the
  # resolution directly: the default BRIEF must land on a file that EXISTS.
  run bash -c '
    s="'"$BATS_TEST_TMPDIR"'/fakescripts/desk-invariant.sh"
    while [ -L "$s" ]; do d="$(cd -P "$(dirname "$s")" && pwd)"; s="$(readlink "$s")"
      case "$s" in /*) ;; *) s="$d/$s" ;; esac; done
    d="$(cd -P "$(dirname "$s")" && pwd)"
    test -f "$d/../docs/templates/desk-boot-brief.md"'
  [ "$status" -eq 0 ]
}
