#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 04-page-channel  —  arm the phone-page break-through (P0-7 / operator decision #2)
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: today pages reach the DESK PANE (autonomy-sweep → cc-notify) but NEVER an away phone —
#   push-critical.sh is inert without creds, and CC_PAGE_TO is empty. Until this is armed, a class-B
#   decision packet / DEAD page is loud-to-disk / silent-to-away-human. This is the one-time secret step.
# C10 + SECRET: agent CANNOT stage the secret. YOU provide the Pushover token/user. Printed-only —
#   this script never writes your secret to disk on your behalf.
# Authoritative: docs/activation/escalation-activate-snippet.md (P0-7 operator step)
# Mark done: touch ~/.claude/autonomy/pending-activation/04-page-channel-activate.sh.done
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail

echo "== 04-page-channel (operator secret — printed instructions only) =="
echo "1. Add to ~/.zshenv (or your secret store):"
echo "     export PUSHOVER_TOKEN=<your-app-token>"
echo "     export PUSHOVER_USER=<your-user-key>"
echo "2. Set the desk page target (a cc-role) for the supervisor + sweeps:"
echo "     export CC_PAGE_TO=desk        # in the same env the launchd jobs inherit"
echo "   (the supervisor plist currently has CC_PAGE_TO=\"\" — set it in the plist's EnvironmentVariables"
echo "    OR in ~/.zshenv so the loaded jobs pick it up on next (re)load.)"
echo "3. Verify the channel end-to-end (effect-check, one time):"
echo "     printf '{\"message\":\"desk page test\",\"cwd\":\"\$HOME\"}' | ~/.claude/hooks/push-critical.sh"
echo "     # → the away phone should buzz. If not, re-check token/user."
echo
echo "ROLLBACK: unset PUSHOVER_TOKEN PUSHOVER_USER CC_PAGE_TO (remove from ~/.zshenv); pages fall back"
echo "          to the desk pane only (the pre-arm behavior — never an error, just away-silent)."
