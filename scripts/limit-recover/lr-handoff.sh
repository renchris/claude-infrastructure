#!/bin/bash
# lr-handoff.sh — package a limit-interrupted session for zero-loss continuation
# on another account: audit + salvage bundle + transcript transplant + launch.
#
# Usage: lr-handoff.sh [--target next|next2|next3|next4|auto] [--model opus|fable|claude-<id>]
#                      [--effort low|medium|high|xhigh|max]
#                      [--sid SID] [--config-dir DIR] [--cwd PATH]
#                      [--context FILE] [--launch|--print-only]
#                      [--no-transplant] [--keep-source] [--force] [--close-source]
#                      [--source-pane PANE-ID] [--in-place]
#
# Defaults: sid/config from the live session env; --target auto routes via
# claude-accounts; --print-only mints $TMPDIR/lr-launch-<sid8>-XXXXXX.sh instead of firing.
#
# --effort: a handoff CONTINUES one session, so the successor must be able to keep the
# effort the source was running at. Without this flag `--model fable` hardcoded
# `--effort high` and a Fable-5-at-MAX session silently transplanted DOWN to high —
# the model was preserved and the reasoning tier was not, which is the half nobody
# checks because the statusline still says "Fable 5". Omitted ⇒ prior behaviour exactly
# (fable ⇒ high; opus ⇒ lr-fire-resume's account-derived default).
#
# --model: `opus` and `fable` are LABELS. `opus` passes NO model id downstream — lr-fire-resume
# resolves it from the model-config SSOT (versions.opus_latest), so there is exactly one copy of that
# perishable fact in the tree. A `claude-*` id is passed through verbatim, for a caller pinning a
# generation the current default is not.
#
# --source-pane <id>: with --close-source, retire THAT pane instead of this one — the form the
# overnight case actually needs. A session at 100% of its window cannot execute a turn, so the husk
# cannot run its own close and the recovery is driven from a third pane; --close-source alone there
# would close the driver. Admitted ONLY when ~/.claude/cc-registry/<id>.json independently names the
# same session id being transplanted (--sid). Missing row, no .session_id, or a different session
# REFUSES — the caller states the pairing, the registry proves it.
#
# --close-source: after the fire, retire THIS pane into the successor via
# `handoff-fire.sh self-close --successor <id> --transplanted-source`. Without it the source pane
# survives the transplant as a HUSK — a window over a transcript that moved to another account and
# will never produce another turn, indistinguishable from live work. Requires --launch and a real
# transplant (the close is admitted on the tombstone lr-transplant writes). If the successor's pane
# id could not be captured, NOTHING is closed: the command is printed and the exit is 3.
#
# --in-place (LIMIT_RECOVER_100P, 2026-09-09): the pane IS the continuation. After the transplant the
# source pane is RECYCLED onto the target account — `handoff-fire.sh --recycle --transplanted-source
# --resume-launcher <this launcher> --resume-cfg <target>` types /exit into the limit-blocked TUI,
# waits for its shell, and types `bash <launcher>` there — so the session resumes with the SAME
# window id and the SAME uuid on the new account: nothing new appears, nothing is left over. With
# --source-pane P it is the driver form (a third session or the launchd poller retires P; admitted on
# P's registry row + the tombstone the transplant just wrote); without it, this pane recycles itself.
# A source whose root process is the launcher itself (an expect-rooted pane fired by an older
# lr-handoff) cannot host a relaunch — its /exit would close the window — so handoff-fire refuses it
# and this script falls through to REPLACE-IN-PLACE: spawn the successor beside the SOURCE pane
# (never beside the driver) and retire the source through the existing --close-source path.
# Requires --launch and a real transplant; incompatible with --print-only, --no-transplant and
# --close-source (the recycle IS the retirement). Exit 0 recycled or replaced; 4 transplanted but the
# relaunch did not verify (the source is a tombstoned husk — the guard blocks its prompts — and the
# launcher path is printed for a manual relaunch).
#
# Output: bundle dir path on the last stdout line. Exit 0 ok, 2 error, 3 fired-but-not-closed.
set -euo pipefail

# ---- PANE-SPAWN LOG (item 1467ea1dad4f) --------------------------------------------------------
# Four spawn sites below (kitty split / iTerm2 split / kitty os-window / iTerm2 window), each on a
# recovery path that runs when a session has ALREADY died — i.e. precisely when nobody is watching
# and an unattributed pane is hardest to explain later. Absent library ⇒ silent no-op.
for _psl in "$(dirname "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")")/../../scripts/lib/pane-spawn-log.sh" \
            "${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/scripts/lib/pane-spawn-log.sh" \
            "${HOME:-}/.claude/scripts/lib/pane-spawn-log.sh"; do
  # shellcheck disable=SC1090  # runtime-resolved source; the ship gate runs shellcheck without -x
  [ -f "$_psl" ] && . "$_psl" 2>/dev/null && break
done
unset _psl

# Bound every call that reaches the iTerm2 / AppleEvent surface (machine-wide API wedge,
# 2026-07-26: a bare `it2 session list --json` returned rc 124 with zero output while blocked forks
# piled up). Both call sites `tell application id "com.googlecode.iterm2"` — the exact wedged surface; each already has a
# manual-fallback message on failure, so a cut degrades into a path that exists. (Both call sites
# now have a kitty arm as well — see the terminal dispatch at the launch block — and it is bounded
# through the SAME wrapper, so neither terminal can strand a recovery on an unbounded call.)
# timeout(1) is resolved by ABSOLUTE PATH as well as PATH — launchd jobs and hooks run with a
# minimal PATH excluding Homebrew, exactly where coreutils installs it, so a PATH-only lookup would
# leave the AUTOMATED callers unbounded while interactive shells stayed safe. No timeout(1) ⇒ run
# unbounded rather than break the call. Seams: LRH_OSA_TIMEOUT_S · LRH_OSA_TIMEOUT_BIN
# (set-but-EMPTY disables verbatim; `${VAR:-}` cannot tell unset from set-empty).
LRH_TIMEOUT_S="${LRH_OSA_TIMEOUT_S:-15}"
if [ -n "${LRH_OSA_TIMEOUT_BIN+set}" ]; then
  LRH_TIMEOUT_BIN="$LRH_OSA_TIMEOUT_BIN"
else
  LRH_TIMEOUT_BIN=""
  for _c in "$(command -v timeout 2>/dev/null || true)" "$(command -v gtimeout 2>/dev/null || true)" \
            /opt/homebrew/bin/timeout /usr/local/bin/timeout \
            /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
    [ -n "$_c" ] && [ -x "$_c" ] && { LRH_TIMEOUT_BIN="$_c"; break; }
  done
fi
lrh_bounded() {
  if [ -z "$LRH_TIMEOUT_BIN" ] || [ ! -x "$LRH_TIMEOUT_BIN" ]; then "$@"; return $?; fi
  "$LRH_TIMEOUT_BIN" -k 3 "$LRH_TIMEOUT_S" "$@"
}
# Resolve the kitty binary ABSOLUTELY. Hooks and launchd jobs run with a minimal PATH that excludes
# Homebrew, so a bare `kitty` does not exist for exactly the AUTOMATED callers this file serves —
# green where a human tests it, dead where it runs. That is what left a teammate pane open for 3h09m
# with its 653 MB claude.exe resident on 2026-08-01 (full account: bin/cc-kitty-bin header).
# Falling back to the previous spelling keeps a partial deploy degraded rather than broken.
CC_KITTY_BIN="${CC_TERM_KITTY:-kitty}"
# Candidate order matters: the SYMLINK-RESOLVED sibling first. ~/.claude/scripts/*.sh are symlinks
# into this checkout, so `dirname "$0"/../bin` alone points at ~/.claude/bin — which only holds
# cc-kitty-bin AFTER install.sh runs. Resolving the link first finds the repo's own bin/ and makes
# the fix live the moment the file does, instead of waiting on a deploy it cannot trigger.
# ${HOME:-} DELIBERATELY: bash expands the ENTIRE for-list before the loop body runs, so a bare
# $HOME under `set -u` aborts this whole script on the third candidate even when the FIRST one
# resolves. With :- it degrades to a nonexistent path `[ -x ]` rejects. See bin/kitty-split-launch.sh.
_CC_KS="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"
for _CC_KB in "$(dirname "$_CC_KS")/../../bin/cc-kitty-bin" "$(dirname "$0")/../../bin/cc-kitty-bin" "${HOME:-}/.claude/bin/cc-kitty-bin"; do
  [ -x "$_CC_KB" ] || continue
  _CC_KR="$("$_CC_KB" 2>/dev/null)" && [ -n "$_CC_KR" ] && { CC_KITTY_BIN="$_CC_KR"; break; }
done
# NOTE the ${CC_KITTY_BIN:-…} fallback at every call site below. These functions are EXTRACTED
# INDIVIDUALLY with sed by tests/*.bats ("NOTHING HERE EXECUTES scripts/handoff-fire.sh"), so a
# function that depends on a top-level variable is unset in every extracted-function test — measured
# 2026-08-01, it turned `it2py bgtab` red. Each call site therefore re-states the pre-resolution
# spelling as its own default: production gets the absolute path from the block above, an extracted
# function degrades to exactly the behaviour it had before this change.

# The kitty control socket gets the SAME bound as the AppleEvent surface. kitty's socket has no
# serializing queue to wedge the way iTerm2's Python API did on 2026-07-25, but an unbounded call
# in a RECOVERY path is the shape of that incident, not the app it happened to.
lrh_kitty() { # bounded `kitty @ …` — socket seam kept out of the call sites
  if [ -n "${CC_TERM_KITTY_TO:-}" ]; then lrh_bounded "${CC_KITTY_BIN:-${CC_TERM_KITTY:-kitty}}" @ --to "$CC_TERM_KITTY_TO" "$@"
  else lrh_bounded "${CC_KITTY_BIN:-${CC_TERM_KITTY:-kitty}}" @ "$@"; fi
}

# THE WINDOW IS NOT THE RESUME (measured 2026-09-08, on a real two-session limit recovery).
# `kitty @ launch` exits 0 and prints the new id the moment the WINDOW exists — which is before the
# launcher has run a single line. A launcher that then dies on its own gate leaves this file
# announcing "fired split pane" / "fired new kitty window" over a window that closed a second later:
# that day BOTH fires reported success, both windows were gone, neither resume ever started, and the
# only trace was two consumed kitty ids. (The killer was capacity-admit refusing the resume with
# exit 9 — a loaded machine is exactly the state a limit recovery runs in, so this is the common
# case, not the exotic one.) The iTerm2 arms only ever claim a fire they VERIFIED via
# osa_type_verified; the kitty arms claimed the launch instead. This closes that asymmetry.
#
# rc 0 = the window is alive, OR the listing cannot discriminate; rc 1 = a USABLE listing that does
# not carry the id. Two indeterminate readings are deliberately treated as alive, matching the
# census suite's property 1 (INDETERMINATE ≠ ZERO — a zero lets a caller act on a live fleet):
# an unreadable/empty `kitty @ ls`, and a listing carrying no window ids at all (impossible for a
# live kitty, therefore an instrument fault rather than evidence of death).
# Seam: LRH_KITTY_SETTLE_S (seconds to wait before reading; 0 = read immediately, for tests).
lrh_kitty_window_alive() {
  local _id="$1" _ls _ids _seen
  [ -n "$_id" ] || return 0
  [ "${LRH_KITTY_SETTLE_S:-4}" = 0 ] || sleep "${LRH_KITTY_SETTLE_S:-4}"
  _ls="$(lrh_kitty ls 2>/dev/null || true)"
  [ -n "$_ls" ] || return 0
  # grep -c, never -q: under `set -o pipefail` a -q exits on the first match, SIGPIPEs its producer,
  # and the pipeline then reports FAILURE over the very input it matched.
  _ids="$(printf '%s' "$_ls" | grep -Ec '"id"[[:space:]]*:[[:space:]]*[0-9]+' || true)"
  [ "${_ids:-0}" -gt 0 ] || return 0
  _seen="$(printf '%s' "$_ls" | grep -Ec "\"id\"[[:space:]]*:[[:space:]]*${_id}([^0-9]|\$)" || true)"
  [ "${_seen:-0}" -gt 0 ]
}


