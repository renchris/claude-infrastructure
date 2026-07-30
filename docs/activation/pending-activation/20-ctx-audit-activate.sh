#!/bin/bash
# 20-ctx-audit-activate.sh — link row 8's context-economy outcome reader into the live layer.
#
# WHY THIS IS AN ACTIVATION STEP AT ALL. Row 8's five owned HOOKS are live symlinks into the shared
# checkout, so for them landing IS deploying and no activation is needed. `bin/cc-ctx-audit` is
# different because it is a BRAND-NEW file and `~/.claude/bin` is a REAL DIRECTORY of PER-FILE
# symlinks — verified, not assumed: `[ -L ~/.claude/bin ]` is false, and `cc-bats` / `cc-blockers`
# are each individual symlinks into the checkout. A per-file symlink directory never links a file
# that did not exist when it was populated (memory deploy-lag-checkout-behind-origin), so a landed
# new binary in `bin/` stays invisible to the live layer until someone makes the link.
#
# This is ONE idempotent command. It is safe to re-run, and it is a no-op if already linked.
#
# WHAT IT DOES NOT DO — deliberately. It does not arm any recycle exec path. Row 8 explicitly
# declines to arm `--live` more widely or to arm `--busy-force` at all (CONTEXT_ECONOMY_V2 §4.5,
# §8): 0 busy-force markers exist fleet-wide, so arming it would be a FIRST-EVER fleet behaviour
# change, and it must not be taken on a metric that could not be read until this reader landed.
# That decision is the operator's, and the data to make it is what this reader now produces.
set -u

REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
SRC="$REPO/bin/cc-ctx-audit"
DST="$HOME/.claude/bin/cc-ctx-audit"

printf '── 20-ctx-audit-activate ─────────────────────────────────────────\n'

# Fail-closed: never link a target that is not actually there (a dangling symlink on PATH is worse
# than an absent command — it fails at exec time with a confusing error instead of "not found").
if [ ! -f "$SRC" ]; then
  printf '✗ REFUSING: %s does not exist.\n' "$SRC"
  printf '  The reader has not reached this checkout yet. Either the land has not deployed, or\n'
  printf '  CC_REPO points at the wrong tree. Check: git -C "%s" log --oneline -1 -- bin/cc-ctx-audit\n' "$REPO"
  exit 1
fi
if [ ! -x "$SRC" ]; then
  printf '✗ REFUSING: %s is not executable.\n' "$SRC"
  exit 1
fi

if [ -L "$DST" ] && [ "$(readlink "$DST")" = "$SRC" ]; then
  printf '✓ already linked (no-op): %s -> %s\n' "$DST" "$SRC"
else
  ln -sfn "$SRC" "$DST" || { printf '✗ ln failed\n'; exit 1; }
  printf '✓ linked: %s -> %s\n' "$DST" "$SRC"
fi

# EFFECT-READ, not an mtime or an existence check: prove the command actually RUNS and produces a
# verdict. Exit 3 is a NON-VERDICT (no recoverable fill denominator in the window) and is a legitimate
# healthy answer here, NOT a failure — collapsing it into "broken" is the defect this row's own exit
# contract exists to prevent. Anything else is a real problem.
printf '\n── verifying the deployed copy actually answers ──\n'
"$DST" --compactions --since all
rc=$?
case "$rc" in
  0) printf '✓ reader runs and produced a verdict (exit 0)\n' ;;
  3) printf '✓ reader runs; exit 3 = NO DATA / no recoverable denominator — a non-verdict, not a failure\n' ;;
  *) printf '✗ reader exited %s — unexpected; investigate before marking this done\n' "$rc"; exit 1 ;;
esac

printf '\n── what to read next ──\n'
printf '  cc-ctx-audit --summary --since 7d      # wall hits + compactions + p95 fill for the week\n'
printf '  cc-ctx-audit --wall-hits --since all   # the 7 sessions a hard context refusal killed\n'
printf '\nDONE. Mark it:\n'
printf '  touch %s/autonomy/pending-activation/20-ctx-audit-activate.sh.done\n' "$HOME/.claude"
