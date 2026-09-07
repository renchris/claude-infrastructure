#!/bin/bash
# 43-autonomy-sweep-band-activate.sh — apply the autonomy sweep's band change to the LIVE launchd job.
#
# WHAT THIS CHANGES, AND WHY IT IS WORTH A RELOAD (docs/plans/CLOUD_BACKLOG_PIPELINE.md §A9;
# migrations/0016 — the same repair 0010 / 37-postland-band-activate.sh made to the verifier).
# `com.chrisren.autonomy-sweep` declared `ProcessType Background`, which applies Darwin's darwinbg
# TASK ROLE. Measured: that role pins every descendant at PRI 4 (E-core confined) and nothing inside
# the job can lift it — `taskpolicy -c utility` from within still reads 4, and `taskpolicy -B -p`
# does not lift it either (tests/postland-band-floor.bats). Live on 2026-09-06: the sweep at PRI 4,
# postland's corpus at 20, a shell at 31.
#
# The sweep now SPAWNS the cloud lane (scripts/cloud-return-lane.sh), which lands every branch a
# cloud VM pushes, and a child inherits the role. One cloud land from that band cost 700-3,900 s
# against a 194 s quiet-box median; 36 of 40 attempted lands were cut by the old in-tick bound.
# The lane's own bound fits a PRI-4 land, so it WORKS without this step — about one branch an hour.
# This step is the ×30-80 on every cloud land and on every other block the sweep runs.
#
# The repo SSOT now drops that key (and `Nice 5`) and instead execs the sweep through
# `taskpolicy -c utility` (fail-open if taskpolicy(8) is missing). `utility` is still demoted below
# interactive and is the band every other actuator in this repo runs in — this is not
# "foregrounding the sweep", it is un-confining it from the E-cores.
#
# WHY IT NEEDS YOU. Applying a plist means `launchctl bootout` + `bootstrap`, which is C10. Until you
# run this, `scripts/launchd-parity-lint.sh` reports CONTENT DRIFT on this one label — that RED is
# this pending step, by construction, not a defect.
#
# Idempotent: re-running it re-copies identical bytes and reloads a job that is already correct.
# REPO IS THE SSOT — this only ever copies repo -> live, never live -> repo (a live->repo copy
# recreates a committed file as a local diff the next fast-forward must conflict on).
set -uo pipefail

REPO="${CC_ACTIVATE_REPO:-$HOME/Development/claude-infrastructure}"
LABEL="com.chrisren.autonomy-sweep"
SRC="$REPO/launchd/$LABEL.plist"
LA_DIR="${CC_ACTIVATE_LA_DIR:-$HOME/Library/LaunchAgents}"
DST="$LA_DIR/$LABEL.plist"
UID_N="$(id -u)"

die() { echo "43-autonomy-sweep-band: $*" >&2; exit 1; }

if [ "${CONFIRM:-0}" != "1" ]; then
  cat <<EOF
43-autonomy-sweep-band-activate.sh — DRY (set CONFIRM=1 to apply)

  Would install : $SRC
             -> : $DST
  Then         : launchctl bootout  gui/$UID_N/$LABEL   (tolerating "not loaded")
                 launchctl bootstrap gui/$UID_N "$DST"
  Then verify  : live declares NO ProcessType key, AND execs via 'taskpolicy -c utility'

  Effect: the autonomy sweep AND the cloud lane it spawns stop being confined to the E-cores
  (PRI 4) and run at the utility band (PRI 20), like every other actuator. Expected: one cloud
  land toward the 194 s quiet-box median instead of ~1 h. Reversible: the pre-change plist is
  backed up beside the live file.

  Run:  CONFIRM=1 bash $0
EOF
  exit 0
fi

[ -f "$SRC" ] || die "repo SSOT missing: $SRC"
/usr/bin/plutil -lint "$SRC" >/dev/null 2>&1 || die "repo SSOT does not parse: $SRC"
mkdir -p "$LA_DIR" || die "cannot create $LA_DIR"

