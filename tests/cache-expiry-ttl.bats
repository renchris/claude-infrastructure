#!/usr/bin/env bats
# cache-expiry-warning.sh — pins the two corrections from USAGE_TELEMETRY_100P §2.4.
#
# The hook fired at a 300s threshold when the real prompt-cache TTL on a Claude subscription is
# ~3600s (measured breakpoint in our own corpus: 65 min; 184 of 238 fires were FALSE, a 77.3%
# false-fire rate over 13,622 user-prompt gaps), and it recommended /clear or /compact "to reduce
# token cost" — which INCREASES quota spend, because against the weekly limit cache_read is charged
# at ~nothing while cache_creation is 42-48% of the bill, so discarding a warm cache converts a free
# operation into a paid one.
#
# Both halves are pinned here. Case 3 is the CONTROL: it drives the OLD 300s threshold through the
# same harness and requires a fire, so a suite that goes silent for a harness reason (a bad path, an
# unreadable tracking file, a swallowed heredoc) cannot pass by emitting nothing everywhere.
#
# RED-PROOF, run against `git show origin/main:hooks/cache-expiry-warning.sh` (the pristine pre-fix
# subject): **5 of 7 fail** — cases 2, 3, 5, 6, 7. Cases 1 and 4 pass on BOTH branches and are named
# here as CONTRACT-PRESERVATION, not counted as proofs: they pin the silent-on-first-message path and
# the JSON envelope, neither of which this change was allowed to alter.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  H="$REPO/hooks/cache-expiry-warning.sh"
  D="$BATS_TEST_TMPDIR"
  # HERMETICITY: the subject resolves its tracking file as ${CLAUDE_CONFIG_DIR:-$HOME/.claude},
  # so pinning CLAUDE_CONFIG_DIR alone is not enough — the FALLBACK still reaches the operator's
  # live ~/.claude the moment that var is unset or empty. Fixture $HOME too, and seed the
  # .claude dir the fallback would use, so neither branch can escape the test tmpdir.
  export HOME="$D/home"
  mkdir -p "$HOME/.claude"
  export CLAUDE_CONFIG_DIR="$D"
}

# write a .last-interaction that is $1 seconds in the past
idle_for() { echo "$(( $(date +%s) - $1 ))" > "$D/.last-interaction"; }

run_hook() { run env CLAUDE_CONFIG_DIR="$D" ${1:+CC_PROMPT_CACHE_TTL_S=$1} bash "$H" </dev/null; }

@test "no tracking file (first message of a session) is silent and exits 0" {
  rm -f "$D/.last-interaction"
  run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "10m idle is SILENT at the corrected 1h default (the 77.3% false-fire class)" {
  idle_for 600
  run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "CONTROL: the same 10m idle DOES fire at the old 300s threshold" {
  # Proves the harness can observe a fire, so the silence above is the subject's behaviour
  # and not a broken test. Without this, every assertion here passes vacuously.
  idle_for 600
  run_hook 300
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  printf '%s' "$output" | grep -q 'PROMPT CACHE EXPIRED'
}

@test "120m idle fires and emits valid JSON on the UserPromptSubmit channel" {
  idle_for 7200
  run_hook
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.hookSpecificOutput.hookEventName == "UserPromptSubmit"' >/dev/null
  printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | length > 0' >/dev/null
}

@test "the message never recommends /clear or /compact (it would RAISE quota spend)" {
  idle_for 7200
  run_hook
  msg="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  ! printf '%s' "$msg" | grep -q '/clear' || false
  ! printf '%s' "$msg" | grep -q '/compact' || false
  # and it must say the quiet part out loud, so a future reader does not re-add the advice
  printf '%s' "$msg" | grep -q 'does NOT save quota'
}

@test "the TTL is not hardcoded to 300 anywhere in the hook" {
  # the original defect, pinned so a revert is caught at the gate rather than in the field
  ! grep -qE '^[[:space:]]*CACHE_TTL=300([[:space:]]|$)' "$H" || false
  grep -q 'CC_PROMPT_CACHE_TTL_S' "$H"
}

@test "the reported TTL in the message tracks the configured one" {
  idle_for 7200
  run_hook 1800
  msg="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  printf '%s' "$msg" | grep -q '30m TTL'
}
