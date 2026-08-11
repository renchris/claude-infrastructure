#!/bin/bash
# migration-class: c10
# migration-step: the interactive account router is built, tested and landed but NOT wired — wiring it edits ~/.zshrc (how every session launches) and flips the accounts.json launcher field that handoff-fire types into panes; both are yours
# migration-run: CONFIRM=1 bash ~/.claude/docs/activation/pending-activation/36-start-latency-router-activate.sh
# migration-subject: ~/.zshrc
# migration-verify: zsh -ic 'whence -w claude1' 2>/dev/null | grep -q function
#
# WHAT LANDED, AND WHY NONE OF IT IS LIVE YET
# ─────────────────────────────────────────────────────────────────────────────────────────────
#   lib/claude-launcher.zsh   defines claude1 (pins account 1) and wraps claude() into a router
#   bin/claude-accounts       --max-wait/--max-age (bounded, non-blocking reads) and
#                             --route interactive (a survival lane, not the dispatch lane)
# Both are inert until ~/.zshrc sources the lib. That is deliberate: the shell file is C10.
#
# WHY THE TWO SURFACES MOVE TOGETHER OR NOT AT ALL
# ─────────────────────────────────────────────────────────────────────────────────────────────
# accounts.json's `accounts[0].launcher` is not documentation — scripts/handoff-fire.sh:6070
# resolves it and TYPES it into a pane to pin the account it just charged with `--assign`
# (:6087). Flip it to `claude1` while the operator's shell has no such function and every
# dispatched fire to account 1 types a command that does not exist. So the landed diff leaves
# accounts.json alone, and the activation script does the zshrc line and the SSOT flip in one
# run, with backups, refusing if either half cannot be completed.
#
# WHY c10 AND NOT mechanical
# ─────────────────────────────────────────────────────────────────────────────────────────────
# migrations/README.md is explicit that a migration touching ~/.zshrc declares c10 and waits for
# a human, and tests/deploy-migrations.bats test 5 fails a `mechanical` that touches a C10
# surface. The substantive reason is the same one the rule encodes: an agent that breaks the
# launcher has broken the thing every future session needs in order to fix it.
#
# THE ONE THING THIS CHANGES ABOUT DAILY USE
# ─────────────────────────────────────────────────────────────────────────────────────────────
# `claude` stops meaning "account 1" and starts meaning "the account with the most runway".
# `claude1` is the new name for the old behaviour. Routing is skipped for --resume/--continue,
# when CLAUDE_CONFIG_DIR is already set (so nested launches inherit their parent's account), and
# when CC_ACCOUNT_PINNED is set (so a dispatched fire's own pick is never overridden). It prints
# one line saying which way it went, because a silent router and a dark one look identical.
# Kill switch: CC_CLAUDE_ROUTE=off.
set -euo pipefail

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
ACTIVATE="$CLAUDE_DIR/docs/activation/pending-activation/36-start-latency-router-activate.sh"

echo "0009: interactive account router — landed, NOT wired."

# ---- report the two preconditions the activation script will hard-require ----------------------
# Reporting only. A c10 body is never executed by deploy-migrations.sh (the runner reads the
# headers above and files the cc-backlog item), so reaching here means somebody ran this by hand.
if [ -r "$CLAUDE_DIR/lib/claude-launcher.zsh" ]; then
  echo "0009: lib/claude-launcher.zsh is LIVE (symlinked) — activation can proceed"
else
  echo "0009: lib/claude-launcher.zsh NOT yet in $CLAUDE_DIR — it is an ADD, so it needs one"
  echo "      converger pass to create the per-file symlink: bash scripts/deploy-live.sh"
fi

if grep -qF 'claude-launcher.zsh' "$HOME/.zshrc" 2>/dev/null; then
  echo "0009: ~/.zshrc already sources the lib — the step below is already done"
else
  echo "0009: ~/.zshrc does not source the lib yet — the router is inert"
fi

echo
echo "0009: run this, and it does the zshrc line + the accounts.json launcher flip together:"
echo "      CONFIRM=1 bash $ACTIVATE"
echo "      (no CONFIRM = dry run; it prints exactly what it would change and exits)"
exit 0
