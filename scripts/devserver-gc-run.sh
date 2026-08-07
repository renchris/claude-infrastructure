#!/usr/bin/env bash
# devserver-gc-run.sh — the launchd wrapper that SCHEDULES the dev-server reaper.
#
# WHY THIS FILE EXISTS: scripts/devserver-census.sh is the decision module; this is the cron and
# NOTHING ELSE. Every safety gate stays in the module, which this wrapper only parameterises and
# never second-guesses. (worktree-gc.sh spent from 2026-07-25 to 2026-08-01 complete, safe and never
# scheduled — 126 worktrees, 1,193 branches. The gap was never the janitor; it was the cron.)
#
# 🚨 CRITICAL — PATH. `lsof` lives in /usr/sbin, NOT /usr/bin. reso's reaper shipped a PATH without
# /usr/sbin, so under launchd lsof was command-not-found, EVERY liveness gate returned empty, and it
# reaped a LIVE worktree (wt-cc-233227-53597, 2026-06-19). devserver-census.sh resolves BOTH its
# owner gate and its browser gate through lsof, so that omission here would turn it into a reaper
# that kills every dev server on the box — including one with a live owner mid-build. The module
# refuses to decide when its oracle is inoperable (D-e positive control), so this PATH and that
# refusal are belt and braces. System dirs first so the entitled system tools win.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
set -uo pipefail

REPO="/Users/chrisren/Development/claude-infrastructure"
# Resolution order: explicit seam (the suite and a pre-deploy smoke run use it) → the deployed live
# layer → the checkout. Never a bare `command -v`: the module is not on PATH.
CENSUS="${CC_DEVGC_CENSUS:-}"
if [ -z "$CENSUS" ]; then
  CENSUS="$HOME/.claude/scripts/devserver-census.sh"
  [ -x "$CENSUS" ] || CENSUS="$REPO/scripts/devserver-census.sh"
fi
DISABLED="$HOME/.claude/autonomy/devserver-gc.disabled"
LAST="$HOME/.claude/logs/devserver-gc.last"
LOG="$HOME/.claude/logs/devserver-gc.out.log"
mkdir -p "$(dirname "$LAST")" 2>/dev/null

# One structured, parseable line per run — `verdict=<v>` plus k=v fields. Every field is ASCII,
# unquoted and whitespace-free, so `grep -o 'verdict=[a-z-]*'` is a total parse. A bare `|| true`
# plus a damping marker on a fake success DELETES the message (memory: claimed-vs-checked).
#   verdict=ok         the sweep RAN. reaped=N kept=N mb=N say what it did.          exit 0
#   verdict=disabled   kill switch present; nothing attempted.                       exit 0
#   verdict=none       no dev servers on the box at all.                             exit 0
#   verdict=oracle-blind  lsof inoperable — the module REFUSED to decide.            exit 3
#   verdict=error      the module failed for any other reason.                       exit 1
emit() { printf '%s ts=%s %s\n' "verdict=$1" "$(date -u +%Y%m%dT%H%M%SZ)" "${2:-}" | tee -a "$LOG" > "$LAST"; }

if [ -e "$DISABLED" ]; then emit disabled "reason=kill-switch"; exit 0; fi
if [ ! -x "$CENSUS" ];  then emit error "reason=module-missing path=$CENSUS"; exit 1; fi

# OBSERVE mode logs the verdicts and removes nothing. It is the DEFAULT until the operator sets
# DEVGC_ACT=1 in the plist — an unattended process that kills the operator's running dev servers is
# a decision they make once, explicitly, not one this file makes for them.
ACT="${DEVGC_ACT:-0}"
if [ "$ACT" = 1 ]; then MODE=(--reap); else MODE=(--reap --dry-run); fi

OUT="$("$CENSUS" "${MODE[@]}" 2>&1)"; RC=$?
printf '%s\n' "$OUT" >> "$LOG"

if [ "$RC" = 3 ]; then emit oracle-blind "reason=lsof-inoperable act=$ACT"; exit 3; fi
if [ "$RC" != 0 ]; then emit error "rc=$RC act=$ACT"; exit 1; fi

REAPED="$(printf '%s\n' "$OUT" | awk '/reaped$/ { print $(NF-1) }' | tail -1)"
KEPT="$(printf '%s\n' "$OUT" | grep -c '^  keep ')"
[ -z "$REAPED" ] && REAPED=0
if [ "$REAPED" = 0 ] && [ "$KEPT" = 0 ]; then emit none "act=$ACT"; exit 0; fi
emit ok "reaped=$REAPED kept=$KEPT act=$ACT"
exit 0
