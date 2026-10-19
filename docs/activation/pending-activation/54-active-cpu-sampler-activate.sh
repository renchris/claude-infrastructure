#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 54-active-cpu-sampler  —  let the admission gate count CPU-active turns, not turns blocked in sleep
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHY (lr-wake 2026-10-18, docs/research/lr-wake-incident-2026-10-18/REPORT.md §4 Wave B2, RC9): the
#   gate's ACTIVE term counted every session whose latest beat is a prompt, including turns parked in
#   `until …; sleep 15` loops, so rescues were refused against a box whose "active" sessions were
#   asleep. capacity-admit.sh now counts mid-turn sessions whose process tree used >= 0.25 core, from
#   ~/.claude/autonomy/active-cpu.json, against a ceiling of ncpu x 0.8 (8 on this 10-core box). Until
#   this job writes that file, the gate keeps its old term: nothing changes before this script runs.
#
# WHAT THIS DOES — no root, re-runnable, every step idempotent:
#   1. installs ~/Library/LaunchAgents/com.claude.active-cpu-sampler.plist from launchd/staged/ if
#      absent or different (staged/ is outside install.sh's glob: this script is the only installer)
#   2. loads (bootstraps) it if it is not loaded, clearing a domain-level disabled bit first
#   3. verifies by READING BACK: active-cpu.json must be rewritten (a newer `t`) within 45 s, parse,
#      and carry a `trees` array. Fails closed otherwise.
#
# REVERT without unloading: CC_ADMIT_ACTIVE_SIGNAL=beat in a caller's environment restores the old
#   term exactly. Uninstall: launchctl bootout gui/$(id -u)/com.claude.active-cpu-sampler;
#   rm ~/Library/LaunchAgents/com.claude.active-cpu-sampler.plist ~/.claude/autonomy/active-cpu.json
#   (with the file gone the gate is back on the old term).
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
LABEL=com.claude.active-cpu-sampler
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
SRC_PLIST="$REPO/launchd/staged/$LABEL.plist"
SAMPLER="$HOME/.claude/scripts/active-cpu-sampler.sh"
DST_PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
OUT="$HOME/.claude/autonomy/active-cpu.json"
DOMAIN="gui/$(id -u)"
if [ $# -gt 0 ]; then echo "usage: $0   (no arguments; re-runnable)" >&2; exit 2; fi

fail() { echo "FAIL: $*" >&2; exit 1; }
[ -f "$SRC_PLIST" ] || fail "missing $SRC_PLIST (has the fix landed and converged into $REPO?)"
/usr/bin/plutil -lint "$SRC_PLIST" >/dev/null || fail "$SRC_PLIST does not parse"
[ -f "$SAMPLER" ] || fail "$SAMPLER is not installed (converge first: CC_DEPLOY_MAX_LAG_COMMITS=0 bash $REPO/scripts/deploy-live.sh)"
command -v jq >/dev/null 2>&1 || fail "jq is not on PATH"

echo "== 1. LaunchAgent plist"
mkdir -p "$HOME/Library/LaunchAgents"
if [ -f "$DST_PLIST" ] && cmp -s "$SRC_PLIST" "$DST_PLIST"; then echo "   present, matches the repo"
else
  /bin/cp "$SRC_PLIST" "$DST_PLIST" || fail "could not write $DST_PLIST"
  echo "   installed"
fi

echo "== 2. load $LABEL"
if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then echo "   loaded"
else
  if launchctl print-disabled "$DOMAIN" 2>/dev/null | grep -F "\"$LABEL\" => disabled" >/dev/null; then
    launchctl enable "$DOMAIN/$LABEL" || fail "launchctl enable $LABEL failed"
    echo "   cleared the domain-level disabled bit"
  fi
  launchctl bootstrap "$DOMAIN" "$DST_PLIST" 2>/dev/null || true
  launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1 && echo "   loaded now" || fail "could not load $LABEL"
fi

echo "== 3. verify a fresh sample (read back, fail closed)"
before="$(jq -r '.t // 0' "$OUT" 2>/dev/null || echo 0)"; before="${before:-0}"
t=""
for _ in $(seq 1 45); do
  now_t="$(jq -r 'select(.trees | type == "array") | .t' "$OUT" 2>/dev/null || true)"
  if [ -n "$now_t" ] && [ "$now_t" -gt "$before" ] 2>/dev/null; then t="$now_t"; break; fi
  sleep 1
done
[ -n "$t" ] || fail "$OUT was not rewritten within 45 s — check /tmp/claude-active-cpu-sampler.stderr.log"
echo "   sample at t=$t: $(jq -r '"\(.trees | length) claude trees, \([.trees[] | select(.mid_turn)] | length) mid-turn, \([.trees[] | select(.mid_turn and .cores >= 0.25)] | length) CPU-active, beats_live=\(.beats_live)"' "$OUT")"
mkdir -p "$HOME/.claude/autonomy/pending-activation" 2>/dev/null || true
touch "$HOME/.claude/autonomy/pending-activation/54-active-cpu-sampler-activate.sh.done" 2>/dev/null || true
echo "OK: $LABEL loaded; the admission gate now counts CPU-active turns (revert: CC_ADMIT_ACTIVE_SIGNAL=beat)"
echo "Then flip its launchd/fleet.manifest row from staged to run."
