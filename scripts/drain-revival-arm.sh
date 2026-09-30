#!/bin/bash
# drain-revival-arm.sh — revive a DEAD 24/7 drain chain, gated and capped (backlog c109e9e850fb).
#
# ── WHY THIS EXISTS ───────────────────────────────────────────────────────────────────────────────
# The drain chain dies with nothing to restart it: it stopped 2026-08-16, again 2026-09-09, and again
# after recycle #336 on 2026-09-22. drain-chain-assert.sh DETECTS the death every sweep and files one
# condition-keyed row; nothing ACTS on it, so a dead chain waits for a human to notice. This arm is
# the actuator, and drain-chain-assert.sh stays the arbiter: its `verdict` is read, never re-derived
# (memory: make-the-actuator-the-arbiter).
#
# ── THREE MODES — CC_DRAIN_AUTOFIRE ───────────────────────────────────────────────────────────────
#   off          the kill switch: nothing runs, not even the detector.
#   would-fire   DEFAULT. Decides exactly as `on` would and logs the decision, but fires nothing and
#                spends no quota. It ships this way so it lands without a ruling: the operator rules
#                the real default after 7 days of these logs (decision row c109e9e850fb, SITTINGS S6).
#   on           fires `drain-recycle-fire.sh --num <N+1> --first`, which opens a NEW pane for the
#                chain's next link (a launchd sweep has no pane to --recycle).
# Any other value FAILS CLOSED: it is treated as off and reported as `bad-mode`.
#
# ── THE GATES, in order, each failing closed (no fire) ────────────────────────────────────────────
#   verdict unreadable → no-verdict · verdict != dead → alive · link number unparseable → no-num ·
#   stamp younger than the cooldown (3600 s) → cooldown-held · stamp write failed → claim-failed.
# The cooldown stamp is CLAIMED BEFORE the fire, so a fire that hangs or fails still spends the hour:
# a failing fire retried every 300 s would be a quota leak with no ceiling. `would-fire` keeps its
# OWN stamp, so its log count is exactly what `on` would have fired under the same hourly cap — the
# number the ruling needs — and switching modes never inherits the other mode's clock.
#
# ── OUTPUT ────────────────────────────────────────────────────────────────────────────────────────
# `--tick` prints ONE compact JSON line (mode, decision, verdict, why, next_num, cmd, fire_rc) and
# exits 0; the sweep journals it verbatim. `--help` prints this header. Anything else exits 2.
# Env seams: CC_DRAIN_ASSERT_BIN · CC_DRAIN_FIRE_BIN · CC_DRAIN_ARM_STATE_DIR ·
# CC_DRAIN_ARM_COOLDOWN_S · CC_DRAIN_ARM_ASSERT_TIMEOUT_S · CC_DRAIN_ARM_FIRE_TIMEOUT_S.
set -uo pipefail

case "${1:-}" in
  --tick) ;;
  -h|--help) sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0 ;;
  *) printf 'drain-revival-arm: usage: drain-revival-arm.sh --tick\n' >&2; exit 2 ;;
esac

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSERT_BIN="${CC_DRAIN_ASSERT_BIN:-$_here/drain-chain-assert.sh}"
FIRE_BIN="${CC_DRAIN_FIRE_BIN:-$_here/drain-recycle-fire.sh}"
STATE_DIR="${CC_DRAIN_ARM_STATE_DIR:-$HOME/.claude/autonomy/drain-arm}"
COOLDOWN_S="${CC_DRAIN_ARM_COOLDOWN_S:-3600}"
ASSERT_TIMEOUT_S="${CC_DRAIN_ARM_ASSERT_TIMEOUT_S:-60}"
FIRE_TIMEOUT_S="${CC_DRAIN_ARM_FIRE_TIMEOUT_S:-300}"

TIMEOUT_BIN=""
for _c in "$(command -v timeout 2>/dev/null || true)" "$(command -v gtimeout 2>/dev/null || true)" \
          /opt/homebrew/bin/timeout /opt/homebrew/bin/gtimeout /usr/local/bin/timeout; do
  [ -n "$_c" ] && [ -x "$_c" ] && { TIMEOUT_BIN="$_c"; break; }
done
bounded() { # <seconds> <cmd…>
  local s="$1"; shift
  if [ -z "$TIMEOUT_BIN" ]; then "$@"; return $?; fi
  "$TIMEOUT_BIN" -k 5 "$s" "$@"
}

mode="${CC_DRAIN_AUTOFIRE:-would-fire}"
decision=""; verdict=""; why=""; next_num=""; cmd=""; fire_rc=""

emit() {
  jq -nc --arg mode "$mode" --arg decision "$decision" --arg verdict "$verdict" --arg why "$why" \
    --arg next "$next_num" --arg cmd "$cmd" --arg frc "$fire_rc" \
    '{mode:$mode, decision:$decision,
      verdict:(if $verdict=="" then null else $verdict end),
      why:(if $why=="" then null else $why end),
      next_num:(if $next=="" then null else ($next|tonumber) end),
      cmd:(if $cmd=="" then null else $cmd end),
      fire_rc:(if $frc=="" then null else ($frc|tonumber) end)}'
  exit 0
}

case "$mode" in
  off) decision="off"; emit ;;
  would-fire|on) ;;
  *) decision="bad-mode"; emit ;;
esac

out="$(bounded "$ASSERT_TIMEOUT_S" bash "$ASSERT_BIN" --json 2>/dev/null)"; arc=$?
verdict="$(printf '%s' "$out" | jq -r '.verdict // empty' 2>/dev/null)"
why="$(printf '%s' "$out" | jq -r '.why // empty' 2>/dev/null)"
brief="$(printf '%s' "$out" | jq -r '.brief // empty' 2>/dev/null)"
case "$verdict" in alive|dead) ;; *) verdict="" ;; esac
if [ "$arc" -ne 0 ] || [ -z "$verdict" ]; then decision="no-verdict"; emit; fi
[ "$verdict" = dead ] || { decision="alive"; emit; }

n="$(basename "${brief:-}" | sed -n 's/^fire-drain-.*-recycle\([0-9][0-9]*\)\.txt$/\1/p')"
[ -n "$n" ] || { decision="no-num"; emit; }
next_num=$(( n + 1 ))
cmd="bash $FIRE_BIN --num $next_num --lane infra --project claude-infrastructure --first --account auto"

case "$mode" in on) stamp="$STATE_DIR/fire.stamp" ;; *) stamp="$STATE_DIR/would-fire.stamp" ;; esac
now="$(date +%s)"
last="$(cat "$stamp" 2>/dev/null || echo 0)"
case "$last" in ''|*[!0-9]*) last=0 ;; esac
if [ "$last" -gt 0 ] && [ $(( now - last )) -lt "$COOLDOWN_S" ]; then decision="cooldown-held"; emit; fi

# CLAIM before acting — see the header. A failed claim is a failed gate.
if ! { mkdir -p "$STATE_DIR" 2>/dev/null && printf '%s\n' "$now" >"$stamp.tmp.$$" 2>/dev/null \
       && mv -f "$stamp.tmp.$$" "$stamp" 2>/dev/null; }; then
  decision="claim-failed"; emit
fi

[ "$mode" = on ] || { decision="would-fire"; emit; }

bounded "$FIRE_TIMEOUT_S" bash "$FIRE_BIN" --num "$next_num" --lane infra \
  --project claude-infrastructure --first --account auto >/dev/null 2>&1
fire_rc=$?
decision="fired"
emit
