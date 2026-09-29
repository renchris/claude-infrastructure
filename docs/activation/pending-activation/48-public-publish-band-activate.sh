#!/bin/bash
# 48-public-publish-band-activate.sh — un-stall the public repo: move the publisher out of the
# background band, clear the stuck tick, and publish once.
#
# WHAT WENT WRONG (docs/plans/PUBLIC_REPO_HYGIENE.md § Publisher stall 2026-09-29).
# github.com/renchris/claude-infrastructure stopped at c3bcaf534 on 2026-09-28T23:45Z:
#   1. the 02:46Z tick's verifier refused 27 e-mail addresses in the TrueMemory upstream drafts
#      (fixed on trunk: ee65d8687 and the synthesis-file row beside it make those paths local-only);
#   2. four fake test secrets landed later and would fail the verifier's gitleaks arm (fixed on trunk:
#      two value rows in .gitleaks.toml);
#   3. launchd ran the job with `ProcessType Background`, the darwinbg task role: every descendant
#      pinned at PRI 4. The 09:34Z tick has sat runnable, not scheduled, for 10+ hours holding its
#      lock, and it is certain to fail anyway (its rules predate fix 1). The repo plist now execs
#      through `taskpolicy -c utility` instead (same repair as 0010 / 0016).
#
# WHAT THIS DOES, in order:
#   a. refuses unless the converged checkout already carries fixes 1-3 (otherwise the next tick fails)
#   b. stops the stuck tick from the bottom up: TERM filter-repo and its children, so publish.sh
#      takes its own failure path (cleans its build dir) and the tick's EXIT trap frees the lock;
#      escalates to KILL only if the tick outlives 120 s, then removes a lock whose holder is dead
#   c. backs up the live plist, installs the repo SSOT, bootout + bootstrap, verifies the loaded argv
#   d. kickstarts one tick and waits for its rc; on rc=0 reads the public repo's main back from GitHub
#
# WHAT IT CANNOT UNDO: step d pushes the projection of private main to the PUBLIC repo. The publisher
# still refuses anything that is not a fast-forward and runs the identifier lint + gitleaks over the
# whole projected history before it pushes.
#
# RUN:   bash <this> --confirm renchris/claude-infrastructure      (without --confirm: dry run)
# Exit: 0 published (or dry run) · 1 a step failed (state printed) · 2 refused (preflight/confirm)
set -uo pipefail

REPO="${CC_ACTIVATE_REPO:-$HOME/Development/claude-infrastructure}"
LABEL="com.claude.public-publish"
SRC="$REPO/launchd/$LABEL.plist"
LA_DIR="${CC_ACTIVATE_LA_DIR:-$HOME/Library/LaunchAgents}"
DST="$LA_DIR/$LABEL.plist"
LOG="$HOME/.claude/logs/public-publish.out.log"
LOCK="${TMPDIR:-/tmp}/public-publish-tick.lock"
TARGET="renchris/claude-infrastructure"
UID_N="$(id -u)"
WAIT_S="${CC_PUBLISH_WAIT_S:-2700}"

say() { echo "48-public-publish: $*"; }
die() { echo "48-public-publish: $1" >&2; exit "${2:-1}"; }

CONFIRM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --confirm) CONFIRM="${2:-}"; shift 2 ;;
    *) die "unknown argument: $1" 2 ;;
  esac
done

# ---- a. preflight: the converged checkout must carry every fix the next tick depends on ----------
pre=0
grep -q "lrr-0123456789ab" "$REPO/.gitleaks.toml" 2>/dev/null \
  || { echo "  MISSING in $REPO/.gitleaks.toml: the fake-fixture allowlist rows" >&2; pre=1; }
grep -q '^path *docs/research/truememory-upstream-2026-09-28/\*' "$REPO/config/public-hygiene.conf" 2>/dev/null \
  || { echo "  MISSING in $REPO/config/public-hygiene.conf: the TrueMemory local-only path rows" >&2; pre=1; }
grep -q '^path *docs/research/truememory-upstream-2026-09-28\.md' "$REPO/config/public-hygiene.conf" 2>/dev/null \
  || { echo "  MISSING in $REPO/config/public-hygiene.conf: the TrueMemory synthesis-file row" >&2; pre=1; }
if grep -q '<string>Background</string>' "$SRC" 2>/dev/null || ! grep -q 'taskpolicy -c utility' "$SRC" 2>/dev/null; then
  echo "  $SRC still declares ProcessType Background or lacks the utility exec" >&2; pre=1
fi
/usr/bin/plutil -lint "$SRC" >/dev/null 2>&1 || { echo "  $SRC does not parse" >&2; pre=1; }
[ "$pre" -eq 0 ] || die "preflight refused — converge the shared checkout first (bash $REPO/scripts/deploy-live.sh)" 2

tick_pid() { launchctl print "gui/$UID_N/$LABEL" 2>/dev/null | awk '$1=="pid"&&$2=="="{print $3; exit}'; }
descendants() {  # all descendants of $1, deepest last
  local p kids
  kids="$(pgrep -P "$1" 2>/dev/null)"
  for p in $kids; do echo "$p"; descendants "$p"; done
}

TP="$(tick_pid)"
if [ "$CONFIRM" != "$TARGET" ]; then
  cat <<EOF
48-public-publish-band-activate.sh — DRY RUN (preflight passed)

  Stuck tick   : ${TP:-none running}$( [ -n "$TP" ] && printf ' (descendants: %s)' "$(descendants "$TP" | tr '\n' ' ')")
  Would install: $SRC -> $DST, then bootout + bootstrap $LABEL
  Then         : kickstart one tick and wait up to ${WAIT_S}s; it pushes a fast-forward to $TARGET

  To execute: bash $0 --confirm $TARGET