LR="$HOME/.claude/scripts/limit-recover"
TARGET="auto" MODEL="opus" EFFORT="" SID="${CLAUDE_CODE_SESSION_ID:-}" CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
# ── SOURCE IDENTITY HELPERS (LIMIT_RECOVER_100P, 2026-09-09) ─────────────────────────────────────
# Three facts about the SOURCE session must be read while it still exists, and none of them is where
# the old code looked (docs/research/lr100p-2026-09-09/q-relaunch-command.md § Tier carry, MEASURED):
#   · the RUNTIME tier lives in the TRANSCRIPT (per-turn message.model + effort), never in argv — pane
#     616 ran claude-fable-5-1/xhigh while its argv said claude-opus-5/high, and the poller's tier-less
#     launcher landed it on Opus/max;
#   · CLAUDE_CODE_TASK_LIST_ID and --permission-mode live only in the PROCESS env/argv and die with it;
#   · the registry row carries neither.
lrh_own_claude_pid() { # → the claude pid this script runs UNDER (the local, self-recycling form), or nothing
  local p="$$" c n=0
  while [[ -n "$p" && "$p" != 0 && "$p" != 1 && $n -lt 16 ]]; do
    c="$(ps -o comm= -p "$p" 2>/dev/null || true)"
    case "${c##*/}" in claude*|node*) printf '%s' "$p"; return 0 ;; esac
    p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ' || true)"; n=$((n + 1))
  done
  return 1
}
# The tier read, the runner resolution and the pane-argv shape live in lr-lib.sh — ONE home, shared
# with lr-reset-poller.sh and lr-fleet.sh (memory: sibling-auditors-must-share-the-state-model).
LRH_LIB=""
for _lrh_lib in "$(dirname "$_CC_KS")/lr-lib.sh" "$(dirname "$0")/lr-lib.sh" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/limit-recover/lr-lib.sh" "$HOME/.claude/scripts/limit-recover/lr-lib.sh"; do
  [[ -f "$_lrh_lib" ]] && { LRH_LIB="$_lrh_lib"; break; }
done
[[ -n "$LRH_LIB" ]] || { echo "lr-handoff: FATAL — cannot find lr-lib.sh beside this script, in \$CLAUDE_CONFIG_DIR/scripts/limit-recover or ~/.claude/scripts/limit-recover" >&2; exit 2; }
LR_LIB_DIR="$(cd "$(dirname "$LRH_LIB")" && pwd)"; export LR_LIB_DIR
# shellcheck source=lr-lib.sh
# shellcheck disable=SC1091
. "$LRH_LIB"
lrh_tier_from_transcript() { lr_tier_from_transcript "$@"; }
# shellcheck disable=SC2153  # LR_LAUNCH_TAIL / LR_SPAWN_SHAPE are lr-lib.sh's outputs, not LRH_ typos
lrh_launch_tail() { lr_launch_tail "$LAUNCHER"; LRH_LAUNCH_TAIL=("${LR_LAUNCH_TAIL[@]}"); LRH_SPAWN_SHAPE="$LR_SPAWN_SHAPE"; }
LRH_LAUNCH_TAIL=()
LRH_SPAWN_SHAPE=""

CWD="$(pwd)" CONTEXT="" LAUNCH=0 PRINT_ONLY=0 NO_TRANSPLANT=0 KEEP_SOURCE=0 FORCE=0 CLOSE_SOURCE=0 IN_PLACE=0
MODEL_EXPLICIT=0 EFFORT_EXPLICIT=0
SOURCE_PANE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --model) MODEL="$2"; MODEL_EXPLICIT=1; shift 2 ;;
    --effort) EFFORT="$2"; EFFORT_EXPLICIT=1; shift 2 ;;
    --sid) SID="$2"; shift 2 ;;
    --config-dir) CFG="$2"; shift 2 ;;
    --cwd) CWD="$2"; shift 2 ;;
    --context) CONTEXT="$2"; shift 2 ;;
    --launch) LAUNCH=1; shift ;;
    --print-only) PRINT_ONLY=1; shift ;;
    --no-transplant) NO_TRANSPLANT=1; shift ;;
    --keep-source) KEEP_SOURCE=1; shift ;;
    --force) FORCE=1; shift ;;
    --close-source) CLOSE_SOURCE=1; shift ;;
    --source-pane) SOURCE_PANE="$2"; shift 2 ;;
    --in-place) IN_PLACE=1; shift ;;
    *) echo "lr-handoff: unknown arg $1" >&2; exit 2 ;;
  esac
