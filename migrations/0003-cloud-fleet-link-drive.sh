#!/bin/bash
# migration-class: c10
# migration-step: re-link any Claude account whose CLI→GitHub link is missing, so cloud sessions can be created from it (drives a TUI in a real pane — C10, yours)
# migration-run: bash ~/Development/claude-infrastructure/scripts/cloud-websetup-drive.sh --all
#
# 0003 — the cloud fleet's ONE operator-owned step, filed where a renderer will surface it.
#
# WHAT IT IS FOR. `claude --cloud "<desc>"` can only create a session from an account whose CLI is
# GitHub-linked, and the only thing that establishes that link is `/web-setup` — a TUI-only slash
# command with no headless equivalent (CLOUD_OBSERVABILITY.md §6.5). `scripts/cloud-websetup-drive.sh`
# automates driving it. This migration is how the operator finds that script without knowing it
# exists: it becomes one counted line in the close block and one `cc-do` entry, instead of a path
# somebody has to remember.
#
# WHY c10 AND NOT mechanical, which is the whole judgement here. On an already-linked account the
# drive is a clean no-op, and it would be tempting to let the converger run it every deploy. It must
# not. On an UNLINKED account the drive opens a kitty window on the operator's physical desk and
# TYPES INTO IT. That is a visible, focus-stealing, input-injecting act, and `scripts/deploy-live.sh`
# runs unattended — including while the operator is typing somewhere else. "Usually a no-op" is
# exactly the shape that makes an unattended actuator look safe right up until the day it is not:
# the one run that does something is the run nobody is watching. So this STAGES and never executes.
#
# WHY IT IS NOT SIMPLY NOTHING — i.e. why file a step at all when all four accounts are currently
# linked. Because "currently" is doing real work in that sentence, and the marker set has ALREADY
# been caught lying about it. Measured 2026-08-08: `~/.claude/autonomy/websetup/` held markers for
# next2, next3 and next4 and **none for `next`**, an account that was linked — and the drive's own
# `--status` still reports `next  none` today. Nothing reconciles the marker against the account, a
# link can lapse on a revoked token, and a new account starts unlinked. The step is the standing
# answer to "cloud creates just started failing on one account"; its remedy travels with it and is
# re-read at consumption, so it cannot rot into a step whose premise died.
#
# PROMOTION IS A ONE-WORD DIFF, as with 0002: if the drive ever grows a genuinely headless path —
# no pane, no typing — `c10` becomes `mechanical` on line 2 and the converger takes it over.
#
# The body below is what a promotion would run. It is NOT executed while the class is c10.
set -uo pipefail

REPO="${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}"
DRIVE="$REPO/scripts/cloud-websetup-drive.sh"

[ -f "$DRIVE" ] || { printf '0003: link driver missing: %s\n' "$DRIVE" >&2; exit 1; }

# Already-linked is SUCCESS, not a no-op to be skipped (migrations/README.md rule 2). The driver is
# idempotent by construction: an account already recorded linked returns 0 without touching a pane,
# and `--force` is the only way to re-drive one.
bash "$DRIVE" --all
