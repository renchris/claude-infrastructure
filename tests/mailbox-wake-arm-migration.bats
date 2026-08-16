#!/usr/bin/env bats
# mailbox-wake-arm-migration.bats — migrations/0007, the registration half of arming-by-construction.
#
# WHY THIS SUITE EXISTS. 0007 is a c10 migration: it is STAGED and handed to the operator to run. An
# operator step handed over untested is the failure mode MEMORY.md calls
# prescribed-remedy-worse-than-the-bug — "run a prescription TWICE, in the context that EXECUTES it".
# So every assertion here executes the real script against a fixtured $HOME.
#
# The load-bearing one is ASYNC: registering the command WITHOUT `asyncRewake: true` would install a
# SYNCHRONOUS hook that blocks every session birth for its full 14400 s timeout — strictly worse than
# not arming at all. That is what the content-verify inside the migration exists to prevent, and what
# the mutation-shaped test below pins.
#
# BATS ERREXIT DISCIPLINE: a non-final `[[ ]]`, `(( ))`, `!` or `A && B` is errexit-EXEMPT and
# therefore a DEAD assertion. Every such assertion carries `|| false`; a final `[ ]` is live.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  MIG="$REPO/migrations/0007-mailbox-wake-arm-registration.sh"
  MIG12="$REPO/migrations/0012-mailbox-wake-arm-stop-rearm.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/hooks" "$HOME/.claude-tertiary"
  cp "$REPO/hooks/mailbox-wake-arm.sh" "$HOME/.claude/hooks/"
  chmod +x "$HOME/.claude/hooks/mailbox-wake-arm.sh"
  export CC_CLAUDE_DIR="$HOME/.claude"
  # A fleet config runs BOTH boundaries — 0007 registers on SessionStart, 0012 on Stop, and each
  # skips a config lacking its own array. One fixture carrying both is what a live config looks like.
  FLEET='{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"~/.claude/hooks/mailbox-drain.sh session-start","timeout":10}]}],"Stop":[{"hooks":[{"type":"command","command":"~/.claude/hooks/session-continue.sh","timeout":10}]}]}}'
  printf '%s' "$FLEET" > "$HOME/.claude/settings.json"
  printf '%s' "$FLEET" > "$HOME/.claude-tertiary/settings.json"
}

entry() { # <config-dir> → the registered wake-arm entry, compact
  jq -c '.hooks.SessionStart[].hooks[]? | select(.command|test("mailbox-wake-arm"))' "$1/settings.json"
}
count() { # <config-dir> → how many wake-arm entries
  jq '[.hooks.SessionStart[].hooks[]? | select(.command|test("mailbox-wake-arm"))] | length' "$1/settings.json"
}
entry_stop() { # <config-dir> → the registered Stop wake-arm entry, compact
  jq -c '.hooks.Stop[].hooks[]? | select(.command|test("mailbox-wake-arm"))' "$1/settings.json"
}
count_stop() { # <config-dir> → how many Stop wake-arm entries
  jq '[.hooks.Stop[].hooks[]? | select(.command|test("mailbox-wake-arm"))] | length' "$1/settings.json"
}

@test "0007 declares its migration class (an undeclared class is a hard error, never a default)" {
  grep -q '^# migration-class: c10$' "$MIG" || false
}

@test "0007 declares the operator step and the exact command to paste" {
  grep -q '^# migration-step: ' "$MIG" || false
  grep -q '^# migration-run: ' "$MIG" || false
}

@test "0007 registers the hook in every FLEET config dir" {
  run bash "$MIG"
  [ "$status" -eq 0 ]
  [ "$(count "$HOME/.claude")" = "1" ]
  [ "$(count "$HOME/.claude-tertiary")" = "1" ]
}

@test "0007 registers it ASYNC — a synchronous entry would block every session birth for 14400s" {
  bash "$MIG" >/dev/null 2>&1
  run entry "$HOME/.claude"
  printf '%s' "$output" | jq -e '.asyncRewake == true' >/dev/null || false
  printf '%s' "$output" | jq -e '.timeout == 14400' >/dev/null || false
}

@test "0007 sets the operator-facing labels the harness renders on a wake" {
  bash "$MIG" >/dev/null 2>&1
  run entry "$HOME/.claude"
  printf '%s' "$output" | jq -e '.rewakeMessage | length > 0' >/dev/null || false
  printf '%s' "$output" | jq -e '.rewakeSummary | length > 0' >/dev/null || false
}

@test "0007 is IDEMPOTENT — a second run adds nothing and still exits 0" {
  bash "$MIG" >/dev/null 2>&1
  run bash "$MIG"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'already registered' || false
  [ "$(count "$HOME/.claude")" = "1" ]
}

@test "0007 never disturbs a sibling hook" {
  bash "$MIG" >/dev/null 2>&1
  run jq '[.hooks.SessionStart[].hooks[]? | select(.command|test("mailbox-drain"))] | length' "$HOME/.claude/settings.json"
  [ "$output" = "1" ]
}

@test "0007 backs up before it edits — 'operator can revert' is a property, not a promise" {
  bash "$MIG" >/dev/null 2>&1
  run bash -c "ls '$HOME/.claude/settings.json.bak-0007-'* 2>/dev/null | wc -l"
  [ "$(printf '%s' "$output" | tr -d ' ')" = "1" ]
  # and the backup is the PRE-edit content: no wake-arm entry in it
  run bash -c "cat '$HOME/.claude/settings.json.bak-0007-'* | grep -c mailbox-wake-arm"
  [ "$(printf '%s' "$output" | tr -d ' ')" = "0" ]
}

