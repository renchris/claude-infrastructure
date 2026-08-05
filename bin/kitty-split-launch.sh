#!/usr/bin/env bash
# kitty-split-launch.sh — open a new kitty split ANCHORED to a specific pane (default: the
# calling pane), never wherever kitty's globally-active tab happens to be.
#
# WHY THIS EXISTS. `kitty @ launch --location=vsplit` places the new window relative to kitty's
# INSTANCE-WIDE active tab — not the tab containing the pane that issued the command. All of a
# kitty instance's OS windows share one control socket and one "active tab" pointer (whichever
# tab was focused most recently), so `kitty @ launch --location=vsplit` fired from pane A, while
# the user's focus sits on pane B in a different OS window, splits B's tab — not A's.
#
# Measured 2026-08-05 (crash-recovery resume): three resumed sessions, launched this way from a
# Bash tool call whose own pane WAS the intended anchor, landed in an unrelated OS window instead
# — twice (once because the caller's own window id had been misidentified, once because kitty's
# active-tab default was trusted at all) — and had to be relocated by hand with
# `kitty @ detach-window --target-tab`.
#
# THE FIX. `kitty @ launch --match "window_id:<anchor>" --next-to "id:<anchor>"` anchors the
# split to an EXPLICITLY NAMED pane regardless of kitty's active-tab state. This is not a new
# discovery — bin/it2-kitty (Agent Teams' teammate-pane creation) has used exactly this pattern
# since it was written, and has never hit the bug above, because it always names its anchor
# rather than trusting kitty's default. This script is that pattern, standalone, for any other
# caller (resume flows, handoff, ad hoc automation) that wants "split next to a specific pane"
# instead of "split wherever kitty's UI focus happens to be".
#
# USAGE
#   kitty-split-launch.sh [--anchor <kitty-window-id>] [--location vsplit|hsplit] [--cwd DIR]
#                          [--title T] [--keep-focus] [--self-retire] -- CMD [ARGS...]
#
#   --anchor    kitty window id to split relative to. Default: $KITTY_WINDOW_ID — i.e. splits
#               land next to whoever RAN this script, not wherever kitty's UI focus happens to
#               be. Pass an explicit id (from `kitty @ ls`) to direct the split elsewhere — this
#               is the "direct them to other windows as needed" escape hatch; the default is not
#               a restriction, it is just what happens when nothing else is asked for.
#   --location  vsplit (right of anchor, default) | hsplit (below anchor)
#   --self-retire  the new pane is a FIRED PEER and may retire itself when its work is done.
#               Writes the fired-peer lifecycle record via `handoff-fire.sh stamp-peer`. Requires
#               --cwd (the stamp's cwd is the tenancy oracle self-close binds on). See below.
#
# Prints kitty @ launch's own stdout (the new window id) — chain further splits by passing that
# id as the next call's --anchor, which is how you stack more than one pane in the same column.
#
# ── WHY --self-retire EXISTS, AND WHY IT IS OPT-IN (item aba6bcbff6de, 2026-08-05) ──────────────
# A pane opened by this script was, until now, invisible to the whole session-lifecycle layer: no
# cc-registry row and no cc-fired stamp, because both are written only by handoff-fire's own fire
# path. For an ad-hoc split that is correct. For a DISPATCHED PEER it is a trap with no exit — the
# self-close origin gate refuses any pane that cannot prove it was fired, and that proof is the
# stamp. Measured 2026-08-05: pane 28 was opened here for the wt-handoff-kitty-daemon dispatch,
# landed its work as 4353c85f, and then could not retire; `--session-id $KITTY_WINDOW_ID` cleared
# the identity gate and hit the provenance gate immediately behind it. The pane and its worktree
# leaked until a human reaped them.
#
# It is OPT-IN because the stamp is a CAPABILITY, not a description. Its presence is what licenses
# cc-reaper to auto-reap the pane (mark_fired_peer: "stamping every fire would license the reaper
# against operator sessions"), so a blanket stamp here would hand every ad-hoc split — including
# ones a human is sitting in — to the reaper. The caller that dispatched a peer is the only party
# that knows it dispatched a peer, so it is the party that says so.
#
# ── WHY THE kitty BINARY IS RESOLVED ABSOLUTELY (item eafe3e78a852, 2026-08-05) ──────────────────
# This script used to invoke a BARE `kitty`. Hooks and launchd jobs run with
# PATH=/usr/bin:/bin:/usr/sbin:/sbin, which excludes Homebrew — so `kitty` did not exist for exactly
# the AUTOMATED callers this script was written to serve (resume flows, handoff, dispatch), while
# working perfectly from the operator's own shell. Worst possible polarity: green where a human
# tests it, dead where it runs. That is the identical defect that left a teammate pane open for
# 3h09m with its 653 MB claude.exe resident on 2026-08-01; bin/cc-kitty-bin exists as the ONE
# resolver for it, and its header already says "so the seventh file cannot reintroduce it". This
# file was the eighth, written after the resolver landed and never wired to it.
#
# Both call sites below take the resolved path — the `exec` AND the --self-retire capture. Fixing
# only the first would leave every stamped dispatch (the shape the item that created --self-retire
# was about) still dead under a minimal PATH.
set -euo pipefail

# Self-path resolved ONCE, up here, because two separate things below need it: the kitty resolver
# and handoff-fire lookup. ~/.claude/bin/kitty-split-launch.sh is a SYMLINK into this checkout
# (scripts/kitty-setup.sh), so the resolved sibling is the repo's own bin/ — which holds
# cc-kitty-bin whether or not install.sh has run since. Unresolved $0 is kept as the second
# candidate for the case where the deployed layer is the only one present.
_ks="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"

