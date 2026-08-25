#!/usr/bin/env bash
# cc-resume-layout.sh — lay a batch of resumed sessions out ONE OS WINDOW PER MONITOR, split panes
# inside each, instead of piling every session into tabs of the operator's own window.
#
#   Usage: cc-resume-layout.sh [--per-window N] [--stagger SECS] [--use-all-screens] [--dry-run]
#          ... reading a TSV on stdin (or --file PATH):
#              account <TAB> session-id <TAB> worktree <TAB> branch [<TAB> label]
#          i.e. lr-select.py's own output, with an optional 5th label column.
#
# ── WHY THIS EXISTS (2026-08-24, operator ruling during a post-crash recovery) ────────────────────
# The skill's Phase 2 said "create an iTerm2 window per account with split panes", and its kitty
# arm said only "anchor the split to the CALLING pane". Neither sentence says where the WINDOWS go,
# so a kitty recovery of 10 sessions did the locally-obvious thing — `kitty @ launch --type=tab`
# ten times — and produced ten tabs crammed into the one OS window the operator was reading, on one
# monitor, with the other three monitors empty. Operator: "do a window per monitor screen with
# split panes across each." That is what this file is; the layout decision now lives in code
# instead of in a sentence each caller re-interprets.
#
# THREE THINGS THAT ARE NOT OBVIOUS AND COST A ROUND EACH:
#
# 1. THE SPLITS LAYOUT HALVES THE CURRENT PANE, so N chained splits give 1/2, 1/4, 1/8 … widths.
#    Measured on this box: four panes came out 149 / 74 / 36 / 36 columns, and a 36-column Claude
#    Code pane wraps its own status footer — which is how "the nudge did not take" was misread,
#    since `esc to interrupt` is not on screen at that width. The cure is already bound in
#    config/kitty.conf:317 (`layout_action equalize`, ⌘⇧E) and is applied here after every group.
#    `goto-layout grid` is NOT the cure: enabled_layouts is `splits,stack`, so grid is refused.
#
# 2. `kitty @ detach-window --target-tab id:N` MATCHES A TAB ID, NOT A WINDOW ID. Passing a window
#    id silently lands the pane in whatever tab happens to hold that number — panes scattered into
#    a tab they were never meant to join. Use `--target-tab window_id:N`. This file avoids detach
#    entirely (it launches in place) precisely so the trap cannot be re-entered.
#
# 3. AN OS WINDOW'S TITLE IS THE ACTIVE PANE'S TITLE, AND CLAUDE CODE PUTS A LIVE SPINNER GLYPH IN
#    IT (⠐ ⠂ ✳ …). So the Accessibility name used to place the window CHANGES BETWEEN TWO READS,
#    and matching on the full name is a race. `kitty @ launch --os-window-title` sets a title that
#    "will override any titles set by programs running in kitty" — a fixed handle, so placement
#    matches on a marker WE own. (Generalisable: never key an automation on a string the subject
#    repaints.)
#
# PLACEMENT is Accessibility (System Events), because kitty has no move-to-display remote command —
# `kitty @ resize-os-window --action` offers resize/hide/toggle-*, and nothing that moves. Screen
# geometry comes from NSScreen via `swift`, converted to the top-left-origin coordinates System
# Events uses. If Accessibility is not granted, the panes are still CREATED and grouped correctly;
# only the per-monitor placement is skipped, and it says so rather than failing the recovery.
#
# The calling pane's monitor is RESERVED by default — the operator is reading that window, and
# covering it with resumed sessions is the defect this file exists to stop. --use-all-screens opts
# out. Fail-loud, no eval, bash 3.2-safe.
set -uo pipefail

KITTY_BIN="${CC_TERM_KITTY:-}"
if [ -z "$KITTY_BIN" ]; then
  for c in /opt/homebrew/bin/kitty /usr/local/bin/kitty "$(command -v kitty 2>/dev/null || true)"; do
    [ -n "$c" ] && [ -x "$c" ] && { KITTY_BIN="$c"; break; }
  done
