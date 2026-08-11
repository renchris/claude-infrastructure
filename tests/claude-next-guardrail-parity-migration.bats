#!/usr/bin/env bats
# claude-next-guardrail-parity-migration.bats — migrations/0009, the guardrail-parity restoration
# for .claude-next (backlog 4ce34a4f703c).
#
# WHY THIS SUITE EXISTS. 0009 is a c10 migration: STAGED and handed to the operator to run. An
# operator step handed over untested is the failure mode MEMORY.md calls
# prescribed-remedy-worse-than-the-bug — so every assertion here EXECUTES the real script against a
# fixtured $HOME rather than reading it.
#
# THE LOAD-BEARING ONE IS ORDERING. Three of the four hook TARGETS are absent from
# .claude-next/hooks, and a settings.json entry pointing at a hook file that does not exist is not
# inert: the harness dispatches it and the exec fails on EVERY matching event — for PreToolUse, that
# is every Bash and AskUserQuestion call in the busiest account. So "wired but unlinked" is strictly
# worse than the defect being fixed, and the test below pins that the migration refuses it.
#
# BATS ERREXIT DISCIPLINE: a non-final `[[ ]]`, `(( ))`, `!` or `A && B` is errexit-EXEMPT and
# therefore a DEAD assertion. Every such assertion carries `|| false`; a final `[ ]` is live.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  MIG="$REPO/migrations/0009-claude-next-guardrail-parity.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  SRC="$HOME/.claude/hooks"; DST="$HOME/.claude-next"
  mkdir -p "$SRC" "$DST/hooks"
  for h in cc-unattended-ask-guard.sh desk-brief-inject.sh session-beat.sh session-deregister.sh; do
    printf '#!/bin/bash\nexit 0\n' > "$SRC/$h"; chmod +x "$SRC/$h"
  done
  # the drifted shape, reduced to its essentials: the five events exist and carry siblings, but none
  # of the five subject entries is present, and only session-deregister.sh is already linked.
  ln -sfn "$SRC/session-deregister.sh" "$DST/hooks/session-deregister.sh"
  jq -n '{hooks:{
      PreToolUse:      [{matcher:"Bash", hooks:[{type:"command",command:"~/.claude/hooks/validate-bash.sh",timeout:5}]}],
      SessionEnd:      [{hooks:[{type:"command",command:"~/.claude/hooks/session-end.sh",timeout:10}]}],
      SessionStart:    [{hooks:[{type:"command",command:"~/.claude/hooks/session-start.sh",timeout:10}]}],
      Stop:            [{hooks:[{type:"command",command:"~/.claude/hooks/operator-readout.sh",timeout:10}]}],
      UserPromptSubmit:[{hooks:[{type:"command",command:"~/.claude/hooks/memory-nudge.sh",timeout:5}]}]
    }}' > "$DST/settings.json"
  export CC_SRC_HOOKS="$SRC" CC_DST_CONFIG="$DST" CC_DRIFT_BIN=/nonexistent
}

wired() { # <event> <substring> → count of matching entries
  jq --arg e "$1" --arg s "$2" \
    '[.hooks[$e][]?.hooks[]?.command | tostring | select(test($s))] | length' "$DST/settings.json"
}

@test "0009 declares its migration class (an undeclared class is a hard error, never a default)" {
  grep -q '^# migration-class: c10$' "$MIG" || false
}

@test "0009 declares the operator step and the exact command to paste" {
  grep -q '^# migration-step: ' "$MIG" || false
  grep -q '^# migration-run: ' "$MIG" || false
}

@test "0009 links the three absent hook targets and leaves the already-linked one alone" {
  run bash "$MIG"
  [ "$status" -eq 0 ]
  for h in cc-unattended-ask-guard.sh desk-brief-inject.sh session-beat.sh session-deregister.sh; do
    [ -f "$DST/hooks/$h" ]
  done
  printf '%s' "$output" | grep -q 'session-deregister.sh — already present' || false
}

