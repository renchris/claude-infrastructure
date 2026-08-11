#!/bin/bash
# migration-class: c10
# migration-step: the postland verifier's launchd job still carries ProcessType Background, which pins its corpus at PRI 4 and costs the lane ~3x wall clock — applying the fixed plist needs a launchctl bootout+bootstrap, which is yours
# migration-run: CONFIRM=1 bash ~/Development/claude-infrastructure/docs/activation/pending-activation/37-postland-band-activate.sh
# migration-subject: ~/Library/LaunchAgents/com.claude.postland-verify.plist
# migration-verify: ! plutil -p ~/Library/LaunchAgents/com.claude.postland-verify.plist | grep '"ProcessType"' >/dev/null && grep -q 'taskpolicy -c utility' ~/Library/LaunchAgents/com.claude.postland-verify.plist
#
# WHAT LANDED IN THIS DIFF, AND WHAT IS LEFT (backlog 70dff02dcf4a, LAND_PIPELINE_V2.md §8)
# ─────────────────────────────────────────────────────────────────────────────────────────────
# launchd/com.claude.postland-verify.plist dropped `ProcessType Background` and now execs the runner
# through `taskpolicy -c utility`. That key applied Darwin's darwinbg TASK ROLE, and the role is a
# one-way floor: measured, every descendant sits at PRI 4 and `taskpolicy -c utility` from inside
# still reads 4 (`taskpolicy -B -p` does not lift it either), whereas a plain `taskpolicy -c
# background` CLAMP is liftable to PRI 20. tests/postland-band-floor.bats pins both halves.
#
# That asymmetry was the whole lane. The corpus is launched `nice -n 19 taskpolicy -c background
# bats …`, but `bats` PATH-resolves to ~/.claude/bin/cc-bats, whose default band is `utility`, so the
# corpus already ran at PRI 20 everywhere the role was absent — and at PRI 4 only under this job.
# Scheduled p50 3.11h vs session-invoked p50 0.98h on the same corpus and box, against a 2h trigger.
#
# WHY c10 AND NOT mechanical
# ─────────────────────────────────────────────────────────────────────────────────────────────
# It touches a launchd plist. migrations/README.md is explicit that such a migration declares c10 and
# waits for a human, and tests/deploy-migrations.bats test 5 fails a `mechanical` that touches a C10
# surface. The concrete reason here is that applying a plist is not a file copy — it is a
# `launchctl bootout` + `bootstrap`, i.e. the verifier goes DOWN and comes back up. If the bootstrap
# fails, the box loses its post-land net entirely, and recovering that is an operator judgement about
# a live job, not something a converger should attempt unattended at 600s cadence.
#
# THE EXPECTED SIDE EFFECT, STATED SO IT IS NOT MISREAD AS A DEFECT
# ─────────────────────────────────────────────────────────────────────────────────────────────
# Between this landing and the operator running the step, `scripts/launchd-parity-lint.sh` reports
# CONTENT DRIFT for this one label: live is behind its repo SSOT. That is exactly what that lint
# exists to say, and it is the pending-step signal. It is NOT visible to the corpus —
# tests/launchd-parity-lint.bats is fully fixtured (LAUNCHD_LINT_LA_DIR / LAUNCHD_LINT_REPO_DIR), so
# no post-land verdict and no auto-revert is exposed to it. Only the nightly bare-run sees it.
#
# PREMISE RE-DERIVED AT CONSUMPTION, NOT AT AUTHORING (memory discovery-critic-premise-goes-stale):
# a sibling may have applied the plist since this was written, and a migration that re-files an
# already-done step trains the operator to ignore the queue.
set -uo pipefail

REPO="${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}"
LABEL="com.claude.postland-verify"
SRC="$REPO/launchd/$LABEL.plist"
ACTIVATE="$REPO/docs/activation/pending-activation/37-postland-band-activate.sh"
LIVE="${CC_MIGRATION_LA_DIR:-$HOME/Library/LaunchAgents}/$LABEL.plist"

# ---- step 1: the artifacts this migration presupposes must actually exist ------------------------
for f in "$SRC" "$ACTIVATE"; do
  if [ ! -f "$f" ]; then
    echo "0010: MISSING $f — the wiring commit did not land intact; refusing to file a step for it" >&2
    exit 1
  fi
done

# The step is only worth filing if the SSOT actually carries the change. If somebody reverted the
# plist, filing "go apply the fixed plist" would send the operator to install the old one.
if grep -q '<string>Background</string>' "$SRC"; then
  echo "0010: repo SSOT still declares ProcessType Background — the plist fix is not in this tree;" >&2
  echo "      refusing to file an activation step that would install the unfixed file." >&2
  exit 1
fi
if ! grep -q 'taskpolicy -c utility' "$SRC"; then
  echo "0010: repo SSOT carries no explicit utility demotion — dropping the key alone would leave" >&2
  echo "      the runner at PRI 31. Refusing to file a step for a half-made change." >&2
  exit 1
fi

# ---- step 2: is it already applied? then this migration is a no-op --------------------------------
# `grep '…' >/dev/null`, never `grep -q`, on the PIPED read: under pipefail an early-exiting consumer
# SIGPIPEs plutil and the pipeline reads FALSE on a MATCH — this test would then declare the job
# already-applied while the task role was still live, and silently retire its own operator step.
if [ -f "$LIVE" ] \
   && ! /usr/bin/plutil -p "$LIVE" 2>/dev/null | grep '"ProcessType"' >/dev/null \
   && grep -q 'taskpolicy -c utility' "$LIVE"; then
  echo "0010: $LABEL already carries the utility band live — nothing to file, recording as applied"
  exit 0
fi

# ---- step 3: hand it to the operator --------------------------------------------------------------
# The runner reads `# migration-step:` / `# migration-run:` above and files the cc-backlog item
# itself; a c10 body is never executed by deploy-migrations.sh, so reaching here at all means
# somebody ran this file by hand. Say what to run rather than doing it for them.
echo
echo "0010: $LABEL still runs under the darwinbg task role (ProcessType Background)."
echo "      Its corpus is pinned at PRI 4 and nothing inside the job can lift it — that is ~3x"
echo "      wall clock on the post-land lane, for a plist key."
echo "      Run:  CONFIRM=1 bash $ACTIVATE"
echo "      It backs up the live plist, installs the repo SSOT, boots the job out and back in,"
echo "      and verifies BOTH that no ProcessType remains AND that the utility demotion is present."
exit 0