fi
# ── PANE-SPAWN LOG (scripts/lib/pane-spawn-log.sh) ──────────────────────────────────────────────
# This file opens OS windows and splits, so every one of those spawns must leave a row — otherwise
# the census's load-bearing inference ("a pane with no row came from OUTSIDE this tree") degrades to
# "…or from cc-resume-layout", which is exactly the ambiguity that log exists to close. The land
# gate (scripts/pane-spawn-coverage-lint.sh) enforces this, and caught this file with 0 of 2 sites
# instrumented on its first run.
for _psl in "$(dirname "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")")/../scripts/lib/pane-spawn-log.sh" \
            "${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/scripts/lib/pane-spawn-log.sh" \
            "${HOME:-}/.claude/scripts/lib/pane-spawn-log.sh"; do
  # shellcheck disable=SC1090  # runtime-resolved source; the ship gate runs shellcheck without -x
  [ -f "$_psl" ] && . "$_psl" 2>/dev/null && break
done
unset _psl
command -v cc_log_pane_spawn >/dev/null 2>&1 || cc_log_pane_spawn() { :; }

# ── CAPACITY ADMISSION (scripts/lib/capacity-admit.sh) ──────────────────────────────────────────
# This file fires a BATCH — N sessions in one run — which is exactly the shape the admission gate
# exists to bound (the 2026-07-21 sprawl: 39 sessions, 8.8 GB, zero free RAM). It was landed without
# one and tests/capacity-admit-coverage.bats case 25 caught it as "a NEW in-repo invoker … not the
# gated launcher", which auto-reverted the commit. The refusal was correct.
#
# THE SHAPE IS boot-resume-launch.sh's, DELIBERATELY, INCLUDING THE HANDSHAKE. bin/reso-resume-one
# carries its own gate, so gating here as well would evaluate twice per spawn and double-spend the
# shared consecutive-refusal budget. The launcher solves that by admitting ONCE and exporting
# CC_ADMIT_DONE=1 so the engine skips its own; this file does the same, via kitty's --env.
# Gating HERE rather than leaving it to the engine buys the thing a batch needs: the engine's shed
# happens inside a freshly-spawned pane, where this loop cannot see it, so a refusal would launch
# all N regardless. Admitted per item, the batch SHEDS ITS TAIL under pressure and says how many.
# ABSENT LIBRARY IS LOUD (§12.2) — never a silent admit.
CC_ADMIT_OK=0
for _cra in "$(dirname "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")")/../scripts/lib/capacity-admit.sh" \
            "${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/scripts/lib/capacity-admit.sh" \
            "${HOME:-}/.claude/scripts/lib/capacity-admit.sh"; do
  # shellcheck disable=SC1090  # runtime-resolved source; the ship gate runs shellcheck without -x
  if [ -f "$_cra" ] && . "$_cra" 2>/dev/null; then CC_ADMIT_OK=1; break; fi
done
unset _cra
if [ "$CC_ADMIT_OK" != 1 ]; then
  printf '%s\n' "cc-resume-layout: capacity-admit ABSENT (scripts/lib/capacity-admit.sh unreachable) — launching UNGATED" >&2
fi

RESUME_ONE="${CC_RESUME_ONE_BIN:-$HOME/.reso/bin/reso-resume-one}"
OSASCRIPT="${CC_OSASCRIPT_BIN:-osascript}"
SWIFT_BIN="${CC_SWIFT_BIN:-/usr/bin/swift}"

PER_WINDOW=0          # 0 = derive from the screen count
STAGGER="${CC_RESUME_STAGGER:-12}"
USE_ALL_SCREENS=0
DRY_RUN=0
FILE=""

die() { printf 'cc-resume-layout: %s\n' "$*" >&2; exit 2; }
note() { printf '%s\n' "$*" >&2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --per-window)      PER_WINDOW="${2:?--per-window needs a number}"; shift 2 ;;
    --stagger)         STAGGER="${2:?--stagger needs seconds}"; shift 2 ;;
    --file)            FILE="${2:?--file needs a path}"; shift 2 ;;
    --use-all-screens) USE_ALL_SCREENS=1; shift ;;
    --dry-run)         DRY_RUN=1; shift ;;
    -h|--help)         sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0 ;;
    *)                 die "unknown argument: $1" ;;
  esac
done

[ -n "$KITTY_BIN" ] && [ -x "$KITTY_BIN" ] || die "no kitty binary (set CC_TERM_KITTY) — this layout is kitty-only"
[ "$DRY_RUN" = 1 ] || [ -x "$RESUME_ONE" ] || die "resume launcher not executable: $RESUME_ONE"

