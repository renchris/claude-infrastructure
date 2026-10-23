#!/usr/bin/env bats
# validate-bash — a headless resume run from a pane must not inherit the pane (pane-end-of-life
# 2026-10-22, Wave A item A5; REPORT.md causes 1 and 5).
#
# THE INCIDENT. Lead 666022fd (pane 16) ran `CLAUDE_CONFIG_DIR=~/.claude-next claude -p --resume
# 570d3917 …` from its Bash tool (bash-commands.log:2221). The child inherited KITTY_WINDOW_ID=16,
# registered as `tty=none pane=16`, and its self-close closed pane 16 with the lead mid-turn.
#
# Each deny is paired with the scrubbed form that must pass, and with the mention-only shapes that
# must pass (bash-commands.log:2222 was the lead's own printf note naming the command — the class
# of lesson research-block-matches-verb-names-in-any-command-text). RED on origin/main: no rule.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/validate-bash.sh"
  unset ITERM_SESSION_ID
  export KITTY_WINDOW_ID=16
  export IT2_WRAPPER_NO_KITTY=1 CC_WCLAIM_GATE=off CC_LINEAGE_GATE=off CC_FIRE_CAPACITY_GATE=off CC_ADMIT_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/handoff-account-sweep.json" \
         CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/claude-accounts" CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/claude-accounts-heal-"
  command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; return 1; }
}

probe() { # <command>
  run bash -c 'jq -nc --arg c "$1" "{tool_input:{command:\$c}, cwd:\"/tmp\", session_id:\"vb-headless\"}" | "$0"' "$HOOK" "$1"
}
decision() { printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo none; }
denied() { [ "$(decision)" = deny ] || { echo "NOT denied: $output"; false; }; }
not_denied() { [ "$(decision)" != deny ] || { echo "DENIED: $output"; false; }; }

@test "DENY the incident command: claude -p --resume from a kitty pane, with a leading assignment" {
  probe 'CLAUDE_CONFIG_DIR=~/.claude-next claude -p --resume 570d3917-0000-4000-8000-000000000085 "finish lane K"'
  denied
  printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason' | grep -qF 'env -u KITTY_WINDOW_ID -u ITERM_SESSION_ID' || false
  printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason' | grep -qF 'cc-husk-sweep --resume --yes --pane' || false
}

@test "DENY the path form and the claudeN launcher, and a compound command" {
  probe '/Users/chrisren/.claude-293/node_modules/.bin/claude -p --resume abc'
  denied
  probe 'cd /tmp/wt && claude4 --print -r abc'
  denied
}

@test "ALLOW the scrubbed form (env -u both), env -i, and an earlier unset" {
  probe 'env -u KITTY_WINDOW_ID -u ITERM_SESSION_ID claude -p --resume abc'
  not_denied
  probe 'env -i PATH=/usr/bin claude -p --resume abc'
  not_denied
  probe 'unset KITTY_WINDOW_ID ITERM_SESSION_ID; claude -p --resume abc'
  not_denied
}

@test "ALLOW a command that only MENTIONS it (printf note, grep, commit message)" {
  probe "printf 'lead note: ran claude -p --resume 570d3917; it finished' >> /tmp/notes.txt"
  not_denied
  probe "grep -n 'claude -p --resume' ~/.claude/logs/bash-commands.log"
  not_denied
  probe 'git commit -m "fix: block claude -p --resume from a pane"'
  not_denied
}

@test "ALLOW an interactive resume, and a headless run that is not a resume" {
  probe 'claude --resume abc'
  not_denied
  probe 'claude -p "summarise this file"'
  not_denied
}

@test "ALLOW when this session has no pane id to leak (a launchd or daemon caller)" {
  unset KITTY_WINDOW_ID
  probe 'claude -p --resume abc'
  not_denied
}

@test "an ITERM_SESSION_ID alone is a leak too, and scrubbing only KITTY_WINDOW_ID does not cure it" {
  unset KITTY_WINDOW_ID; export ITERM_SESSION_ID="w0t0p0:1C80FDB5-1BB5-4C5D-9107-899232DA2371"
  probe 'env -u KITTY_WINDOW_ID claude -p --resume abc'
  denied
}

@test "kill switch CC_HEADLESS_RESUME_GATE=off admits it" {
  export CC_HEADLESS_RESUME_GATE=off
  probe 'claude -p --resume abc'
  not_denied
}
