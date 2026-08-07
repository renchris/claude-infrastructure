#!/bin/bash
# migration-class: c10
# migration-step: repoint the PreToolUse/Bash curl-gate.py registration at the scoped shim (settings.json is the live permission surface — C10, yours)
# migration-run: CONFIRM=1 bash ~/Development/claude-infrastructure/docs/activation/pending-activation/26-curl-gate-scope-activate.sh
#
# 0002 — the doc's own §4 item 3, converted from a rotting queue entry into a filed, named,
# once-paged operator step.
#
# THE STATE THIS ENCODES (verified on disk 2026-08-07): `hooks/curl-gate-scope.sh` is built, has 14
# bats cases, and is DEPLOYED to the live layer — and `~/.claude/settings.json:435` still registers
# the unscoped `hooks/curl-gate.py`. The file is live and the registration is inert, which is §2.6's
# exact residue: a conclusion that beat the diode at the revision edge and is still stuck at the
# REGISTRATION edge. It has sat in the hand-queue as `26-curl-gate-scope-activate.sh` for over 24 h
# among 37 siblings, re-listed in full at every session start by an alarm that always fires.
#
# WHY c10 AND NOT mechanical. `settings.json` is the live permission/hook surface of every account.
# §3's rescope of C10 — "operator RUNS" becomes "operator CAN REVERT" — is explicitly the one clause
# the doc says a human must ratify, once, and that ratification has not happened. So this migration
# STAGES: `scripts/deploy-migrations.sh` files it to `cc-backlog needs` (event-keyed, so re-filing on
# every converge folds onto the same id — paged once) and never executes the body below.
#
# WHY IT IS STILL A MIGRATION. Three properties the hand-queue could not give it:
#   1. It is filed into a store `hooks/operator-readout.sh` already renders, so it reaches the
#      operator's close block by construction instead of as one line in a 38-item banner.
#   2. Its remedy travels with it and is re-read at consumption, so it cannot rot into a step whose
#      premise died (MEMORY.md work-item-remedy-can-become-forbidden).
#   3. Promotion is a ONE-WORD DIFF. The day the operator ratifies the rescope, `c10` becomes
#      `mechanical` on line 2 and the converger takes this over — no rewrite, no second author.
#
# The body delegates to the existing activation rather than duplicating its edit. That script already
# carries the jq repoint, the per-dir backup, the restore-on-failure and the `--undo`; a second
# implementation of a settings.json rewrite is exactly the parallel store this mechanism deletes.
set -uo pipefail

REPO="${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}"
ACT="$REPO/docs/activation/pending-activation/26-curl-gate-scope-activate.sh"

[ -f "$ACT" ] || { printf '0002: activation script missing: %s\n' "$ACT" >&2; exit 1; }

# Already-applied is success, not a no-op to be skipped: rule 2 in migrations/README.md. The
# activation is itself idempotent (it repoints an entry that already names the shim to the same
# value), so this is safe to reach twice.
CONFIRM=1 bash "$ACT"
