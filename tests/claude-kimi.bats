#!/usr/bin/env bats
# claude-kimi — the isolated metered Kimi K3 launcher. Its `selftest` RED-proves the internal
# invariants (key resolution, contract shape, ISOLATION from the 4 Max config dirs, glob-safe model
# string); these bats add CLI-level regression on the turnkey activation contract:
#   * no key  → activation notice, exit 0, ~$0 idle (never launches / costs anything)
#   * with key → the EXACT verified metered env contract Claude Code receives (DRYRUN, no real call)
#   * isolation is structural, not incidental (config dir never a Max dir; auth is AUTH_TOKEN)
#   * metered (Moonshot) vs subscription (kimi.com/coding) endpoint is surfaced, not conflated.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  T="$REPO/bin/claude-kimi"
  # Fully isolate every run from the operator's real key + config: temp key file, temp config dir,
  # a stub "claude" binary, and DRYRUN so nothing ever execs a real session.
  export KIMI_KEY_FILE="$BATS_TEST_TMPDIR/key"
  export CLAUDE_KIMI_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"
  export CLAUDE_KIMI_CLAUDE_BIN="$BATS_TEST_TMPDIR/claude-stub"
  printf '#!/bin/bash\necho "STUB-CLAUDE $*"\n' > "$CLAUDE_KIMI_CLAUDE_BIN"
  chmod +x "$CLAUDE_KIMI_CLAUDE_BIN"
  unset KIMI_API_KEY
}

@test "selftest passes and runs all 12 RED-proof checks (a zero-check suite must not 'pass')" {
  run "$T" selftest
  [ "$status" -eq 0 ]
  n_ok="$(printf '%s' "$output" | grep -c '^  ok ')"
  [ "$n_ok" -eq 12 ]
  # and never a silent NOT-ok slipping through with exit 0
  ! printf '%s' "$output" | grep -q '^  NOT ok '
}

@test "no key → activation notice on stderr, exit 0, ~\$0 idle (claude never invoked)" {
  run "$T"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NOT yet activated"* ]]
  [[ "$output" == *"platform.moonshot.ai"* ]]
  # the stub claude must NOT have run
  ! [[ "$output" == *"STUB-CLAUDE"* ]]
}

@test "no key, even WITH claude-args → still just the notice, exit 0 (cannot launch keyless)" {
  run "$T" --permission-mode auto "build me a UI"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NOT yet activated"* ]]
  ! [[ "$output" == *"STUB-CLAUDE"* ]]
}

@test "with key (DRYRUN) → EXACT verified metered contract, args passed through, no real launch" {
  export KIMI_API_KEY='sk-test-key'
  export CLAUDE_KIMI_DRYRUN=1
  run "$T" --resume xyz "a prompt"
  [ "$status" -eq 0 ]
  # verified endpoint + auth model + isolation, line-for-line
  [[ "$output" == *"ANTHROPIC_BASE_URL=https://api.moonshot.ai/anthropic"* ]]
  [[ "$output" == *"ANTHROPIC_AUTH_TOKEN=<key-present>"* ]]
  [[ "$output" == *"ANTHROPIC_MODEL=kimi-k3[1m]"* ]]
  [[ "$output" == *"CLAUDE_CODE_SUBAGENT_MODEL=kimi-k3[1m]"* ]]
  [[ "$output" == *"ENABLE_TOOL_SEARCH=false"* ]]
  [[ "$output" == *"CLAUDE_CODE_MAX_CONTEXT_TOKENS=1048576"* ]]
  [[ "$output" == *"CLAUDE_CONFIG_DIR=$BATS_TEST_TMPDIR/cfg"* ]]
  # caller args are forwarded to the (would-be) exec line
  [[ "$output" == *"--resume xyz a prompt"* ]]
  # the contract must NOT carry a conflicting ANTHROPIC_API_KEY
  ! [[ "$output" == *"ANTHROPIC_API_KEY="* ]]
}

