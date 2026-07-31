#!/usr/bin/env bash
# keychain-guard (PreToolUse / Bash): block `security list-keychains ... -s $UNQUOTED_VAR`.
#
# Why: Claude Code's Bash tool runs zsh, where an UNQUOTED variable does NOT word-split.
# So `security list-keychains -d user -s $orig_list` (with a saved multi-path list) passes the
# whole string as ONE argument -> the search list collapses to a single malformed entry and
# System.keychain is dropped -> Chromium/Dia OSCrypt can't find "Dia Safe Storage" ->
# "Encryption is not available" -> Chromium PERMANENTLY DELETEs every cookie (per-eTLD group drop).
# That is the exact chain that wiped all Dia logins on 2026-07-09.
# Fix pattern: pass keychain paths as SEPARATE QUOTED literals, never an unquoted joined var.
#
# This guard blocks ONLY that pattern and FAILS OPEN on any parse error (never blocks unrelated cmds).
# See memory: dia-keychain-searchlist-encryption.

# Builtin read, NOT `$(cat)`: command substitution forks AND execs /bin/cat on the hottest path
# in the system (this hook fires on EVERY Bash tool call). Measured 2026-07-31: ~6 ms per hook,
# ~18% of the 163 ms PreToolUse/Bash chain across the five hooks that did this. `read -d ''`
# returns non-zero at EOF -- the normal case here -- hence `|| true`; it also PRESERVES the
# trailing newline that `$(cat)` strips, so strip it back off for byte-parity with the old value.
IFS= read -r -d '' payload || true
while [ "${payload%$'\n'}" != "${payload}" ]; do payload="${payload%$'\n'}"; done
[ -n "$payload" ] || exit 0

cmd=""
if command -v jq >/dev/null 2>&1; then
  cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)"
fi
if [ -z "$cmd" ] && [ -x /usr/bin/python3 ]; then
  cmd="$(printf '%s' "$payload" | /usr/bin/python3 -c 'import sys,json
try:
    print(json.load(sys.stdin).get("tool_input",{}).get("command",""))
except Exception:
    pass' 2>/dev/null)"
fi
[ -n "$cmd" ] || exit 0

# Only relevant to keychain search-list writes.
case "$cmd" in *list-keychains*) : ;; *) exit 0 ;; esac

# Remove double- and single-quoted spans so only UNQUOTED text remains.
stripped="$(printf '%s' "$cmd" | sed -E 's/"[^"]*"//g; s/'"'"'[^'"'"']*'"'"'//g')"

# Block iff, within one simple command, `list-keychains ... -s ...` is followed by an unquoted $VAR.
if printf '%s' "$stripped" | grep -Eq 'list-keychains[^;&|]*-s[^;&|]*\$[A-Za-z_{(]'; then
  # shellcheck disable=SC2016  # single quotes are DELIBERATE: this is verbatim advisory text shown
  # to the agent, so its `$VAR` and backtick spans must reach the reader UNEXPANDED.
  reason='BLOCKED by keychain-guard: `security list-keychains -s` with an UNQUOTED variable. The Bash tool runs zsh, where unquoted $VAR does NOT word-split, so a multi-path search list collapses into ONE malformed entry and drops System.keychain — this caused the permanent Dia cookie wipe on 2026-07-09. Pass keychain paths as SEPARATE QUOTED literals, e.g.: security list-keychains -d user -s "$HOME/Library/Keychains/login.keychain-db" "/Library/Keychains/System.keychain". Never restore the search list from an unquoted joined variable; build a quoted array of literal paths. See memory: dia-keychain-searchlist-encryption.'
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  elif [ -x /usr/bin/python3 ]; then
    /usr/bin/python3 -c 'import json,sys;print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":sys.argv[1]}}))' "$reason"
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"blocked: unquoted security list-keychains -s variable (keychain-guard)"}}'
  fi
  exit 0
fi
exit 0