done
[[ -n "$SID" ]] || { echo "lr-handoff: no --sid and CLAUDE_CODE_SESSION_ID unset" >&2; exit 2; }
# --close-source retires THIS pane once the successor is carrying the session. Both of its
# preconditions are decidable here, before any work is done, and both are incoherence rather than
# bad luck — so refuse now rather than fire and fail at the end.
if [[ $IN_PLACE -eq 1 ]]; then
  if [[ $LAUNCH -ne 1 || $PRINT_ONLY -eq 1 ]]; then
    echo "lr-handoff: --in-place needs --launch (and not --print-only) — the recycle IS the launch" >&2; exit 2
  fi
  if [[ $NO_TRANSPLANT -eq 1 ]]; then
    echo "lr-handoff: --in-place is incompatible with --no-transplant — the recycle is admitted on the transplant tombstone, which --no-transplant never writes" >&2; exit 2
  fi
  if [[ $CLOSE_SOURCE -eq 1 ]]; then
    echo "lr-handoff: --in-place and --close-source are two dispositions of the same pane; the recycle IS the retirement — pass one" >&2; exit 2
  fi
fi
if [[ $CLOSE_SOURCE -eq 1 ]]; then
  # Nothing was fired ⇒ no successor exists ⇒ there is nothing for the close to hand off to.
  if [[ $LAUNCH -ne 1 || $PRINT_ONLY -eq 1 ]]; then
    echo "lr-handoff: --close-source needs --launch (and not --print-only) — closing this pane with nothing fired strands the work" >&2; exit 2
  fi
  # handoff-fire's transplanted-source class is admitted on the TOMBSTONE lr-transplant writes. With
  # --no-transplant there is no transplant and no tombstone, so the close would be refused there —
  # correctly, and only after this pane had already fired. Say so now.
  if [[ $NO_TRANSPLANT -eq 1 ]]; then
    echo "lr-handoff: --close-source is incompatible with --no-transplant — the close is admitted on the transplant tombstone, which --no-transplant never writes" >&2; exit 2
  fi
fi
# --source-pane retires a pane OTHER than this one. THE CASE THE FLAG EXISTS FOR (measured
# 2026-08-10): three sessions were transplanted off next3 while next3 sat at 100% of its 5-hour
# window. A session at its limit cannot execute a turn, so it cannot run the command that closes it
# — the transplant has to be driven from a THIRD pane, where --close-source alone would have closed
# the DRIVER. It was not used, and three husk panes were left standing.
#
# THE BINDING, and why the naive version of this flag was correctly refused: letting a caller assert
# "pane P holds session X" with nothing tying P to X closes an innocent pane that merely got named.
# The evidence already exists and already has a consumer — ~/.claude/cc-registry/<pane>.json, written
# by hooks/session-start.sh, carries that pane's own session_id, and handoff-fire's successor_pin
# reads exactly this row to prove the SUCCESSOR half of this same close. So the pairing is checked,
# never asserted: the row for P must name the sid being transplanted.
#
# THIS COPY IS AN ADVANCE CHECK, NOT THE GATE. handoff-fire.sh re-runs it at the close and is the
# arbiter (a predicate re-implemented outside its actuator drifts from it — so this one deliberately
# reads the SAME row, the SAME field, and refuses on the SAME three states). Its only job is the one
# the two preconditions above already do: a mismatch is decidable now, and refusing now costs a
# message, while refusing at the end costs a transplant that has already moved the transcript.
if [[ -n "$SOURCE_PANE" ]]; then
  if [[ $CLOSE_SOURCE -ne 1 ]]; then
    if [[ $IN_PLACE -ne 1 ]]; then
      echo "lr-handoff: --source-pane names the pane --close-source should retire, so it needs --close-source (or --in-place, which recycles it)" >&2; exit 2
    fi
  fi
  LRH_REG="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}/$SOURCE_PANE.json"
  if [[ ! -f "$LRH_REG" ]]; then
    echo "lr-handoff: --source-pane $SOURCE_PANE has no session-registry row ($LRH_REG) — that row is the only thing tying a named pane to the session it holds, so there is nothing here to prove this is the transplanted session's pane" >&2; exit 2
  fi
  command -v jq >/dev/null 2>&1 || { echo "lr-handoff: --source-pane needs jq to read $LRH_REG — unreadable evidence is not evidence" >&2; exit 2; }
  LRH_REG_SID="$(jq -r '.session_id // empty' "$LRH_REG" 2>/dev/null || true)"
  if [[ -z "$LRH_REG_SID" ]]; then
    echo "lr-handoff: the registry row for pane $SOURCE_PANE names no .session_id — it records that a pane exists, not which session lives in it" >&2; exit 2
  fi
  if [[ "$LRH_REG_SID" != "$SID" ]]; then
    echo "lr-handoff: REFUSED — pane $SOURCE_PANE does NOT hold session ${SID:0:8}; the registry says it holds ${LRH_REG_SID:0:8} ($LRH_REG). Closing it would retire a live session that merely got named." >&2; exit 2
  fi
fi
# Reject an unknown effort HERE rather than let it reach the launcher. %q already makes the
# value inert as source, so this is not a quoting defence — it is a liveness one: the binary
# refuses an unrecognised --effort at startup, and that refusal would land in a freshly spawned
# pane on the transplanted session, i.e. after the transcript has already moved accounts.
case "$EFFORT" in
  ""|low|medium|high|xhigh|max) ;;
  *) echo "lr-handoff: --effort must be low|medium|high|xhigh|max (got '$EFFORT')" >&2; exit 2 ;;
esac
# Same liveness argument for --model: `opus` and `fable` are LABELS this script maps, anything else
# is passed through as a literal model id. Requiring the `claude-` prefix rejects a mistyped label
# (`opus5`, `sonnet`) HERE, rather than as a binary startup refusal in a freshly spawned pane — i.e.
# after the transcript has already moved accounts. It deliberately does not enumerate ids: that list
# is perishable, and hardcoding one is the defect this whole change is about.
case "$MODEL" in
  opus|fable|claude-*) ;;
  *) echo "lr-handoff: --model must be opus|fable or an explicit claude-* model id (got '$MODEL')" >&2; exit 2 ;;
esac
CFG="${CFG/#\~/$HOME}"

# --- account routing --------------------------------------------------------
# Backed by the accounts.json-generated map (any N accounts) — see lib/account-map.generated.sh.
# shellcheck source=/dev/null
for _CC_AM in "${CC_ACCOUNT_MAP:-}" "$(dirname "$0")/../../lib/account-map.generated.sh" "$HOME/.claude/lib/account-map.generated.sh"; do
  [ -n "$_CC_AM" ] && [ -f "$_CC_AM" ] && { source "$_CC_AM"; break; }
done
acct_to_cfg() {
  if cc_acct_dir_for_name "$1"; then echo "$CC_ACCT_DIR"; else echo ""; fi
}
if [[ "$TARGET" == "auto" ]]; then
  kind="general"; case "$MODEL" in fable|claude-fable-*) kind="fable" ;; esac
  TARGET=$("$HOME/bin/claude-accounts" --route "$kind" 2>/dev/null | tr -d '[:space:]' || true)
  [[ -n "$TARGET" ]] || { echo "lr-handoff: claude-accounts --route $kind returned nothing — pass --target explicitly" >&2; exit 2; }
fi
TCFG=$(acct_to_cfg "$TARGET")
[[ -n "$TCFG" && -d "$TCFG" ]] || { echo "lr-handoff: bad target '$TARGET'" >&2; exit 2; }
SRC_REAL=$(python3 -c "import os,sys;print(os.path.realpath(sys.argv[1]))" "$CFG/projects")
TGT_REAL=$(python3 -c "import os,sys;print(os.path.realpath(sys.argv[1]))" "$TCFG/projects")
if [[ "$SRC_REAL" == "$TGT_REAL" && $FORCE -ne 1 ]]; then
  echo "lr-handoff: REFUSED — target '$TARGET' shares the source account's session store (use --force to override)" >&2
  exit 2
fi