# ---- back up before clobbering (a veto-after only works if the prior state survives) -------------
if [ -f "$DST" ]; then
  BAK="$DST.pre-band.$(date -u +%Y%m%dT%H%M%SZ)"
  cp -p "$DST" "$BAK" || die "backup failed: $BAK"
  echo "43-autonomy-sweep-band: backed up live plist -> $BAK"
else
  echo "43-autonomy-sweep-band: no live plist present; this will install one"
fi

cp "$SRC" "$DST" || die "copy failed: $SRC -> $DST"
echo "43-autonomy-sweep-band: installed repo SSOT -> $DST"

# ---- reload ---------------------------------------------------------------------------------------
# bootout on a job that is not loaded exits non-zero; that is not a failure of this script.
launchctl bootout "gui/$UID_N/$LABEL" >/dev/null 2>&1 \
  && echo "43-autonomy-sweep-band: booted out $LABEL" \
  || echo "43-autonomy-sweep-band: $LABEL was not loaded (nothing to boot out)"

launchctl bootstrap "gui/$UID_N" "$DST" >/dev/null 2>&1 \
  || die "bootstrap FAILED for $LABEL — the job is now UNLOADED. Restore with: cp ${BAK:-<backup>} $DST && launchctl bootstrap gui/$UID_N $DST"
echo "43-autonomy-sweep-band: bootstrapped $LABEL"

# ---- verify the EFFECT, not the intent -----------------------------------------------------------
# Both halves, because absence of the role is not enough: a plist with neither the role nor a clamp
# would leave the runner at PRI 31, which is a different (and unintended) change.
fail=0
# `grep -q` DRAINED, not short-circuited: under `set -o pipefail` an early-exiting consumer SIGPIPEs
# plutil, the pipeline exits 141, and the condition reads FALSE **on a match** — i.e. it would report
# "no ProcessType" precisely when the key is still there. Redirecting instead of -q keeps grep reading
# to EOF so the pipeline's status means what it says.
if /usr/bin/plutil -p "$DST" 2>/dev/null | grep '"ProcessType"' >/dev/null; then
  echo "43-autonomy-sweep-band: VERIFY FAILED — live plist still declares ProcessType" >&2; fail=1
else
  echo "43-autonomy-sweep-band: verified — live plist declares no ProcessType (no darwinbg task role)"
fi
if grep -q 'taskpolicy -c utility' "$DST"; then
  echo "43-autonomy-sweep-band: verified — live plist execs the runner via 'taskpolicy -c utility'"
else
  echo "43-autonomy-sweep-band: VERIFY FAILED — live plist carries no explicit utility demotion" >&2; fail=1
fi
# The EFFECT is the loaded job's argv, not the file: install.sh already copies the SSOT file into
# place at every converge, so the file matched the whole time the running job kept the old role.
if launchctl print "gui/$UID_N/$LABEL" 2>/dev/null | grep 'taskpolicy -c utility' >/dev/null; then
  echo "43-autonomy-sweep-band: verified — $LABEL is loaded AND its argv execs via 'taskpolicy -c utility'"
else
  echo "43-autonomy-sweep-band: VERIFY FAILED — $LABEL is not loaded with the utility exec after bootstrap" >&2; fail=1
fi
[ "$fail" -eq 0 ] || die "one or more post-conditions failed (see above); the backup is beside $DST"

cat <<EOF

43-autonomy-sweep-band: DONE.
  scripts/launchd-parity-lint.sh goes green again on this label now that live matches the repo SSOT.
  The next tick picks up the new band. Read it back with:
      ps -axo pid,pri,ni,command | grep -E 'autonomy-sweep|cloud-return-lane' | grep -v grep
  The sweep and the lane should read PRI 20 (utility), not 4. Then watch the lane's own rows:
      jq -c 'select(.tool=="cloud-return-lane")' ~/.claude/autonomy/idl.jsonl | tail -3
  If cloud lands (\`~/.claude/land.log\`, branches claude/*) still run 700-3,900 s at PRI 20, the band was
  not the cost and §A9's ×30-80 estimate should be re-derived rather than re-explained.
EOF
exit 0
