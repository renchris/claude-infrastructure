#!/usr/bin/env bash
# workflow-script-edit-allow.sh — PreToolUse + PermissionRequest (Write|Edit|MultiEdit) hook that
# auto-allows editing a Dynamic Workflow's own files, and stays SILENT for every other path.
#
# Why a hook and not an allow rule: workflow scripts live under the config dir
# (~/.claude*/projects/<project>/<session>/workflows/scripts/*.js), and Claude Code treats every
# file under a config dir as SENSITIVE. That check outranks `Edit(...)` allow rules, so a rule alone
# still prompts. Measured 2026-09-29 on 2.1.284, headless `--permission-mode default`:
#   allow rules only                   → denied ("… which is a sensitive file")
#   PreToolUse allow only              → denied (the sensitive check re-asks)
#   PermissionRequest allow only       → denied (the request never reached the hook)
#   PreToolUse + PermissionRequest     → written
# So this one script is registered on BOTH events and answers each in that event's own shape.
#
# Scope: the path must resolve under $HOME/.claude or $HOME/.claude-<account>, in
# projects/<project>/<session>/workflows/ or the user-level workflows/ dir, with no `..` segment.
# Anything else → exit 0 silent, so the normal permission flow decides.

in="$(cat)"
event="$(jq -r '.hook_event_name // empty' <<<"$in" 2>/dev/null)"
path="$(jq -r '.tool_input.file_path // empty' <<<"$in" 2>/dev/null)"
[ -n "$path" ] || exit 0

case "$path" in
  */../*|*/..|../*) exit 0 ;;
esac

rel="${path#"$HOME"/}"
[ "$rel" != "$path" ] || exit 0

case "$rel" in
  .claude/projects/*/*/workflows/*|.claude-*/projects/*/*/workflows/*) ;;
  .claude/workflows/*|.claude-*/workflows/*) ;;
  *) exit 0 ;;
esac
# the account segment itself may not contain a slash (.claude-foo/bar/projects/… is not a config dir)
acct="${rel%%/*}"
case "$acct" in
  .claude|.claude-[A-Za-z0-9_-]*) ;;
  *) exit 0 ;;
esac

case "$event" in
  PermissionRequest)
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}' ;;
  *)
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"Dynamic Workflow script (workflow-script-edit-allow.sh)"}}' ;;
esac
exit 0
