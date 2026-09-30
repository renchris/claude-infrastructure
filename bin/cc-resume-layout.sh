#!/usr/bin/env bash
# cc-resume-layout.sh — lay a batch of resumed sessions out ONE OS WINDOW PER MONITOR, split panes
# inside each, instead of piling every session into tabs of the operator's own window.
#
#   Usage: cc-resume-layout.sh [--per-window N] [--stagger SECS] [--use-all-screens] [--dry-run]
#          cc-resume-layout.sh --desktops [--to unix:/path] [--per-window N<=4] [--stagger SECS] [--dry-run]
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
# --desktops (2026-09-30, operator ruling after the 15:24 reboot recovery): the per-monitor layout put
# five panes side by side, 37 columns each at this font, which wraps Claude Code's footer. The
# operator's layout is ONE native-fullscreen OS window per macOS Desktop, at most 4 panes each as a
# 2x2, grouped by project. Built from the recipe measured that afternoon: A|B by vsplit, then C
# beside A and D beside B, each turned under its neighbour with `layout_action rotate` (the splits
# layout only — never switch layouts); then native fullscreen through System Events AXFullScreen on
# the window whose title carries a temporary marker, one window at a time, verdict by READING
# AXFullScreen back (kitty @ ls has no fullscreen field, and back-to-back toggles are dropped).
# Prints one `cc-resume-layout: verdict=… launched=… shed=… failed=… windows=… fullscreen_ok=…
# fullscreen_failed=…` line on stdout; scripts/boot-resume.sh parses it. Exit 3 = no live kitty.
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
DESKTOPS=0
TO_ARG=""
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
    --desktops)        DESKTOPS=1; shift ;;
    --to)              TO_ARG="${2:?--to needs unix:/path}"; shift 2 ;;
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

# ── --desktops ──────────────────────────────────────────────────────────────────────────────────
if [ "$DESKTOPS" = 1 ]; then
  SETTLE="${CC_DESKTOP_SETTLE:-1.5}"
  FS_DELAY="${CC_DESKTOP_FS_DELAY:-2.5}"
  [ "$PER_WINDOW" -ge 1 ] 2>/dev/null && [ "$PER_WINDOW" -le 4 ] || PER_WINDOW=4

  # The control socket. boot-resume runs this from launchd, where no KITTY_WINDOW_ID exists, so
  # an explicit socket (or the live one cc-kitty-socket finds) is what makes kitty reachable.
  SOCK="${TO_ARG:-${CC_TERM_KITTY_TO:-}}"
  if [ -z "$SOCK" ] && [ -z "${KITTY_WINDOW_ID:-}" ] && [ "$DRY_RUN" = 0 ]; then
    for _ks in "${CC_KITTY_SOCKET_BIN:-}" \
               "$(dirname "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")")/cc-kitty-socket" \
               "${HOME:-}/.claude/bin/cc-kitty-socket"; do
      [ -n "$_ks" ] && [ -x "$_ks" ] && { SOCK="$("$_ks" 2>/dev/null | head -1)"; break; }
    done
    [ -n "$SOCK" ] || { note "cc-resume-layout: no live kitty control socket — nothing to lay out into"; exit 3; }
  fi
  k() { if [ -n "$SOCK" ]; then "$KITTY_BIN" @ --to "$SOCK" "$@"; else "$KITTY_BIN" @ "$@"; fi; }
  shq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
  fs_osa() { # <marker> → "true" | "false" | "nomatch" | "" — the AXFullScreen READ-BACK
    "$OSASCRIPT" <<EOF 2>/dev/null
tell application "System Events" to tell process "kitty"
  repeat with x in windows
    if name of x contains "$1" then
      if value of attribute "AXFullScreen" of x is false then set value of attribute "AXFullScreen" of x to true
      delay $FS_DELAY
      return (value of attribute "AXFullScreen" of x) as text
    end if
  end repeat
  return "nomatch"
end tell
EOF
  }

  # PLAN: group by project (the repo a worktree belongs to), pack projects into windows of at most
  # PER_WINDOW panes, first-fit-decreasing; a project bigger than a window is chunked. Output:
  # "<window#>\t<row index>\t<group label>", in launch order.
  PLAN="$(i=0; for r in "${ROWS[@]}"; do printf '%s\t%s\n' "$i" "$(printf '%s' "$r" | cut -f3)"; i=$((i + 1)); done \
    | python3 -c '
