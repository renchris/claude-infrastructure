#!/usr/bin/env bash
# cc-resume-layout.sh — lay a batch of resumed sessions out ONE OS WINDOW PER MONITOR, split panes
# inside each, instead of piling every session into tabs of the operator's own window.
#
#   Usage: cc-resume-layout.sh [--per-window N] [--stagger SECS] [--use-all-screens] [--dry-run]
#          cc-resume-layout.sh --desktops [--to unix:/path] [--per-window N<=4, <=6 with --restore] [--stagger SECS] [--restore [--tree FILE] [--keep-shells]] [--dry-run]
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
#     project grouping above. Windows launch most-prompted first, and inside a project window rows
#     with a prompt (column 10) come first: a prompted session was cut off with work in hand, and
#     launching it last cost about 90 s per prompted row at the 2026-10-21 restore (R17; the load
#     gate that ordering once deferred to is gone).
#   · KITTY'S HEALTH: one `kitty @` call in flight (this loop never backgrounds one), 30 s of backoff
#     after a timed-out call, and the restore stops when kitty holds more than 180 fds (C3: its soft
#     limit is 256).
#   · PROOF: each launch prints `cc-resume-layout: map sid=<sid> wid=<wid> oswin=<n>` on stdout. A
#     launch that errored or timed out prints `maybe sid=…` and counts as restored only once the
#     session has a live holder (lr_holder_count) and its transcript gained a SessionStart:resume
#     record, re-checked for CC_RESTORE_MAYBE_S (at least 240 s).
#   · FULLSCREEN by kitty's own action, by window id: `KITTY_WINDOW_ID=<head> action --self
#     toggle_fullscreen` once `ls --match id:<head>` finds the window (0.48.2 IGNORES `action
#     --match` and toggles the ACTIVE window — kitty-crash-2026-10-15 README), 3 s apart. The verdict is the READ-BACK
#     (the window's frame fills its display, via hb_display_probe, polled up to
#     CC_RESTORE_FS_VERIFY=10 s); a window read back as windowed gets focus-window and ONE more
#     toggle. A refused toggle, or an unreadable state, is never re-toggled. An unread frame is read
#     once more, then looked up in com.apple.spaces' fullscreen Spaces; still unread, it counts as
#     fullscreen_unknown, never as ok (R21). After a placing pass, kitty's own startup window (one
#     pane, a login shell that never ran a command) is closed: strays_closed=N.
#   · STAGGER: 2 s after each launch (CC_RESTORE_STAGGER), not the plain path's 12 s (R17).
#
# --restore, LAYOUT FIDELITY (2026-10-05, W3 P7; plan § Amendment B gaps 2 and 3): when the heartbeat
# recorded kitty's tree, each window comes back as it was, and the one-row plan above is only the
# fallback for rows no tree places. Nothing here runs without --restore.
#   · THE TREE is hb.kitty-ls.json (scripts/lib/restore-heartbeat.sh): --tree FILE, else the newest one
#     under the heartbeat root for each kitty pid the rows' group column names (k<pid>w<os window>).
#     CC_RESTORE_TREE=off turns the replay off, and a tree with hb.layout-degraded beside it (the
#     reboot prep could not vouch for it) is not replayed unless --tree names it. A row is matched to its old pane through the
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
# reso-resume-one is #!/usr/bin/env bash and every resumed pane starts it: run by path at a session
# root it keeps ~1.1 KiB of kernel memory on macOS 15.8.1, so the pane command names its interpreter
# (plan KALLOC_TRIGGER_ELIMINATION W4, scripts/../scripts/lib/cc-run.sh). Fail-open: no runner, path as before.
# shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
if [ -f "${BASH_SOURCE[0]%/*}/../scripts/lib/cc-run.sh" ]; then . "${BASH_SOURCE[0]%/*}/../scripts/lib/cc-run.sh"; else cc_argv() { CC_ARGV=("$1"); }; fi

