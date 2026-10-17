#!/usr/bin/env bash
# ms365-shared-guard.sh — PreToolUse for mcp__ms365__*: keep `select-account` per SESSION once every
# session shares ONE ms365 server (DESIGN row X4 note, docs/research/load-root-cause-2026-10-17/).
#
# The server loads its selected account once per process (auth.js:393-399), so on a shared server one
# session's select-account would move every session. This hook makes the selection a per-session
# default instead, which is what each session's own stdio process gave it before:
#   · select-account <a> → write <a> to ~/.claude/state/ms365-account/<session_id> and DENY the call
#     with "selected <a> for this session" (a deny is the only way a hook can answer a call);
#   · any later mcp__ms365__* call from that session with no `account` gets it via updatedInput
#     (no permissionDecision, so every other permission rule still runs on the rewritten input);
#   · login, verify-login, logout, list-accounts, remove-account pass through untouched — the MSAL
#     cache is already one identity shared by every config dir, so their reach is unchanged.
# No deny anywhere else.
#
# INERT unless ~/.claude/state/ms365-shared.active exists. Only migrations/0066 writes that marker,
# after the cutover gate passes, and the same marker switches mcp-ssot-wire.sh to the http form.
# Fails open: any doubt prints nothing, and no output means the call runs exactly as issued.
[ -e "$HOME/.claude/state/ms365-shared.active" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
input="$(cat)"
# \x1f, not tab: tab is IFS-whitespace, so an empty field would shift every later one left.
IFS=$'\x1f' read -r tool sid has acct <<EOF
$(printf '%s' "$input" | jq -r '[.tool_name // "", .session_id // "",
  ((.tool_input // {}) | has("account") | tostring), (.tool_input.account // "" | tostring)] | join("\u001f")' 2>/dev/null)
EOF
case "$tool" in mcp__ms365__?*) ;; *) exit 0 ;; esac
case "$sid" in ''|*[!A-Za-z0-9_-]*) exit 0 ;; esac
dir="$HOME/.claude/state/ms365-account"

case "${tool#mcp__ms365__}" in
  select-account)
    [ -n "$acct" ] || exit 0
    mkdir -p "$dir" && printf '%s\n' "$acct" > "$dir/.$sid.$$" && mv -f "$dir/.$sid.$$" "$dir/$sid" || exit 0
    jq -nc --arg r "selected $acct for this session" \
      '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
    exit 0 ;;
  login|verify-login|logout|list-accounts|remove-account|parse-teams-url) exit 0 ;;
esac

[ "$has" = false ] && [ -s "$dir/$sid" ] || exit 0
mine="$(head -n 1 "$dir/$sid")"
[ -n "$mine" ] || exit 0
printf '%s' "$input" | jq -c --arg a "$mine" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", updatedInput: ((.tool_input // {}) + {account: $a})}}' 2>/dev/null
exit 0
