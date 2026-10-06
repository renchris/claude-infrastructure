#!/usr/bin/env bash
# cc-resume-layout.sh — lay a batch of resumed sessions out ONE OS WINDOW PER MONITOR, split panes
# inside each, instead of piling every session into tabs of the operator's own window.
#
#   Usage: cc-resume-layout.sh [--per-window N] [--stagger SECS] [--use-all-screens] [--dry-run]
#          cc-resume-layout.sh --desktops [--to unix:/path] [--per-window N<=4, <=6 with --restore] [--stagger SECS] [--restore [--tree FILE]] [--dry-run]
#          ... reading a TSV on stdin (or --file PATH):
#              account <TAB> session-id <TAB> worktree <TAB> branch [<TAB> label]
#          i.e. lr-select.py's own output, with an optional 5th label column. Under --restore the
#          W3 row contract adds 6 model, 7 effort, 8 group, 9 slot, 10 prompt_file, 11 permission_mode (a cell holding
#          only \037 is empty); a 5-column row behaves exactly as before.
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
#
# --desktops --restore (2026-10-04, W3 P3b; docs/research/session-durability-2026-10/W3-build-plan.md
# § P3b and § Amendment D): the unattended restore path. Nothing here runs without --restore, which
# only cc-restore and a restore-v2 reboot pass; the default path above keeps its 2x2 and AX loop.
#   · ONE ROW per OS window, at most 6 panes: a head, then each pane a vsplit next to the previous,
#     then `goto-layout horizontal` on the head's tab and scripts/kitty-equalize.py, whose
#     reset_window_sizes evens a horizontal tab out. `layout_action equalize` is never sent: it
#     exists only in splits and rings the bell in a horizontal tab (a1e4490ae).
#   · WAIT, NOT SHED: capacity is re-asked with the non-charging probe (cc_capacity_probe), so a wait
#     never spends the refusal budget that admits on the 3rd refusal; busy sessions are capped by
#     CC_ADMIT_RESTORE_R. Only CC_RESTORE_DEADLINE (30 min) sheds the rest.
#   · ORDER: heartbeat groups (columns 8-9) keep their own windows in slot order; without them, the
#     project grouping above. Rows with a prompt (column 10) launch last, so the load gate meets them
#     after the idle rows have settled.
#   · KITTY'S HEALTH: one `kitty @` call in flight (this loop never backgrounds one), 30 s of backoff
#     after a timed-out call, and the restore stops when kitty holds more than 180 fds (C3: its soft
#     limit is 256).
#   · PROOF: each launch prints `cc-resume-layout: map sid=<sid> wid=<wid> oswin=<n>` on stdout. A
#     launch that errored or timed out prints `maybe sid=…` and counts as restored only once the
#     session has a live holder (lr_holder_count) and its transcript gained a SessionStart:resume
#     record, re-checked for CC_RESTORE_MAYBE_S (at least 240 s).
#   · FULLSCREEN by kitty's own action, by window id: `action --match id:<head> toggle_fullscreen`
#     (kitty dispatches it to the matched window's OS window), 3 s apart. The verdict is the READ-BACK
#     (the window's frame fills its display, via hb_display_probe, polled up to
#     CC_RESTORE_FS_VERIFY=10 s); a window read back as windowed gets focus-window and ONE more
#     toggle. A refused toggle, or an unreadable state, is never re-toggled.
#
# --restore, LAYOUT FIDELITY (2026-10-05, W3 P7; plan § Amendment B gaps 2 and 3): when the heartbeat
# recorded kitty's tree, each window comes back as it was, and the one-row plan above is only the
# fallback for rows no tree places. Nothing here runs without --restore.
#   · THE TREE is hb.kitty-ls.json (scripts/lib/restore-heartbeat.sh): --tree FILE, else the newest one
#     under the heartbeat root for each kitty pid the rows' group column names (k<pid>w<os window>).
#     CC_RESTORE_TREE=off turns the replay off. A row is matched to its old pane through the
#     hb.roster.json beside the tree (paneUUID is the kitty window id).
#   · SPLITS: every tab's layout_state pairs are rebuilt with their orientation and bias. A pair is
#     made by splitting the pane already there: the new pane is the first leaf of the pair's second
#     half, launched --location=vsplit|hsplit --next-to it with kitty's own --bias (the share of the
#     NEW pane, in percent). So no equalize runs on a replayed splits tab; it would erase the biases.
#     A tab in another layout comes back as a row in group order, then goto-layout to that layout.
#   · TABS in their recorded order (launch --type=tab into the window). The first tab stays active:
#     focus-tab would pull the operator's focus across OS windows.
#   · PANES: one with a row resumes its session; a non-Claude pane is reopened as a shell in its
#     recorded cwd; a Claude pane with no row was not restored on purpose and is left out, its
#     neighbour taking the space as when kitty closes a window. A tree has no 6-pane cap.
#   · DISPLAY: hb.displays.tsv beside the tree maps each OS window to its display. Right after a
#     window's head opens it is moved there through System Events (found by a title marker held for
#     that one call), then fullscreen is toggled in the recorded window order, and only for windows
#     that were fullscreen. Without the file, or without Accessibility, the panes are still right
#     and only the placement is skipped, out loud.
#   · --dry-run --tree FILE reads files only, and with no rows on stdin takes them from the roster
#     beside the tree. It prints one `cc-resume-layout: tree oswin=… panes=… layout=… display=…`
#     line per window on stdout.
#   · A maybe row still gets no map line (plan § G), and a shell pane never does.
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
RESTORE=0             # --restore: the unattended restore path (W3)
TREE=""               # --tree FILE: the recorded kitty tree to replay (--restore only)
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
    --restore)         RESTORE=1; shift ;;
    --tree)            TREE="${2:?--tree needs a kitty ls JSON file}"; shift 2 ;;
    -h|--help)         sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0 ;;
    *)                 die "unknown argument: $1" ;;
  esac
done

if [ -n "$TREE" ]; then
  [ "$DESKTOPS" = 1 ] && [ "$RESTORE" = 1 ] || die "--tree needs --desktops --restore"
  [ -r "$TREE" ] || die "--tree: cannot read $TREE"
fi
# The tree dry run reads files only, so it needs no kitty binary.
[ -n "$TREE" ] && [ "$DRY_RUN" = 1 ] && [ -z "$KITTY_BIN" ] && KITTY_BIN=/usr/bin/true
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
done < <(if [ -n "$FILE" ]; then cat -- "$FILE"
         elif [ -n "$TREE" ] && [ "$DRY_RUN" = 1 ] && [ -t 0 ]; then :
         else cat; fi)