# --- repo guards -----------------------------------------------------------
BRANCH="" HEAD="" WT_TOP=""
if git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
  WT_TOP=$(git -C "$CWD" rev-parse --show-toplevel)
  BRANCH=$(git -C "$CWD" branch --show-current || true)
  HEAD=$(git -C "$CWD" rev-parse --short HEAD 2>/dev/null || true)
  if [[ "$BRANCH" == pool/* ]]; then
    NEWBR="recovered/${SID:0:8}"
    git -C "$CWD" switch -C "$NEWBR" >&2
    echo "lr-handoff: branch was $BRANCH (pool refresher would hard-reset it) — renamed to $NEWBR" >&2
    BRANCH="$NEWBR"
  fi
  DIRTY=$(git -C "$CWD" status --porcelain | wc -l | tr -d ' ')
  [[ "$DIRTY" != "0" ]] && echo "lr-handoff: WARNING — $DIRTY dirty paths; commit in-scope WIP before firing (bundle records the list)" >&2
fi

# --- bundle ----------------------------------------------------------------
# ── READ THE SOURCE'S IDENTITY WHILE IT STILL EXISTS ────────────────────────────────────────────
SRC_PID="" SRC_ARGV="" SRC_TASK_LIST="" SRC_PERM="" RT_MODEL="" RT_EFFORT=""
if [[ -n "${LR_SOURCE_PID+x}" ]]; then
  SRC_PID="$LR_SOURCE_PID"                          # test seam: name the process (or none) explicitly
elif [[ -n "$SOURCE_PANE" ]]; then
  SRC_PID="$(jq -r '.pid // empty' "$LRH_REG" 2>/dev/null || true)"
elif [[ -n "${CLAUDE_CODE_SESSION_ID:-}" && "${CLAUDE_CODE_SESSION_ID}" == "$SID" ]]; then
  # The local form IS the session: its own ancestry is the source's. Gated on the sid match so a
  # driver (or a test harness) running lr-handoff for SOME OTHER session never reads its own claude
  # as the source — measured 2026-09-09 as a hermeticity leak in tests/lr-handoff-launcher-quoting.
  SRC_PID="$(lrh_own_claude_pid || true)"
  SRC_TASK_LIST="${CLAUDE_CODE_TASK_LIST_ID:-}"
fi
if [[ -n "$SRC_PID" ]] && kill -0 "$SRC_PID" 2>/dev/null; then
  SRC_ARGV="$(ps -Eww -o command= -p "$SRC_PID" 2>/dev/null || true)"
  _tl="$(printf '%s' "$SRC_ARGV" | tr ' ' '\n' | sed -n 's/^CLAUDE_CODE_TASK_LIST_ID=//p' | awk 'NR<=1')"
  [[ -n "$_tl" ]] && SRC_TASK_LIST="$_tl"
  SRC_PERM="$(printf '%s' "$SRC_ARGV" | sed -n 's/.*--permission-mode \([A-Za-z]*\).*/\1/p' | awk 'NR<=1')"
fi
if _rt="$(lrh_tier_from_transcript "$CFG" "$SID")"; then
  RT_MODEL="${_rt%% *}"; RT_EFFORT="${_rt#* }"; [[ "$RT_EFFORT" == "$_rt" ]] && RT_EFFORT=""
fi
# The transcript's tier is what the session was ACTUALLY running when it hit the limit; an explicit
# --model/--effort from the caller still wins (a thinking session states its own tier). A label
# ("opus"/"fable") is not a tier — it is replaced by the measured model id when one is on disk.
if [[ $MODEL_EXPLICIT -eq 0 && -n "$RT_MODEL" ]]; then
  echo "lr-handoff: tier carried from the transcript: model $RT_MODEL${RT_EFFORT:+ effort $RT_EFFORT} (argv said: $(printf '%s' "$SRC_ARGV" | sed -n 's/.*\(--model [^ ]*\).*/\1/p' | head -1))" >&2
  MODEL="$RT_MODEL"
fi
if [[ $EFFORT_EXPLICIT -eq 0 && -z "$EFFORT" && -n "$RT_EFFORT" ]]; then EFFORT="$RT_EFFORT"; fi
case "$MODEL" in claude-fable-*) [[ "$TARGET" == "auto" ]] && echo "lr-handoff: a Fable session routes on the fable lane" >&2 ;; esac

TS=$(date -u +%Y%m%dT%H%M%SZ)
BUNDLE="$HOME/.reso/limit-recover/$SID/bundle-$TS"
mkdir -p "$BUNDLE"
set +e
python3 "$LR/lr-audit.py" --config-dir "$CFG" --session "$SID" --cwd "$CWD" \
  --json "$BUNDLE/audit.json" --md "$BUNDLE/audit.md" \
  --salvage-dir "$BUNDLE/salvage" --quiet
AUDIT_RC=$?
set -e
[[ $AUDIT_RC -eq 2 ]] && { echo "lr-handoff: lr-audit failed (artifacts missing)" >&2; exit 2; }

SESSION_DIR=$(jq -r '.session_dir' "$BUNDLE/audit.json")
[[ -d "$SESSION_DIR/workflows/scripts" ]] && rsync -a "$SESSION_DIR/workflows/scripts/" "$BUNDLE/workflow-scripts/"
if [[ -n "$CONTEXT" && -f "$CONTEXT" ]]; then
  cp "$CONTEXT" "$BUNDLE/HANDOFF-CONTEXT.md"
else
  # A DRIVER (or the poller) cannot author narrative — the source cannot be asked. Quote disk, mark
  # the rest UNRECONSTRUCTED (commands/limit-recover.md § ingest honours the marker: STOP-ASK before
  # assuming). Every field below is mechanically derived; none is a judgment.
  _dod=""
  for _dp in "$(dirname "$0")/../../hooks/lib/dod-path.sh" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/dod-path.sh" "$HOME/.claude/hooks/lib/dod-path.sh"; do
    if [[ -f "$_dp" ]]; then
      # shellcheck disable=SC1090  # runtime-resolved library; fail-open
      _dod="$( { . "$_dp" && dod_read_content "${WT_TOP:-$CWD}"; } 2>/dev/null || true)"
      break
    fi
  done
  _last_msg="$(/usr/bin/python3 - "$CFG" "$SID" <<'PY' 2>/dev/null || true
import glob, json, sys
cfg, sid = sys.argv[1], sys.argv[2]
files = glob.glob(f"{cfg}/projects/*/{sid}.jsonl") + glob.glob(f"{cfg}/projects/*/{sid}.jsonl.handed-off")
last_limit = None; texts = []
for f in files:
    for line in open(f, errors="replace"):
        if '"assistant"' not in line:
            continue
        try:
            d = json.loads(line)
        except Exception:
            continue
        if d.get("type") != "assistant":
            continue
        m = d.get("message") if isinstance(d.get("message"), dict) else {}
        c = m.get("content")
        txt = c if isinstance(c, str) else " ".join(x.get("text", "") for x in (c or []) if isinstance(x, dict) and x.get("type") == "text")
        if d.get("isApiErrorMessage"):
            if "hit your" in txt:
                last_limit = d.get("timestamp") or ""
            continue
        if txt.strip():
            texts.append((d.get("timestamp") or "", txt.strip()))
pick = [t for t in texts if not last_limit or t[0] < last_limit]
print((pick[-1][1] if pick else "")[:2000])
PY
)"
  { echo "# HANDOFF-CONTEXT — UNRECONSTRUCTED (written by the recovery driver, not by the session)"
    echo
    echo "The source session ${SID:0:8} could not be asked (limit-blocked). Everything below is QUOTED FROM DISK by lr-handoff.sh; treat scope as UNRECONSTRUCTED and STOP-ASK before assuming anything the audit does not prove."
    echo
    echo "## Scope (frozen) — durable DoD store for this repo"
    if [[ -n "$_dod" ]]; then printf '%s\n' "$_dod"; else echo "UNRECONSTRUCTED — no DoD capture for ${WT_TOP:-$CWD}"; fi
    echo
    echo "## Tier at the limit"
    echo "model ${RT_MODEL:-unknown} · effort ${RT_EFFORT:-unknown} · permission-mode ${SRC_PERM:-auto} · task list ${SRC_TASK_LIST:-none}"
    echo
    echo "## Last assistant message before the limit"
    if [[ -n "$_last_msg" ]]; then printf '%s\n' "$_last_msg"; else echo "(none found)"; fi
    echo
    echo "## Worktree"
    echo "cwd ${WT_TOP:-$CWD} · branch ${BRANCH:-?} · head ${HEAD:-?} · dirty paths ${DIRTY:-?} (git-status.txt / git-log.txt beside this file)"
    echo
    echo "## Next action"
    echo "UNRECONSTRUCTED — run Step 0 (lr-audit) in the target and derive the next action from audit.md and the transcript; the driver did not guess one."
  } > "$BUNDLE/HANDOFF-CONTEXT.md"