@test "0007 SKIPS a config that is not a fleet config rather than inventing a SessionStart array" {
  mkdir -p "$HOME/.claude-quaternary"
  printf '{"hooks":{}}' > "$HOME/.claude-quaternary/settings.json"
  run bash "$MIG"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'not a fleet config' || false
  run jq -c '.hooks' "$HOME/.claude-quaternary/settings.json"
  [ "$output" = "{}" ]
}

@test "0007 REFUSES when the adapter is not on the live layer (a registered no-op reads GREEN)" {
  rm -f "$HOME/.claude/hooks/mailbox-wake-arm.sh"
  run bash "$MIG"
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q 'NOT registered' || false
  [ "$(count "$HOME/.claude")" = "0" ]
}

@test "0007 leaves VALID json (a corrupt settings.json would deafen every hook, not just this one)" {
  bash "$MIG" >/dev/null 2>&1
  run jq -e . "$HOME/.claude/settings.json"
  [ "$status" -eq 0 ]
}

# ── 0012 — the STOP half (W2) ────────────────────────────────────────────────────────────────────
# Same c10 discipline, one event over. What is NOT the same is the failure it is guarding against:
# 0007 registered wrong would block session BIRTH; 0012 registered wrong would block EVERY TURN END,
# and — because the harness dedupes nothing (P-W2c) — registered without the subject's claim guard it
# would start one watcher per idle boundary and wake the model once per watcher on the same mail.
# The guard precondition is therefore an assertion about a FILE THIS SCRIPT DOES NOT SHIP, which is
# the only shape that survives a partial converge of a symlink farm.

@test "0012 declares its migration class (an undeclared class is a hard error, never a default)" {
  grep -q '^# migration-class: c10$' "$MIG12" || false
}

@test "0012 declares the operator step and the exact command to paste" {
  grep -q '^# migration-step: ' "$MIG12" || false
  grep -q '^# migration-run: ' "$MIG12" || false
}

@test "0012 registers the hook on STOP in every FLEET config dir" {
  run bash "$MIG12"
  [ "$status" -eq 0 ]
  [ "$(count_stop "$HOME/.claude")" = "1" ]
  [ "$(count_stop "$HOME/.claude-tertiary")" = "1" ]
}

@test "0012 registers it ASYNC — a synchronous entry would wedge every turn end for 14400s" {
  bash "$MIG12" >/dev/null 2>&1
  run entry_stop "$HOME/.claude"
  printf '%s' "$output" | jq -e '.asyncRewake == true' >/dev/null || false
  printf '%s' "$output" | jq -e '.timeout == 14400' >/dev/null || false
}

@test "0012 sets the operator-facing labels the harness renders on a wake" {
  bash "$MIG12" >/dev/null 2>&1
  run entry_stop "$HOME/.claude"
  printf '%s' "$output" | jq -e '.rewakeMessage | length > 0' >/dev/null || false
  printf '%s' "$output" | jq -e '.rewakeSummary | length > 0' >/dev/null || false
}

@test "0012 is IDEMPOTENT — a second run adds nothing and still exits 0" {
  bash "$MIG12" >/dev/null 2>&1
  run bash "$MIG12"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'already registered' || false
  [ "$(count_stop "$HOME/.claude")" = "1" ]
}

@test "0012 REFUSES when the subject carries no CLAIM GUARD — one watcher per idle boundary" {
  # The registration is only safe in the same breath as the guard. A live layer that took the
  # settings edit but not the hook would wake the model once per accumulated watcher, which is the
  # exact turn-burn W2 exists to make cheap.
  grep -v '_armed_already' "$REPO/hooks/mailbox-wake-arm.sh" > "$HOME/.claude/hooks/mailbox-wake-arm.sh"
  chmod +x "$HOME/.claude/hooks/mailbox-wake-arm.sh"
  run bash "$MIG12"
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q 'no claim guard' || false
  [ "$(count_stop "$HOME/.claude")" = "0" ]
}

@test "0012 REFUSES when the adapter is not on the live layer (a registered no-op reads GREEN)" {
  rm -f "$HOME/.claude/hooks/mailbox-wake-arm.sh"
  run bash "$MIG12"
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q 'NOT registered' || false
  [ "$(count_stop "$HOME/.claude")" = "0" ]
}

@test "0012 SKIPS a config with no Stop array rather than inventing one" {
  mkdir -p "$HOME/.claude-quaternary"
  printf '{"hooks":{"SessionStart":[{"hooks":[]}]}}' > "$HOME/.claude-quaternary/settings.json"
  run bash "$MIG12"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'not a fleet config' || false
  run jq -e '.hooks | has("Stop")' "$HOME/.claude-quaternary/settings.json"
  [ "$status" -ne 0 ]
}

@test "0012 backs up before it edits, and never disturbs a sibling Stop hook" {
  bash "$MIG12" >/dev/null 2>&1
  run bash -c "ls '$HOME/.claude/settings.json.bak-0012-'* 2>/dev/null | wc -l"
  [ "$(printf '%s' "$output" | tr -d ' ')" = "1" ]
  run jq '[.hooks.Stop[].hooks[]? | select(.command|test("session-continue"))] | length' "$HOME/.claude/settings.json"
  [ "$output" = "1" ]
}

@test "0012 leaves the SessionStart registration alone — the two halves are independent" {
  bash "$MIG" >/dev/null 2>&1
  bash "$MIG12" >/dev/null 2>&1
  [ "$(count "$HOME/.claude")" = "1" ]
  [ "$(count_stop "$HOME/.claude")" = "1" ]
  run jq -e . "$HOME/.claude/settings.json"
  [ "$status" -eq 0 ]
}
