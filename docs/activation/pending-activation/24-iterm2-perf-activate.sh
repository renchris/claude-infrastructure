#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 24-iterm2-perf  —  apply the measured iTerm2 render knobs (row 13 completion, M8 / §11.9)
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: writes the 8 REQUIRED rows of config/iterm2-perf.keys to com.googlecode.iterm2 via
#   `defaults write`, after saving every prior value to a timestamped undo file. Then runs
#   scripts/iterm2-perf-parity.sh, which must flip from DRIFT-everywhere to MATCH.
#
# WHY: §11.9(2) measured the render bottleneck as LEGACY CPU GLYPH DRAWING on ONE saturated
#   iTerm2 thread (56-70% of main), with the app default disableAdaptiveFrameRateInInteractiveApps
#   =YES exempting exactly our ~60 alternate-screen TUI panes from the throughput throttle.
#   Expected return: ~0.5-0.9 cores (adaptive) + ~0.3-0.6 (frame ceilings) + ~0.15-0.4
#   (fastForegroundJobUpdates) + ~0.1-0.3 (dimming/animation) of the measured ~1.9-core render floor.
#
# WHY C10: machine-wide app preferences are the operator's surface; agents stage, the operator runs.
# UNDO: re-run with --undo (restores the saved prior values, deleting keys that were unset).
# Mark done:  touch <this file>.done
#
# TWO MANUAL SIDE-LEVERS (no defaults key exists — do them in the UI if you want the win):
#   · Displays: the two external monitors at 120 Hz DOUBLE iTerm2's update cadence on ARM
#     (§11.9 A3: activeUpdateCadence "doubled on ARM Macs for displays that support at least
#     120hz"). System Settings → Displays → refresh rate 60 Hz halves the frame ceiling for free.
#   · Browser class: Chrome/Discord helpers measured ~0.4-0.5 cores of the stable floor — quit
#     them when not in use. (Both optional; neither is parity-checked.)
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
KEYS="$REPO/config/iterm2-perf.keys"
PARITY="$REPO/scripts/iterm2-perf-parity.sh"
UNDO="$HOME/.claude/autonomy/iterm2-perf-undo.tsv"

[ -f "$KEYS" ] || { echo "✗ missing $KEYS (land M8 first)" >&2; exit 1; }

if [ "${1:-}" = "--undo" ]; then
  [ -f "$UNDO" ] || { echo "✗ no undo file at $UNDO" >&2; exit 1; }
  while IFS=$'\t' read -r dom key prior; do
    [ -n "$dom" ] || continue
    if [ "$prior" = "__UNSET__" ]; then
      defaults delete "$dom" "$key" 2>/dev/null && echo "  ← $key deleted (was unset)" || echo "  · $key already unset"
    else
      defaults write "$dom" "$key" "$prior" && echo "  ← $key restored to $prior"
    fi
  done < "$UNDO"
  echo "undo complete — restart iTerm2 to fully apply."
  exit 0
fi

echo "== 24-iterm2-perf =="
echo "Plan (required rows from $KEYS):"
grep -Ev '^[[:space:]]*(#|$)' "$KEYS" | while read -r dom key typ val _; do
  cur=$(defaults read "$dom" "$key" 2>/dev/null || echo '<unset>')
  printf '  %-45s %-8s -> %-6s (now: %s)\n' "$key" "($typ)" "$val" "$cur"
done

if [ "${CONFIRM:-0}" != 1 ]; then
  echo
  echo "(dry run — re-run with CONFIRM=1 to apply; '--undo' reverts:)"
  _pfx=""; [ -n "${CC_REPO+set}" ] && _pfx="CC_REPO=$REPO "
  echo "    CONFIRM=1 ${_pfx}bash $HOME/.claude/autonomy/pending-activation/24-iterm2-perf-activate.sh"
  exit 0
fi

echo "[1] saving prior values → $UNDO"
mkdir -p "$(dirname "$UNDO")"
: > "$UNDO"
grep -Ev '^[[:space:]]*(#|$)' "$KEYS" | while read -r dom key typ val _; do
  prior=$(defaults read "$dom" "$key" 2>/dev/null || echo "__UNSET__")
  printf '%s\t%s\t%s\n' "$dom" "$key" "$prior" >> "$UNDO"
done

echo "[2] writing"
fails=0
while read -r dom key typ val _; do
  case "$typ" in
    bool)  defaults write "$dom" "$key" -bool "$val" ;;
    float) defaults write "$dom" "$key" -float "$val" ;;
    *)     echo "  ✗ unknown type '$typ' for $key — skipped" >&2; fails=$((fails+1)); continue ;;
  esac && echo "  + $key = $val" || { echo "  ✗ write failed: $key" >&2; fails=$((fails+1)); }
done < <(grep -Ev '^[[:space:]]*(#|$)' "$KEYS")
[ "$fails" -eq 0 ] || { echo "✗ $fails write(s) failed — check, then --undo if needed" >&2; exit 1; }

echo "[3] parity verification"
if [ -x "$PARITY" ]; then
  bash "$PARITY" || echo "  (non-zero parity rc above — UNSET/DRIFT rows should now be gone; investigate any that remain)"
else
  echo "  · parity script not deployed yet — verify manually with the defaults reads above"
fi

echo
echo "NOTES: most knobs apply live; activeUpdateCadence affects NEW sessions only (full effect as"
echo "panes recycle). A full iTerm2 restart applies everything at once — your call on timing."
echo "Then:  touch $HOME/.claude/autonomy/pending-activation/24-iterm2-perf-activate.sh.done"