fi
if git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$CWD" status --porcelain > "$BUNDLE/git-status.txt" || true
  git -C "$CWD" log --oneline -15 > "$BUNDLE/git-log.txt" || true
fi

INGEST_PROMPT="/limit-recover ingest $BUNDLE"
jq -n \
  --arg sid "$SID" --arg source_cfg "$CFG" --arg target "$TARGET" --arg target_cfg "$TCFG" \
  --arg cwd "$CWD" --arg wt "$WT_TOP" --arg branch "$BRANCH" --arg head "$HEAD" \
  --arg ts "$TS" --arg model "$MODEL" --arg task_list "$SRC_TASK_LIST" \
  --arg sha "$(jq -r '.transcript_sha256' "$BUNDLE/audit.json")" \
  --arg gaps "$(jq -r '.counts.gaps' "$BUNDLE/audit.json")" \
  --arg ingest "$INGEST_PROMPT" \
  --arg src_argv "$SRC_ARGV" --arg rt_model "$RT_MODEL" --arg rt_effort "${EFFORT:-$RT_EFFORT}" --arg perm "${SRC_PERM:-auto}" \
  --arg src_pane "${SOURCE_PANE:-}" --arg in_place "$IN_PLACE" \
  '{sid:$sid, source_cfg:$source_cfg, target:$target, target_cfg:$target_cfg, cwd:$cwd,
    worktree:$wt, branch:$branch, head:$head, ts:$ts, model:$model, task_list:$task_list,
    transcript_sha256:$sha, gaps_at_handoff:($gaps|tonumber), ingest_prompt:$ingest,
    source_argv:$src_argv, runtime_model:$rt_model, runtime_effort:$rt_effort, permission_mode:$perm,
    source_pane:$src_pane, in_place:($in_place=="1")}' \
  > "$BUNDLE/MANIFEST.json"

# --- transplant ------------------------------------------------------------
if [[ $NO_TRANSPLANT -ne 1 ]]; then
  TARGS=(--sid "$SID" --from "$CFG" --to "$TCFG")
  [[ -n "$SRC_TASK_LIST" ]] && TARGS+=(--task-list "$SRC_TASK_LIST")   # the SOURCE's board, never the driver's
  [[ $KEEP_SOURCE -eq 1 ]] && TARGS+=(--keep-source)
  [[ $FORCE -eq 1 ]] && TARGS+=(--force)
  "$LR/lr-transplant.sh" "${TARGS[@]}" > "$BUNDLE/transplant.json"
  echo "lr-handoff: transplant ok -> $(jq -r '.target_transcript' "$BUNDLE/transplant.json")" >&2
fi

# --- pre-seed the resume environment (as EARLY as possible) ----------------
# Set the iTerm2 clear-scrollback pref + target-account folder-trust NOW, before the
# osascript opens the pane, so iTerm2's async cross-process pref-read has SECONDS to
# land before the new pane's TUI emits CSI 3 J — closing the write-then-launch race
# (lr-fire-resume.sh re-runs it too; idempotent, fail-open).
"$LR/lr-preseed-env.sh" "$TCFG" "${WT_TOP:-$CWD}" || true

# --- launch ----------------------------------------------------------------
# Per-uid 0700 temp dir, not the mode-1777 /tmp (CWE-377/CWE-59). This file is written, chmod +x'd
# and then executed BY PATH from another process (an iTerm2 pane types `exec /bin/bash $LAUNCHER`),
# so a name another uid can pre-create turns the `cat >` into an arbitrary-file clobber plus a
# chmod +x on the target. `${TMPDIR:-/tmp}` alone is not enough — launchd does not inject TMPDIR
# into agent jobs (measured 2026-07-30), so getconf reads the per-uid dir from confstr instead.
lrh_tmpdir() {
  local d="${TMPDIR:-}"
  [[ -n "$d" ]] || d="$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null || true)"
  { [[ -n "$d" ]] && [[ -d "$d" ]] && [[ -w "$d" ]]; } || d="/tmp"
  printf '%s' "${d%/}"
}
# MINT THE UNIQUE NAME FIRST, ADD `.sh` AFTER: BSD mktemp only substitutes a TRAILING `XXXXXX`, so
# a `…-XXXXXX.sh` template yields that LITERAL constant name and every mint after the first dies
# `File exists`. The suffix is kept because --print-only hands this path to `cursor` and to the
# operator as the manual fallback. ${SID:0:8} is a readability prefix, never the entropy.
LAUNCHER="$(mktemp "$(lrh_tmpdir)/lr-launch-${SID:0:8}-XXXXXX")" || {
  echo "lr-handoff: could not mint a launch script in a secure temp dir" >&2; exit 1; }
mv "$LAUNCHER" "$LAUNCHER.sh" && LAUNCHER="$LAUNCHER.sh"
# The launcher is GENERATED BASH that is then EXECUTED (`write text "exec /bin/bash $LAUNCHER"`
# in both osascript branches below, and by hand on the manual-fallback path) — so every field
# interpolated here is SOURCE, not data. An unquoted one is arbitrary code execution, not a
# quoting nit. `git check-ref-format` ACCEPTS $ ` ( ) ; | & ' " in a branch name — it refuses
# only control chars, space, ~, ^ and : , and ${IFS} substitutes for the space — so a branch
# this session did not NAME (a fetched remote/PR branch, a pool/* name, any name read rather
# than authored) carries a payload straight into the launcher. Worse, it lands SILENTLY: the
# `"$BRANCH"` quotes in the old `${BRANCH:+--branch "$BRANCH"}` were consumed by the WRITING
# shell, so the payload was emitted unquoted and the substitution left a plausible `--branch wip`
# in the launcher's argv with nothing to show code had run.
# Build the argv as an ARRAY and render it with %q, which round-trips under bash 3.2 (the
# /bin/bash that runs the launcher) and never emits a raw newline — that single-line guarantee
# is also what keeps the header comments below un-escapable.
FIRE_ARGV=("$LR/lr-fire-resume.sh" "$TARGET" "${WT_TOP:-$CWD}" "$SID")
[[ -n "$BRANCH" ]] && FIRE_ARGV+=(--branch "$BRANCH")
case "$MODEL" in
  fable)
    FIRE_ARGV+=(--model claude-fable-5-1 --effort "${EFFORT:-high}")
    ;;
  opus)
    # The opus path passes no --model ON PURPOSE: lr-fire-resume resolves it from the model-config
    # SSOT (versions.opus_latest). Naming an id here would put a SECOND copy of a perishable fact in
    # the tree, and the first copy is exactly what silently pinned every non-fable transplant to Opus
    # 4.8 for weeks after the Opus 5 flip. An explicit --effort must still reach it, or the flag
    # would be silently fable-only.
    if [[ -n "$EFFORT" ]]; then FIRE_ARGV+=(--effort "$EFFORT"); fi
    ;;
  *)
    # An explicit model id, passed through verbatim — a caller pinning a specific generation (a
    # session being moved that was NOT on the current default) must be able to say so.
    FIRE_ARGV+=(--model "$MODEL")
    if [[ -n "$EFFORT" ]]; then FIRE_ARGV+=(--effort "$EFFORT"); fi
    ;;
esac
[[ -n "$SRC_PERM" ]] && FIRE_ARGV+=(--permission-mode "$SRC_PERM")
FIRE_ARGV+=(--prompt "$INGEST_PROMPT")
# The launcher restores the two env vars lr-fire-resume's spawn whitelist would otherwise lose
# (q-relaunch-command.md § env): the nested-subagent depth bound and the SOURCE's task board. It is
# run as `bash <launcher>` — never `exec bash` — by every path below, so the pane's shell survives.
cat > "$LAUNCHER" <<EOF
#!/bin/bash
# Resume the handed-off session $(printf '%q' "$SID") on account $(printf '%q' "$TARGET") with the ingest prompt.
# Regenerable: bundle at $(printf '%q' "$BUNDLE")
export CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH="\${CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH:-1}"
${SRC_TASK_LIST:+export CLAUDE_CODE_TASK_LIST_ID=$(printf '%q' "$SRC_TASK_LIST")}
exec $(printf '%q ' "${FIRE_ARGV[@]}")
EOF
chmod +x "$LAUNCHER"

