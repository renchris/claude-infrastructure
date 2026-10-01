#!/bin/bash
# migration-class: mechanical
# migration-verify: [ ! -e "$HOME/.claude/DEPLOY-crash-diagnostics.sh" ] && [ ! -e "$HOME/.claude/DEPLOY-DESK-RECYCLE-FIX.sh" ] && [ ! -e "$HOME/.claude/DEPLOY-NOW.sh.pre-ssot.bak" ]
#
# The verifier is config-dir-INVARIANT on purpose: registration-state.sh re-runs it once per config
# dir, and these three files are a fact about the ONE live root (~/.claude), never about an account.
#
# ══ 0049 — move three spent raw-ff DEPLOY scripts out of the live ~/.claude root (backlog 5cb75cf245f1)
# WHAT. Three unversioned files sit in the live root, none of them reachable from the repo, so no land
# can ever remove them:
#   DEPLOY-crash-diagnostics.sh   one-shot for ef7f7a4 (`pull --ff-only` on the shared checkout)
#   DEPLOY-DESK-RECYCLE-FIX.sh    one-shot for 2ebab2b (`merge --ff-only` on the shared checkout)
#   DEPLOY-NOW.sh.pre-ssot.bak    install.sh's backup of the pre-SSOT real DEPLOY-NOW.sh
# Both one-shot targets are ancestors of origin/main (spent), and DEPLOY-NOW.sh is now a symlink to
# scripts/deploy-now.sh, so install.sh's .bak arm cannot re-create the third. All three raw-ff the
# shared checkout, which .claude/commands/ship.md forbids — a session that found and ran one would
# advance the live layer while creating no symlinks (the bare-ff hazard validate-bash.sh denies).
#
# WHY A MECHANICAL MIGRATION, NOT AN OPERATOR `rm`. The row was filed operator-only on the belief that
# deleting live-layer files is C10. It is not: README.md limits c10 to settings.json, a launchd plist
# or credentials, and this DELETES nothing — each file is MOVED, bytes intact, into the converger's own
# backup store ($CC_MIGRATION_STATE/superseded/<name>.<epoch>), the same place the materialise phase
# keeps every copy it overwrites. Revert is one `mv` back.
#
# SAFETY. Only a REGULAR file is moved (never a symlink, so the live DEPLOY-NOW.sh link is untouchable
# even if a future name collides), and an existing backup name is never clobbered. Idempotent by
# construction: once the three are gone it is a no-op that still exits 0.
set -uo pipefail

LIVE="${CC_MIGRATION_LIVE_ROOT:-$HOME/.claude}"
DEST="${CC_MIGRATION_STATE:-$HOME/.claude/autonomy/migrations}/superseded"
ts="$(date +%s)"
moved=0

mkdir -p "$DEST" || { printf '0049: cannot create %s\n' "$DEST" >&2; exit 1; }
for name in DEPLOY-crash-diagnostics.sh DEPLOY-DESK-RECYCLE-FIX.sh DEPLOY-NOW.sh.pre-ssot.bak; do
  src="$LIVE/$name"
  [ -e "$src" ] || [ -L "$src" ] || continue
  if [ -L "$src" ] || [ ! -f "$src" ]; then
    printf '0049: %s is not a regular file — leaving it alone\n' "$src" >&2
    exit 1
  fi
  dst="$DEST/$name.$ts"
  [ -e "$dst" ] && { printf '0049: backup %s already exists — refusing to clobber it\n' "$dst" >&2; exit 1; }
  mv "$src" "$dst" || { printf '0049: mv %s -> %s failed\n' "$src" "$dst" >&2; exit 1; }
  printf '0049: moved %s -> %s\n' "$src" "$dst"
  moved=$((moved + 1))
done
printf '0049: %s file(s) moved, live root clean of the three spent DEPLOY scripts\n' "$moved"
exit 0