# ── 1. the batch ────────────────────────────────────────────────────────────────────────────────
# Read with IFS=$'\t' and -r. A tab IS IFS whitespace, so a run of empty fields would collapse and
# shift every later column left; each row is therefore required to carry its 4 mandatory fields and
# is rejected loudly if it does not (memory: ifs-whitespace-collapses-empty-fields).
ROWS=()
while IFS= read -r line; do
  [ -z "$line" ] && continue
  case "$line" in '#'*) continue ;; esac
  n=$(printf '%s' "$line" | awk -F'\t' '{print NF}')
  [ "$n" -ge 4 ] || die "row has $n tab-separated fields, need >=4: $line"
  ROWS+=("$line")
done < <(if [ -n "$FILE" ]; then cat -- "$FILE"; else cat; fi)

N=${#ROWS[@]}
[ "$N" -gt 0 ] || die "no rows on stdin — nothing to lay out"

# ── 2. screens, in System Events (top-left origin, y down) coordinates ──────────────────────────
# NSScreen is bottom-left origin with y up; AX is top-left origin with y down, anchored at the top
# of the MAIN screen. y_ax = mainHeight - (y_ns + height). visibleFrame, not frame, so a window on
# the built-in display is not placed under the menu bar.
SCREENS=()
if [ -x "$SWIFT_BIN" ]; then
  swift_src="$(mktemp -t ccscreens).swift"
  cat > "$swift_src" <<'SWIFT'
import AppKit
let main = NSScreen.screens.first?.frame.height ?? 0
for s in NSScreen.screens {
    let v = s.visibleFrame
    let yAX = main - (v.origin.y + v.height)
    print("\(Int(v.origin.x))\t\(Int(yAX))\t\(Int(v.width))\t\(Int(v.height))")
}
SWIFT
  while IFS= read -r sline; do
    [ -n "$sline" ] && SCREENS+=("$sline")
  done < <("$SWIFT_BIN" "$swift_src" 2>/dev/null)
  rm -f "$swift_src"
fi
NSCREENS=${#SCREENS[@]}
[ "$NSCREENS" -gt 0 ] || note "cc-resume-layout: screen geometry unreadable — grouping still applies, placement skipped"

# The calling pane's OS window occupies a screen the operator is looking at. Drop that screen from
# the pool unless told otherwise.
#
# HOW THE CALLER'S SCREEN IS IDENTIFIED — MEASURED, NOT ASSUMED. Two tempting shortcuts are both
# wrong here, and the second one was measured wrong on this box:
#   · the AX *name* of the caller's window is its active pane's title, which Claude Code repaints
#     with a spinner glyph, so it differs between two reads;
#   · System Events' `window 1` (frontmost) is NOT reliably the caller — a recovery focuses panes
#     as it works, and a test run reserved the screen of a window the agent had last touched while
#     the operator sat on a different display. A wrong reserve covers the window they are reading,
#     which is the exact defect this file exists to prevent, so a guess is not good enough.
# What IS exact: `kitty @ ls` reports each OS window's `platform_window_id` — the CGWindow number —
# and CGWindowListCopyWindowInfo maps that number to bounds in the same top-left-origin coordinates
# System Events uses. So the caller's OS window is resolved by identity, not by focus or title.
# Unresolvable ⇒ reserve NOTHING rather than guess, and say so.
RESERVED=-1
if [ "$USE_ALL_SCREENS" = 0 ] && [ "$NSCREENS" -gt 1 ] && [ -n "${KITTY_WINDOW_ID:-}" ] && [ -x "$SWIFT_BIN" ]; then
  pwid="$("$KITTY_BIN" @ ls 2>/dev/null | KW="$KITTY_WINDOW_ID" python3 -c '
import json,os,sys
kw=int(os.environ["KW"])
try: data=json.load(sys.stdin)
except Exception: sys.exit(0)
for o in data:
    for t in o["tabs"]:
        for w in t["windows"]:
            if w["id"] == kw:
                print(o.get("platform_window_id") or ""); sys.exit(0)
' 2>/dev/null || true)"
  case "$pwid" in
    ''|*[!0-9]*) note "cc-resume-layout: caller's OS window id unresolvable — reserving no screen" ;;
    *)
      cg_src="$(mktemp -t ccwin).swift"
      cat > "$cg_src" <<'SWIFT'
