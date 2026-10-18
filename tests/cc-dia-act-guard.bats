#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2088  # a literal ~ or $HOME is the command TEXT the hook must read
# The agent never writes ~/.config/cc-dia-act/ (the operator's allow-hosts list, the supervised-run
# records and the bot-wall cooldowns that bin/cc-dia-act keeps): hooks/validate-bash.sh denies Bash
# calls that name it or run `cc-dia-act allow|disallow`, and hooks/check-edit-boundary.sh denies
# Write/Edit into it. The operator's own `!` line never reaches a PreToolUse hook.
# RED-proof: new guard. Both deny cases went red with the DIA-ACT-OPERATOR-FILES block (resp. the
# check-edit-boundary arm) deleted from a scratch copy.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  D="$BATS_TEST_TMPDIR"
  unset KITTY_WINDOW_ID VALIDATE_BASH_LEGACY VALIDATE_BASH_DISABLED
  export IT2_WRAPPER_NO_KITTY=1
  export CC_SHARED_CHECKOUT="$D/shared"; mkdir -p "$D/shared"
  export CC_VB_DECISION_LOG="$D/decisions.jsonl"
  if ! command -v jq >/dev/null 2>&1; then skip "jq not installed"; fi
}

bash_probe() {
  run bash -c 'jq -nc --arg c "$1" "{tool_name:\"Bash\", tool_input:{command:\$c}, session_id:\"sid-dia\"}" | "$0"' \
    "$REPO/hooks/validate-bash.sh" "$1"
}
write_probe() {
  run bash -c 'jq -nc --arg p "$1" "{tool_name:\"Write\", tool_input:{file_path:\$p, content:\"x\"}, session_id:\"sid-dia\", cwd:\"/tmp\"}" | "$0"' \
    "$REPO/hooks/check-edit-boundary.sh" "$1"
}
decision() {
  if [ -z "$output" ]; then echo none; return; fi
  printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo none
}

@test "validate-bash denies agent writes to the operator's cc-dia-act files and his allow command" {
  for c in 'cc-dia-act allow odysseypa.traviscountytx.gov' \
           '~/.claude/bin/cc-dia-act disallow example.gov' \
           'printf "x\n" >> ~/.config/cc-dia-act/allow-hosts' \
           'rm -rf "$HOME/.config/cc-dia-act/cooldown"' \
           "touch \$HOME/.config/cc-dia-act/supervised/example.gov" \
           "rm ~/.config/'cc-dia-act'/cooldown/x"; do
    bash_probe "$c"
    [ "$status" -eq 0 ]
    [ "$(decision)" = deny ] || { echo "not denied: $c"; false; }
  done
  printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason' | grep -q 'cc-dia-act status'
}

@test "validate-bash leaves the agent's own cc-dia-act subcommands alone" {
  for c in 'cc-dia-act status' 'cc-dia-act read --window ABC-1' \
           'cc-dia-act click --window ABC-1 --text Search' 'bats tests/cc-dia-act.bats'; do
    bash_probe "$c"
    [ "$status" -eq 0 ]
    [ "$(decision)" != deny ] || { echo "denied: $c"; false; }
  done
}

@test "check-edit-boundary denies Write into ~/.config/cc-dia-act and allows a neighbouring path" {
  write_probe "$HOME/.config/cc-dia-act/allow-hosts"
  [ "$status" -eq 0 ]
  [ "$(decision)" = deny ]
  write_probe "~/.config/cc-dia-act/supervised/example.gov"
  [ "$(decision)" = deny ]
  write_probe "$HOME/.config/other-tool/settings"
  [ "$status" -eq 0 ]
  [ "$(decision)" = none ]
}