@test "ISOLATION: the resolved config dir is never one of the 4 Max dirs nor a \$HOME/.claude-* dir" {
  export KIMI_API_KEY='sk-test-key'
  export CLAUDE_KIMI_DRYRUN=1
  # default (no override) config dir must be OUTSIDE the mirror namespace
  unset CLAUDE_KIMI_CONFIG_DIR
  run "$T"
  [ "$status" -eq 0 ]
  cfg_line="$(printf '%s\n' "$output" | grep '^CLAUDE_CONFIG_DIR=')"
  [[ "$cfg_line" != *"/.claude"$'\n' ]]
  # not the source or any Max account dir
  for d in "$HOME/.claude" "$HOME/.claude-next" "$HOME/.claude-secondary" "$HOME/.claude-tertiary" "$HOME/.claude-quaternary"; do
    [ "$cfg_line" != "CLAUDE_CONFIG_DIR=$d" ]
  done
  # and never matches the mirror-captured $HOME/.claude-* glob
  case "$cfg_line" in "CLAUDE_CONFIG_DIR=$HOME/.claude-"*) false ;; *) true ;; esac
}

@test "key file resolves when no env var, and stray whitespace is stripped" {
  printf '  sk-from-file \n' > "$KIMI_KEY_FILE"
  export CLAUDE_KIMI_DRYRUN=1
  run "$T"
  [ "$status" -eq 0 ]
  # a wired key → contract emitted (not the activation notice)
  [[ "$output" == *"ANTHROPIC_BASE_URL="* ]]
  ! [[ "$output" == *"NOT yet activated"* ]]
}

@test "env KIMI_API_KEY takes precedence over the key file" {
  printf 'sk-from-file\n' > "$KIMI_KEY_FILE"
  export KIMI_API_KEY='sk-from-env'
  run "$T" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"WIRED"* ]]
}

@test "status distinguishes metered (Moonshot) from SUBSCRIPTION (kimi.com/coding)" {
  export KIMI_API_KEY='sk-test'
  run "$T" status
  [[ "$output" == *"metered pay-per-token"* ]]
  KIMI_BASE_URL='https://api.kimi.com/coding/' run "$T" status
  [[ "$output" == *"SUBSCRIPTION"* ]]
}

@test "overrides: KIMI_BASE_URL and KIMI_MODEL flow into the contract" {
  export KIMI_API_KEY='sk-test'
  export CLAUDE_KIMI_DRYRUN=1
  export KIMI_BASE_URL='https://api.kimi.com/coding/'
  export KIMI_MODEL='k3'
  run "$T"
  [[ "$output" == *"ANTHROPIC_BASE_URL=https://api.kimi.com/coding/"* ]]
  [[ "$output" == *"ANTHROPIC_MODEL=k3"* ]]
}

@test "set-key writes the key 0600 from STDIN (never argv → no shell-history leak)" {
  run bash -c "printf 'sk-piped-key\n' | '$T' set-key"
  [ "$status" -eq 0 ]
  [ -f "$KIMI_KEY_FILE" ]
  [ "$(cat "$KIMI_KEY_FILE")" = "sk-piped-key" ]
  # 0600 perms (owner rw only)
  perm="$(stat -f '%Lp' "$KIMI_KEY_FILE" 2>/dev/null || stat -c '%a' "$KIMI_KEY_FILE")"
  [ "$perm" = "600" ]
}

@test "help prints usage and the activation steps" {
  run "$T" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude-kimi"* ]]
  [[ "$output" == *"ACTIVATION"* ]]
}

@test "structural: no Anthropic model id (claude-opus/sonnet/haiku/fable-N) hardcoded in routing CODE" {
  # comments stripped first — the model must route ONLY through \$KIMI_MODEL, else a Kimi session
  # could silently emit a real Anthropic model id against the Kimi endpoint.
  ! sed 's/[[:space:]]*#.*$//' "$T" | grep -qE 'claude-(opus|sonnet|haiku|fable)-[0-9]'
}