import CoreGraphics
import Foundation
let want = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1]) ?? -1 : -1
if let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] {
    for w in list {
        guard let num = w[kCGWindowNumber as String] as? Int, num == want,
              let b = w[kCGWindowBounds as String] as? [String: Any],
              let x = b["X"] as? Double, let y = b["Y"] as? Double else { continue }
        print("\(Int(x))\t\(Int(y))")
        break
    }
}
SWIFT
      bounds="$("$SWIFT_BIN" "$cg_src" "$pwid" 2>/dev/null)"
      rm -f "$cg_src"
      ox="$(printf '%s' "$bounds" | cut -f1)"
      oy="$(printf '%s' "$bounds" | cut -f2)"
      case "$ox$oy" in
        ''|*[!0-9-]*) note "cc-resume-layout: caller's window bounds unreadable — reserving no screen" ;;
        *)
          i=0
          for s in "${SCREENS[@]}"; do
            sx=$(printf '%s' "$s" | cut -f1); sy=$(printf '%s' "$s" | cut -f2)
            sw=$(printf '%s' "$s" | cut -f3); sh=$(printf '%s' "$s" | cut -f4)
            # Compare against the window's CENTRE: an origin can sit a pixel outside its own
            # screen rect (title bar above the visibleFrame) and match nothing, or the neighbour.
            cxp=$((ox + 40)); cyp=$((oy + 40))
            if [ "$cxp" -ge "$sx" ] && [ "$cxp" -lt $((sx + sw)) ] && [ "$cyp" -ge "$sy" ] && [ "$cyp" -lt $((sy + sh)) ]; then
              RESERVED=$i; break
            fi
            i=$((i + 1))
          done
          ;;
      esac
      ;;
  esac
fi

POOL=()
i=0
for s in "${SCREENS[@]}"; do
  [ "$i" != "$RESERVED" ] && POOL+=("$s")
  i=$((i + 1))