EOF
  exit 0
fi

# ---- b. stop the stuck tick from the bottom up --------------------------------------------------
if [ -n "$TP" ]; then
  FR="$(pgrep -f 'git-filter-repo' 2>/dev/null | while read -r p; do descendants "$TP" | grep -x "$p" >/dev/null && echo "$p"; done)"
  if [ -n "$FR" ]; then
    kids="$(for p in $FR; do descendants "$p"; done)"
    say "stopping stuck tick $TP: TERM filter-repo $FR ${kids:+and its children $kids}"
    read -r -a victims <<< "${FR//$'\n'/ } ${kids//$'\n'/ }"
    kill -TERM "${victims[@]}" 2>/dev/null
  else
    say "stopping stuck tick $TP: no filter-repo child, TERM the tick's descendants"
    read -r -a victims <<< "$(descendants "$TP" | tr '\n' ' ')"
    [ "${#victims[@]}" -gt 0 ] && kill -TERM "${victims[@]}" 2>/dev/null
  fi
  for _ in $(seq 1 120); do kill -0 "$TP" 2>/dev/null || break; sleep 1; done
  if kill -0 "$TP" 2>/dev/null; then
    say "tick $TP outlived 120 s after TERM — KILL its whole tree"
    read -r -a victims <<< "$(descendants "$TP" | tr '\n' ' ')"
    kill -KILL "${victims[@]}" "$TP" 2>/dev/null
    sleep 2
  fi
  kill -0 "$TP" 2>/dev/null && die "tick $TP is still alive after KILL — stopping here, nothing reloaded"
  say "tick $TP is gone"
else
  say "no tick running"
fi
if [ -d "$LOCK" ]; then
  rmdir "$LOCK" 2>/dev/null && say "removed stale lock $LOCK (its holder is dead)" \
    || die "lock $LOCK exists and could not be removed"
fi
for d in "${TMPDIR:-/tmp}"/public-publish.[0-9]*; do
  [ -d "$d" ] || continue
  pid="${d##*.}"
  kill -0 "$pid" 2>/dev/null && continue
  rm -rf "$d" && say "removed orphaned build dir $d"
done

# ---- c. install the SSOT plist and reload -------------------------------------------------------
mkdir -p "$LA_DIR" || die "cannot create $LA_DIR"
BAK=""
if [ -f "$DST" ]; then
  BAK="$DST.pre-band.$(date -u +%Y%m%dT%H%M%SZ)"
  cp -p "$DST" "$BAK" || die "backup failed: $BAK"
  say "backed up live plist -> $BAK"
fi
cp "$SRC" "$DST" || die "copy failed: $SRC -> $DST"
launchctl bootout "gui/$UID_N/$LABEL" >/dev/null 2>&1 && say "booted out $LABEL" || say "$LABEL was not loaded"
launchctl bootstrap "gui/$UID_N" "$DST" >/dev/null 2>&1 \
  || die "bootstrap FAILED — $LABEL is UNLOADED. Restore: cp ${BAK:-<backup>} $DST && launchctl bootstrap gui/$UID_N $DST"
launchctl print "gui/$UID_N/$LABEL" 2>/dev/null | grep 'taskpolicy -c utility' >/dev/null \
  || die "VERIFY FAILED — $LABEL is not loaded with the utility exec"
if /usr/bin/plutil -p "$DST" 2>/dev/null | grep '"ProcessType"' >/dev/null; then
  die "VERIFY FAILED — live plist still declares ProcessType"
fi
say "verified — $LABEL loaded, argv execs via 'taskpolicy -c utility', no ProcessType"

# ---- d. publish once and read the result back from GitHub ---------------------------------------
before="$(wc -l < "$LOG" 2>/dev/null || echo 0)"
launchctl kickstart "gui/$UID_N/$LABEL" || die "kickstart failed"
say "kickstarted one tick; waiting up to ${WAIT_S}s for its rc (log: $LOG)"
rc=""
for _ in $(seq 1 "$WAIT_S"); do
  rc="$(tail -n +"$((before + 1))" "$LOG" 2>/dev/null | sed -n 's/.*public-publish-tick: rc=\([0-9]*\).*/\1/p' | tail -1)"
  [ -n "$rc" ] && break
  sleep 1
done
tail -n +"$((before + 1))" "$LOG" 2>/dev/null | grep -E 'verdict=|projection-verifier|ff=|pushed=|rc=' | sed 's/^/  /'
[ -n "$rc" ] || die "no rc after ${WAIT_S}s — the tick is still running; re-read $LOG later"
[ "$rc" = "0" ] || die "tick exited rc=$rc — nothing new was pushed; see $LOG"
pushed="$(tail -n +"$((before + 1))" "$LOG" | sed -n 's/^pushed=\([0-9a-f]*\).*/\1/p' | tail -1)"
remote="$(gh api "repos/$TARGET/commits/main" -q .sha 2>/dev/null)"
if [ -n "$pushed" ] && [ "$pushed" = "$remote" ]; then
  say "DONE — $TARGET main is $remote, read back from GitHub"
elif [ -z "$pushed" ]; then
  say "DONE — rc=0 with nothing to push (public main already current: ${remote:-unread})"
else
  die "pushed $pushed but GitHub reports main=${remote:-unreadable}"
fi
exit 0