# handoff-fire.sh — the ONE actuator for both the in-place recycle and the close-source retirement.
lrh_hf_bin() {
  local hf="${CC_HANDOFF_FIRE_BIN:-}"
  [[ -n "$hf" ]] || hf="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/../handoff-fire.sh"
  [[ -f "$hf" ]] || hf="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/handoff-fire.sh"
  [[ -f "$hf" ]] || hf="$HOME/.claude/scripts/handoff-fire.sh"
  printf '%s' "$hf"
}

# ── IN-PLACE (LIMIT_RECOVER_100P): the pane IS the continuation ──────────────────────────────────
# Ordering is load-bearing: the transplant above ALREADY wrote the lock + tombstone, so at this point
# the source is PROVABLY retired at its pane — which is what admits a driver that does not own the
# pane to type /exit into it (handoff-fire's remote form replaces the self-identity gate with the
# registry binding + this tombstone). The relaunch is `bash <launcher>` — the same launcher the spawn
# paths below hand to a NEW pane, typed into the OLD pane's surviving shell instead, and NOT exec'd,
# so the shell outlives the resumed session and the pane stays recyclable next time.
LRH_REPLACE=0
if [[ $IN_PLACE -eq 1 ]]; then
  HF="$(lrh_hf_bin)"
  if [[ ! -x "$HF" ]]; then
    echo "lr-handoff: --in-place cannot reach handoff-fire.sh (looked beside this script, in \$CLAUDE_CONFIG_DIR/scripts, and in ~/.claude/scripts). The transplant is DONE; relaunch by hand as a NEW pane's own command: exec /bin/bash $LAUNCHER" >&2
    echo "$BUNDLE"; exit 4
  fi
  RCY_ARGS=(--recycle --transplanted-source --resume-launcher "$LAUNCHER" --resume-cfg "$TCFG" --resume-cwd "${WT_TOP:-$CWD}")
  if [[ -n "$SOURCE_PANE" ]]; then
    RCY_ARGS+=(--source-pane "$SOURCE_PANE" --source-session "$SID" --await)
    echo "lr-handoff: IN-PLACE — recycling pane $SOURCE_PANE (registry-bound to ${SID:0:8}) onto '$TARGET': same window, same uuid" >&2
  else
    echo "lr-handoff: IN-PLACE — recycling THIS pane onto '$TARGET': same window, same uuid ${SID:0:8} (the /exit ends this process; the watcher carries the relaunch)" >&2
  fi
  LRH_RCY_ERR="$(mktemp "$(lrh_tmpdir)/lr-inplace-XXXXXX")" || LRH_RCY_ERR=/dev/null
  set +e
  "$HF" "${RCY_ARGS[@]}" 2> >(tee "$LRH_RCY_ERR" >&2)
  LRH_RCY_RC=$?
  set -e
  if [[ $LRH_RCY_RC -eq 0 ]]; then
    echo "lr-handoff: recycled IN PLACE — pane ${SOURCE_PANE:-<this pane>} continues session ${SID:0:8} on '$TARGET' (same window id, same uuid; engagement verified by a new assistant turn in $TCFG's copy)" >&2
    rm -f "$LRH_RCY_ERR" 2>/dev/null || true
    echo "$BUNDLE"; exit 0
  fi
  if grep -q 'has NO shell under its session' "$LRH_RCY_ERR" 2>/dev/null; then
    # The source's root is its own launcher (an expect-rooted pane): a /exit there closes the WINDOW,
    # so there is no shell to relaunch into. REPLACE in place instead — the successor is spawned
    # beside the SOURCE (anchor = the source pane, never the driver) and the source is retired through
    # the existing --close-source path once the successor is verified alive and engaged.
    echo "lr-handoff: pane ${SOURCE_PANE:-<this pane>} is launcher-rooted (no shell survives its /exit) — REPLACING in place: successor beside it, then the source is retired" >&2
    LRH_REPLACE=1
    [[ -n "$SOURCE_PANE" ]] && CLOSE_SOURCE=1
    rm -f "$LRH_RCY_ERR" 2>/dev/null || true
  else
    { echo "lr-handoff: --in-place: the recycle did NOT verify (handoff-fire rc=$LRH_RCY_RC). The transplant is DONE — session ${SID:0:8} now lives under $TCFG and the source pane is a tombstoned husk (handed-off-session-guard blocks its prompts)."
      echo "lr-handoff: relaunch it by hand as a NEW pane's own command:  exec /bin/bash $LAUNCHER"
      [[ -n "$SOURCE_PANE" ]] && echo "lr-handoff: then retire the husk:  $HF self-close --successor <new-pane-id> --transplanted-source --source-pane $SOURCE_PANE --source-session $SID"
    } >&2
    rm -f "$LRH_RCY_ERR" 2>/dev/null || true
    echo "$BUNDLE"; exit 4
  fi
fi

# VERIFIED TYPING (backlog item 270106134cc8). Both spawn shapes below type a command into a pane
# that has just been created. They used to blind-send it with `write text`, surviving only because
# `exec` happens to be a shell builtin — a property nothing pinned. Under `setopt CORRECT` an
# unrecognised command word parks the pane on an unanswerable `[nyae]` prompt while this script
# reports a successful fire. Resolution ladder: beside-script → CFG → ~/.claude.
_cctv="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/../lib/cc-type-verified.sh"
[ -f "$_cctv" ] || _cctv="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/lib/cc-type-verified.sh"
[ -f "$_cctv" ] || _cctv="$HOME/.claude/scripts/lib/cc-type-verified.sh"
# shellcheck source=../lib/cc-type-verified.sh
# shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
if ! . "$_cctv" 2>/dev/null; then
  # Fail LOUD. Unlike the poller there is no typing-free fallback here — both paths type — so
  # degrading would mean blind-sending, which is the failure mode this change removes.
  echo "lr-handoff: FATAL — cannot source $_cctv (verified typing unavailable)" >&2
  exit 2
fi

