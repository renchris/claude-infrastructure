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
zsh -fc "source \"$HOME/.claude/lib/config-mirror.zsh\"; _cc_sync_account \"$cfg\"" >/dev/null 2>&1 || true
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"knowledge-layer mirror re-asserted for %s (auth/.claude.json/sessions isolated)."}}\n' "${cfg##*/}"
exit 0
