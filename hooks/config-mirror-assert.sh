#!/bin/bash
# SessionStart backstop: re-assert the knowledge-layer mirror for the CURRENT account, in case a
# session was launched WITHOUT the zsh wrapper (raw `claude`, IDE, --resume). No-op for account 1
# (default ~/.claude, CLAUDE_CONFIG_DIR unset) and for any non-claude config dir. Race-safe: runs
# the mirror in default (no --convert) mode, which only creates missing symlinks + heals leaks.
# A hook fires AFTER config is loaded, so it fixes the NEXT session, not the running one — the
# launcher wrapper is the primary mechanism; this is belt-and-suspenders.
set -euo pipefail
cfg="${CLAUDE_CONFIG_DIR:-}"
[ -z "$cfg" ] && exit 0                        # account 1 default → nothing to mirror
[ "$cfg" = "$HOME/.claude" ] && exit 0         # the source itself
case "$cfg" in "$HOME/.claude-"*) ;; *) exit 0 ;; esac
# -f = skip rc files (fast, no p10k/nvm cost); source the single-source-of-truth lib, then sync.
# Stderr is CAPTURED rather than discarded: the mirror reports a forked real dir there (a condition
# safe mode cannot fix, so it survives every future run until someone converts it), and discarding
# that is what let ~/.claude-next carry a frozen `commands` for seven weeks with nothing said.
err="$(zsh -fc "source \"$HOME/.claude/lib/config-mirror.zsh\"; _cc_sync_account \"$cfg\"" 2>&1 >/dev/null || true)"
forks="$(printf '%s\n' "$err" | grep -c 'FORKED real' 2>/dev/null || true)"
msg="knowledge-layer mirror re-asserted for ${cfg##*/} (auth/.claude.json/sessions isolated)."
if [ "${forks:-0}" -gt 0 ] 2>/dev/null; then
  # Name them. A bare count is the defect the fork itself had — something is wrong, nothing says what.
  names="$(printf '%s\n' "$err" | sed -n "s/.*FORKED real '\([^']*\)'.*/\1/p" | paste -sd' ' -)"
  msg="$msg  ⚠ $forks FORKED real entry(ies) shadow ~/.claude in ${cfg##*/}: $names — this account does NOT see updates to them, and safe mode cannot fix it. Converge with all that account's panes closed: zsh -fc 'source ~/.claude/lib/config-mirror.zsh; _cc_sync_account --convert $cfg'"
fi
# Build the JSON with a real encoder — the message now carries operator text and paths, and a
# printf-built string would break the hook's stdout contract on the first quote or backslash.
CC_MSG="$msg" python3 -c 'import json,os;print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":os.environ["CC_MSG"]}}))' 2>/dev/null \
  || printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"knowledge-layer mirror re-asserted for %s."}}\n' "${cfg##*/}"
exit 0
