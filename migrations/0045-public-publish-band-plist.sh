#!/bin/bash
# migration-class: c10
# migration-step: the public-repo publisher (com.claude.public-publish) still runs as ProcessType Background, which pinned its tick at PRI 4 for 10+ hours and stalled github.com/renchris/claude-infrastructure; reloading the fixed plist and publishing once is yours
# migration-run: bash ~/Development/claude-infrastructure/docs/activation/pending-activation/48-public-publish-band-activate.sh --confirm renchris/claude-infrastructure
# migration-subject: ~/Library/LaunchAgents/com.claude.public-publish.plist
# migration-verify: launchctl print gui/$(id -u)/com.claude.public-publish 2>/dev/null | grep 'taskpolicy -c utility' >/dev/null && ! plutil -p ~/Library/LaunchAgents/com.claude.public-publish.plist | grep '"ProcessType"' >/dev/null
#
# WHAT LANDED, AND WHAT IS LEFT (docs/plans/PUBLIC_REPO_HYGIENE.md § Publisher stall 2026-09-29)
# ─────────────────────────────────────────────────────────────────────────────────────────────
# launchd/com.claude.public-publish.plist dropped `ProcessType Background` and `LowPriorityIO` and now
# execs the tick through `taskpolicy -c utility`, the repair 0010 and 0016 made to postland-verify and
# the autonomy sweep. Measured on this job: filter-repo's history pass took 86-137 s at foreground
# priority and 534-5,605 s under launchd, and the 09:34Z tick sat runnable with 0 context switches for
# 10+ hours holding the tick's lock. c10 because applying a plist is a bootout + bootstrap of a live
# job (migrations/README.md), and because the activation step also pushes to the public repo.
#
# Until the step runs, scripts/launchd-parity-lint.sh reports CONTENT DRIFT on this label: that RED
# is this pending step, by construction. The applied test reads the LOADED job, not the file, since
# install.sh copies the file into place at every converge while the running job keeps its old argv.
set -uo pipefail

REPO="${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}"
LABEL="com.claude.public-publish"
SRC="$REPO/launchd/$LABEL.plist"
ACTIVATE="$REPO/docs/activation/pending-activation/48-public-publish-band-activate.sh"
LIVE="${CC_MIGRATION_LA_DIR:-$HOME/Library/LaunchAgents}/$LABEL.plist"

for f in "$SRC" "$ACTIVATE"; do
  if [ ! -f "$f" ]; then
    echo "0045: MISSING $f — the wiring commit did not land intact; refusing to file a step for it" >&2
    exit 1
  fi
done
if grep -q '<string>Background</string>' "$SRC" || ! grep -q 'taskpolicy -c utility' "$SRC"; then
  echo "0045: repo SSOT does not carry the band fix; refusing to file a step that installs the unfixed file" >&2
  exit 1
fi

# `grep … >/dev/null`, never `grep -q`, on a piped read: under pipefail an early-exiting consumer
# SIGPIPEs the producer and the pipeline reads FALSE on a match.
if launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | grep 'taskpolicy -c utility' >/dev/null \
   && [ -f "$LIVE" ] \
   && ! /usr/bin/plutil -p "$LIVE" 2>/dev/null | grep '"ProcessType"' >/dev/null; then
  echo "0045: $LABEL already runs in the utility band — nothing to file, recording as applied"
  exit 0
fi

echo
echo "0045: $LABEL still runs under the darwinbg task role (ProcessType Background)."
echo "      Run:  bash $ACTIVATE --confirm renchris/claude-infrastructure"
echo "      It stops the stuck tick, installs the repo plist, reloads the job, publishes once and"
echo "      reads the public repo's main back from GitHub."
exit 0