import os, subprocess, sys
per = int(sys.argv[1])
def key(wt):
    try:
        out = subprocess.run(["git", "-C", wt, "rev-parse", "--path-format=absolute", "--git-common-dir"],
                             capture_output=True, text=True, timeout=10)
        if out.returncode == 0 and out.stdout.strip():
            return os.path.basename(os.path.dirname(out.stdout.strip().rstrip("/")))
    except Exception:
        pass
    return os.path.basename(wt.rstrip("/")) or "?"
groups, order = {}, []
for line in sys.stdin:
    i, _, wt = line.rstrip("\n").partition("\t")
    g = key(wt) if wt else "?"
    if g not in groups:
        groups[g] = []; order.append(g)
    groups[g].append(int(i))
chunks = [(g, groups[g][j:j + per]) for g in order for j in range(0, len(groups[g]), per)]
chunks.sort(key=lambda c: -len(c[1]))
bins = []
for g, idx in chunks:
    for b in bins:
        if len(b[0]) + len(idx) <= per:
            b[0].extend(idx); b[1].append(g); break
    else:
        bins.append([list(idx), [g]])
for n, (idx, gs) in enumerate(bins, 1):
    for i in idx:
        print("%d\t%d\t%s" % (n, i, "+".join(gs)))
' "$PER_WINDOW")" || die "the window planner failed"

  launched=0; failed=0; shed=0; done_rows=0; nwin=0
  WIN_HEAD=(); WIN_PANES=()          # per window: head id; space-separated pane ids
  cur=""; A=""; B=""; pos=0; panes=""
  close_window() { # equalize the window just built and remember it for the fullscreen pass
    [ -n "$A" ] || return 0
    [ "$DRY_RUN" = 1 ] || KITTY_WINDOW_ID="$A" k action --self layout_action equalize >/dev/null 2>&1 \
      || note "  [CC-DESK-$cur] equalize refused — panes may be uneven"
    WIN_HEAD+=("$A"); WIN_PANES+=("${panes# }"); nwin=$((nwin + 1))
  }
  while IFS=$'\t' read -r win idx grp; do
    [ -n "$win" ] || continue
    if [ "$win" != "$cur" ]; then close_window; cur="$win"; A=""; B=""; pos=0; panes=""; fi
    row="${ROWS[$idx]}"
    acct="$(printf '%s' "$row" | cut -f1)"; sid="$(printf '%s' "$row" | cut -f2)"
    wt="$(printf '%s' "$row" | cut -f3)";   br="$(printf '%s' "$row" | cut -f4)"
    case "$pos" in 0) how="head" ;; 1) how="vsplit" ;; *) how="vsplit+rotate" ;; esac
    if [ "$DRY_RUN" = 1 ]; then
      note "DRY [CC-DESK-$win $grp] $how $acct $sid $wt"
      A="dry"; pos=$((pos + 1)); continue
    fi
    # ADMIT per pane; a refusal SHEDS the rest of the batch (capacity does not recover in a loop).
    if [ "$CC_ADMIT_OK" = 1 ] && ! cc_capacity_admit cc-resume-layout "resume ${sid} on ${acct}"; then
      note "cc-resume-layout: SHED — $(cc_capacity_admit_reason)"
      shed=$((N - done_rows)); break
    fi
    done_rows=$((done_rows + 1))
    # SHELL ROOT, as scripts/boot-resume-launch.sh's kitty arm: the pane must outlive the session
    # in it, or a later recycle of this pane strands (tests/kitty-recovery-launch.bats SURVIVABILITY).
    cmd="'env' 'CC_ADMIT_DONE=1' $(shq "$RESUME_ONE") $(shq "$acct") $(shq "$wt") $(shq "$sid")"
    [ -n "$br" ] && cmd="$cmd $(shq "$br")"
    LA=(launch)
    case "$pos" in
      0) LA+=(--type=os-window) ;;
      1|2) LA+=(--location=vsplit --match "window_id:$A" --next-to "id:$A") ;;
      *) anc="${B:-$A}"; LA+=(--location=vsplit --match "window_id:$anc" --next-to "id:$anc") ;;
    esac
    { [ -n "$wt" ] && [ -d "$wt" ]; } && LA+=(--cwd "$wt")
    LA+=(--env CC_ADMIT_DONE=1 -- zsh -ic "$cmd; exec zsh -i")
    wid="$(k "${LA[@]}" 2>&1)"
    case "$wid" in
      ''|*[!0-9]*) note "cc-resume-layout: launch failed for $sid: $wid"; failed=$((failed + 1)); continue ;;
    esac
    if [ "$pos" = 0 ]; then
      cc_log_pane_spawn os-window kitty "$wid" "$wt" "resume-layout CC-DESK-$win head sid=$sid acct=$acct"
      A="$wid"
    else
      cc_log_pane_spawn split kitty "$wid" "$wt" "resume-layout CC-DESK-$win $how sid=$sid acct=$acct"
      [ "$pos" = 1 ] && B="$wid"
      # C and D: launched beside A / B, then turned UNDER it — the 2x2 without leaving `splits`.
      [ "$pos" -ge 2 ] && { KITTY_WINDOW_ID="$wid" k action --self layout_action rotate >/dev/null 2>&1 \
        || note "  [CC-DESK-$win] rotate refused for $wid — pane stays beside its neighbour"; }
    fi
    panes="$panes $wid"; pos=$((pos + 1)); launched=$((launched + 1))
    note "  [CC-DESK-$win $grp] win $wid  $acct  $(basename "$wt")"
    sleep "$STAGGER"
  done <<EOF
