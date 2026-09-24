#!/bin/bash
# migration-class: c10
# migration-step: make every Claude account run ONE settings.json — back up the four account copies, fold the ruled differences into ~/.claude/settings.json, and replace each account's settings.json with a symlink to it (operator ruling 2026-09-23: accounts are interchangeable). It writes settings.json, which is C10. Read the --dry-run first.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0037-settings-parity.sh
# migration-subject: bin/cc-settings-parity
# migration-verify: "$HOME/.claude/bin/cc-settings-parity" check >/dev/null 2>&1
#
# The verifier is spelled config-dir-INVARIANT on purpose: registration-state.sh re-runs each
# verifier once per config dir with CC_CLAUDE_DIR re-aimed, and this effect is SINGULAR — a fact
# about the whole fleet (every account dir from accounts.json links to one file), so it must give
# the same answer from every dir (migrations/README.md § "Mind the per-config-dir loop").
#
# ══ 0037 — one settings.json for every account ═══════════════════════════════════════════════════
# Operator ruling 2026-09-23, verbatim: "We use /accounts indiscriminately just for weekly usage.
# There is no functional difference between accounts. We hope there is no disparity between all of
# them, all of our behavior, configuration, should be account agnostic."
#
# WHAT WAS WRONG, MEASURED 2026-09-23. Each account dir (~/.claude-next, -secondary, -tertiary,
# -quaternary) held its OWN real settings.json and none loaded ~/.claude/settings.json. All four
# lacked the PostToolUseFailure hooks (log-bash, mailbox-drain post-tool, permission-beacon clear),
# pr-gate, handoff-claim-assert and mail-images-auto; three lacked five autoMode.soft_deny rules
# (Git Push to Default Branch, Production Reads, Sandbox Network Callback, Create Public Surface,
# Memory Poisoning); and each carried its own effortLevel, tui, plugin and permission quirks. The
# mirror (lib/config-mirror.zsh) refuses to replace a forked real file in safe mode, so the fork was
# the steady state. Per-dir c10 migrations run at different times then widened it one file at a time.
#
# WHY A SYMLINK, AND WHY THAT IS SAFE. Measured before it was chosen: on a throwaway
# CLAUDE_CONFIG_DIR whose settings.json linked to a scratch file, a Claude Code user-settings write
# (`claude plugin disable … --scope user`) kept the link and changed the target on 2.1.183, 2.1.220,
# 2.1.260 and 2.1.280. So /effort, /config and permission-accepts from any account land in the one
# file from now on. The residue is OUR writers: `mv tmp "$f"` over a symlink path replaces the link
# with a real file. `cc-settings-parity check` reports exactly that (FORKED, even when the bytes are
# identical today), and the SessionStart hook config-mirror-assert.sh prints it in the affected
# account — see migrations/README.md rule 7 for how a new settings migration avoids it.
#
# WHAT WINS. The shared file, for every key it carries (it was the superset). Exceptions, each with
# its reason and conviction, are the OVERLAY and DISPOSITIONS tables at the top of
# bin/cc-settings-parity — the one place the canonical content is defined. Two are OPEN operator
# decisions filed with cc-decide (tui fullscreen on .claude-next; the frontend-design plugin on
# .claude-tertiary); the tables hold the conservative value until ruled.
#
# FAIL CLOSED. Nothing is written if any account carries a key or a hook command the tables do not
# rule on (it names each), if any file is unreadable, or if a file changes between the read and the
# write. Backups of all five files go to ~/.claude/backups/settings-parity-0037-<stamp>/ — deliberately
# NOT beside each file, where they would join the ~358 settings.json.bak-* entries the mirror already
# reports as FORKED noise. The exact revert is printed.
#
# IDEMPOTENT. A second run finds every account linked and prints "already converged".
#
# LIVE PANES. No pane gate, unlike 0013: the swap is one rename(2) per file, never a window with the
# file absent. A running session may pick the new content up through Claude Code's settings watcher
# (not measured here — the same exposure every edit to ~/.claude/settings.json already carries); what
# it loaded at startup it otherwise keeps. New sessions get the shared file.
#
# Usage:  bash migrations/0037-settings-parity.sh --dry-run   # the per-account diff; writes nothing
#         bash migrations/0037-settings-parity.sh             # apply
# bash 3.2-safe.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="${CC_MIGRATION_REPO:-$(dirname "$here")}"
engine="$repo/bin/cc-settings-parity"
[ -f "$engine" ] || { printf '0037: engine %s missing — nothing written\n' "$engine" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf '0037: python3 required — nothing written\n' >&2; exit 1; }

case "${1:-}" in
  ''|--dry-run) ;;
  *) printf '0037: unknown argument %s (use --dry-run or nothing)\n' "$1" >&2; exit 2 ;;
esac

python3 "$engine" converge ${1:+"$1"}
rc=$?
[ "$rc" -eq 0 ] || exit "$rc"
[ "${1:-}" = --dry-run ] && exit 0
# Read the effect back through the verifier, never through the writer's own claim.
python3 "$engine" check