# Falling back to the previous spelling on any resolver miss keeps a partial deploy degraded rather
# than broken — cc-kitty-bin is a side-car and must never fail wider than itself.
#
# ${HOME:-} DELIBERATELY, and it is not defensive noise — measured. Bash expands the ENTIRE for-list
# before the loop body runs, so a bare $HOME under `set -u` aborts the whole script on the third
# candidate even when the FIRST one exists and would have resolved. That would make this resolver
# fail wider than the thing it is resolving: before this change the default path never read $HOME at
# all (only the opt-in --self-retire tail did), so a bare spelling here would have converted a
# working HOME-less launch into `HOME: unbound variable`. With :- the candidate degrades to a
# nonexistent path, `[ -x ]` rejects it, and the loop moves on.
CC_KITTY_BIN="${CC_TERM_KITTY:-kitty}"
for _CC_KB in "$(dirname "$_ks")/cc-kitty-bin" "$(dirname "$0")/cc-kitty-bin" "${HOME:-}/.claude/bin/cc-kitty-bin"; do
  [ -x "$_CC_KB" ] || continue
  _CC_KR="$("$_CC_KB" 2>/dev/null)" && [ -n "$_CC_KR" ] && { CC_KITTY_BIN="$_CC_KR"; break; }
done
KITTY="${CC_KITTY_BIN:-${CC_TERM_KITTY:-kitty}}"

anchor="${KITTY_WINDOW_ID:-}"
location="vsplit"
cwd=""
title=""
keep_focus=()
self_retire=0

while [ $# -gt 0 ]; do
  case "$1" in
    --anchor) anchor="$2"; shift 2 ;;
    --location) location="$2"; shift 2 ;;
    --cwd) cwd="$2"; shift 2 ;;
    --title) title="$2"; shift 2 ;;
    --keep-focus) keep_focus=(--keep-focus); shift ;;
    --self-retire) self_retire=1; shift ;;
    --) shift; break ;;
    *) echo "kitty-split-launch: unknown arg $1" >&2; exit 2 ;;
  esac
done

if [ -z "$anchor" ]; then
  echo "kitty-split-launch: no anchor — pass --anchor <window-id> or run from inside kitty (KITTY_WINDOW_ID unset)" >&2
  exit 2
fi
if [ $# -eq 0 ]; then
  echo "kitty-split-launch: no command given (after --)" >&2
  exit 2
fi

if [ "$self_retire" = 1 ] && [ -z "$cwd" ]; then
  # Refused rather than defaulted. Defaulting to $PWD would stamp the DISPATCHER's directory as the
  # peer's, and the origin gate binds tenancy on exactly that field — so the peer would be refused
  # as a stale tenant of a worktree it never ran in, which is the original bug wearing a stamp.
  echo "kitty-split-launch: --self-retire requires --cwd (the stamp's cwd is the tenancy oracle self-close binds on)" >&2
  exit 2
fi

args=(launch --type=window --location="$location" --match "window_id:$anchor" --next-to "id:$anchor")
[ -n "$cwd" ] && args+=(--cwd "$cwd")
[ -n "$title" ] && args+=(--title "$title")
[ "${#keep_focus[@]}" -gt 0 ] && args+=("${keep_focus[@]}")
args+=(-- "$@")

# The no-stamp path keeps the `exec` verbatim: same stdout, same exit status, same process. Only
# --self-retire needs this script to outlive the launch, so only it pays for a subshell.
[ "$self_retire" = 1 ] || exec "$KITTY" @ "${args[@]}"

# kitty @ launch prints the new window id, and it is the ONLY place that id exists — the caller
# needs it on stdout exactly as before, so capture, stamp, then re-emit verbatim.
new_id="$("$KITTY" @ "${args[@]}")"
printf '%s\n' "$new_id"

case "$new_id" in
  ''|*[!0-9]*)
    # A pane may well have been created; what failed is our ability to NAME it, and an unnamed pane
    # cannot be stamped. Loud, and never fatal to the launch the caller already got.
    echo "kitty-split-launch: --self-retire could not stamp — kitty @ launch printed no window id (got '${new_id}'); the pane is live but has no fired-peer stamp and will not be able to self-close." >&2
    exit 0 ;;
esac

# ONE writer for the stamp format: handoff-fire.sh owns mark_fired_peer, and `stamp-peer` is its
# sanctioned entry point for panes handoff-fire did not spawn itself. Resolve it the way the rest of
# this repo does — the symlink-resolved sibling first (via the $_ks computed at the top), so the fix
# is live the moment the file is, then the deployed layer.
hf=""
for cand in "$(dirname "$_ks")/../scripts/handoff-fire.sh" "$HOME/.claude/scripts/handoff-fire.sh"; do
  [ -x "$cand" ] && { hf="$cand"; break; }
done
if [ -z "$hf" ]; then
  echo "kitty-split-launch: --self-retire could not stamp — handoff-fire.sh not found; pane $new_id is live but will not be able to self-close." >&2
  exit 0
fi
"$hf" stamp-peer --pane "$new_id" --cwd "$cwd" --by "$anchor" \
  || echo "kitty-split-launch: --self-retire stamp FAILED for pane $new_id — it is live but will not be able to self-close." >&2
exit 0