if [[ $LAUNCH -eq 1 && $PRINT_ONLY -ne 1 ]]; then
  # Split a pane to the RIGHT of the invoking pane (⌘D equivalent) so the recovered
  # session lands beside its recovery operator. New window ONLY when there is no
  # invoking pane (headless/cron) or the split fails. Validated live 2026-07-11.
  #
  # ⚠️ NEVER `… with default profile command "X"` (incident 2026-07-25). That form does not run X
  # once — iTerm2 records it as a SESSION-SCOPED PROFILE OVERRIDE (use_custom_command=Yes), and ⌘D
  # ("Split with Current Profile") copies the current session's profile, override included. So every
  # ⌘D off this pane re-ran the launcher: one fire at 01:28 left 4 pinned panes, and three ⌘D presses
  # spawned three concurrent `claude --resume` of the SAME transcript where the operator expected a
  # plain shell. Create a BARE pane and `write text` the launcher instead — the same create-then-type
  # pattern handoff-fire.sh already uses. `exec` preserves the old lifecycle (pane dies with the
  # launcher); the pane's profile stays clean, so ⌘D yields a login shell.
  # Repair for panes created before this fix: scripts/iterm-clear-sticky-command.sh
  #
  # TERMINAL DISPATCH (2026-07-31). Both branches below `tell application id "com.googlecode.iterm2"`,
  # so inside a kitty fleet BOTH of them refuse and the recovery degrades to the printed manual
  # fallback — i.e. limit recovery, the one path whose entire job is to lose nothing, silently
  # stopped firing anything. Under kitty the same two intents are `kitty @ launch --type=window
  # --location=vsplit` (the ⌘D-equivalent split, RIGHT of the invoking pane — the same orientation
  # mapping bin/it2-kitty:125 pins) and `--type=os-window` (the no-invoking-pane fallback).
  # ITERM_SESSION_ID is SYNTHESIZED inside kitty as "w0t0p0:$KITTY_WINDOW_ID" by the login shim, so
  # the existing `${ITERM_SESSION_ID##*:}` strip already yields the right anchor: in a kitty fleet a
  # "session uuid" IS the integer kitty window id. The predicate MIRRORS bin/it2-wrapper:75 exactly,
  # kill switch included — a split made with one terminal's client and addressed with the other's is
  # precisely the failure the three-way predicate agreement test exists to prevent.
  # The launcher reaches kitty as ARGV (`launch … -- /bin/bash "$LAUNCHER"`), never as typed text,
  # so the write-text quoting above does not apply on that side; `exec`-equivalent lifecycle is
  # preserved (the window dies with the launcher) and, kitty having no profile-override concept, the
  # 2026-07-25 sticky-command incident has no analogue to re-create there.
  OWN_PANE="${ITERM_SESSION_ID##*:}"
  # THE ANCHOR. A driver-run recovery (or the launchd poller, which has no pane at all) must land the
  # successor beside the SOURCE pane, so the operator sees the continuation appear where the session
  # was — never beside whoever happened to run the command. Without --source-pane the anchor stays
  # the invoking pane, exactly as before.
  LRH_ANCHOR="${SOURCE_PANE:-$OWN_PANE}"
  FIRED=""
  # NEW_PANE — the id of the pane this fire CREATED, empty until one is known. FIRED keeps its
  # existing meaning untouched (a status: "split" or empty, read by the announcement branch below);
  # this is a second variable rather than a richer FIRED precisely so no existing consumer changes.
  #
  # Every arm below already had the id in its hand and threw it away: kitty prints the new window id
  # on stdout and the call redirected it to /dev/null; the two AppleScript arms already `return id of`
  # the new session because osa_type_verified has to address it. Nothing new is asked of any
  # terminal — the id is simply kept. It is what --close-source hands to `self-close --successor`,
  # and an empty NEW_PANE is what makes that path REFUSE rather than close this pane blind.
  NEW_PANE=""
  IN_KITTY=0
  if [ -n "${KITTY_WINDOW_ID:-}" ] && [ -z "${IT2_WRAPPER_NO_KITTY:-}" ]; then IN_KITTY=1; fi
  # An explicit socket is explicit intent (bin/it2-kitty:197) — honor it even with no kitty env.
  if [ "$IN_KITTY" = 0 ] && [ -n "${CC_TERM_KITTY_TO:-}" ] && [ -z "${IT2_WRAPPER_NO_KITTY:-}" ]; then IN_KITTY=1; fi
  # DAEMON-CONTEXT DISPATCH (2026-08-07). This file's caller of record is lr-reset-poller — a
  # launchd job with NO kitty env — so the env test above reads iTerm2 for a fleet that lives in
  # kitty, and the fallback chain below drives AppleScript at an app the operator abandoned.
  # bin/cc-kitty-socket verifies a LIVE kitty by its control socket; with IN_KITTY=1 and no
  # invoking pane (OWN_PANE empty under launchd), the existing `elif IN_KITTY` arm below already
  # fires the right intent: a new kitty os-window through lrh_kitty/CC_TERM_KITTY_TO. Env still
  # wins when present; the resolver decides only the ABSENT case.
  if [ "$IN_KITTY" = 0 ] && [ -z "${KITTY_WINDOW_ID:-}" ] && [ -z "${IT2_WRAPPER_NO_KITTY:-}" ]; then
    _lrh_sock=""
    for _lrh_ksb in "$(dirname "$_CC_KS")/../../bin/cc-kitty-socket" \
                    "$(dirname "$0")/../../bin/cc-kitty-socket" \
                    "${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/bin/cc-kitty-socket" \
                    "${HOME:-}/.claude/bin/cc-kitty-socket"; do
      [ -x "$_lrh_ksb" ] && { _lrh_sock="$(lrh_bounded "$_lrh_ksb" 2>/dev/null)" || _lrh_sock=""; break; }
    done
    if [ -n "$_lrh_sock" ]; then CC_TERM_KITTY_TO="$_lrh_sock"; export CC_TERM_KITTY_TO; IN_KITTY=1; fi
  fi
  if [[ -n "$LRH_ANCHOR" && $IN_KITTY -eq 1 ]]; then
    # A kitty window id is always an integer. A non-integer means the id came from a real-iTerm2
    # run; refuse the split rather than let --match fall through to the operator's ACTIVE window.
    case "$LRH_ANCHOR" in
      ''|*[!0-9]*) FIRED="" ;;
      *) lrh_launch_tail
         # --source-window pins `--cwd=current` to the ANCHOR. Without it kitty resolves `current`
         # against the operator's ACTIVE window — MEASURED 2026-09-09 (q-survivability-spawn § P4):
         # the successor inherited an unrelated live session's cwd AND title, the 2026-08-07
         # pane-theft class. No --title: it is sticky and would freeze the ✳/◐ liveness glyph;
         # provenance rides in --var (kitty @ ls user_vars, unforgeable by the child).
         LRH_FOCUS=(); [[ -n "$SOURCE_PANE" ]] && LRH_FOCUS=(--dont-take-focus)
         if KID="$(lrh_kitty launch --type=window --location=vsplit \
           --match "window_id:$LRH_ANCHOR" --next-to "id:$LRH_ANCHOR" --source-window "id:$LRH_ANCHOR" --cwd=current \
           ${LRH_FOCUS[@]+"${LRH_FOCUS[@]}"} \
           --var "lr_continuation_of=$SID" --var "lr_source_pane=$LRH_ANCHOR" --var "lr_target_account=$TARGET" \
           "${LRH_LAUNCH_TAIL[@]}" 2>/dev/null)"; then
           FIRED="split"
           # `kitty @ launch` prints the new window id, and only that, on success. Accept it ONLY as
           # a bare integer: kitty's id space is integers, so anything else is a diagnostic or a
           # future format change, and passing that on as a pane id would send self-close hunting a
           # pane that never existed. A rejected id is not a failed fire — the split stands, and
           # --close-source refuses instead of closing blind.
           KID="$(printf '%s' "$KID" | tr -d '[:space:]')"
           case "$KID" in ''|*[!0-9]*) ;; *) NEW_PANE="$KID" ;; esac
           # A window that did not survive its launcher is not a fire — see lrh_kitty_window_alive.
           if [ -n "$NEW_PANE" ] && ! lrh_kitty_window_alive "$NEW_PANE"; then
             echo "lr-handoff: the kitty split window ($NEW_PANE) did not survive the launch — the launcher exited before the resume engaged; not claiming a fire" >&2
             FIRED=""; NEW_PANE=""
           fi
           # `|| true`: this is the LAST command of the arm, and under `set -e` a false && -list
           # here would exit the script — which is now REACHABLE, because a demoted fire makes the
           # first test false on purpose.
           { [ -n "$FIRED" ] && command -v cc_log_pane_spawn >/dev/null 2>&1 \
             && cc_log_pane_spawn split kitty "" "${PWD:-}" "lr-handoff vsplit anchor:$LRH_ANCHOR"; } || true
         fi ;;
    esac
  elif [[ -n "${ITERM_SESSION_ID:-}" ]]; then
    command -v cc_log_pane_spawn >/dev/null 2>&1 && cc_log_pane_spawn split iterm2 "" "${PWD:-}" "lr-handoff osascript split-vertically anchor:$LRH_ANCHOR"
    # SPLIT ONLY, returning the new pane's id — the command is typed afterwards, through
    # osa_type_verified. `write text` appends the newline itself, so the old combined form EXECUTED
    # the line before anything could confirm it arrived intact; splitting create from type is what
    # makes the echo-verify possible at all. The kitty arm above needs none of this: it execs the
    # launcher via argv, so nothing it passes is ever re-parsed by a shell.
    NEWPANE=$(lrh_bounded osascript 2>/dev/null <<OSA || true
if not (application id "com.googlecode.iterm2" is running) then return ""
tell application id "com.googlecode.iterm2"
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        if id of s is "$LRH_ANCHOR" then
          tell s
            set newPane to (split vertically with default profile)
          end tell
          return id of newPane
        end if
      end repeat
    end repeat
  end repeat
  return ""
end tell
OSA
)
    NEWPANE="$(printf '%s' "$NEWPANE" | tr -d '[:space:]')"
    # FIRED stays empty unless the command was VERIFIABLY typed, so an unverifiable pane falls
    # through to the new-window path below rather than reporting a fire that never engaged.
    if [[ -n "$NEWPANE" ]] && osa_type_verified "$NEWPANE" "bash $LAUNCHER"; then
      FIRED="split"
      # Only on the VERIFIED branch. An unverifiable pane is one the launcher may never have reached,
      # and handing it to self-close as a successor would name a husk as the continuation.
      NEW_PANE="$NEWPANE"
    fi
  fi
  # THE FALLBACK IS A PANE'S OWN COMMAND, NOT A COMMAND TO RUN (cc-backlog c6089dc2efe6). The
  # launcher ends in `exec expect … spawn … claude --resume`, so the resumed TUI is a child of
  # whatever PTY ran it and dies the moment that command returns. Every automated path here hands it
  # to a NEW pane as that pane's argv or typed command line, which is why they work — and a human or
  # an agent who instead runs the printed path from an existing shell (a Claude Bash call, a `-c`)
  # gets a session that comes up, ingests, thinks, and dies with the command. Measured 2026-09-05 on
  # session 2de07510, twice. So the fallback is printed WITH its constraint; a path with no usage is
  # how a fallback that provably cannot work gets handed out looking like a working one.
  _LRH_FB="run it as a NEW pane's own typed command (open a pane, then type: bash $LAUNCHER — no exec, so the pane's shell survives and stays recyclable) — running it from a Bash TOOL call instead kills the resumed session the moment expect's interact reads EOF on a non-tty stdin"
  if [[ "$FIRED" == "split" ]]; then
    if [[ $LRH_REPLACE -eq 1 ]]; then
      echo "lr-handoff: REPLACED in place — successor pane ${NEW_PANE:-?} fired beside source pane $LRH_ANCHOR on '$TARGET'; the source is retired below once the successor is verified (manual fallback: $_LRH_FB)" >&2
    else
      echo "lr-handoff: fired split pane (right of pane $LRH_ANCHOR, ${LRH_SPAWN_SHAPE:-argv}-rooted) on '$TARGET' (manual fallback: $_LRH_FB)" >&2
    fi
  elif [[ $IN_KITTY -eq 1 ]]; then
    command -v cc_log_pane_spawn >/dev/null 2>&1 && cc_log_pane_spawn os-window kitty "" "${PWD:-}" "lr-handoff fallback os-window"
    lrh_launch_tail
    if KID="$(lrh_kitty launch --type=os-window --cwd="${WT_TOP:-$CWD}" \
         --var "lr_continuation_of=$SID" --var "lr_source_pane=${SOURCE_PANE:-}" --var "lr_target_account=$TARGET" \
         "${LRH_LAUNCH_TAIL[@]}" 2>/dev/null)"; then
      KID="$(printf '%s' "$KID" | tr -d '[:space:]')"
      case "$KID" in ''|*[!0-9]*) ;; *) NEW_PANE="$KID" ;; esac
      # Same survival test as the split arm — and note the announcement below used to run
      # UNCONDITIONALLY, so this arm printed "fired new kitty window" even on the line right after
      # its own "kitty launch failed".
      if lrh_kitty_window_alive "${NEW_PANE:-}"; then
        echo "lr-handoff: no invoking pane / split failed — fired new kitty window (${LRH_SPAWN_SHAPE:-argv}-rooted) on '$TARGET' (manual fallback: $_LRH_FB)" >&2
      else
        echo "lr-handoff: the new kitty window (${NEW_PANE:-?}) did not survive the launch — $_LRH_FB" >&2
        NEW_PANE=""
      fi
    else
      echo "lr-handoff: kitty launch failed — $_LRH_FB" >&2
    fi
  else
    command -v cc_log_pane_spawn >/dev/null 2>&1 && cc_log_pane_spawn window iterm2 "" "${PWD:-}" "lr-handoff fallback create-window"
    # CREATE ONLY, then type through osa_type_verified (same reason as the split arm above).
    WINPANE=$(lrh_bounded osascript 2>/dev/null <<OSA || true
if not (application id "com.googlecode.iterm2" is running) then return ""
tell application id "com.googlecode.iterm2"
  set newWin to (create window with default profile)
  return id of (current session of newWin)
end tell
OSA
)
    WINPANE="$(printf '%s' "$WINPANE" | tr -d '[:space:]')"
    if [[ -n "$WINPANE" ]] && osa_type_verified "$WINPANE" "bash $LAUNCHER"; then
      NEW_PANE="$WINPANE"      # verified branch only — same reason as the split arm above
      echo "lr-handoff: no invoking pane / split failed — fired new iTerm2 window on '$TARGET' (manual fallback: $_LRH_FB)" >&2
    else
      echo "lr-handoff: iTerm2 launch failed — $_LRH_FB" >&2
    fi
  fi