N=${#ROWS[@]}
# The tree dry run with no rows: one row per session in the roster recorded beside the tree.
if [ "$N" -eq 0 ] && [ -n "$TREE" ] && [ "$DRY_RUN" = 1 ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && ROWS+=("$line")
  done < <(python3 -c '
import json, sys
for e in json.load(open(sys.argv[1])):
    if e.get("session_id"):
        print("\t".join([str(e.get("account") or "?"), e["session_id"], e.get("cwd") or "\x1f", "\x1f",
                         str(e.get("name") or e["session_id"][:8]).replace("\t", " ").replace("\n", " ")]))
' "$(dirname "$TREE")/hb.roster.json" 2>/dev/null)
  N=${#ROWS[@]}
fi
[ "$N" -gt 0 ] || die "no rows on stdin — nothing to lay out"

# ── --desktops ──────────────────────────────────────────────────────────────────────────────────
if [ "$DESKTOPS" = 1 ]; then
  SETTLE="${CC_DESKTOP_SETTLE:-1.5}"
  FS_DELAY="${CC_DESKTOP_FS_DELAY:-2.5}"
  # 4 panes as a 2x2 on the default path; 6 in one row under --restore (the operator's 3-6 per window).
  PW_CAP=4; [ "$RESTORE" = 1 ] && PW_CAP=6
  [ "$PER_WINDOW" -ge 1 ] 2>/dev/null && [ "$PER_WINDOW" -le "$PW_CAP" ] || PER_WINDOW="$PW_CAP"

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
  # BOUNDED (2026-10-02, W3 P2): `kitty @` against a wedged socket never returns, and this runs
  # unattended from launchd, so one stuck call hung the whole restore. Every call now ends within
  # CC_RESUME_K_TIMEOUT seconds with rc 124: 120 s by default, 15 s only under --restore. The default
  # path is today's live reboot path, and a loaded kitty can take tens of seconds to answer a launch
  # (W3 amendment §C 3), so the tight bound waits for the restore path that is built around it.
  # Stock macOS has no timeout(1); without one, a perl alarm kills the call's whole process group
  # (a pipe held by a grandchild would hang `$(k …)`). CC_RESUME_K_TIMEOUT_BIN set to "" forces the
  # perl path (tests pin both).
  if [ "$RESTORE" = 1 ]; then K_TO="${CC_RESUME_K_TIMEOUT:-15}"; else K_TO="${CC_RESUME_K_TIMEOUT:-120}"; fi
  K_TOBIN="${CC_RESUME_K_TIMEOUT_BIN-$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null \
    || { [ -x /opt/homebrew/bin/timeout ] && printf '%s' /opt/homebrew/bin/timeout; })}"
  kb() {
    if [ -n "$K_TOBIN" ]; then "$K_TOBIN" "$K_TO" "$@"; return $?; fi
    /usr/bin/perl -e 'my $t = shift; my $pid = fork; exit 125 unless defined $pid;
      if ($pid == 0) { setpgrp(0, 0); exec { $ARGV[0] } @ARGV; exit 127 }
      $SIG{ALRM} = sub { kill "TERM", -$pid; select(undef, undef, undef, 0.5); kill "KILL", -$pid; exit 124 };
      alarm $t; waitpid($pid, 0); exit(($? & 127) ? 128 + ($? & 127) : $? >> 8)' "$K_TO" "$@"
  }
  k() { if [ -n "$SOCK" ]; then kb "$KITTY_BIN" @ --to "$SOCK" "$@"; else kb "$KITTY_BIN" @ "$@"; fi; }
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

  # ── --restore: its own planner, loop and fullscreen pass (the header's --restore paragraph) ──────
  if [ "$RESTORE" = 1 ]; then
    PAD=$'\037'                                   # boot-resume.sh's TSV_PAD: an empty cell
    R_WAIT="${CC_RESTORE_WAIT:-30}"; R_DEADLINE="${CC_RESTORE_DEADLINE:-1800}"
    R_BACKOFF="${CC_RESTORE_K_BACKOFF:-30}"; FD_MAX="${CC_RESTORE_FD_MAX:-180}"
    FS_GAP="${CC_RESTORE_FS_GAP:-3}"
    MAYBE_S="${CC_RESTORE_MAYBE_S:-240}"; MAYBE_POLL="${CC_RESTORE_MAYBE_POLL:-10}"
    RESTORE_R="${CC_ADMIT_RESTORE_R:-${CC_ADMIT_ACTIVE_CEILING:-8}}"
    LSOF_BIN="${CC_LSOF_BIN:-/usr/sbin/lsof}"
    HERE="$(dirname "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")")"
    cell() { local v; v="$(printf '%s' "$1" | cut -f"$2")"; [ "$v" = "$PAD" ] && v=""; printf '%s' "$v"; }

    # The equalizer runs INSIDE kitty, so it needs an absolute path.
    EQ_KITTEN="${CC_KITTY_EQUALIZE_KITTEN:-}"
    if [ -z "$EQ_KITTEN" ]; then
      for _eq in "$HERE/../scripts/kitty-equalize.py" "${HOME:-}/.claude/scripts/kitty-equalize.py"; do
        [ -f "$_eq" ] && { EQ_KITTEN="$(cd "$(dirname "$_eq")" && pwd -P)/$(basename "$_eq")"; break; }
      done
      unset _eq
    fi

    # lr_holder_count, for the maybe re-check. Absent ⇒ the transcript alone decides, and it says so.
    HOLDER_OK=0
    if [ "$DRY_RUN" = 0 ]; then
      for _lr in "$HERE/../scripts/limit-recover/lr-lib.sh" "${HOME:-}/.claude/scripts/limit-recover/lr-lib.sh"; do
        # shellcheck disable=SC1090  # runtime-resolved source; the ship gate runs shellcheck without -x
        if [ -f "$_lr" ] && . "$_lr" 2>/dev/null && command -v lr_holder_count >/dev/null 2>&1; then HOLDER_OK=1; break; fi
      done
      unset _lr
      [ "$HOLDER_OK" = 1 ] || note "cc-resume-layout: lr-lib.sh unreachable — maybe rows are judged by transcript alone"
    fi
    holders() { [ "$HOLDER_OK" = 1 ] && lr_holder_count "$1" 2>/dev/null; return 0; }
    # Every SessionStart:resume record across the account stores. Mirrored stores count twice both
    # before and after a launch, so a GAIN is still a gain.
    resume_marks() {
      local f c n=0
      for f in "${HOME:-}"/.claude*/projects/*/"$1".jsonl; do
        [ -f "$f" ] || continue
        c="$(grep -c '"hookName":"SessionStart:resume"' "$f" 2>/dev/null)"; n=$((n + ${c:-0}))
      done
      printf '%s\n' "$n"
    }
    # kitty's fd count; empty when unreadable. The pid is the one listen_on embeds (kitty.conf:
    # unix:/tmp/kitty-{kitty_pid}), else the KITTY_PID kitty exports into its panes.
    kitty_fds() {
      local pid="${CC_RESTORE_KITTY_PID:-}"
      if [ -z "$pid" ]; then
        case "$SOCK" in unix:*/kitty-*) pid="${SOCK##*/kitty-}" ;; esac
        case "$pid" in ''|*[!0-9]*) pid="${KITTY_PID:-}" ;; esac
      fi
      case "$pid" in ''|*[!0-9]*) return 0 ;; esac
      # A failed or empty lsof is BLIND, not zero fds: `lsof | grep -c` would print 0 for both.
      local out
      out="$("$LSOF_BIN" -nP -p "$pid" -Ff 2>/dev/null)" || return 0
      [ -n "$out" ] || return 0
      printf '%s\n' "$out" | grep -c '^f[0-9]' || true
    }
    # A kitty call from the main shell: after a timeout, back off before the next one.
    kr() {
      local rc=0
      k "$@" || rc=$?
      [ "$rc" = 124 ] && { note "cc-resume-layout: kitty @ $1 timed out — backing off ${R_BACKOFF}s"; sleep "$R_BACKOFF"; }
      return "$rc"
    }

    # The display probe lives in the heartbeat library (hb_display_probe). Absent ⇒ no window is moved.
    if [ "$DRY_RUN" = 0 ]; then
      for _hb in "$HERE/../scripts/lib/restore-heartbeat.sh" "${HOME:-}/.claude/scripts/lib/restore-heartbeat.sh"; do
        # shellcheck disable=SC1090  # runtime-resolved source; the ship gate runs shellcheck without -x
        [ -f "$_hb" ] && . "$_hb" 2>/dev/null && break
      done
      unset _hb
    fi

    # THE RECORDED TREES: --tree, else the newest heartbeat tree of each kitty the rows' groups name.
    TREES=()
    if [ -n "$TREE" ]; then TREES=("$TREE")
    elif [ "${CC_RESTORE_TREE:-}" != off ]; then
      hbroot="${CC_HEARTBEAT_DIR:-${HOME:-}/.claude/autonomy/heartbeat}"
      for kp in $(for r in "${ROWS[@]}"; do cell "$r" 8; echo; done | sed -n 's/^k\([0-9][0-9]*\)w[0-9][0-9]*$/\1/p' | sort -u); do
        best=""; bs=-1
        for f in "$hbroot"/*/"$kp"/hb.kitty-ls.json; do
          [ -f "$f" ] || continue
          st="$(head -n 1 "${f%/*}/hb.start" 2>/dev/null | awk '{ print $1 }')"
          case "$st" in ''|*[!0-9]*) st=0 ;; esac
          if [ "$st" -gt "$bs" ]; then best="$f"; bs="$st"; fi
        done
        [ -n "$best" ] && TREES+=("$best")
      done
    fi

    # PLAN, three kinds of line, fields separated by \037 (so an empty field keeps its place):
    #   W  window#  source  platform_window_id  tabs  panes  claude  shells  layout-signature
    #      then the window's hb.displays.tsv fields (uuid dx dy dw dh fullscreen wx wy ww wh) or 10 empties
    #   T  how many windows came from a recorded tree (they are numbered first, in recorded order)
    #   P  window#  tab  pane-key  row|shell  row-index  head|tab|vsplit|hsplit  anchor-key  bias
    #      shell-cwd  group-label  keep|<layout to go to>      — in launch order
    # Windows holding a prompt row (column 10) launch last, and inside a project window so do those rows.
    PLAN="$(i=0; for r in "${ROWS[@]}"; do
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$i" "$(cell "$r" 3)" "$(cell "$r" 8)" "$(cell "$r" 9)" "$(cell "$r" 10)" "$(cell "$r" 2)"
        i=$((i + 1)); done \
      | python3 -c '
import json, os, subprocess, sys
per = int(sys.argv[1]); trees = [t for t in sys.argv[2:] if t]
S = "\x1f"
def key(wt):
    try:
        out = subprocess.run(["git", "-C", wt, "rev-parse", "--path-format=absolute", "--git-common-dir"],
                             capture_output=True, text=True, timeout=10)
        if out.returncode == 0 and out.stdout.strip():
            return os.path.basename(os.path.dirname(out.stdout.strip().rstrip("/")))
    except Exception:
        pass
    return os.path.basename(wt.rstrip("/")) or "?"
def slot(r):
    try:
        return (0, int(r[1]), r[0])
    except ValueError:
        return (1, 0, r[0])
rows = []
for line in sys.stdin:
    f = line.rstrip("\n").split("\t") + [""] * 6
    rows.append((int(f[0]), f[1], f[2], f[3], 1 if f[4] else 0, f[5]))
by_sid = {r[5]: r for r in rows if r[5]}
used = set()

# ── recorded trees: a window is a list of tabs, a tab is (layout, node); a node is a leaf
#    {"leaf": ("row", index, prompt) | ("shell", cwd)} or a pair {"h", "bias", "one", "two"} ──
def sig(n):
    if "leaf" in n:
        return "p"
    b = n["bias"]
    return "%s%s(%s,%s)" % ("H" if n["h"] else "V", "" if abs(b - 0.5) < 0.005 else ":%.2f" % b, sig(n["one"]), sig(n["two"]))
def leaves(n):
    return [n["leaf"]] if "leaf" in n else leaves(n["one"]) + leaves(n["two"])
def first(n):
    return n if "leaf" in n else first(n["one"])
def chain(ls):   # a row of panes: what head + vsplit-beside-the-previous builds
    n = {"leaf": ls[-1]}
    for l in reversed(ls[:-1]):
        n = {"h": True, "bias": 0.5, "one": {"leaf": l}, "two": n}
    return n
def load(path):
    try:
        data = json.load(open(path))
    except Exception:
        return None
    if not isinstance(data, list):
        return None
    d = os.path.dirname(os.path.abspath(path))
    pane_sid, disp = {}, {}
    try:
        for e in json.load(open(os.path.join(d, "hb.roster.json"))):
            if e.get("session_id") and e.get("paneUUID") not in (None, ""):
                pane_sid[str(e["paneUUID"])] = e["session_id"]
    except Exception:
        pass
    try:
        for line in open(os.path.join(d, "hb.displays.tsv")):
            f = line.rstrip("\n").split("\t")
            if len(f) == 11:
                disp[f[0]] = f[1:]
    except Exception:
        pass
    kp = os.path.basename(d)
    return data, pane_sid, disp, (kp if kp.isdigit() else "tree")
def tab_node(t, pane_sid):
    wmap = {w.get("id"): w for w in t.get("windows") or [] if isinstance(w, dict)}
    st = t.get("layout_state") or {}
    gl = ((st.get("all_windows") or {}).get("window_groups")
          or [{"id": g.get("id"), "window_ids": g.get("windows")} for g in t.get("groups") or []]
          or [{"id": w, "window_ids": [w]} for w in wmap])
    groups = {g.get("id"): [w for w in g.get("window_ids") or [] if w in wmap] for g in gl}
    def leaf(gid):
        wids = groups.get(gid) or []
        if not wids:
            return None
        for w in wids:                      # a Claude pane that has a row
            sid = pane_sid.get(str(w))
            if sid in by_sid and sid not in used:
                used.add(sid); r = by_sid[sid]
                return {"leaf": ("row", r[0], r[4])}
        if not pane_sid:                    # no roster beside the tree: find the sid in the pane itself
            blob = json.dumps([[wmap[w].get(k) for k in ("cmdline", "last_reported_cmdline", "foreground_processes", "user_vars")] for w in wids])
            for sid, r in by_sid.items():
                if sid not in used and sid in blob:
                    used.add(sid)
                    return {"leaf": ("row", r[0], r[4])}
        if any(str(w) in pane_sid for w in wids):
            return None                     # a Claude pane with no row: its session is not being restored
        return {"leaf": ("shell", wmap[wids[-1]].get("cwd") or "")}
    def build(x):
        if x is None or isinstance(x, bool):
            return None
        if isinstance(x, int):
            return leaf(x)
        a, b = build(x.get("one")), build(x.get("two"))
        if a is None or b is None:
            return a or b                   # the pane that stays takes the space of the pair, as kitty does
        try:
            bias = min(0.99, max(0.01, float(x.get("bias", 0.5))))
        except (TypeError, ValueError):
            bias = 0.5
        return {"h": x.get("horizontal", True) is not False, "bias": bias, "one": a, "two": b}
    name = t.get("layout") or "splits"
    if st.get("class") == "Splits" and isinstance(st.get("pairs"), dict):
        n = build(st["pairs"])
        return ("splits", n) if n else None
    ls = [l for l in (leaf(g.get("id")) for g in gl) if l]
    if not ls:
        return None
    # A stack tab shows one pane and keeps no record of the splits under it: bring it back as a row.
    return ("horizontal" if name in ("stack", "splits") else name, chain([l["leaf"] for l in ls]))

wins = []          # {"src", "pwid", "disp", "tabs": [(layout, node)], "grp", "prompt"}
for path in trees:
    got = load(path)
    if got is None:
        print("cc-resume-layout: tree unreadable, ignored: %s" % path, file=sys.stderr)
        continue
    data, pane_sid, disp, kp = got
    for o in data:
        if not isinstance(o, dict):
            continue
        tabs = [tn for tn in (tab_node(t, pane_sid) for t in o.get("tabs") or [] if isinstance(t, dict)) if tn]
        if not tabs:
            continue
        pwid = str(o.get("platform_window_id") or "")
        src = "k%sw%s" % (kp, o.get("id"))
        ls = [l for _, n in tabs for l in leaves(n)]
        wins.append({"src": src, "pwid": pwid, "disp": disp.get(pwid), "tabs": tabs, "grp": src,
                     "prompt": any(l[0] == "row" and l[2] for l in ls)})
ntree = len(wins)

# ── rows no tree placed: one row of panes per window (P3b). Heartbeat groups (column 8) keep their
#    own windows in slot order (column 9); the rest pack by project. ──
groups, order = {}, []
for i, wt, grp, sl, prompt, sid in rows:
    if sid in used:
        continue
    k = ("hb", grp) if grp else ("proj", key(wt) if wt else "?")
    if k not in groups:
        groups[k] = []; order.append(k)
    groups[k].append((i, sl, prompt))
fb, chunks = [], []
for k in order:
    rs = groups[k]
    if k[0] == "hb":
        rs = sorted(rs, key=slot)
        fb += [(rs[j:j + per], [k[1]]) for j in range(0, len(rs), per)]
    else:
        rs = sorted(rs, key=lambda r: (r[2], r[0]))
        chunks += [(k[1], rs[j:j + per]) for j in range(0, len(rs), per)]
chunks.sort(key=lambda c: -len(c[1]))
bins = []
for g, rs in chunks:
    for b in bins:
        if len(b[0]) + len(rs) <= per:
            b[0].extend(rs); b[1].append(g); break
    else:
        bins.append([list(rs), [g]])
fb += [(sorted(rs, key=lambda r: r[2]), gs) for rs, gs in bins]
fb.sort(key=lambda w: any(r[2] for r in w[0]))
for rs, gs in fb:
    wins.append({"src": "plan", "pwid": "", "disp": None, "grp": "+".join(gs),
                 "tabs": [("horizontal", chain([("row", r[0], r[2]) for r in rs]))],
                 "prompt": any(r[2] for r in rs)})
for n, w in enumerate(wins, 1):
    w["n"] = n

# ── ops. A pair is built by splitting the pane that is already there: the new pane is the first
#    leaf of the second half of the pair, and the --bias of kitty gives it the share of that half. ──
nkey = [0]
def emit(w, ti, layout, node):
    ops, sim = [], {}
    def op(leaf, how, anchor, bias=""):
        nkey[0] += 1; k = nkey[0]
        kind, a, b = leaf if leaf[0] == "row" else (leaf[0], "", leaf[1])
        ops.append([str(w["n"]), str(ti), str(k), kind, str(a), how, str(anchor), bias,
                    b if kind == "shell" else "", w["grp"], "keep" if layout == "splits" else layout])
        return k
    def grow(n, anchor):
        if "leaf" in n:
            return
        bias = "" if abs(n["bias"] - 0.5) < 1e-9 else "%.4f" % ((1 - n["bias"]) * 100)
        k = op(first(n["two"])["leaf"], "vsplit" if n["h"] else "hsplit", anchor, bias)
        grow(n["one"], anchor); grow(n["two"], k)
    grow(node, op(first(node)["leaf"], "head" if ti == 0 else "tab", "" if ti == 0 else w["head"]))
    if ti == 0:
        w["head"] = int(ops[0][2])
    # Replay the ops the way Pair.split_and_add in kitty does, and refuse a plan that would not
    # rebuild the recorded shape.
    def split(n, o):
        if "leaf" in n:
            if n["leaf"] != o[6]:
                return n
            return {"h": o[5] == "vsplit", "bias": 1 - float(o[7]) / 100 if o[7] else 0.5, "one": n, "two": {"leaf": o[2]}}
        return dict(n, one=split(n["one"], o), two=split(n["two"], o))
    built = {"leaf": ops[0][2]}
    for o in ops[1:]:
        built = split(built, o)
    if sig(built) != sig(node):
        raise SystemExit("cc-resume-layout: planner bug: %s would rebuild %s, recorded %s" % (w["src"], sig(built), sig(node)))
    return ops
out = []
for w in wins:
    w["ops"] = [o for ti, (layout, node) in enumerate(w["tabs"]) for o in emit(w, ti, layout, node)]
    ls = [l for _, n in w["tabs"] for l in leaves(n)]
    out.append(S.join(["W", str(w["n"]), w["src"], w["pwid"], str(len(w["tabs"])), str(len(ls)),
                       str(sum(1 for l in ls if l[0] == "row")), str(sum(1 for l in ls if l[0] == "shell")),
                       ";".join("%s:%s" % (lay, sig(n)) for lay, n in w["tabs"])] + (w["disp"] or [""] * 10)))
out.append(S.join(["T", str(ntree)]))
for w in sorted(wins, key=lambda w: w["prompt"]):      # windows holding a prompt row launch last
    out += [S.join(["P"] + o) for o in w["ops"]]
print("\n".join(out))
' "$PER_WINDOW" ${TREES[@]+"${TREES[@]}"})" || die "the window planner failed"

    # The non-charging probe; a library too old to carry it falls back to the charging admit, loudly.
    PROBE_FN=cc_capacity_probe
    if [ "$CC_ADMIT_OK" = 1 ] && ! command -v cc_capacity_probe >/dev/null 2>&1; then
      PROBE_FN=cc_capacity_admit
      note "cc-resume-layout: capacity-admit.sh has no cc_capacity_probe — each wait now spends the refusal budget"
    fi
    t0=$SECONDS; stopped=none; fd_blind=0
    launched=0; failed=0; shed=0; nwin=0; nshell=0; placed=0; place_bad=0
    WIN_HEAD=(); WIN_NUM=(); MAYBE_SID=(); MAYBE_BASE=(); WIDS=(); WDISP=(); WFS=()
    NTREE=0
    while IFS=$'\037' read -r _t wn src pwid ntabs npanes nclaude nsh lsig duuid ddx ddy ddw ddh dfs dwx dwy dww dwh; do
      case "$_t" in
        T) NTREE="$wn" ;;
        W) [ -n "$duuid" ] && { WDISP[wn]="$duuid $ddx $ddy $ddw $ddh $dfs $dwx $dwy $dww $dwh"; WFS[wn]="$dfs"; }
           # The dry run's answer for the operator's preview: what each window comes back as.
           if [ "$DRY_RUN" = 1 ] && [ "${#TREES[@]}" -gt 0 ]; then
             printf 'cc-resume-layout: tree oswin=%s src=%s platform_window_id=%s tabs=%s panes=%s claude=%s shells=%s layout=%s display=%s display_rect=%s fullscreen=%s\n' \
               "$wn" "$src" "${pwid:-none}" "$ntabs" "$npanes" "$nclaude" "$nsh" "$lsig" "${duuid:-unrecorded}" \
               "$([ -n "$duuid" ] && printf '%s,%s,%sx%s' "$ddx" "$ddy" "$ddw" "$ddh" || printf none)" "${dfs:-unrecorded}"
           fi ;;
      esac
    done <<EOF
$PLAN
EOF
    [ "${#TREES[@]}" -gt 0 ] && note "cc-resume-layout: replaying $NTREE recorded window(s) from ${TREES[*]}"

    # The displays attached now, read once and only when a window has a display to go back to.
    CUR_DISPLAYS=""
    if [ "$DRY_RUN" = 0 ] && [ "${#WDISP[@]}" -gt 0 ]; then
      if command -v hb_display_probe >/dev/null 2>&1; then
        CUR_DISPLAYS="$(CC_HB_SWIFT_BIN="$SWIFT_BIN" hb_display_probe 2>/dev/null)" || CUR_DISPLAYS=""
      fi
      [ -n "$CUR_DISPLAYS" ] || note "cc-resume-layout: the attached displays are unreadable — windows open where kitty puts them"
    fi
    # place_window <window#> <head pane> — put a new OS window on its recorded display, before any
    # fullscreen. A window that was fullscreen only has to land on the display; one that was not gets
    # its old frame back. A display is matched by uuid, else by identical bounds, else left alone.
    place_window() {
      local n="$1" wid="$2" rec="${WDISP[$1]:-}" uuid dx dy dw dh fs wx wy ww wh cur cx cy cw ch x y w h marker r
      [ -n "$rec" ] || return 0
      read -r uuid dx dy dw dh fs wx wy ww wh <<EOF
$rec
EOF
      if [ "$DRY_RUN" = 1 ]; then
        note "DRY [CC-DESK-$n] place on display $uuid ($dx,$dy ${dw}x${dh})$([ "$fs" = 1 ] || printf ' at %s,%s %sx%s' "$wx" "$wy" "$ww" "$wh")"
        return 0
      fi
      [ -n "$CUR_DISPLAYS" ] || return 0
      cur="$(printf '%s\n' "$CUR_DISPLAYS" | awk -F'\t' -v u="$uuid" '$1 == u { print $2, $3, $4, $5; exit }')"
      [ -n "$cur" ] || cur="$(printf '%s\n' "$CUR_DISPLAYS" | awk -F'\t' -v a="$dx" -v b="$dy" -v c="$dw" -v d="$dh" \
        '$2 == a && $3 == b && $4 == c && $5 == d { print $2, $3, $4, $5; exit }')"
      if [ -z "$cur" ]; then
        place_bad=$((place_bad + 1)); note "  [CC-DESK-$n] display $uuid is not attached — window left where kitty put it"
        return 0
      fi
      read -r cx cy cw ch <<EOF
$cur
EOF
      if [ "$fs" = 1 ]; then x=$((cx + 20)); y=$((cy + 45)); w=$((cw - 40)); h=$((ch - 90))
      else x=$((cx + wx - dx)); y=$((cy + wy - dy)); w="$ww"; h="$wh"; fi
      marker="CC-DESK-$n-$$"
      kr set-window-title --match "id:$wid" "$marker" >/dev/null 2>&1
      sleep "$SETTLE"
      r="$(kb "$OSASCRIPT" <<EOF 2>/dev/null
tell application "System Events" to tell process "kitty"
  repeat with x in windows
    if name of x contains "$marker" then
      set position of x to {$x, $y}
      set size of x to {$w, $h}
      return "ok"
    end if
  end repeat
  return "nomatch"
end tell
EOF
)"
      kr set-window-title --match "id:$wid" "" >/dev/null 2>&1
      if [ "$r" = ok ]; then placed=$((placed + 1)); note "  [CC-DESK-$n] placed on display $uuid at $x,$y ${w}x${h}"
      else place_bad=$((place_bad + 1)); note "  [CC-DESK-$n] NOT placed (${r:-no answer}) — Accessibility for kitty? The panes are right, the display is not"; fi
    }

    cur=""; ctab=""; head=""; thead=""; tlast=""; tfin=""
    close_restore_tab() { # a replayed splits tab stays as built; any other becomes its layout, then even widths
      [ -n "$thead" ] || return 0
      [ "$tfin" = keep ] && return 0
      if [ "$DRY_RUN" = 1 ]; then
        note "DRY [CC-DESK-$cur] goto-layout --match window_id:$thead $tfin"
        note "DRY [CC-DESK-$cur] kitten ${EQ_KITTEN:-kitty-equalize.py} (reset_window_sizes)"
      else
        kr goto-layout --match "window_id:$thead" "$tfin" >/dev/null 2>&1 \
          || note "  [CC-DESK-$cur] goto-layout $tfin refused — the panes stay as splits"
        if [ -z "$EQ_KITTEN" ]; then
          note "  [CC-DESK-$cur] scripts/kitty-equalize.py not found — panes may be uneven"
        else
          KITTY_WINDOW_ID="$thead" kr action --self kitten "$EQ_KITTEN" >/dev/null 2>&1 \
            || note "  [CC-DESK-$cur] equalize kitten refused — panes may be uneven"
        fi
      fi
    }
    close_restore_window() {
      close_restore_tab
      [ -n "$head" ] || return 0
      WIN_HEAD+=("$head"); WIN_NUM+=("$cur"); nwin=$((nwin + 1))
    }
    while IFS=$'\037' read -r _t win tab key kind idx how anc bias pcwd grp fin; do
      [ "$_t" = P ] || continue
      if [ "$win" != "$cur" ]; then close_restore_window; cur="$win"; ctab="$tab"; head=""; thead=""; tlast=""
      elif [ "$tab" != "$ctab" ]; then close_restore_tab; ctab="$tab"; thead=""; tlast=""; fi
      tfin="$fin"
      acct=""; sid=""; wt="$pcwd"; br=""; model=""; effort=""; prompt_file=""; pmode=""
      if [ "$kind" = row ]; then
        row="${ROWS[$idx]}"
        acct="$(cell "$row" 1)"; sid="$(cell "$row" 2)"; wt="$(cell "$row" 3)"; br="$(cell "$row" 4)"
        model="$(cell "$row" 6)"; effort="$(cell "$row" 7)"
        prompt_file="$(cell "$row" 10)"; pmode="$(cell "$row" 11)"   # P4: handed to reso-resume-one as they are
        # reso-resume-one exits 2 on an effort it does not know, after the pane is already open.
        case "$effort" in ''|low|medium|high|xhigh|max) ;; *) note "cc-resume-layout: effort '$effort' for $sid is not one reso-resume-one takes — dropped"; effort="" ;; esac
        case "$model" in *[!A-Za-z0-9._-]*) note "cc-resume-layout: model '$model' for $sid is malformed — dropped"; model="" ;; esac
      fi
      if [ "$DRY_RUN" = 1 ]; then
        at=""; [ -n "$anc" ] && [ "$how" != tab ] && at=" next-to=#$anc"
        if [ "$kind" = row ]; then
          note "DRY [CC-DESK-$win $grp] $how $acct $sid $wt${model:+ model=$model}${effort:+ effort=$effort}${pmode:+ permission_mode=$pmode}${prompt_file:+ prompt_file=$prompt_file} pane=#$key$at${bias:+ bias=$bias}"
        else
          note "DRY [CC-DESK-$win $grp] $how shell $wt pane=#$key$at${bias:+ bias=$bias}"
        fi
        if [ -z "$head" ]; then head="<head of CC-DESK-$win>"; place_window "$win" "$head"; fi
        [ -n "$thead" ] || { thead="<head of CC-DESK-$win>"; [ "$tab" = 0 ] || thead="<head of CC-DESK-$win tab $tab>"; }
        continue
      fi
      [ "$stopped" = none ] || { [ "$kind" = row ] && shed=$((shed + 1)); continue; }
      # CAPACITY: re-ask the same row with the probe until it admits, or the deadline passes.
      # Only rc 9 is a refusal worth waiting on; any other rc is the probe failing, and it is admitted
      # out loud rather than mistaken for a full box until the deadline sheds everything. A shell
      # pane is not a session and is never asked about.
      if [ "$kind" = row ] && [ "$CC_ADMIT_OK" = 1 ]; then
        while :; do
          prc=0; CC_ADMIT_RESTORE_R="$RESTORE_R" "$PROBE_FN" cc-resume-layout "restore ${sid} on ${acct}" || prc=$?
          [ "$prc" = 9 ] || {
            [ "$prc" = 0 ] || note "cc-resume-layout: capacity probe failed (rc $prc) for $sid — launching it UNGATED"
            break
          }
          if [ $((SECONDS - t0)) -ge "$R_DEADLINE" ]; then
            stopped=deadline; note "cc-resume-layout: SHED — ${R_DEADLINE}s deadline passed: $(cc_capacity_admit_reason)"; break
          fi
          note "cc-resume-layout: WAIT ${R_WAIT}s, then re-ask for $sid — $(cc_capacity_admit_reason)"
          sleep "$R_WAIT"
        done
        [ "$stopped" = none ] || { shed=$((shed + 1)); continue; }
      fi
      fds="$(kitty_fds)"
      case "$fds" in
        ''|*[!0-9]*) [ "$fd_blind" = 1 ] || { note "cc-resume-layout: kitty fd count unreadable — the fd guard is blind"; fd_blind=1; } ;;
        *) if [ "$fds" -gt "$FD_MAX" ]; then
             stopped=fd; note "cc-resume-layout: STOP — kitty holds $fds fds (> $FD_MAX); the rest are shed"
             [ "$kind" = row ] && shed=$((shed + 1))
             continue
           fi ;;
      esac
      # WHERE: beside the pane the plan names. When that pane never opened (a maybe, or shed), the
      # last pane of this tab stands in; with none, the pane opens the tab, or the window, itself.
      a=""
      case "$how" in
        head) ;;
        tab) a="$head" ;;
        *) [ -n "$anc" ] && a="${WIDS[$anc]:-}"
           [ -n "$a" ] || a="$tlast"
           [ -n "$a" ] || { how=tab; a="$head"; } ;;
      esac
      [ "$how" = tab ] && [ -z "$a" ] && how="head"
      LA=(launch --keep-focus)
      case "$how" in
        head) LA+=(--type=os-window) ;;
        tab) LA+=(--type=tab --match "window_id:$a") ;;
        *) LA+=("--location=$how" --match "window_id:$a" --next-to "id:$a")
           [ -n "$bias" ] && LA+=(--bias "$bias") ;;
      esac
      { [ -n "$wt" ] && [ -d "$wt" ]; } && LA+=(--cwd "$wt")
      if [ "$kind" = row ]; then
        base="$(resume_marks "$sid")"
        # The spawn goes through reso-resume-one, which wraps claude in cc-close-attrib (P2); the cert
        # store is set here as well so no keychain read can stall a restore.
        cmd="'env' 'CC_ADMIT_DONE=1' 'CLAUDE_CODE_CERT_STORE=bundled'"
        [ -n "$model" ] && cmd="$cmd $(shq "CC_RESUME_MODEL=$model")"
        cmd="$cmd $(shq "$RESUME_ONE") $(shq "$acct") $(shq "$wt") $(shq "$sid")"
        [ -n "$br" ] && cmd="$cmd $(shq "$br")"
        [ -n "$effort" ] && cmd="$cmd '--effort' $(shq "$effort")"
        [ -n "$pmode" ] && cmd="$cmd '--permission-mode' $(shq "$pmode")"
        [ -n "$prompt_file" ] && cmd="$cmd '--prompt-file' $(shq "$prompt_file")"
        LA+=(--env CC_ADMIT_DONE=1 --env CLAUDE_CODE_CERT_STORE=bundled -- zsh -ic "$cmd || exec zsh -i")
      fi
      # A shell pane takes no command: kitty starts its configured shell in the recorded cwd.
      rc=0; wid="$(k "${LA[@]}" 2>&1)" || rc=$?
      case "$wid" in
        ''|*[!0-9]*)
          if [ "$kind" = row ]; then
            printf 'cc-resume-layout: maybe sid=%s rc=%s\n' "$sid" "$rc"
            note "cc-resume-layout: launch unconfirmed for $sid (rc $rc): $wid — re-checked after the batch"
            MAYBE_SID+=("$sid"); MAYBE_BASE+=("$base")
          else
            note "cc-resume-layout: shell pane in ${wt:-?} did not open (rc $rc): $wid"
          fi
          [ "$rc" = 124 ] && { note "cc-resume-layout: backing off ${R_BACKOFF}s after the timeout"; sleep "$R_BACKOFF"; }
          continue ;;
      esac
      what="sid=$sid acct=$acct"; [ "$kind" = row ] || what="shell"
      case "$how" in
        head) cc_log_pane_spawn os-window kitty "$wid" "$wt" "resume-layout CC-DESK-$win restore head $what" ;;
        tab) cc_log_pane_spawn tab kitty "$wid" "$wt" "resume-layout CC-DESK-$win restore tab $tab $what" ;;
        *) cc_log_pane_spawn split kitty "$wid" "$wt" "resume-layout CC-DESK-$win restore $how $what" ;;
      esac
      WIDS[key]="$wid"; tlast="$wid"
      [ -n "$thead" ] || thead="$wid"
      if [ -z "$head" ]; then head="$wid"; place_window "$win" "$wid"; fi
      if [ "$kind" = row ]; then
        launched=$((launched + 1))
        printf 'cc-resume-layout: map sid=%s wid=%s oswin=%s\n' "$sid" "$wid" "$win"
        note "  [CC-DESK-$win $grp] win $wid  $acct  $(basename "$wt")"
        sleep "$STAGGER"
      else
        nshell=$((nshell + 1)); note "  [CC-DESK-$win $grp] win $wid  shell  ${wt:-?}"
      fi
    done <<EOF
$PLAN
EOF
    close_restore_window

    # FULLSCREEN by id, paced: back-to-back toggles are dropped, and a second toggle undoes the first.
    # In window-number order, which for replayed windows is the recorded order; a window recorded as
    # not fullscreen is left windowed.
    # rc 0 from the toggle only says kitty took the request: on 2026-10-05 all five accepted toggles
    # left their windows on the main Desktop (fullscreen_ok=5). So the verdict is the READ-BACK —
    # the window's CGWindow frame filling its display (hb_display_probe's fullscreen column) — and a
    # window read back as windowed gets ONE more toggle after focus-window. Never re-toggled without
    # a positive "windowed" reading, since a second toggle would undo a first that landed late.
    # No probe or no frame ⇒ unknown, counted as before (by rc) and said so.
    fs_state() { # <head pane> → 1 | 0 | "" — this pane's OS window, fullscreen per its frame
      local pwid
      command -v hb_display_probe >/dev/null 2>&1 || return 0
      pwid="$(kr ls 2>/dev/null | python3 -c 'import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for o in data:
    if any(w.get("id") == int(sys.argv[1]) for t in o.get("tabs") or [] for w in t.get("windows") or []):
        print(o.get("platform_window_id") or "")
        break' "$1" 2>/dev/null)"
      [ -n "$pwid" ] || return 0
      CC_HB_SWIFT_BIN="$SWIFT_BIN" hb_display_probe "$pwid" 2>/dev/null | awk -F'\t' -v p="$pwid" '$1 == p { print $7; exit }'
    }
    fs_settled() { # <head pane> → fs_state, polled up to FS_VERIFY s while it reads windowed
      local s t=0
      while :; do
        s="$(fs_state "$1")"
        [ "$s" = 0 ] && [ "$t" -lt "$FS_VERIFY" ] || { printf '%s' "$s"; return 0; }
        sleep 1; t=$((t + 1))
      done
    }
    FS_VERIFY="${CC_RESTORE_FS_VERIFY:-10}"
    fs_ok=0; fs_bad=0
    for w in $(j=0; while [ "$j" -lt "${#WIN_HEAD[@]}" ]; do printf '%s %s\n' "${WIN_NUM[$j]}" "$j"; j=$((j + 1)); done | sort -n | cut -d' ' -f2); do
      hd="${WIN_HEAD[$w]}"; n="${WIN_NUM[$w]}"
      if [ "${WFS[$n]:-1}" = 0 ]; then
        note "$([ "$DRY_RUN" = 1 ] && printf 'DRY' || printf ' ') [CC-DESK-$n] left windowed, as recorded"
      elif [ "$DRY_RUN" = 1 ]; then
        note "DRY [CC-DESK-$n] action --match id:$hd toggle_fullscreen"
      elif kr action --match "id:$hd" toggle_fullscreen >/dev/null 2>&1; then
        sleep "$FS_GAP"; st="$(fs_settled "$hd")"
        if [ "$st" = 0 ]; then
          note "  [CC-DESK-$n] window $hd still windowed after its toggle — focusing it and toggling once more"
          kr focus-window --match "id:$hd" >/dev/null 2>&1
          kr action --match "id:$hd" toggle_fullscreen >/dev/null 2>&1
          sleep "$FS_GAP"; st="$(fs_settled "$hd")"
        fi
        case "$st" in
          1) fs_ok=$((fs_ok + 1)); note "  [CC-DESK-$n] fullscreen (read back, window $hd)" ;;
          0) fs_bad=$((fs_bad + 1)); note "  [CC-DESK-$n] NOT fullscreen after two toggles (read back, window $hd)" ;;
          *) fs_ok=$((fs_ok + 1)); note "  [CC-DESK-$n] fullscreen toggled (window $hd; not read back — no display probe)" ;;
        esac
      else
        fs_bad=$((fs_bad + 1)); note "  [CC-DESK-$n] toggle_fullscreen refused for window $hd — not re-toggled"; sleep "$FS_GAP"
      fi
    done
    # Only a replay prints this line, so the default restore's stdout is still map lines then verdict.
    [ "${#TREES[@]}" -gt 0 ] && printf 'cc-resume-layout: layout tree_windows=%s shells=%s placed=%s placed_failed=%s\n' \
      "$NTREE" "$nshell" "$placed" "$place_bad"

    # MAYBE rows: restored only with a live holder AND a new SessionStart:resume record.
    maybe_left=0
    if [ "${#MAYBE_SID[@]}" -gt 0 ]; then
      note "cc-resume-layout: re-checking ${#MAYBE_SID[@]} maybe row(s) for up to ${MAYBE_S}s"
      MSTATE=(); j=0; while [ "$j" -lt "${#MAYBE_SID[@]}" ]; do MSTATE+=(open); j=$((j + 1)); done
      t1=$SECONDS
      while :; do
        open=0; j=0
        while [ "$j" -lt "${#MAYBE_SID[@]}" ]; do
          if [ "${MSTATE[$j]}" = open ]; then
            h="$(holders "${MAYBE_SID[$j]}")"
            if [ "$(resume_marks "${MAYBE_SID[$j]}")" -gt "${MAYBE_BASE[$j]}" ] && { [ -z "$h" ] || [ "$h" -ge 1 ]; }; then
              MSTATE[j]=restored
            else
              open=$((open + 1))
            fi
          fi
          j=$((j + 1))
        done
        [ "$open" -gt 0 ] && [ $((SECONDS - t1)) -lt "$MAYBE_S" ] || break
        sleep "$MAYBE_POLL"
      done
      j=0
      while [ "$j" -lt "${#MAYBE_SID[@]}" ]; do
        st="${MSTATE[$j]}"; h="$(holders "${MAYBE_SID[$j]}")"
        if [ "$st" = open ]; then
          if [ "$h" = 0 ]; then st=failed; failed=$((failed + 1)); else st=unconfirmed; maybe_left=$((maybe_left + 1)); fi
        else
          launched=$((launched + 1))
        fi
        printf 'cc-resume-layout: maybe-resolved sid=%s state=%s holders=%s\n' "${MAYBE_SID[$j]}" "$st" "${h:-unknown}"
        j=$((j + 1))
      done
    fi

    if [ "$DRY_RUN" = 1 ]; then verdict=ok
    elif [ "$launched" -eq 0 ] && [ "$maybe_left" -eq 0 ]; then verdict=failed
    elif [ "$failed" -eq 0 ] && [ "$fs_bad" -eq 0 ] && [ "$maybe_left" -eq 0 ] && [ "$shed" -eq 0 ]; then verdict=ok
    elif [ "$failed" -eq 0 ] && [ "$fs_bad" -eq 0 ] && [ "$maybe_left" -eq 0 ]; then verdict=shed
    else verdict=degraded; fi
    printf 'cc-resume-layout: verdict=%s launched=%s shed=%s failed=%s windows=%s fullscreen_ok=%s fullscreen_failed=%s maybe=%s stopped=%s\n' \
      "$verdict" "$launched" "$shed" "$failed" "$nwin" "$fs_ok" "$fs_bad" "$maybe_left" "$stopped"
    [ "$verdict" = failed ] && exit 4
    exit 0
  fi

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
    # `||`: rc 0 is reso-resume-one's "ended on purpose, close the pane" (scripts/boot-resume-launch.sh
    # carries the why); every failure keeps the shell.
    LA+=(--env CC_ADMIT_DONE=1 -- zsh -ic "$cmd || exec zsh -i")
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