done
[ ${#POOL[@]} -gt 0 ] || POOL=("${SCREENS[@]}")   # every screen reserved ⇒ use them all rather than none
NPOOL=${#POOL[@]}

# ── 3. partition ────────────────────────────────────────────────────────────────────────────────
if [ "$PER_WINDOW" -le 0 ]; then
  if [ "$NPOOL" -gt 0 ]; then
    PER_WINDOW=$(( (N + NPOOL - 1) / NPOOL ))
  else
    PER_WINDOW=4
  fi
fi
[ "$PER_WINDOW" -ge 1 ] || PER_WINDOW=1
NGROUPS=$(( (N + PER_WINDOW - 1) / PER_WINDOW ))
SHED=0

note "cc-resume-layout: $N session(s) · ${NSCREENS} screen(s) (reserved index ${RESERVED}) · ${NGROUPS} window(s) × up to ${PER_WINDOW} pane(s)"

# ── 4. launch, group by group ───────────────────────────────────────────────────────────────────
g=0
while [ "$g" -lt "$NGROUPS" ]; do
  start=$(( g * PER_WINDOW ))
  marker="CC-RESUME-W$((g + 1))"
  head_win=""
  k=0
  while [ "$k" -lt "$PER_WINDOW" ]; do
    idx=$(( start + k ))
    [ "$idx" -ge "$N" ] && break
    row="${ROWS[$idx]}"
    # FIELD ORDER: lr-select.py:434 emits acct/SID/cwd/branch — the sid is FIELD 2, the worktree
    # FIELD 3 — and boot-resume.sh:293 reads its winners back in exactly that order. This file
    # shipped with f2/f3 swapped, so it handed reso-resume-one the SID as its worktree argument
    # and the PATH as its session-id (`--cwd <a uuid>`), i.e. the documented one-liner
    # `lr-select.py … | cc-resume-layout.sh` could never have launched anything. Fixed 2026-08-25.
    acct="$(printf '%s' "$row" | cut -f1)"
    sid="$(printf '%s' "$row" | cut -f2)"
    wt="$(printf '%s' "$row" | cut -f3)"
    br="$(printf '%s' "$row" | cut -f4)"

    # ADMIT before spawning. A refusal SHEDS the rest of the batch rather than this one item:
    # capacity does not recover inside a loop, so continuing would just collect N more refusals.
    if [ "$DRY_RUN" = 0 ] && [ "$CC_ADMIT_OK" = 1 ]; then
      if ! cc_capacity_admit cc-resume-layout "resume ${sid} on ${acct}"; then
        note "cc-resume-layout: SHED — $(cc_capacity_admit_reason)"
        note "cc-resume-layout: $((N - idx)) session(s) NOT launched; re-run when the box has room."
        SHED=$((N - idx))
        break
      fi
    fi

    if [ "$DRY_RUN" = 1 ]; then
      if [ -z "$head_win" ]; then
        note "DRY [$marker] os-window: $RESUME_ONE $acct $wt $sid $br"
        head_win="dry"
      else
        note "DRY [$marker] split   : $RESUME_ONE $acct $wt $sid $br"
      fi
      k=$((k + 1)); continue
    fi

    if [ -z "$head_win" ]; then
      head_win="$("$KITTY_BIN" @ launch --type=os-window --os-window-title "$marker" \
                    --env CC_ADMIT_DONE=1 \
                    --cwd "$wt" -- "$RESUME_ONE" "$acct" "$wt" "$sid" "$br" 2>&1)"
      case "$head_win" in
        ''|*[!0-9]*) note "cc-resume-layout: head launch failed for $sid: $head_win"; head_win=""; k=$((k + 1)); continue ;;
      esac
      cc_log_pane_spawn os-window kitty "$head_win" "$wt" "resume-layout $marker head sid=$sid acct=$acct"
      note "  [$marker] win $head_win  $acct  $(basename "$wt")"
    else
      # Alternate the split axis so a 4-pane group tiles 2x2 rather than into four thin columns.
      loc=vsplit; [ $((k % 2)) -eq 1 ] && loc=hsplit
      wid="$("$KITTY_BIN" @ launch --location="$loc" --match "window_id:$head_win" \
               --next-to "id:$head_win" --env CC_ADMIT_DONE=1 \
               --cwd "$wt" -- "$RESUME_ONE" "$acct" "$wt" "$sid" "$br" 2>&1)"
      cc_log_pane_spawn split kitty "$wid" "$wt" "resume-layout $marker $loc sid=$sid acct=$acct"
      note "  [$marker] win $wid  $acct  $(basename "$wt")"
    fi
    sleep "$STAGGER"
    k=$((k + 1))
  done

  if [ "$DRY_RUN" = 0 ] && [ -n "$head_win" ] && [ "$head_win" != dry ]; then
    # EQUALIZE: `kitty @ action` acts on the ACTIVE window, not the one it was invoked from
    # (config/kitty.conf:313-315), so the head must be focused first.
    "$KITTY_BIN" @ focus-window --match "id:$head_win" >/dev/null 2>&1
    sleep 1
    "$KITTY_BIN" @ action layout_action equalize >/dev/null 2>&1 \
      || note "  [$marker] equalize refused — panes may be uneven"

    # PLACE on this group's screen, by the marker title we own.
    gi=$(( g % NPOOL ))
    if [ "$NPOOL" -gt 0 ] && [ "$NSCREENS" -gt 0 ]; then
      s="${POOL[$gi]}"
      sx=$(printf '%s' "$s" | cut -f1); sy=$(printf '%s' "$s" | cut -f2)
      sw=$(printf '%s' "$s" | cut -f3); sh=$(printf '%s' "$s" | cut -f4)
      placed="$("$OSASCRIPT" <<EOF 2>/dev/null
tell application "System Events" to tell process "kitty"
  repeat with w in windows
    if name of w contains "$marker" then
      set position of w to {$sx, $sy}
      set size of w to {$sw, $sh}
      return "ok"
    end if
  end repeat
  return "nomatch"
end tell
EOF
)"
      case "$placed" in
        ok) note "  [$marker] placed at ${sx},${sy} ${sw}x${sh}" ;;
        *)  note "  [$marker] NOT placed (Accessibility denied, or title override unsupported) — panes are correct, position is not" ;;
      esac
    fi
  fi
  [ "$SHED" -gt 0 ] && break
  g=$((g + 1))
done

# Give the operator their focus back — this script is run from the pane they are reading.
if [ "$DRY_RUN" = 0 ] && [ -n "${KITTY_WINDOW_ID:-}" ]; then
  "$KITTY_BIN" @ focus-window --match "id:$KITTY_WINDOW_ID" >/dev/null 2>&1 || true
fi
exit 0