# Homebrew's cask wrapper (/opt/homebrew/bin/kitty) is a #! script whose whole body is
# `exec "<app binary>" "$@"`. Run that binary directly: every by-path #! exec keeps ~1.1 KiB of kernel
# memory on macOS 15.8.1 (docs/research/kalloc-longterm-2026-10-21/REPORT.md §3 Phase 1). Anything that
# is not such a wrapper (a test stub on PATH, a dev build) is returned unchanged.
_kitty_unwrap() { # <path> -> the app binary a Homebrew wrapper execs, else <path>
  local t="$1" l
  if [ -L "$t" ]; then l="$(readlink "$t")"; case "$l" in /*) t="$l" ;; *) t="$(dirname "$t")/$l" ;; esac; fi
  case "$t" in
    */.homebrew-command-wrappers/*)
      while IFS= read -r l; do
        case "$l" in 'exec "'*) l="${l#exec \"}"; l="${l%%\"*}"; [ -x "$l" ] && { printf '%s' "$l"; return 0; } ;; esac
      done < "$t" ;;
  esac
  printf '%s' "$1"
}
KITTY_BIN="${CC_TERM_KITTY:-}"
if [ -z "$KITTY_BIN" ]; then
  for c in /opt/homebrew/bin/kitty /usr/local/bin/kitty "$(command -v kitty 2>/dev/null || true)"; do
    [ -n "$c" ] && [ -x "$c" ] && { KITTY_BIN="$(_kitty_unwrap "$c")"; break; }
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
STAGGER="${CC_RESUME_STAGGER:-}"   # "" ⇒ 12 s, or CC_RESTORE_STAGGER (2 s) under --restore (below)
USE_ALL_SCREENS=0
DRY_RUN=0
RESTORE=0             # --restore: the unattended restore path (W3)
TREE=""               # --tree FILE: the recorded kitty tree to replay (--restore only)
KEEP_SHELLS=0         # --keep-shells: a recorded pane that held no session comes back as a shell
LIVE_MAP=""           # --live-map FILE: recorded pane → live window id, for sessions already running
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
    --keep-shells)     KEEP_SHELLS=1; shift ;;
    --live-map)        LIVE_MAP="${2:?--live-map needs a file}"; shift 2 ;;
    -h|--help)         sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0 ;;
    *)                 die "unknown argument: $1" ;;
  esac
done

# The pause after each launched session. R17 (reboot-resume 2026-10-21): 12 s added about 5.2 minutes
# of pure sleep to a 26-session restore, which already waits on its own capacity probe and kitty's
# answer to every launch, so under --restore it is 2 s. The plain path keeps 12 s.
if [ -z "$STAGGER" ]; then
  if [ "$RESTORE" = 1 ]; then STAGGER="${CC_RESTORE_STAGGER:-2}"; else STAGGER=12; fi
fi

if [ -n "$LIVE_MAP" ]; then
  [ -n "$TREE" ] || die "--live-map needs --tree"
  [ -r "$LIVE_MAP" ] || die "--live-map: cannot read $LIVE_MAP"
fi
if [ -n "$TREE" ]; then
  [ "$DESKTOPS" = 1 ] && [ "$RESTORE" = 1 ] || die "--tree needs --desktops --restore"
  [ -r "$TREE" ] || die "--tree: cannot read $TREE"
fi
# The tree dry run reads files only, so it needs no kitty binary.
[ -n "$TREE" ] && [ "$DRY_RUN" = 1 ] && [ -z "$KITTY_BIN" ] && KITTY_BIN=/usr/bin/true
[ -n "$KITTY_BIN" ] && [ -x "$KITTY_BIN" ] || die "no kitty binary (set CC_TERM_KITTY) — this layout is kitty-only"
[ "$DRY_RUN" = 1 ] || [ -x "$RESUME_ONE" ] || die "resume launcher not executable: $RESUME_ONE"
# Its argv once: `kitty @ launch -- "${RESUME_ONE_ARGV[@]}"`, and resume_one_q (beside shq, below)
# for the single-quoted command strings a pane's shell runs.
cc_argv "$RESUME_ONE"; RESUME_ONE_ARGV=("${CC_ARGV[@]}")
# Every resumed pane is rooted in bin/cc-pane-runner (husk-history FIX-DESIGN §4 W2.4), in
# scripts/handoff-fire.sh's argv shape: the command rides in CC_PANE_CMD and runs under `$SHELL -l -i -c`,
# reso-resume-one returns claude's status to the runner, and the runner closes, holds or keeps the pane
# and records which. No runner ⇒ refuse: a bare root dies with the session or ends in a shell nothing closes.
RUNNER="${CC_PANE_RUNNER_BIN:-}"
if [ -z "$RUNNER" ]; then
  for _r in "$(dirname "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")")/cc-pane-runner" "${HOME:-}/.claude/bin/cc-pane-runner"; do
    [ -x "$_r" ] && { RUNNER="$_r"; break; }
  done
fi
[ "$DRY_RUN" = 1 ] || { [ -n "$RUNNER" ] && [ -x "$RUNNER" ]; } || die "bin/cc-pane-runner not found — refusing to root resumed panes in the resume itself"
# shellcheck disable=SC2016  # $CC_PANE_RUNNER expands in the PANE's shell, from the --env
runner_tail() { # $1=the pane's command line → appended to LA
  LA+=(--env "CC_PANE_CMD=$1" --env "CC_PANE_CMD_INTERACTIVE=1" --env "CC_PANE_RUNNER=${RUNNER:-cc-pane-runner}"
       -- "${SHELL:-/bin/zsh}" -l -i -c 'exec /bin/bash "$CC_PANE_RUNNER"')
}

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
  # Each spawn's pane-spawn-log row asks the restore heartbeat to re-read THIS kitty's tree (R23);
  # under launchd there is no KITTY_LISTEN_ON to name it, so the socket rides along.
  [ -n "$SOCK" ] && export CC_SPAWN_KITTY_TO="$SOCK"
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
  resume_one_q() { local w o=""; for w in "${RESUME_ONE_ARGV[@]}"; do o="$o${o:+ }$(shq "$w")"; done; printf '%s' "$o"; }
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
    FS_GAP="${CC_RESTORE_FS_GAP:-1}"
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
    # resume_marks <sid> <cwd> — the SessionStart:resume records in the session's transcripts.
    # R6 (reboot-resume 2026-10-21): this globbed every project dir of every account store (about
    # 73,000 directories, with ~/.claude-next/projects a symlink to ~/.claude/projects, so that store
    # twice) once per launched row, as the maybe baseline. The transcript sits at
    # <config>/projects/<cwd slug>/<sid>.jsonl, the path restore-heartbeat.sh's _hb_transcript tries
    # first, so that path is read in each store, each real path once. Only when no store has it does
    # the glob run, over each projects root once by real path, and what it finds is cached for the
    # session (MARK_CACHE) and counted beside the direct paths ever after, so a baseline and a
    # re-check always count the same files plus any new one.
    MARK_CACHE=""; MARK_ROOTS=""
    mark_roots() { # every account store's projects dir, once per real path (kept once one exists)
      # An EMPTY answer is not kept: a store whose projects dir the resumed session creates during
      # the launch must be seen by the re-check, or the maybe row can never resolve.
      [ -n "$MARK_ROOTS" ] && return 0
      local d r seen=$'\n'
      for d in "${HOME:-}"/.claude*/projects; do
        [ -d "$d" ] || continue
        r="$(cd "$d" 2>/dev/null && pwd -P)" || continue
        case "$seen" in *$'\n'"$r"$'\n'*) continue ;; esac
        seen="$seen$r"$'\n'; MARK_ROOTS="$MARK_ROOTS$r"$'\n'
      done
      return 0
    }
    resume_marks() {
      local sid="$1" slug f r c n=0 files="" glob=""
      mark_roots
      # Claude Code's project slug: every character outside [A-Za-z0-9] becomes - (doc_classifier ⇒ doc-classifier).
      slug="$(printf '%s' "${2:-}" | tr -c 'A-Za-z0-9' '-')"
      if [ -n "${2:-}" ]; then
        while IFS= read -r r; do
          [ -n "$r" ] && [ -f "$r/$slug/$sid.jsonl" ] && files="$files$r/$slug/$sid.jsonl"$'\n'
        done <<EOF
$MARK_ROOTS
EOF
      fi
      case "$MARK_CACHE" in
        *$'\n'"$sid"$'\t'*) glob="${MARK_CACHE#*$'\n'"$sid"$'\t'}"; glob="${glob%%$'\n'*}" ;;
        *) if [ -z "$files" ]; then
             note "cc-resume-layout: no transcript for $sid at its cwd path — searching every project dir once"
             while IFS= read -r r; do
               [ -n "$r" ] || continue
               for f in "$r"/*/"$sid".jsonl; do [ -f "$f" ] && glob="$glob$f"$'\037'; done
             done <<EOF
$MARK_ROOTS
EOF
             [ -n "$glob" ] && MARK_CACHE="$MARK_CACHE"$'\n'"$sid"$'\t'"$glob"
           fi ;;
      esac
      [ -n "$glob" ] && files="$files$(printf '%s' "$glob" | tr '\037' '\n')"$'\n'
      while IFS= read -r f; do
        [ -n "$f" ] && [ -f "$f" ] || continue
        c="$(grep -c '"hookName":"SessionStart:resume"' "$f" 2>/dev/null)"; n=$((n + ${c:-0}))
      done <<EOF
$(printf '%s' "$files" | awk 'NF && !seen[$0]++')
EOF
      RM_N="$n"   # a variable, not stdout: in $(…) the cache above would die with the subshell
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
        # The crash page's copy in its event outlives the 7-day prune of the heartbeat root.
        for f in "$hbroot"/*/"$kp"/hb.kitty-ls.json \
                 "${CC_BOOT_RESUME_STATE_DIR:-${HOME:-}/.claude/autonomy/boot-resume}"/events/*/hb/"$kp"/hb.kitty-ls.json; do
          [ -f "$f" ] || continue
          st="$(head -n 1 "${f%/*}/hb.start" 2>/dev/null | awk '{ print $1 }')"
          case "$st" in ''|*[!0-9]*) st=0 ;; esac
          if [ "$st" -gt "$bs" ]; then best="$f"; bs="$st"; fi
        done
        # The reboot prep marks a tree it could not vouch for (scripts/alarm-reboot-prep.sh). Half an
        # arrangement is worse than the plain rows, so that tree is not replayed, and it says so.
        if [ -n "$best" ] && [ -f "${best%/*}/hb.layout-degraded" ]; then
          note "cc-resume-layout: ⚠ the recorded tree of kitty $kp is marked degraded ($(head -n 1 "${best%/*}/hb.layout-degraded" 2>/dev/null)) — not replayed; its sessions come back in the plain row layout"
          best=""
        fi
        [ -n "$best" ] && TREES+=("$best")
      done
      # BY SESSION ID (2026-10-15): rows from lr-select or a hand-built TSV carry no k<pid>w<n> group,
      # so the loop above finds no tree and every session came back in the plain row layout — after
      # the 00:01:27 crash, 20 sessions in different pane positions. A row's session id in a
      # heartbeat roster names the tree it was recorded in. Newest tree first; a tree joins only for
      # sessions no tree already chosen holds, so an older arrangement never overrides a newer one.
      # Only rows with NO group: a grouped row names its kitty, and that kitty's record governs — a
      # tree marked degraded, or gone, means the plain row layout, never an older arrangement.
      while IFS= read -r f; do
        [ -n "$f" ] && TREES+=("$f")
      done < <(for r in "${ROWS[@]}"; do printf '%s\t%s\n' "$(cell "$r" 8)" "$(cell "$r" 2)"; done \
               | awk -F'\t' '$1 !~ /^k[0-9]+w[0-9]+$/ { print $2 }' | python3 -c '
import glob, json, os, subprocess, sys
root, chosen = sys.argv[1], sys.argv[2:]
want = {l.strip() for l in sys.stdin if l.strip()}
def roster(d):
    try:
        return {e.get("session_id") for e in json.load(open(os.path.join(d, "hb.roster.json"))) if isinstance(e, dict)}
    except Exception:
        return set()
for f in chosen:
    want -= roster(os.path.dirname(f))
cands = []
def live_kitty(pid):   # a running kitty records where its panes ARE now, not where they were
    try:
        out = subprocess.run(["/bin/ps", "-p", pid, "-o", "comm="], capture_output=True, text=True, timeout=5).stdout
    except Exception:
        return False
    return out.strip().endswith("kitty")
# The crash page copies the heartbeat of the dead kitty into its event (events/<id>/hb/<pid>/), which
# outlives the 7-day prune of the heartbeat root (restore-heartbeat.sh hb_prune).
events = os.path.join(os.environ.get("CC_BOOT_RESUME_STATE_DIR") or os.path.expanduser("~/.claude/autonomy/boot-resume"), "events")
for f in glob.glob(os.path.join(root, "*", "*", "hb.kitty-ls.json")) + glob.glob(os.path.join(events, "*", "hb", "*", "hb.kitty-ls.json")):
    d = os.path.dirname(f)
    if os.path.exists(os.path.join(d, "hb.layout-degraded")) or live_kitty(os.path.basename(d)):
        continue
    try:
        st = int(open(os.path.join(d, "hb.start")).read().split()[0])
    except Exception:
        st = 0
    cands.append((st, f))
for _, f in sorted(cands, reverse=True):
    got = want & roster(os.path.dirname(f))
    if got:
        print(f); want -= got
' "$hbroot" ${TREES[@]+"${TREES[@]}"} 2>/dev/null)
    fi
    [ "${#TREES[@]}" -gt 0 ] && [ -z "$TREE" ] && note "cc-resume-layout: recorded tree(s) found: ${TREES[*]}"

    # PLAN, three kinds of line, fields separated by \037 (so an empty field keeps its place):
    #   W  window#  source  platform_window_id  tabs  panes  claude  shells  layout-signature
    #      then the window's hb.displays.tsv fields (uuid dx dy dw dh fullscreen wx wy ww wh) or 10 empties
    #   T  how many windows came from a recorded tree (they are numbered first, in recorded order)
    #   P  window#  tab  pane-key  row|shell  row-index  head|tab|vsplit|hsplit  anchor-key  bias
    #      shell-cwd  group-label  keep|<layout to go to>      — in launch order
    # Windows holding the most prompt rows (column 10) launch first, and inside a project window so do those rows.
    PLAN="$(i=0; for r in "${ROWS[@]}"; do
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$i" "$(cell "$r" 3)" "$(cell "$r" 8)" "$(cell "$r" 9)" "$(cell "$r" 10)" "$(cell "$r" 2)"
        i=$((i + 1)); done \
      | CC_RESTORE_KEEP_SHELLS="$KEEP_SHELLS" CC_RESTORE_LIVE_MAP="$LIVE_MAP" python3 -c '
import json, os, subprocess, sys
per = int(sys.argv[1]); trees = [t for t in sys.argv[2:] if t]
S = "\x1f"
import re
KEEP_SHELLS = os.environ.get("CC_RESTORE_KEEP_SHELLS") == "1"
# --live-map: "<recorded pane id> TAB <live window id> [TAB <live OS window id>]" for recorded panes
# whose session is ALREADY running in the live kitty. Such a pane is used where it is (a "live"
# leaf), never relaunched. A tab is rebuilt in ONE live OS window, that of its first live pane: a
# live pane of the same recorded tab that sits in another OS window stays there, because moving a
# pane between OS windows is what crashed kitty 0.48.2 on 2026-10-15.
# A line "host <recorded OS window id> <live window id>" rebuilds that recorded window inside the
# live OS window of that pane (a placeholder holding its Desktop), the host kept as an extra pane.
LIVE, LIVE_OS, HOST = {}, {}, {}
if os.environ.get("CC_RESTORE_LIVE_MAP"):
    for ln in open(os.environ["CC_RESTORE_LIVE_MAP"]):
        f = ln.split()
        if len(f) >= 3 and f[0] == "host" and f[1].isdigit() and f[2].isdigit():
            HOST[f[1]] = f[2]
        elif len(f) >= 2 and f[0].isdigit() and f[1].isdigit():
            LIVE[f[0]] = f[1]
            LIVE_OS[f[0]] = f[2] if len(f) >= 3 else "?"
# a pane whose process is Claude Code, or the launcher that resumes it
CLAUDE_RE = re.compile(r"(^|[/ ])(claude|claude\.exe|reso-resume-one|cc-close-attrib|cc-pane-runner)( |\Z)")
TEAMMATE_RE = re.compile(r"--agent-id|--parent-session-id")
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
# ── PANE → SESSION (2026-10-25). The roster names a pane for each session, but a reconstructed
#    roster can name the wrong pane, or none (after the 2026-10-25 reboot voiceink came back in a new
#    window although pane 12 still ran "reso-resume-one … 509e3aad…"). In order of proof: a pane
#    whose process argv carries the session id (a resume launcher, not a teammate: a teammate argv
#    names its PARENT session); the roster pane, when its recorded cwd agrees with the row; the one
#    unclaimed pane recorded in the cwd of the row, a Claude pane first; the roster pane regardless.
#    A pane cwd is that of its Claude PROCESS, never the kitty "cwd" field, which is the shell cwd: pane 297
#    read lead-idle-fix there while its claude (pid 3378, the tombstone of 3f1c1301) ran in
#    lkw-scope-floor. A teammate pane never takes a session. ──
def norm(p):
    p = (p or "").rstrip("/")
    return os.path.realpath(p) if p else ""
def pane_cwd(w):   # the recorded cwd of the pane: that of its claude process, else of its first process, else of the kitty window
    fg = [p for p in w.get("foreground_processes") or [] if isinstance(p, dict)]
    for p in fg:
        if CLAUDE_RE.search(" ".join(str(a) for a in p.get("cmdline") or [])) and p.get("cwd"):
            return p["cwd"]
    return (fg[0].get("cwd") if fg and fg[0].get("cwd") else None) or w.get("cwd") or ""
def argvs(w):
    return [" ".join(str(a) for a in p.get("cmdline") or []) for p in w.get("foreground_processes") or [] if isinstance(p, dict)]
RESUMERS = ("reso-resume-one", "lr-fire-resume", "cc-restore-one")
def resumed_sids(w):   # session ids a pane process RESUMES: an exact argv token, never a substring
    out = set()
    for p in w.get("foreground_processes") or []:
        a = [str(x) for x in (p.get("cmdline") or [])] if isinstance(p, dict) else []
        if any(TEAMMATE_RE.search(x) for x in a):
            continue
        launcher = any(os.path.basename(x) in RESUMERS for x in a[:2])
        for i, x in enumerate(a):
            if x in by_sid and (launcher or (i and a[i - 1] in ("--resume", "-r", "--session-id"))):
                out.add(x)
            for f in ("--resume=", "--session-id="):
                if x.startswith(f) and x[len(f):] in by_sid:
                    out.add(x[len(f):])
    return out
def is_teammate(w):
    return any(TEAMMATE_RE.search(c) for c in argvs(w))
def is_claude(w):
    return any(CLAUDE_RE.search(" ".join(str(a) for a in p.get("cmdline") or []))
               for p in w.get("foreground_processes") or [] if isinstance(p, dict))
def cwd_ok(pc, wt):
    a, b = norm(pc), norm(wt)
    return not a or not b or a == b or a.startswith(b + "/")
def assign(data, pane_sid):
    """{pane id (str): sid} for every row this tree holds, cwd-validated."""
    panes = {}
    for o in data:
        for t in (o.get("tabs") or []) if isinstance(o, dict) else []:
            for w in t.get("windows") or []:
                if isinstance(w, dict) and w.get("id") is not None:
                    panes[str(w["id"])] = w
    out, taken = {}, set()
    sid_pane = {}
    for p, s in pane_sid.items():
        if p in panes:
            sid_pane.setdefault(s, p)
    if not pane_sid:                        # no roster beside the tree: find the sid in the pane itself
        for p, w in panes.items():
            blob = json.dumps([w.get(k) for k in ("cmdline", "last_reported_cmdline", "foreground_processes", "user_vars")])
            for s in by_sid:
                if s not in sid_pane and s in blob:
                    sid_pane[s] = p
    for p, w in panes.items():              # proof: the session id in a resume argv
        if is_teammate(w):
            continue
        hit = resumed_sids(w)
        if len(hit) == 1:
            out[p] = hit.pop(); taken.add(p)
    rows_here = [s for s in by_sid if s in sid_pane and s not in out.values()]
    for s in rows_here:                     # then every roster pane whose cwd agrees with its row
        p = sid_pane[s]
        if p not in taken and cwd_ok(pane_cwd(panes[p]), by_sid[s][1]):
            out[p] = s; taken.add(p)
    pending = [s for s in rows_here if s not in out.values()] + \
              [s for s in by_sid if s not in sid_pane and s not in out.values() and by_sid[s][1]]
    for s in pending:
        wt = by_sid[s][1]
        # never a pane the roster gives to ANOTHER session: that would put s in the place of another
        cands = [p for p, w in panes.items() if p not in taken and not is_teammate(w) and norm(pane_cwd(w))
                 and cwd_ok(pane_cwd(w), wt) and pane_sid.get(p) in (None, s)]
        cands.sort(key=lambda p: (0 if is_claude(panes[p]) else 1, int(p) if p.isdigit() else 0))
        if cands:
            out[cands[0]] = s; taken.add(cands[0])
            if s in sid_pane and sid_pane[s] != cands[0]:
                print("cc-resume-layout: %s: roster pane %s is recorded in %s, not %s — using pane %s, recorded there"
                      % (s, sid_pane[s], pane_cwd(panes[sid_pane[s]]) or "?", wt, cands[0]), file=sys.stderr)
        elif s in sid_pane and sid_pane[s] not in taken:
            out[sid_pane[s]] = s; taken.add(sid_pane[s])   # no pane in its cwd: the roster stays the best record
    return out, panes
def tab_node(t, pane_sid, given, panes):
    wmap = {w.get("id"): w for w in t.get("windows") or [] if isinstance(w, dict)}
    st = t.get("layout_state") or {}
    gl = ((st.get("all_windows") or {}).get("window_groups")
          or [{"id": g.get("id"), "window_ids": g.get("windows")} for g in t.get("groups") or []]
          or [{"id": w, "window_ids": [w]} for w in wmap])
    groups = {g.get("id"): [w for w in g.get("window_ids") or [] if w in wmap] for g in gl}
    home = next((LIVE_OS[str(w)] for g in gl for w in groups.get(g.get("id")) or [] if str(w) in LIVE), None)
    def leaf(gid):
        wids = groups.get(gid) or []
        if not wids:
            return None
        for w in wids:                      # a pane whose session already runs in the live kitty
            if str(w) in LIVE:
                return {"leaf": ("live", LIVE[str(w)])} if LIVE_OS[str(w)] == home else None
        for w in wids:                      # a pane holding a row being restored
            sid = given.get(str(w))
            if sid in by_sid and sid not in used:
                used.add(sid); r = by_sid[sid]
                return {"leaf": ("row", r[0], r[4])}
        if any(str(w) in pane_sid or is_claude(wmap[w]) for w in wids):
            return None                     # a Claude pane with no row: its session is not being restored
        # A pane that held no session comes back only under --keep-shells: an empty shell where the
        # operator expects a session is the defect the 2026-10-25 restore left in 11 panes.
        return {"leaf": ("shell", wmap[wids[-1]].get("cwd") or "")} if KEEP_SHELLS else None
    # build → (node, width span, height span): the spans are the share of the recorded
    # extent that panes still being restored cover. The bias of a kept pair is re-derived from them, so a
    # space of a dropped pane goes to its neighbours in their RECORDED proportions. Keeping the raw bias
    # is what left two of an even four-pane row at 1/4 and 3/4 after the 2026-10-25 reboot: kitty
    # writes an even row a|b|c|d as biases 1/4, 1/3, 1/2, and with c and d gone the 1/4 survived.
    def build(x):
        if x is None or isinstance(x, bool):
            return None, 0.0, 0.0
        if isinstance(x, int):
            n = leaf(x)
            return (n, 1.0, 1.0) if n else (None, 0.0, 0.0)
        a, ah, av = build(x.get("one"))
        b, bh, bv = build(x.get("two"))
        h = x.get("horizontal", True) is not False
        try:
            bias = min(0.99, max(0.01, float(x.get("bias", 0.5))))
        except (TypeError, ValueError):
            bias = 0.5
        ua, ub = (ah, bh) if h else (av, bv)
        span = bias * ua + (1 - bias) * ub
        cross = max(av, bv) if h else max(ah, bh)
        sh, sv = (span, cross) if h else (cross, span)
        if a is None or b is None:
            return (a or b), sh, sv         # the pane that stays takes the space of the pair, as kitty does
        nb = bias * ua / span if span > 0 else 0.5
        nb = min(0.99, max(0.01, nb))
        if abs(nb - 0.5) < 1e-6:
            nb = 0.5
        return {"h": h, "bias": nb, "one": a, "two": b}, sh, sv
    name = t.get("layout") or "splits"
    if st.get("class") == "Splits" and isinstance(st.get("pairs"), dict):
        n = build(st["pairs"])[0]
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
    given, panes = assign(data, pane_sid)
    for o in data:
        if not isinstance(o, dict):
            continue
        tabs = [tn for tn in (tab_node(t, pane_sid, given, panes) for t in o.get("tabs") or [] if isinstance(t, dict)) if tn]
        if not tabs or all(l[0] == "live" for _, n in tabs for l in leaves(n)):
            continue                        # nothing to launch here (a fully live window is left alone)
        pwid = str(o.get("platform_window_id") or "")
        src = "k%sw%s" % (kp, o.get("id"))
        ls = [l for _, n in tabs for l in leaves(n)]
        wins.append({"src": src, "pwid": pwid, "disp": disp.get(pwid), "tabs": tabs, "grp": src,
                     "host": HOST.get(str(o.get("id"))),
                     "prompt": sum(1 for l in ls if l[0] == "row" and l[2])})
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
        rs = sorted(rs, key=lambda r: (-r[2], r[0]))
        chunks += [(k[1], rs[j:j + per]) for j in range(0, len(rs), per)]
chunks.sort(key=lambda c: -len(c[1]))
bins = []
for g, rs in chunks:
    for b in bins:
        if len(b[0]) + len(rs) <= per:
            b[0].extend(rs); b[1].append(g); break
    else:
        bins.append([list(rs), [g]])
fb += [(sorted(rs, key=lambda r: -r[2]), gs) for rs, gs in bins]
fb.sort(key=lambda w: -sum(r[2] for r in w[0]))
# A window no tree places goes to the display most recorded windows were on, fullscreen: left to
# kitty it opens wherever the key window is (2026-10-25: voiceink landed on the display of the lead).
dd = {}
for w in wins:
    if w["disp"]:
        dd.setdefault(w["disp"][0], [0, w["disp"]])[0] += 1
home = None
if dd:
    d0 = max(dd.values(), key=lambda v: v[0])[1]
    home = d0[:5] + ["1"] + d0[1:5]
for rs, gs in fb:
    wins.append({"src": "plan", "pwid": "", "disp": home, "grp": "+".join(gs),
                 "tabs": [("horizontal", chain([("row", r[0], r[2]) for r in rs]))],
                 "prompt": sum(r[2] for r in rs)})
for n, w in enumerate(wins, 1):
    w["n"] = n

# ── ops. A pair is built by splitting the pane that is already there: the new pane is the first
#    leaf of the second half of the pair, and the --bias of kitty gives it the share of that half. ──
nkey = [0]
def kt_tree(n, key):   # planner node → scripts/lib/kitty_tree.py TREE, each leaf its op key
    if "leaf" in n:
        return key[id(n)]
    return {"h": n["h"], "b": n["bias"], "one": kt_tree(n["one"], key), "two": kt_tree(n["two"], key)}
def nodes(n):
    return [n] if "leaf" in n else nodes(n["one"]) + nodes(n["two"])
def emit_live(w, ti, layout, node):
    """A tab that already runs in the live kitty: its live panes stay (kind live, no launch), each
    new pane opens beside the first live one, and the tab is then SET to the planned tree by the
    read-back (L line), so the order of the launches does not matter."""
    ops, key = [], {}
    def op(kind, a, b, how, anchor):
        nkey[0] += 1; k = nkey[0]
        ops.append([str(w["n"]), str(ti), str(k), kind, a, how, str(anchor), "", b, w["grp"], "keep"])
        return k
    ls = nodes(node)
    lives = [n for n in ls if n["leaf"][0] == "live"]
    for n in lives:
        key[id(n)] = op("live", n["leaf"][1], "", "live", "")
    # the host: a live pane outside the record, kept as an extra (the read-back appends it)
    anchor = key[id(lives[0])] if lives else op("live", w["host"], "", "live", "")
    for n in ls:
        if n["leaf"][0] == "row":
            key[id(n)] = op("row", str(n["leaf"][1]), "", "vsplit", anchor)
        elif n["leaf"][0] == "shell":
            key[id(n)] = op("shell", "", n["leaf"][1], "vsplit", anchor)
    if ti == 0:
        w["head"] = anchor
    w.setdefault("live_specs", []).append((ti, kt_tree(node, {i: str(k) for i, k in key.items()})))
    return ops
def emit(w, ti, layout, node):
    if any(l[0] == "live" for l in leaves(node)) or (ti == 0 and w.get("host")):
        return emit_live(w, ti, layout, node)
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
for w in wins:
    for ti, spec in w.get("live_specs", []):
        out.append(S.join(["L", str(w["n"]), str(ti), json.dumps(spec)]))
# Recorded windows launch in their recorded order, which is the order their Desktops come back in
# (each goes fullscreen as its head opens); then the planned ones, most prompt rows first (R17).
for w in wins[:ntree] + sorted(wins[ntree:], key=lambda w: -w["prompt"]):
    out += [S.join(["P"] + o) for o in w["ops"]]
print("\n".join(out))
' "$PER_WINDOW" ${TREES[@]+"${TREES[@]}"})" || die "the window planner failed"

    # The non-charging probe; a library too old to carry it falls back to the charging admit, loudly.
    PROBE_FN=cc_capacity_probe
    if [ "$CC_ADMIT_OK" = 1 ] && ! command -v cc_capacity_probe >/dev/null 2>&1; then
      PROBE_FN=cc_capacity_admit
      note "cc-resume-layout: capacity-admit.sh has no cc_capacity_probe — each wait now spends the refusal budget"
    fi
    # FULLSCREEN, PER WINDOW, AS ITS HEAD OPENS (2026-10-25). It used to be one pass after the whole
    # batch, so every window sat windowed on the first Desktop for the batch's whole length (10
    # sessions at --stagger 20 plus a 30 s capacity wait: about four minutes after the 2026-10-25
    # reboot) before moving to its own Space. Now each window is toggled right after its head opens,
    # before its other panes (their widths are fractions, so the resize keeps them), and the next
    # window is opened only after this one is read back. The Spaces therefore come back in launch
    # order, which for recorded windows is the recorded order.
    # A window opened while its display shows a fullscreen Space opens on that display's Desktop
    # BEHIND it, and kitty's first toggle then only brings that Desktop forward (measured
    # 2026-10-25, three of three; focus-window before the toggle did not help, and the incident's
    # retries took the second toggle). So the second toggle is expected for every window after the
    # first. A toggle that lands takes about 1.5 s, so the first read-back waits up to FS_FIRST
    # (4 s) before the second toggle, and a second toggle is sent only after a positive "windowed"
    # reading, because a toggle that landed late would be undone by another.
    # rc 0 from the toggle only says kitty took the request: on 2026-10-05 all five accepted toggles
    # left their windows on the main Desktop. So the verdict is the READ-BACK: the window's
    # CGWindow frame filling its display (hb_display_probe's fullscreen column).
    # kitty 0.48.2 drops `action --match` (the client sends match_window, the server reads match)
    # and toggles whichever window is ACTIVE, so the target rides in KITTY_WINDOW_ID with --self.
    # R21 (reboot-resume 2026-10-21): an unread state was counted as fullscreen_ok, so all 8 windows
    # of that restore were reported fullscreen without one being checked. Now a probe that answers
    # nothing is asked ONCE more, then cross-checked against WindowServer's own record of fullscreen
    # Spaces (com.apple.spaces: each fullscreen Space carries fs_wid, the CGWindow number, which is
    # kitty's platform_window_id); a window still unread is fullscreen_unknown, never ok.
    # CC_DEFAULTS_BIN is the seam; under bats with it unset nothing real is read.
    spaces_fs_wids() { # → one CGWindow number per line, for every fullscreen Space
      local db="${CC_DEFAULTS_BIN:-}"
      if [ -z "$db" ]; then
        [ -n "${BATS_TEST_FILENAME:-}${BATS_TEST_TMPDIR:-}${BATS_VERSION:-}" ] && return 0
        db=/usr/bin/defaults
      fi
      [ -x "$db" ] || return 0
      kb "$db" export com.apple.spaces - 2>/dev/null | python3 -c 'import plistlib, sys
try:
    d = plistlib.loads(sys.stdin.buffer.read())
except Exception:
    sys.exit(0)
for m in (d.get("SpacesDisplayConfiguration") or {}).get("Management Data", {}).get("Monitors") or []:
    for s in m.get("Spaces") or []:
        if s.get("type") == 4 and isinstance(s.get("fs_wid"), int):
            print(s["fs_wid"])' 2>/dev/null
    }
    fs_probe() { # <pwid> → "<fullscreen column> <display uuid>" for that window, or nothing
      command -v hb_display_probe >/dev/null 2>&1 || return 0
      CC_HB_SWIFT_BIN="$SWIFT_BIN" hb_display_probe "$1" 2>/dev/null | awk -F'\t' -v p="$1" '$1 == p { print $7, $2; exit }'
    }
    # <head pane> → "1 <uuid>" (frame fills its display) | "S" (no frame read, but a fullscreen
    # Space holds it) | "0 <uuid>" (windowed) | "" (unknown)
    fs_state() {
      local pwid s
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
      s="$(fs_probe "$pwid")"
      [ -n "$s" ] || { sleep "${CC_RESTORE_FS_RETRY_S:-1}"; s="$(fs_probe "$pwid")"; }
      # A herestring, not `| grep -q`: under pipefail the early exit would SIGPIPE the producer.
      [ -z "$s" ] && grep -qx -- "$pwid" <<<"$(spaces_fs_wids)" && s=S
      printf '%s' "$s"
    }
    fs_settled() { # <head pane> <bound s> → fs_state, polled every FS_POLL s up to the bound while it reads windowed
      local s i=0 n
      n="$(awk -v b="$2" -v p="$FS_POLL" 'BEGIN { print (p > 0 ? int(b / p) : 0) }')"
      while :; do
        s="$(fs_state "$1")"
        [ "${s%% *}" = 0 ] && [ "$i" -lt "$n" ] || { printf '%s' "$s"; return 0; }
        sleep "$FS_POLL"; i=$((i + 1))
      done
    }
    FS_FIRST="${CC_RESTORE_FS_FIRST:-4}"; FS_VERIFY="${CC_RESTORE_FS_VERIFY:-10}"; FS_POLL="${CC_RESTORE_FS_POLL:-0.5}"
    fs_ok=0; fs_bad=0; fs_unk=0
    fs_window() { # <window#> <head pane> — toggle and read back; a window recorded as not fullscreen stays windowed
      local n="$1" hd="$2" st uuid want
      if [ "${WFS[$n]:-1}" = 0 ]; then
        note "$([ "$DRY_RUN" = 1 ] && printf 'DRY' || printf ' ') [CC-DESK-$n] left windowed, as recorded"; return 0
      fi
      if [ "$DRY_RUN" = 1 ]; then note "DRY [CC-DESK-$n] KITTY_WINDOW_ID=$hd action --self toggle_fullscreen"; return 0; fi
      # The existence check runs first: a toggle must never be sent for a window that is gone.
      if ! kr ls --match "id:$hd" >/dev/null 2>&1; then
        fs_bad=$((fs_bad + 1)); note "  [CC-DESK-$n] window $hd not found — not toggled"; return 0
      fi
      if ! KITTY_WINDOW_ID="$hd" kr action --self toggle_fullscreen >/dev/null 2>&1; then
        fs_bad=$((fs_bad + 1)); note "  [CC-DESK-$n] toggle_fullscreen refused for window $hd — not re-toggled"; sleep "$FS_GAP"; return 0
      fi
      sleep "$FS_GAP"; st="$(fs_settled "$hd" "$FS_FIRST")"
      if [ "${st%% *}" = 0 ]; then
        note "  [CC-DESK-$n] window $hd still windowed after its first toggle (it opened behind a fullscreen Space) — toggling once more"
        KITTY_WINDOW_ID="$hd" kr action --self toggle_fullscreen >/dev/null 2>&1
        sleep "$FS_GAP"; st="$(fs_settled "$hd" "$FS_VERIFY")"
      fi
      uuid=""; case "$st" in *" "*) uuid="${st#* }" ;; esac
      case "${st%% *}" in
        1) fs_ok=$((fs_ok + 1)); note "  [CC-DESK-$n] fullscreen (read back, window $hd${uuid:+, display $uuid})" ;;
        S) fs_ok=$((fs_ok + 1)); note "  [CC-DESK-$n] fullscreen (its frame unread; a fullscreen Space holds window $hd, per com.apple.spaces)" ;;
        0) fs_bad=$((fs_bad + 1)); note "  [CC-DESK-$n] NOT fullscreen after two toggles (read back, window $hd)" ;;
        *) fs_unk=$((fs_unk + 1)); note "  [CC-DESK-$n] fullscreen toggled, state UNKNOWN (window $hd: no frame read twice, and no fullscreen Space names it)" ;;
      esac
      # A window opened by position is counted placed only once a read-back finds it on its display.
      want="${WDISP[$n]:-}"; want="${want%% *}"
      if [ -n "${WPOS[$n]:-}" ] && [ -n "$uuid" ] && [ -n "$want" ]; then
        if [ "$uuid" = "$want" ]; then placed=$((placed + 1))
        else place_bad=$((place_bad + 1)); note "  [CC-DESK-$n] ⚠ opened on display $uuid, recorded $want"; fi
      fi
    }

    t0=$SECONDS; stopped=none; fd_blind=0
    launched=0; failed=0; shed=0; nwin=0; nshell=0; placed=0; place_bad=0
    WIN_HEAD=(); WIN_NUM=(); MAYBE_SID=(); MAYBE_BASE=(); MAYBE_WT=(); WIDS=(); WDISP=(); WFS=(); WPOS=()
    ROW_EXPECT=""   # "<wid>=<sid> …" for the census, "?=<sid>" for a planned row with no pane
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
    # win_pos <window#> → "X x Y" (no spaces) where the window's head opens, from its recorded display
    # as attached now, or nothing. kitty's own `launch --os-window-position` puts the window there as
    # it is created (measured 2026-10-25 on kitty 0.48.2, both of two windows on the named display),
    # so a fullscreen window needs no Accessibility move: the move's title-marker match missed one
    # window after the 2026-10-25 reboot ("nomatch", it opened behind a fullscreen Space), and that
    # window went fullscreen on the lead's display instead of its own.
    win_pos() {
      local rec="${WDISP[$1]:-}" uuid dx dy dw dh fs wx wy ww wh cur cx cy cw ch
      [ -n "$rec" ] && [ -n "$CUR_DISPLAYS" ] || return 0
      read -r uuid dx dy dw dh fs wx wy ww wh <<EOF
$rec
EOF
      cur="$(printf '%s\n' "$CUR_DISPLAYS" | awk -F'\t' -v u="$uuid" '$1 == u { print $2, $3, $4, $5; exit }')"
      [ -n "$cur" ] || cur="$(printf '%s\n' "$CUR_DISPLAYS" | awk -F'\t' -v a="$dx" -v b="$dy" -v c="$dw" -v d="$dh" \
        '$2 == a && $3 == b && $4 == c && $5 == d { print $2, $3, $4, $5; exit }')"
      [ -n "$cur" ] || return 0
      read -r cx cy cw ch <<EOF
$cur
EOF
      if [ "$fs" = 1 ]; then printf '%sx%s' "$((cx + 20))" "$((cy + 45))"
      else printf '%sx%s' "$((cx + wx - dx))" "$((cy + wy - dy))"; fi
    }
    # place_window <window#> <head pane> — a window recorded as NOT fullscreen gets its old frame back
    # through System Events (kitty has no launch size). A fullscreen one opened by position is
    # counted by fs_window's read-back instead. A display is matched by uuid, else by identical
    # bounds, else left alone.
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
      if [ "$fs" = 1 ] && [ -n "${WPOS[$n]:-}" ]; then
        note "  [CC-DESK-$n] opened on display $uuid at ${WPOS[$n]} (kitty --os-window-position)"; return 0
      fi
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

    # TREE READ-BACK (2026-10-15). Launching each pane --next-to its anchor builds the recorded tree
    # only while every launch lands: a split whose anchor timed out (a maybe row) opens beside the
    # tab's last pane instead (WHERE, below), and nothing read the result back. So a replayed splits
    # tab is read back from `kitty @ ls` once built, and a tree that differs from the plan in shape,
    # axis, bias or pane order is set EXACTLY by scripts/kitty-apply-layout.py — a kitten that calls
    # kitty's own Splits.set_layout_state on the panes already there, so nothing restarts — then
    # read back again. The verdict is the second read-back, never the kitten's word.
    APPLY_KITTEN="${CC_KITTY_APPLY_LAYOUT_KITTEN:-}"
    if [ -z "$APPLY_KITTEN" ]; then
      for _ak in "$HERE/../scripts/kitty-apply-layout.py" "${HOME:-}/.claude/scripts/kitty-apply-layout.py"; do
        [ -f "$_ak" ] && { APPLY_KITTEN="$(cd "$(dirname "$_ak")" && pwd -P)/$(basename "$_ak")"; break; }
      done
      unset _ak
    fi
    KTREE_LIB=""
    for _kl in "$HERE/../scripts/lib" "${HOME:-}/.claude/scripts/lib"; do
      [ -f "$_kl/kitty_tree.py" ] && { KTREE_LIB="$_kl"; break; }
    done
    unset _kl
    TOPS=""; tree_ok=0; tree_fixed=0; tree_bad=0; tree_unk=0
    RB_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cc-resume-tree.XXXXXX" 2>/dev/null)" || RB_DIR=""
    # A live tab's planned tree (L lines): the read-back sets the tab to it, launches included.
    if [ -n "$RB_DIR" ]; then
      while IFS=$'\037' read -r _t lw lt lspec; do
        [ "$_t" = L ] && printf '%s\n' "$lspec" > "$RB_DIR/live-$lw-$lt.json"
      done <<EOF
$PLAN
EOF
    fi
    # tree_check <ls.json> → prints "ok" | "differs <spec.json>" | "unknown <why>"; the spec holds
    # the planned tree in this tab's window ids, ready for the kitten.
    tree_check() {
      printf '%s' "$TOPS" | python3 -c '
import json, sys
sys.path.insert(0, sys.argv[1])
import kitty_tree as kt
ls_path, wids, spec_path, head = sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5])
ops = [l.split("\x1f") for l in sys.stdin.read().splitlines() if l.startswith("P\x1f")]
wid = dict(p.split("=", 1) for p in wids.split())
plan = None
try:                # a live tab: the planner wrote its tree (L line)
    plan = json.load(open(sys.argv[6]))
except Exception:
    for o in ops:   # P win tab key kind idx how anchor bias sid — what the planner meant (TOPS)
        key, how, anc, bias = o[3], o[6], o[7], o[8]
        plan = key if plan is None else kt.split_at(plan, anc, key, how == "vsplit", bias or None)
try:
    tabs = kt.ls_tabs(json.load(open(ls_path)))
except Exception as e:
    print("unknown kitty-ls-unreadable"); sys.exit(0)
tab = next((t for t in tabs if head in t["windows"]), None)
if tab is None:
    print("unknown head-pane-gone"); sys.exit(0)
blob = {w["id"]: json.dumps(w) for o in json.load(open(ls_path)) for t in o.get("tabs") or [] for w in t.get("windows") or []}
def resolve(key):
    w = wid.get(key)
    if w and int(w) in tab["windows"]:
        return int(w)
    return None
want = kt.relabel(plan, resolve)
# A maybe row has no wid; its pane is found by the session id in its command line.
have_ids = set(kt.leaves(want))
for o in ops:
    if o[3] not in wid and o[4] == "row":
        sid = o[9] if len(o) > 9 else ""
        hit = [w for w in tab["windows"] if w not in have_ids and sid and sid in blob.get(w, "")]
        if len(hit) == 1:
            wid[o[3]] = str(hit[0]); have_ids.add(hit[0])
want = kt.relabel(plan, resolve)
extra = [w for w in tab["windows"] if w not in set(kt.leaves(want))]
def cols(n):    # side-by-side columns a tree spans
    if not kt.is_pair(n):
        return 1
    return cols(n["one"]) + cols(n["two"]) if n["h"] else max(cols(n["one"]), cols(n["two"]))
for x in extra:  # each pane the record does not know gets one more equal column on the right
    want = x if want is None else {"h": True, "b": cols(want) / (cols(want) + 1.0), "one": want, "two": x}
d = kt.diff(want, tab["tree"])
if not d:
    print("ok"); sys.exit(0)
json.dump({"pairs": kt.to_pairs(want), "result": spec_path + ".result", "diff": d}, open(spec_path, "w"))
print("differs %s %s" % (spec_path, "; ".join(d)[:400]))
' "$KTREE_LIB" "$1" "$(for k2 in "${!WIDS[@]}"; do printf '%s=%s ' "$k2" "${WIDS[$k2]}"; done)" "$2" "$3" "$RB_DIR/live-$cur-$ctab.json" 2>/dev/null \
        || printf 'unknown read-back-failed\n'
    }
    verify_restore_tab() {
      local r spec why
      [ "$DRY_RUN" = 1 ] && return 0
      if [ -z "$KTREE_LIB" ] || [ -z "$RB_DIR" ]; then
        note "  [CC-DESK-$cur] tree read-back skipped — scripts/lib/kitty_tree.py or a temp dir is missing"
        return 0
      fi
      kr ls > "$RB_DIR/ls.json" 2>/dev/null || {
        tree_unk=$((tree_unk + 1)); note "  [CC-DESK-$cur] tree read-back: kitty @ ls failed"
        printf 'cc-resume-layout: tree-verify oswin=%s tab=%s verdict=unknown\n' "$cur" "$ctab"; return 0; }
      r="$(tree_check "$RB_DIR/ls.json" "$RB_DIR/spec-$cur-$ctab.json" "$thead")"
      case "$r" in
        ok) tree_ok=$((tree_ok + 1)); note "  [CC-DESK-$cur] tree read back as recorded"
            printf 'cc-resume-layout: tree-verify oswin=%s tab=%s verdict=ok\n' "$cur" "$ctab"; return 0 ;;
        differs*) ;;
        *) tree_unk=$((tree_unk + 1)); note "  [CC-DESK-$cur] tree read-back: $r"
           printf 'cc-resume-layout: tree-verify oswin=%s tab=%s verdict=unknown\n' "$cur" "$ctab"; return 0 ;;
      esac
      spec="$(printf '%s' "$r" | awk '{ print $2 }')"; why="${r#differs * }"
      note "  [CC-DESK-$cur] tree differs from the record ($why) — setting it exactly"
      if [ -n "$APPLY_KITTEN" ]; then
        kr kitten --match "id:$thead" "$APPLY_KITTEN" "$spec" >/dev/null 2>&1 \
          || note "  [CC-DESK-$cur] the apply-layout kitten was refused"
        sleep "${CC_RESTORE_APPLY_SETTLE:-1}"
      else
        note "  [CC-DESK-$cur] scripts/kitty-apply-layout.py not found — the tree stays as launched"
      fi
      kr ls > "$RB_DIR/ls.json" 2>/dev/null
      r="$(tree_check "$RB_DIR/ls.json" "$RB_DIR/spec-$cur-$ctab-2.json" "$thead")"
      if [ "$r" = ok ]; then
        tree_fixed=$((tree_fixed + 1)); note "  [CC-DESK-$cur] tree set and read back as recorded"
        printf 'cc-resume-layout: tree-verify oswin=%s tab=%s verdict=fixed\n' "$cur" "$ctab"
      else
        tree_bad=$((tree_bad + 1)); note "  [CC-DESK-$cur] ⚠ tree STILL differs after the kitten: $r ($(cat "$spec.result" 2>/dev/null))"
        printf 'cc-resume-layout: tree-verify oswin=%s tab=%s verdict=mismatch\n' "$cur" "$ctab"
      fi
    }

    # The windows kitty had BEFORE this restore opened any: the stray-window pass below may close only
    # one of these, never a window this run made.
    PRE_LS=""; [ "$DRY_RUN" = 0 ] && PRE_LS="$(kr ls 2>/dev/null)"

    cur=""; ctab=""; head=""; thead=""; tlast=""; tfin=""
    close_restore_tab() { # a replayed splits tab stays as built; any other becomes its layout, then even widths
      [ -n "$thead" ] || return 0
      [ "$tfin" = keep ] && { verify_restore_tab; TOPS=""; return 0; }
      TOPS=""
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
      TOPS="${TOPS}P"$'\037'"$win"$'\037'"$tab"$'\037'"$key"$'\037'"$kind"$'\037'"$idx"$'\037'"$how"$'\037'"$anc"$'\037'"$bias"$'\037'"$sid"$'\n'
      # A recorded pane whose session already runs here (--live-map): kept where it is, never launched.
      if [ "$kind" = live ]; then
        if [ "$DRY_RUN" = 0 ] && ! kr ls --match "id:$idx" >/dev/null 2>&1; then
          note "  [CC-DESK-$win] live pane $idx is gone — the panes planned beside it open beside the next one"; continue
        fi
        WIDS[key]="$idx"; tlast="$idx"; [ -n "$thead" ] || thead="$idx"; [ -n "$head" ] || head="$idx"
        note "$([ "$DRY_RUN" = 1 ] && printf 'DRY [CC-DESK-%s %s] live pane %s kept in place pane=#%s' "$win" "$grp" "$idx" "$key" \
               || printf '  [CC-DESK-%s %s] win %s  live — kept in place' "$win" "$grp" "$idx")"
        continue
      fi
      if [ "$DRY_RUN" = 1 ]; then
        at=""; [ -n "$anc" ] && [ "$how" != tab ] && at=" next-to=#$anc"
        if [ "$kind" = row ]; then
          note "DRY [CC-DESK-$win $grp] $how $acct $sid $wt${model:+ model=$model}${effort:+ effort=$effort}${pmode:+ permission_mode=$pmode}${prompt_file:+ prompt_file=$prompt_file} pane=#$key$at${bias:+ bias=$bias}"
        else
          note "DRY [CC-DESK-$win $grp] $how shell $wt pane=#$key$at${bias:+ bias=$bias}"
        fi
        if [ -z "$head" ]; then head="<head of CC-DESK-$win>"; place_window "$win" "$head"; fs_window "$win" "$head"; fi
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
        head) LA+=(--type=os-window)
              WPOS[win]="$(win_pos "$win")"; [ -n "${WPOS[$win]}" ] && LA+=("--os-window-position=${WPOS[$win]}") ;;
        tab) LA+=(--type=tab --match "window_id:$a") ;;
        *) LA+=("--location=$how" --match "window_id:$a" --next-to "id:$a")
           [ -n "$bias" ] && LA+=(--bias "$bias") ;;
      esac
      { [ -n "$wt" ] && [ -d "$wt" ]; } && LA+=(--cwd "$wt")
      if [ "$kind" = row ]; then
        resume_marks "$sid" "$wt"; base="$RM_N"
        # The spawn goes through reso-resume-one, which wraps claude in cc-close-attrib (P2); the cert
        # store is set here as well so no keychain read can stall a restore.
        cmd="'env' 'CC_ADMIT_DONE=1' 'CLAUDE_CODE_CERT_STORE=bundled'"
        [ -n "$model" ] && cmd="$cmd $(shq "CC_RESUME_MODEL=$model")"
        cmd="$cmd $(resume_one_q) $(shq "$acct") $(shq "$wt") $(shq "$sid")"
        [ -n "$br" ] && cmd="$cmd $(shq "$br")"
        [ -n "$effort" ] && cmd="$cmd '--effort' $(shq "$effort")"
        [ -n "$pmode" ] && cmd="$cmd '--permission-mode' $(shq "$pmode")"
        [ -n "$prompt_file" ] && cmd="$cmd '--prompt-file' $(shq "$prompt_file")"
        LA+=(--env CC_ADMIT_DONE=1 --env CLAUDE_CODE_CERT_STORE=bundled); runner_tail "$cmd"
      fi
      # A shell pane takes no command: kitty starts its configured shell in the recorded cwd.
      rc=0; wid="$(k "${LA[@]}" 2>&1)" || rc=$?
      case "$wid" in
        ''|*[!0-9]*)
          if [ "$kind" = row ]; then
            printf 'cc-resume-layout: maybe sid=%s rc=%s\n' "$sid" "$rc"
            note "cc-resume-layout: launch unconfirmed for $sid (rc $rc): $wid — re-checked after the batch"
            MAYBE_SID+=("$sid"); MAYBE_BASE+=("$base"); MAYBE_WT+=("$wt")
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
      if [ -z "$head" ]; then head="$wid"; place_window "$win" "$wid"; fs_window "$win" "$wid"; fi
      if [ "$kind" = row ]; then
        launched=$((launched + 1)); ROW_EXPECT="$ROW_EXPECT $wid=$sid"
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

    # STRAY STARTUP WINDOWS (R21, 2026-10-21): kitty opens its own window at login, a bare login
    # shell, and the restore left it beside the 8 it built as a ninth window. After a pass that
    # placed windows, an OS window that existed BEFORE this run and still holds exactly one pane,
    # whose only process is the SAME login shell ("-zsh" or "/bin/zsh -l -i", same pid as before) and which
    # never ran a command (no last_reported_cmdline), is closed. Anything else is left alone: a
    # window the operator typed in, one with a program running, one this run made, the caller's own.
    strays=0
    if [ "$DRY_RUN" = 0 ] && [ "$nwin" -gt 0 ] && [ "$launched" -gt 0 ] && [ -n "$PRE_LS" ]; then
      for sw in $(kr ls 2>/dev/null | python3 -c '
import json, os, sys
def shells(data):
    out = {}
    for o in data if isinstance(data, list) else []:
        tabs = o.get("tabs") or []
        if len(tabs) != 1 or len(tabs[0].get("windows") or []) != 1:
            continue
        w = tabs[0]["windows"][0]
        fg = w.get("foreground_processes") or []
        if w.get("is_self") or w.get("last_reported_cmdline") or len(fg) != 1:
            continue
        # A login shell is "-zsh" (argv0 dashed) or "/bin/zsh -l -i" (flags only), never one with a script or -c.
        argv = fg[0].get("cmdline") or []
        if not argv or os.path.basename(argv[0].lstrip("-")) not in ("zsh", "bash", "fish", "sh") \
                or any(a not in ("-l", "-i", "--login", "-il", "-li") for a in argv[1:]):
            continue
        out[w.get("id")] = fg[0].get("pid")
    return out
try:
    pre, post = shells(json.loads(sys.argv[1])), shells(json.load(sys.stdin))
except Exception:
    sys.exit(0)
made = set(sys.argv[2].split()); me = sys.argv[3]
for wid, pid in post.items():
    if wid in pre and pre[wid] == pid and str(wid) not in made and str(wid) != me:
        print(wid)' "$PRE_LS" "${WIDS[*]:-}" "${KITTY_WINDOW_ID:-}" 2>/dev/null); do
        if kr close-window --match "id:$sw" >/dev/null 2>&1; then
          strays=$((strays + 1)); note "cc-resume-layout: closed kitty's stray startup window (pane $sw: a login shell that never ran a command)"
        else
          note "cc-resume-layout: could not close stray window $sw — left open"
        fi
      done
      # The tree changed: ask for the heartbeat's re-read, as a spawn does (pane-spawn-log.sh, R23).
      [ "$strays" -gt 0 ] && command -v _cc_spawn_tree_refresh >/dev/null 2>&1 && _cc_spawn_tree_refresh kitty
    fi

    # Only a replay prints this line, so the default restore's stdout is still map lines then verdict.
    [ "${#TREES[@]}" -gt 0 ] && printf 'cc-resume-layout: layout tree_windows=%s shells=%s placed=%s placed_failed=%s tree_ok=%s tree_fixed=%s tree_mismatch=%s tree_unknown=%s\n' \
      "$NTREE" "$nshell" "$placed" "$place_bad" "$tree_ok" "$tree_fixed" "$tree_bad" "$tree_unk"
    [ -n "$RB_DIR" ] && rm -f "$RB_DIR"/*.json "$RB_DIR"/*.result 2>/dev/null && rmdir "$RB_DIR" 2>/dev/null

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
            resume_marks "${MAYBE_SID[$j]}" "${MAYBE_WT[$j]}"
            if [ "$RM_N" -gt "${MAYBE_BASE[$j]}" ] && { [ -z "$h" ] || [ "$h" -ge 1 ]; }; then
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

    # THE CENSUS (2026-10-25). Counting launches proved nothing about what the operator sees: that
    # restore reported launched=10 over 11 panes that were bare shells, and no step looked at a pane.
    # bin/cc-panes now reads every planned row back from kitty itself — the pane is there, its
    # process is Claude Code resuming THAT session, and its screen is at a prompt or working —
    # polled for up to CC_RESTORE_CENSUS_S while sessions start. A row not found that way (shed,
    # failed, maybe, a pane at a shell) makes the verdict failed, whatever the counts said.
    census=skipped; census_bad=0
    if [ "$DRY_RUN" = 0 ]; then
      PANES_BIN="${CC_PANES_BIN:-$HERE/cc-panes}"
      exp="$ROW_EXPECT"
      for r in "${ROWS[@]}"; do
        s2="$(cell "$r" 2)"
        case " $exp " in *"=$s2 "*) ;; *) exp="$exp ?=$s2" ;; esac
      done
      if [ -x "$PANES_BIN" ]; then
        crc=0
        # cc-panes bounds itself: every kitty call it makes, and the whole wait.
        cc_argv "$PANES_BIN"   # through its interpreter, never by path (scripts/lib/cc-run.sh)
        cout="$("${CC_ARGV[@]}" ${SOCK:+--to "$SOCK"} --expect "$exp" \
                --wait "${CC_RESTORE_CENSUS_S:-240}" --poll "${CC_RESTORE_CENSUS_POLL:-10}" 2>&1)" || crc=$?
        printf '%s\n' "$cout" | grep -v '^cc-panes: expect ok=' | sed 's/^/  /' >&2
        census_bad="$(printf '%s\n' "$cout" | sed -n 's/^cc-panes: expect ok=[0-9]* bad=\([0-9]*\).*/\1/p' | tail -1)"
        case "$crc" in
          0) census=ok; census_bad=0 ;;
          1) census=fail ;;
          *) census=unknown; note "cc-resume-layout: the census could not read kitty (rc $crc)" ;;
        esac
      else
        census=unavailable; note "cc-resume-layout: bin/cc-panes not found — no pane was read back"
      fi
    fi
    if [ "$DRY_RUN" = 1 ]; then verdict=ok
    elif [ "$launched" -eq 0 ] && [ "$maybe_left" -eq 0 ]; then verdict=failed
    elif [ "$census" = fail ]; then verdict=failed
    elif [ "$failed" -eq 0 ] && [ "$fs_bad" -eq 0 ] && [ "$maybe_left" -eq 0 ] && [ "$shed" -eq 0 ] && [ "$census" = ok ]; then verdict=ok
    elif [ "$failed" -eq 0 ] && [ "$fs_bad" -eq 0 ] && [ "$maybe_left" -eq 0 ] && [ "$census" = ok ]; then verdict=shed
    else verdict=degraded; fi
    printf 'cc-resume-layout: verdict=%s launched=%s shed=%s failed=%s windows=%s fullscreen_ok=%s fullscreen_failed=%s fullscreen_unknown=%s maybe=%s stopped=%s strays_closed=%s census=%s census_bad=%s\n' \
      "$verdict" "$launched" "$shed" "$failed" "$nwin" "$fs_ok" "$fs_bad" "$fs_unk" "$maybe_left" "$stopped" "$strays" "$census" "${census_bad:-0}"
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
    # RUNNER ROOT (runner_tail, above): the runner owns the pane's end.
    cmd="'env' 'CC_ADMIT_DONE=1' $(resume_one_q) $(shq "$acct") $(shq "$wt") $(shq "$sid")"
    [ -n "$br" ] && cmd="$cmd $(shq "$br")"
    LA=(launch)
    case "$pos" in
      0) LA+=(--type=os-window) ;;
      1|2) LA+=(--location=vsplit --match "window_id:$A" --next-to "id:$A") ;;
      *) anc="${B:-$A}"; LA+=(--location=vsplit --match "window_id:$anc" --next-to "id:$anc") ;;
    esac
    { [ -n "$wt" ] && [ -d "$wt" ]; } && LA+=(--cwd "$wt")
    LA+=(--env CC_ADMIT_DONE=1); runner_tail "$cmd"
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
                    --cwd "$wt" -- "${RESUME_ONE_ARGV[@]}" "$acct" "$wt" "$sid" "$br" 2>&1)"
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
               --cwd "$wt" -- "${RESUME_ONE_ARGV[@]}" "$acct" "$wt" "$sid" "$br" 2>&1)"
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
