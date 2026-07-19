#!/usr/bin/env bats
# cc-unattended-ask-guard — RED-proves the executable half of the CC_UNATTENDED AskUserQuestion
# guard (T-P15-7 / G-P15-5). Until this landed the guard was PROSE-ONLY in
# commands/limit-recover.md; nothing refused the blocking elicitation. These tests fail against
# an absent/reverted hook and against the two classic ways this guard rots:
#   (a) the interactive path stops being unchanged (a human's ask gets blocked), and
#   (b) a falsy CC_UNATTENDED=0 gets misread as truthy.
# The load-bearing invariant is asserted first: CC_UNATTENDED unset ⇒ exit 0, ZERO output.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/cc-unattended-ask-guard.sh"
  TMPL="$REPO/settings-templates/settings.example.json"
  ASK='{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Wait for reset, or continue cross-account?","header":"Limit"}]}}'
}

# ── The load-bearing invariant: interactive is UNCHANGED ──────────────────────────────────
@test "interactive (CC_UNATTENDED unset) → exit 0 and emits NOTHING (path unchanged)" {
  run env -u CC_UNATTENDED "$HOOK" <<<"$ASK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "falsy CC_UNATTENDED=0 → exit 0 (NOT misread as truthy — the classic bug)" {
  run env CC_UNATTENDED=0 "$HOOK" <<<"$ASK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "falsy CC_UNATTENDED=false → exit 0" {
  run env CC_UNATTENDED=false "$HOOK" <<<"$ASK"
  [ "$status" -eq 0 ]
}

@test "empty CC_UNATTENDED= → exit 0 (empty is interactive)" {
  run env CC_UNATTENDED= "$HOOK" <<<"$ASK"
  [ "$status" -eq 0 ]
}

# ── Unattended: the blocking elicitation is refused with a routing reason ───────────────────
@test "unattended (CC_UNATTENDED=1) + AskUserQuestion → exit 2 (blocked)" {
  run env CC_UNATTENDED=1 "$HOOK" <<<"$ASK"
  [ "$status" -eq 2 ]
}

@test "block reason routes to a cc-decide class-B packet + standing-value default" {
  run env CC_UNATTENDED=1 "$HOOK" <<<"$ASK"
  [ "$status" -eq 2 ]
  [[ "$output" == *"cc-decide open --class B"* ]]
  [[ "$output" == *"gate-classify.sh"* ]]
  [[ "$output" == *"--default"* ]]
  [[ "$output" == *"PROCEED"* ]]
}

@test "block reason echoes the blocked question so the agent can name the fork" {
  run env CC_UNATTENDED=1 "$HOOK" <<<"$ASK"
  [[ "$output" == *"Wait for reset, or continue cross-account?"* ]]
}

@test "truthy aliases (true|yes|on|1, case-insensitive) all block" {
  for v in true YES On 1 TRUE; do
    run env CC_UNATTENDED="$v" "$HOOK" <<<"$ASK"
    [ "$status" -eq 2 ] || { echo "value '$v' did not block (status=$status)"; return 1; }
  done
}

# ── Decision hinges on the env, not the payload: block-safe on garbage in ───────────────────
@test "unattended + empty stdin → still exit 2 (a strand blocks even with no parseable question)" {
  run env CC_UNATTENDED=1 "$HOOK" <<<""
  [ "$status" -eq 2 ]
}

@test "unattended + malformed JSON stdin → still exit 2 (fail-safe toward blocking)" {
  run env CC_UNATTENDED=1 "$HOOK" <<<"not json {{"
  [ "$status" -eq 2 ]
}

# ── Defensive scope + operability ───────────────────────────────────────────────────────────
@test "non-AskUserQuestion tool under unattended → exit 0 (guard scoped to AskUserQuestion)" {
  run env CC_UNATTENDED=1 "$HOOK" <<<'{"tool_name":"Bash","tool_input":{"command":"ls"}}'
  [ "$status" -eq 0 ]
}

@test "kill switch CC_UNATTENDED_ASK_GUARD_DISABLED=1 → exit 0 even when unattended" {
  run env CC_UNATTENDED=1 CC_UNATTENDED_ASK_GUARD_DISABLED=1 "$HOOK" <<<"$ASK"
  [ "$status" -eq 0 ]
}

# ── The "executable/wired, not prose-only" proof: the hook is registered + runnable ─────────
@test "hook file is executable (install.sh will symlink a runnable file)" {
  [ -x "$HOOK" ]
}

@test "settings template registers the hook under an AskUserQuestion PreToolUse matcher" {
  run jq -e '.hooks.PreToolUse[] | select(.matcher | test("AskUserQuestion")) | .hooks[].command | select(test("cc-unattended-ask-guard.sh"))' "$TMPL"
  [ "$status" -eq 0 ]
}
