#!/usr/bin/env bats
# handoff-intent-nudge: CHEAP GATES FIRST (2026-10-11, docs/research/load-hook-timeouts-2026-10-11).
#
# THE DEFECT. Every UserPromptSubmit hook runs in parallel, so a prompt waits on the slowest. This
# hook caused 95 of 162 prompt-hook cancels in 40 min: it ran agent_is_assignee — a full-table argv
# `ps -axo pid=,ppid=,command=` (559 s once during a ps wave) — BEFORE its cheap intent grep, i.e.
# on every prompt, including the harness's own <task-notification> machine prompts.
#
# WHAT IS ASSERTED. A `ps` stub on PATH drops a marker and exits 1, so "the walk ran" is a file, not
# a timing guess. Non-intent, <task-notification> and typed /handoff prompts must leave NO marker;
# the positive control (an intent prompt with no fixture) must leave one, or every no-marker test is
# vacuous. The assignee and lead cases ride the CC_WF_PSTABLE_FILE seam agent-identity.sh honours,
# and pin that the reorder kept both outcomes.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/handoff-intent-nudge.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$CLAUDE_CONFIG_DIR"
  export CC_WF_TEAM_ROOTS="$BATS_TEST_TMPDIR/teamroot"; mkdir -p "$CC_WF_TEAM_ROOTS"
  unset CLAUDE_JOB_DIR CC_WF_PSTABLE_FILE CC_WF_START_PID CC_WF_MAX_HOPS AGENT_IDENTITY_LIB
  MARK="$BATS_TEST_TMPDIR/ps-ran"
  STUB="$BATS_TEST_TMPDIR/stub"; mkdir -p "$STUB"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\nexit 1\n' "$MARK" > "$STUB/ps"
  chmod +x "$STUB/ps"
  export PATH="$STUB:$PATH"
  CCBIN="/x/claude-code/bin/claude.exe"
}

# Run the hook under the interpreter it is deployed with (/bin/bash 3.2 on macOS), prompt as $1.
nudge() {
  run /bin/bash -c 'jq -cn --arg p "$1" "{prompt:\$p}" | /bin/bash "$0"' "$HOOK" "$1"
}

pstable() {
  local p="$BATS_TEST_TMPDIR/pstable"; : > "$p"
  local r; for r in "$@"; do printf '%s\n' "$r" >> "$p"; done
  export CC_WF_PSTABLE_FILE="$p" CC_WF_START_PID=1000
}

@test "positive control: an intent prompt with no fixture DOES reach ps (else every no-marker test is vacuous)" {
  nudge "please hand off when done"
  [ "$status" -eq 0 ]
  [ -f "$MARK" ] || { echo "ps stub never ran"; false; }
  # Form-agnostic: both the table call (`-axo pid=,ppid=,command=`) and a per-hop
  # `-o pid=,ppid=,command= -p PID` walk name `command=`, so this survives either lib shape.
  grep -q -- 'command=' "$MARK"
  [[ "$output" == *"HANDOFF-INTENT PARITY"* ]] || { echo "$output"; false; }
}

@test "a non-intent prompt never runs ps and emits nothing" {
  nudge "fix the flaky test in tests/foo.bats and commit"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "$output"; false; }
  [ ! -e "$MARK" ] || { echo "ps ran:"; cat "$MARK"; false; }
}

@test "a <task-notification> prompt quoting handoff words never runs ps and emits nothing" {
  nudge "<task-notification><summary>agent finished; it says: hand off and self-close</summary></task-notification>"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "$output"; false; }
  [ ! -e "$MARK" ] || { echo "ps ran:"; cat "$MARK"; false; }
}

@test "a <task-notification> after leading whitespace is still a machine prompt" {
  nudge "$(printf '\n  \t<task-notification>please hand off</task-notification>')"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "$output"; false; }
  [ ! -e "$MARK" ] || { echo "ps ran:"; cat "$MARK"; false; }
}

@test "the tag mid-prompt is NOT a machine prompt: a human quoting it still gets the nudge" {
  pstable "1000 1001 bash /x/hook.sh" "1001 1 $CCBIN --model claude-opus-5"
  nudge "the <task-notification> said to hand off — do it"
  [ "$status" -eq 0 ]
  [[ "$output" == *"HANDOFF-INTENT PARITY"* ]] || { echo "$output"; false; }
}

@test "the typed /handoff command exits silently and never runs ps" {
  nudge "/handoff paste only"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "$output"; false; }
  [ ! -e "$MARK" ] || { echo "ps ran:"; cat "$MARK"; false; }
}

@test "an intent prompt from an assignee is still suppressed" {
  pstable \
    "1000 1001 bash /x/hook.sh" \
    "1001 1002 /bin/zsh -c source /snap.zsh" \
    "1002 1003 $CCBIN --agent-id tm@session-t1 --agent-name tm --team-name session-t1 --parent-session-id p1" \
    "1003 1 -zsh"
  mkdir -p "$CC_WF_TEAM_ROOTS/session-t1"
  jq -n '{members:[{name:"lead",tmuxPaneId:"leader",agentType:"team-lead"},{name:"tm",tmuxPaneId:"%1",agentType:"general-purpose"}]}' \
    > "$CC_WF_TEAM_ROOTS/session-t1/config.json"
  nudge "please hand off when done"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "an intent prompt from a non-assignee still emits the nudge JSON" {
  pstable \
    "1000 1001 bash /x/hook.sh" \
    "1001 1002 /bin/zsh -c source /snap.zsh" \
    "1002 1003 $CCBIN --permission-mode auto --model claude-opus-5 --effort high" \
    "1003 1 -zsh"
  nudge "you may self-close once landed"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r .hookSpecificOutput.hookEventName)" = UserPromptSubmit ]
  ctx="$(printf '%s' "$output" | jq -r .hookSpecificOutput.additionalContext)"
  [[ "$ctx" == "HANDOFF-INTENT PARITY"* ]] || { echo "$ctx"; false; }
  [[ "$ctx" == *"--successor <pane-uuid>"* ]] || { echo "$ctx"; false; }
}

@test "fail-open: no agent-identity lib anywhere still nudges on intent" {
  run /bin/bash -c 'jq -cn --arg p "$1" "{prompt:\$p}" | AGENT_IDENTITY_LIB="$2" /bin/bash "$0"' \
    "$HOOK" "please hand off" "$BATS_TEST_TMPDIR/no-such-lib.sh"
  # $0 resolves the repo lib first only when AGENT_IDENTITY_LIB is unset; pointing it at a missing
  # file falls through to the sandboxed CLAUDE_CONFIG_DIR / HOME copies, which do not exist.
  [ "$status" -eq 0 ]
  [[ "$output" == *"HANDOFF-INTENT PARITY"* ]] || { echo "$output"; false; }
}

@test "fail-open: unparseable input exits 0 silently" {
  run /bin/bash -c 'printf "not json at all" | /bin/bash "$0"' "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$MARK" ]
}