@test "0009 wires all five entries exactly once" {
  run bash "$MIG"
  [ "$status" -eq 0 ]
  [ "$(wired PreToolUse       'cc-unattended-ask-guard')" -eq 1 ]
  [ "$(wired SessionEnd       'session-deregister')"      -eq 1 ]
  [ "$(wired SessionStart     'desk-brief-inject')"       -eq 1 ]
  # ONE backslash, not two: these are single-quoted, so `\\.` reaches jq as a regex matching a
  # literal BACKSLASH followed by any char — it can never match, and the test reds for a reason that
  # has nothing to do with the subject.
  [ "$(wired Stop             'session-beat\.sh stop')"   -eq 1 ]
  [ "$(wired UserPromptSubmit 'session-beat\.sh prompt')" -eq 1 ]
}

@test "0009 NEVER wires a hook whose target is missing (the wired-but-unlinked hazard)" {
  # The ordering guarantee, stated as the failure it prevents. With the source hook absent the link
  # cannot be made, and the entry must NOT be written — an entry pointing at a nonexistent file
  # fails on every matching event, which for PreToolUse is every Bash call in the account.
  rm -f "$SRC/cc-unattended-ask-guard.sh"
  run bash "$MIG"
  [ "$status" -eq 1 ]
  [ "$(wired PreToolUse 'cc-unattended-ask-guard')" -eq 0 ]
  # …and the failure is LOUD, not a silent skip
  printf '%s' "$output" | grep -q 'SOURCE MISSING' || false
  # the other four are independent and must still land — one missing source is not a reason to
  # abandon four guardrails (a partial fix beats none, provided it is reported)
  [ "$(wired SessionStart 'desk-brief-inject')" -eq 1 ]
}

@test "0009 joins the EXISTING matcher group rather than forking a sibling" {
  # A matcher group is a dispatch unit. Appending a second no-matcher Stop group would still 'work',
  # but it silently changes the grouping the harness dispatches, and drift-assert (which compares by
  # entry, not by group) would never notice. Pin the structure, not just the presence.
  run bash "$MIG"
  [ "$status" -eq 0 ]
  [ "$(jq '.hooks.Stop | length' "$DST/settings.json")" -eq 1 ]
  [ "$(jq '.hooks.Stop[0].hooks | length' "$DST/settings.json")" -eq 2 ]
  # PreToolUse is the exception BY DESIGN: no AskUserQuestion group exists, so one is created
  [ "$(jq '[.hooks.PreToolUse[] | select(.matcher == "AskUserQuestion")] | length' "$DST/settings.json")" -eq 1 ]
}

@test "0009 is idempotent — a second run changes nothing and mints no second backup" {
  bash "$MIG" >/dev/null 2>&1
  local before; before="$(jq -S . "$DST/settings.json")"
  run bash "$MIG"
  [ "$status" -eq 0 ]
  [ "$(jq -S . "$DST/settings.json")" = "$before" ]
  printf '%s' "$output" | grep -q 'already wired' || false
  [ "$(find "$DST" -maxdepth 1 -name 'settings.json.bak-0009-*' | wc -l | tr -d ' ')" -eq 1 ]
}

@test "0009 backs up before writing and the backup is the PRE-migration content" {
  local before; before="$(jq -S . "$DST/settings.json")"
  run bash "$MIG"
  [ "$status" -eq 0 ]
  local bak; bak="$(find "$DST" -maxdepth 1 -name 'settings.json.bak-0009-*' | head -1)"
  [ -n "$bak" ]
  [ "$(jq -S . "$bak")" = "$before" ]
}

@test "0009 leaves a settings.json it cannot parse completely untouched" {
  # A malformed live config is not this migration's to repair, and a jq edit over it would emit an
  # empty file — the one outcome strictly worse than the drift.
  printf 'not json at all' > "$DST/settings.json"
  run bash "$MIG"
  [ "$status" -eq 1 ]
  [ "$(cat "$DST/settings.json")" = "not json at all" ]
}

@test "0009 skips a config dir that is not a fleet config" {
  # No settings.json at all: nothing to do, and inventing one is a scope this migration never claimed.
  rm -f "$DST/settings.json"
  run bash "$MIG"
  [ "$status" -eq 0 ]
  [ ! -f "$DST/settings.json" ]
}
