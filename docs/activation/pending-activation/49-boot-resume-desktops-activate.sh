#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 49-boot-resume-desktops  —  make a hard restart bring the live fleet back on its own
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: two idempotent steps.
#   1  reload com.claude.boot-resume from the repo SSOT: the job now execs through
#      `taskpolicy -c utility` instead of declaring `ProcessType Background`.
#   2  write `resume` to ~/.claude/autonomy/boot-resume/mode (the posture; default is `page`).
#
# WHY: after the 2026-09-30 15:24 reboot, boot-resume looked for the wrong sessions (11 stale crash
#   ghosts, overlap 0 with the 20 that were live) and, in page mode, would only have paged. The code
#   now reads the reboot roster / shutdown tombstones, resumes into one native-fullscreen 2x2 Desktop
#   per 4 sessions, and nudges only the sessions the shutdown cut off mid-turn. Step 1 fixes the
#   starvation measured the same day: under the darwinbg task role one run sat 10 minutes inside
#   `sysctl -n kern.boottime` at load 185, and the login run took more than 17 minutes.
#
# WHY C10 (agent stages; operator runs): step 1 reloads a LaunchAgent and step 2 is the reboot
#   posture, which the boot-resume header names as the operator's call.
#
# UNDO: echo page > ~/.claude/autonomy/boot-resume/mode   (page mode can never open a pane)
#       the pre-change plist is backed up beside the live file.
#
# RUN IT:  bash ~/.claude/autonomy/pending-activation/49-boot-resume-desktops-activate.sh --confirm boot-resume
#          (CONFIRM=1 is accepted too, like its siblings.) A bare run is a dry run.
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail

REPO="${CC_ACTIVATE_REPO:-$HOME/Development/claude-infrastructure}"
LABEL="com.claude.boot-resume"
SRC="$REPO/launchd/$LABEL.plist"
LA_DIR="${CC_ACTIVATE_LA_DIR:-$HOME/Library/LaunchAgents}"
DST="$LA_DIR/$LABEL.plist"
STATE_DIR="${CC_BOOT_RESUME_STATE_DIR:-$HOME/.claude/autonomy/boot-resume}"
UID_N="$(id -u)"
N=49-boot-resume-desktops

die() { echo "$N: $*" >&2; exit 1; }

go=0
[ "${CONFIRM:-0}" = 1 ] && go=1
case "${1:-} ${2:-}" in "--confirm boot-resume") go=1 ;; "--confirm "*) die "--confirm must name the target: --confirm boot-resume" ;; esac

if [ "$go" != 1 ]; then
  cat <<EOF
$N — DRY (pass --confirm boot-resume to apply)

  1  install $SRC -> $DST, then launchctl bootout + bootstrap gui/$UID_N/$LABEL
     verify: the LOADED job's argv execs via 'taskpolicy -c utility'
  2  write 'resume' to $STATE_DIR/mode   (now: $(tr -d '[:space:]' 2>/dev/null < "$STATE_DIR/mode" || echo 'absent = page'))

  Effect: at the next login after a restart, the sessions that were live come back by themselves,
  4 to a fullscreen Desktop, and only the ones cut off mid-turn are told to continue.
EOF
  exit 0
fi

[ -f "$SRC" ] || die "repo SSOT missing: $SRC"
/usr/bin/plutil -lint "$SRC" >/dev/null 2>&1 || die "repo SSOT does not parse: $SRC"
mkdir -p "$LA_DIR" || die "cannot create $LA_DIR"
BAK=""
if [ -f "$DST" ]; then
  BAK="$DST.pre-desktops.$(date -u +%Y%m%dT%H%M%SZ)"
  cp -p "$DST" "$BAK" || die "backup failed: $BAK"
  echo "$N: backed up live plist -> $BAK"
fi
cp "$SRC" "$DST" || die "copy failed: $SRC -> $DST"
launchctl bootout "gui/$UID_N/$LABEL" >/dev/null 2>&1 \
  && echo "$N: booted out $LABEL" || echo "$N: $LABEL was not loaded (nothing to boot out)"
launchctl bootstrap "gui/$UID_N" "$DST" >/dev/null 2>&1 \
  || die "bootstrap FAILED — $LABEL is now UNLOADED. Restore: cp ${BAK:-<backup>} $DST && launchctl bootstrap gui/$UID_N $DST"

mkdir -p "$STATE_DIR" || die "cannot create $STATE_DIR"
printf 'resume\n' > "$STATE_DIR/mode" || die "cannot write $STATE_DIR/mode"

# Verify the EFFECT with reads that did not make the change: the loaded job's argv, and the posture
# as boot-resume itself resolves it.
fail=0
if launchctl print "gui/$UID_N/$LABEL" 2>/dev/null | grep 'taskpolicy -c utility' >/dev/null; then
  echo "$N: verified — $LABEL is loaded and execs via 'taskpolicy -c utility'"
else
  echo "$N: VERIFY FAILED — $LABEL is not loaded with the utility exec" >&2; fail=1
fi
if [ "$(tr -d '[:space:]' < "$STATE_DIR/mode" 2>/dev/null)" = resume ]; then
  echo "$N: verified — boot-resume posture reads 'resume'"
else
  echo "$N: VERIFY FAILED — $STATE_DIR/mode does not read 'resume'" >&2; fail=1
fi
[ "$fail" -eq 0 ] || die "one or more post-conditions failed (see above)"
echo "$N: DONE. Undo the posture any time with: echo page > $STATE_DIR/mode"