$PLAN
EOF
  close_window
  [ "$DRY_RUN" = 1 ] && nwin="$(printf '%s\n' "$PLAN" | cut -f1 | sort -u | grep -c . || true)"

  # FULLSCREEN, one window at a time: each becomes its own Desktop (Space).
  fs_ok=0; fs_bad=0
  if [ "$DRY_RUN" = 0 ]; then
    w=0
    while [ "$w" -lt "${#WIN_HEAD[@]}" ]; do
      marker="CC-DESK-$((w + 1))"; hd="${WIN_HEAD[$w]}"
      # The OS window's title is its ACTIVE pane's, and Claude Code repaints pane titles — so the
      # marker goes on every pane, and it is a title WE own rather than one we read.
      for p in ${WIN_PANES[$w]}; do k set-window-title --match "id:$p" "$marker" >/dev/null 2>&1; done
      k focus-window --match "id:$hd" >/dev/null 2>&1
      sleep "$SETTLE"
      r="$(fs_osa "$marker")"
      [ "$r" = true ] || { sleep "$SETTLE"; r="$(fs_osa "$marker")"; }
      if [ "$r" = true ]; then fs_ok=$((fs_ok + 1)); note "  [$marker] fullscreen (read back)"
      else fs_bad=$((fs_bad + 1)); note "  [$marker] NOT fullscreen (read back: ${r:-no answer}) — Accessibility for kitty?"; fi
      for p in ${WIN_PANES[$w]}; do k set-window-title --match "id:$p" "" >/dev/null 2>&1; done
      w=$((w + 1))
    done
    [ -n "${KITTY_WINDOW_ID:-}" ] && k focus-window --match "id:$KITTY_WINDOW_ID" >/dev/null 2>&1
  fi

  if [ "$DRY_RUN" = 1 ]; then verdict=ok
  elif [ "$launched" -eq 0 ]; then verdict=failed
  elif [ "$failed" -eq 0 ] && [ "$fs_bad" -eq 0 ] && [ "$shed" -eq 0 ]; then verdict=ok
  elif [ "$failed" -eq 0 ] && [ "$fs_bad" -eq 0 ]; then verdict=shed
  else verdict=degraded; fi
  printf 'cc-resume-layout: verdict=%s launched=%s shed=%s failed=%s windows=%s fullscreen_ok=%s fullscreen_failed=%s\n' \
    "$verdict" "$launched" "$shed" "$failed" "$nwin" "$fs_ok" "$fs_bad"
  [ "$verdict" = failed ] && exit 4
  exit 0
fi

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
    # EQUALIZE the group we just built. `equalize` is a TAB-level action and kitty routes those
    # through the FOCUSED tab, so this used to focus the head and sleep 1s purely to aim a bare
    # `kitty @ action`. `--self` aims it directly off KITTY_WINDOW_ID (measured 2026-09-19 — see
    # the `map cmd+shift+e` note in config/kitty.conf for the three-arm control), which drops both
    # the focus steal and the per-group second: recovering 5 groups no longer yanks the operator
    # through 5 OS windows. `--match` is NOT the alternative — it returns rc 0 and does nothing.
    KITTY_WINDOW_ID="$head_win" "$KITTY_BIN" @ action --self layout_action equalize >/dev/null 2>&1 \
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
