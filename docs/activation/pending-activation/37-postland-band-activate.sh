#!/bin/bash
# 37-postland-band-activate.sh — apply the postland verifier's band change to the LIVE launchd job.
#
# WHAT THIS CHANGES, AND WHY IT IS WORTH A RELOAD (backlog 70dff02dcf4a, LAND_PIPELINE_V2.md §8).
# `com.claude.postland-verify` declared `ProcessType Background`, which applies Darwin's darwinbg
# TASK ROLE. Measured: that role pins every descendant at PRI 4 (E-core confined) and nothing inside
# the job can lift it — `taskpolicy -c utility` from within still reads 4, and `taskpolicy -B -p`
# does not lift it either. A plain `taskpolicy -c background` clamp, by contrast, IS liftable.
#
# That distinction was the entire wall-clock story of this lane. The corpus is launched as
# `nice -n 19 taskpolicy -c background bats …`, but `bats` PATH-resolves to ~/.claude/bin/cc-bats,
# whose default band is `utility` — so OUTSIDE this job the corpus already ran at PRI 20, and only
# under the task role did it run at 4. Same corpus, same box, two populations: scheduled p50 3.11h
# vs session-invoked p50 0.98h, against a 2h breach trigger.
#
# The repo SSOT now drops that key and instead execs the runner through `taskpolicy -c utility`
# (fail-open if taskpolicy(8) is missing). `utility` is still demoted below interactive and is the
# band every other actuator in this repo moved to at 2514226e — this is not "foregrounding the
# verifier", it is un-confining it from the E-cores.
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
LABEL="com.claude.postland-verify"
SRC="$REPO/launchd/$LABEL.plist"
LA_DIR="${CC_ACTIVATE_LA_DIR:-$HOME/Library/LaunchAgents}"
DST="$LA_DIR/$LABEL.plist"
UID_N="$(id -u)"

die() { echo "37-postland-band: $*" >&2; exit 1; }

if [ "${CONFIRM:-0}" != "1" ]; then
  cat <<EOF
37-postland-band-activate.sh — DRY (set CONFIRM=1 to apply)

  Would install : $SRC
             -> : $DST
  Then         : launchctl bootout  gui/$UID_N/$LABEL   (tolerating "not loaded")
                 launchctl bootstrap gui/$UID_N "$DST"
  Then verify  : live declares NO ProcessType key, AND execs via 'taskpolicy -c utility'

  Effect: the postland corpus stops being confined to the E-cores (PRI 4) and runs at the
  utility band (PRI 20), like every other actuator. Expected: scheduled lane p50 3.11h -> toward
  the session lane's 0.98h. Reversible: the pre-change plist is backed up beside the live file.

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
  echo "37-postland-band: backed up live plist -> $BAK"
else
  echo "37-postland-band: no live plist present; this will install one"
fi

cp "$SRC" "$DST" || die "copy failed: $SRC -> $DST"
echo "37-postland-band: installed repo SSOT -> $DST"

# ---- reload ---------------------------------------------------------------------------------------
# bootout on a job that is not loaded exits non-zero; that is not a failure of this script.
launchctl bootout "gui/$UID_N/$LABEL" >/dev/null 2>&1 \
  && echo "37-postland-band: booted out $LABEL" \
  || echo "37-postland-band: $LABEL was not loaded (nothing to boot out)"

launchctl bootstrap "gui/$UID_N" "$DST" >/dev/null 2>&1 \
  || die "bootstrap FAILED for $LABEL — the job is now UNLOADED. Restore with: cp ${BAK:-<backup>} $DST && launchctl bootstrap gui/$UID_N $DST"
echo "37-postland-band: bootstrapped $LABEL"

# ---- verify the EFFECT, not the intent -----------------------------------------------------------
# Both halves, because absence of the role is not enough: a plist with neither the role nor a clamp
# would leave the runner at PRI 31, which is a different (and unintended) change.
fail=0
# `grep -q` DRAINED, not short-circuited: under `set -o pipefail` an early-exiting consumer SIGPIPEs
# plutil, the pipeline exits 141, and the condition reads FALSE **on a match** — i.e. it would report
# "no ProcessType" precisely when the key is still there. Redirecting instead of -q keeps grep reading
# to EOF so the pipeline's status means what it says.
if /usr/bin/plutil -p "$DST" 2>/dev/null | grep '"ProcessType"' >/dev/null; then
  echo "37-postland-band: VERIFY FAILED — live plist still declares ProcessType" >&2; fail=1
else
  echo "37-postland-band: verified — live plist declares no ProcessType (no darwinbg task role)"
fi
if grep -q 'taskpolicy -c utility' "$DST"; then
  echo "37-postland-band: verified — live plist execs the runner via 'taskpolicy -c utility'"
else
  echo "37-postland-band: VERIFY FAILED — live plist carries no explicit utility demotion" >&2; fail=1
fi
if launchctl print "gui/$UID_N/$LABEL" >/dev/null 2>&1; then
  echo "37-postland-band: verified — $LABEL is loaded"
else
  echo "37-postland-band: VERIFY FAILED — $LABEL is not loaded after bootstrap" >&2; fail=1
fi
[ "$fail" -eq 0 ] || die "one or more post-conditions failed (see above); the backup is beside $DST"

cat <<EOF

37-postland-band: DONE.
  scripts/launchd-parity-lint.sh goes green again on this label now that live matches the repo SSOT.
  The next scheduled run picks up the new band. Re-read the lane with:
      bash $REPO/scripts/cycle-time-census.sh --all
  If the scheduled/session ratio stays near 3x over stamps written from here on, the diagnosis in
  LAND_PIPELINE_V2.md §8 is wrong and should be re-derived rather than re-explained.
EOF
exit 0