else
  command -v cursor >/dev/null 2>&1 && cursor "$LAUNCHER" >/dev/null 2>&1 || true
  echo "lr-handoff: launch script ready (not fired): $LAUNCHER" >&2
fi

echo "$BUNDLE"

# ── --close-source: retire THIS pane, now that the successor is carrying the session ──────────────
# The transplant already moved the session to another account and the fire above put a successor on
# it. What is left here is a HUSK: a pane over a transcript that has been handed off, which will
# never produce another turn but is indistinguishable from live work in the operator's window.
#
# The close goes through handoff-fire.sh self-close and NOTHING ELSE. Never `it2 session close`,
# never raw osascript, never a typed /exit: a pane the operator watches must not vanish without its
# continuation being visible, and self-close is the only path that verifies the successor is alive
# AND engaged, announces the succession into the successor's own transcript, and focuses it after the
# close. --transplanted-source is the class this qualifies under; --allow-origin-close is NOT used
# and must not be, and --successor-assume-engaged is deliberately not passed — a transplant whose
# successor never woke is the one failure this close must not walk past.
#
# NO PANE ID ⇒ NO CLOSE. Every arm above captures the id it created, but a kitty that answered with
# something other than an integer, or an AppleScript pane whose typed launcher could not be verified,
# leaves NEW_PANE empty. There is then no successor to name, and a close on an unnamed successor is
# exactly the vanishing pane the succession contract exists to prevent — so print the command the
# operator can run once they know the pane, and exit non-zero. The fire itself already happened and
# is reported above; this failure is about the CLOSE, not the recovery.
if [[ $CLOSE_SOURCE -eq 1 ]]; then
  # CC_HANDOFF_FIRE_BIN is a TEST SEAM, in the same shape as cc-type-verified.sh's CC_OSASCRIPT_BIN
  # and this file's CC_TERM_KITTY: without it a test of --close-source would resolve the REAL
  # handoff-fire.sh beside this script and actually arm a close. Resolution ladder otherwise
  # unchanged: beside-script → $CLAUDE_CONFIG_DIR → ~/.claude.
  HF="${CC_HANDOFF_FIRE_BIN:-}"
  [[ -n "$HF" ]] || HF="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/../handoff-fire.sh"
  [[ -f "$HF" ]] || HF="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/handoff-fire.sh"
  [[ -f "$HF" ]] || HF="$HOME/.claude/scripts/handoff-fire.sh"
  if [[ -z "${NEW_PANE:-}" ]]; then
    { echo "lr-handoff: --close-source could NOT identify the pane it created — this pane stays OPEN."
      echo "lr-handoff: the recovery itself fired; only the close is unresolved. Find the successor's"
      echo "lr-handoff: pane id, then run:"
      echo "  $HF self-close --successor <successor-pane-id> --transplanted-source${SOURCE_PANE:+ --source-pane $SOURCE_PANE --source-session $SID}"
    } >&2
    exit 3
  fi
  if [[ ! -x "$HF" ]]; then
    { echo "lr-handoff: --close-source cannot reach handoff-fire.sh (looked beside this script, in \$CLAUDE_CONFIG_DIR/scripts, and in ~/.claude/scripts)."
      echo "lr-handoff: this pane stays OPEN. Run the close by hand once it is reachable:"
      echo "  <handoff-fire.sh> self-close --successor $NEW_PANE --transplanted-source${SOURCE_PANE:+ --source-pane $SOURCE_PANE --source-session $SID}"
    } >&2
    exit 3
  fi
  # THE DEFAULT PATH IS UNCHANGED, byte for byte: with no --source-pane this is the same exec with
  # the same four words it has always had. The remote form APPENDS the pair handoff-fire admits the
  # other pane on, and nothing else — same subcommand, same class flag, still never
  # --allow-origin-close and still never --successor-assume-engaged.
  if [[ -n "$SOURCE_PANE" ]]; then
    echo "lr-handoff: --close-source — retiring pane $SOURCE_PANE (registry-bound to session ${SID:0:8}) into successor $NEW_PANE via handoff-fire self-close" >&2
    exec "$HF" self-close --successor "$NEW_PANE" --transplanted-source --source-pane "$SOURCE_PANE" --source-session "$SID"
  fi
  echo "lr-handoff: --close-source — retiring this pane into successor $NEW_PANE via handoff-fire self-close" >&2
  exec "$HF" self-close --successor "$NEW_PANE" --transplanted-source
fi
