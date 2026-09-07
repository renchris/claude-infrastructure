#!/bin/bash
# migration-class: c10
# migration-step: the autonomy sweep's launchd job still carries ProcessType Background, which pins it and the cloud lane it spawns at PRI 4 (E-core confined, one land ~1 h) — applying the fixed plist needs a launchctl bootout+bootstrap, which is yours
# migration-run: CONFIRM=1 bash ~/Development/claude-infrastructure/docs/activation/pending-activation/43-autonomy-sweep-band-activate.sh
# migration-subject: ~/Library/LaunchAgents/com.chrisren.autonomy-sweep.plist
# migration-verify: ! plutil -p ~/Library/LaunchAgents/com.chrisren.autonomy-sweep.plist | grep '"ProcessType"' >/dev/null && grep -q 'taskpolicy -c utility' ~/Library/LaunchAgents/com.chrisren.autonomy-sweep.plist
#
# WHAT LANDED IN THIS DIFF, AND WHAT IS LEFT (docs/plans/CLOUD_BACKLOG_PIPELINE.md §A9)
# ─────────────────────────────────────────────────────────────────────────────────────────────
# launchd/com.chrisren.autonomy-sweep.plist dropped `ProcessType Background` (+ `Nice 5`) and now
# execs the sweep through `taskpolicy -c utility` — the exact repair migrations/0010 made to
# com.claude.postland-verify. That key applies Darwin's darwinbg TASK ROLE, a one-way floor: every
# descendant sits at PRI 4 and `taskpolicy -c utility` from inside still reads 4
# (tests/postland-band-floor.bats iii), while a plain `-c utility` CLAMP is P-core eligible at PRI 20.
#
# WHY IT MATTERS MORE HERE THAN FOR THE VERIFIER. The sweep now SPAWNS the cloud lane
# (scripts/cloud-return-lane.sh), which lands every branch a cloud VM pushes, and a child inherits
# the role. Measured 2026-09-06 with the sweep at PRI 4 on a box at load 100-160: one cloud land
# 700-3,900 s against a 194 s quiet-box median; 36 of 40 attempted lands cut. `bin/cc-bats` puts the
# background-band tax on a long batch job at ~84-89×. The lane's own bound (5,400 s) fits a PRI-4
# land, so the lane WORKS without this step — it just lands about one branch an hour instead of
# several. This step is the ×30-80.
#
# WHY c10 AND NOT mechanical
# ─────────────────────────────────────────────────────────────────────────────────────────────
# It touches a launchd plist. migrations/README.md is explicit that such a migration declares c10 and
# waits for a human, and tests/deploy-migrations.bats test 5 fails a `mechanical` that touches a C10
# surface. Applying a plist is a `launchctl bootout` + `bootstrap`: the box's whole autonomy tick
# goes DOWN and comes back up, and if the bootstrap fails nothing sweeps pages, alarms, custody or
# the cloud lane until a human notices — an operator judgement about a live job, not a converger's.
#
# THE EXPECTED SIDE EFFECT, STATED SO IT IS NOT MISREAD AS A DEFECT
# ─────────────────────────────────────────────────────────────────────────────────────────────
# Until the operator runs the step, `scripts/launchd-parity-lint.sh` reports CONTENT DRIFT for this
# one label: live is behind its repo SSOT. That RED is this pending step, by construction.
#
# PREMISE RE-DERIVED AT CONSUMPTION, NOT AT AUTHORING (memory discovery-critic-premise-goes-stale):
# a sibling may have applied the plist since this was written, and a migration that re-files an
# already-done step trains the operator to ignore the queue.
set -uo pipefail

REPO="${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}"
LABEL="com.chrisren.autonomy-sweep"
SRC="$REPO/launchd/$LABEL.plist"
ACTIVATE="$REPO/docs/activation/pending-activation/43-autonomy-sweep-band-activate.sh"
LIVE="${CC_MIGRATION_LA_DIR:-$HOME/Library/LaunchAgents}/$LABEL.plist"

# ---- step 1: the artifacts this migration presupposes must actually exist ------------------------
for f in "$SRC" "$ACTIVATE"; do
  if [ ! -f "$f" ]; then
    echo "0016: MISSING $f — the wiring commit did not land intact; refusing to file a step for it" >&2
    exit 1
  fi
done

# The step is only worth filing if the SSOT actually carries the change. If somebody reverted the
# plist, filing "go apply the fixed plist" would send the operator to install the old one.
if grep -q '<string>Background</string>' "$SRC"; then
  echo "0016: repo SSOT still declares ProcessType Background — the plist fix is not in this tree;" >&2
  echo "      refusing to file an activation step that would install the unfixed file." >&2
  exit 1
fi
if ! grep -q 'taskpolicy -c utility' "$SRC"; then
  echo "0016: repo SSOT carries no explicit utility demotion — dropping the key alone would leave" >&2
  echo "      the sweep at PRI 31. Refusing to file a step for a half-made change." >&2
  exit 1
fi

# ---- step 2: is it already applied? then this migration is a no-op --------------------------------
# `grep '…' >/dev/null`, never `grep -q`, on the PIPED read: under pipefail an early-exiting consumer
# SIGPIPEs plutil and the pipeline reads FALSE on a MATCH — this test would then declare the job
# already-applied while the task role was still live, and silently retire its own operator step.
if [ -f "$LIVE" ] \
   && ! /usr/bin/plutil -p "$LIVE" 2>/dev/null | grep '"ProcessType"' >/dev/null \
   && grep -q 'taskpolicy -c utility' "$LIVE"; then
  echo "0016: $LABEL already carries the utility band live — nothing to file, recording as applied"
  exit 0
fi

# ---- step 3: hand it to the operator --------------------------------------------------------------
# The runner reads `# migration-step:` / `# migration-run:` above and files the cc-backlog item
# itself; a c10 body is never executed by deploy-migrations.sh, so reaching here at all means
# somebody ran this file by hand. Say what to run rather than doing it for them.
echo
echo "0016: $LABEL still runs under the darwinbg task role (ProcessType Background)."
echo "      Every cloud land the lane it spawns performs is pinned at PRI 4 — about one branch an hour."
echo "      Run:  CONFIRM=1 bash $ACTIVATE"
echo "      It backs up the live plist, installs the repo SSOT, boots the job out and back in,"
echo "      and verifies BOTH that no ProcessType remains AND that the utility demotion is present."
exit 0
