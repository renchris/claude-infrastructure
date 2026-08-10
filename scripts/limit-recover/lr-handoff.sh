#!/bin/bash
# lr-handoff.sh — package a limit-interrupted session for zero-loss continuation
# on another account: audit + salvage bundle + transcript transplant + launch.
#
# Usage: lr-handoff.sh [--target next|next2|next3|next4|auto] [--model opus|fable]
#                      [--effort low|medium|high|xhigh|max]
#                      [--sid SID] [--config-dir DIR] [--cwd PATH]
#                      [--context FILE] [--launch|--print-only]
#                      [--no-transplant] [--keep-source] [--force]
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
# Output: bundle dir path on the last stdout line. Exit 0 ok, 2 error.
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


LR="$HOME/.claude/scripts/limit-recover"
TARGET="auto" MODEL="opus" EFFORT="" SID="${CLAUDE_CODE_SESSION_ID:-}" CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CWD="$(pwd)" CONTEXT="" LAUNCH=0 PRINT_ONLY=0 NO_TRANSPLANT=0 KEEP_SOURCE=0 FORCE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --effort) EFFORT="$2"; shift 2 ;;
    --sid) SID="$2"; shift 2 ;;
    --config-dir) CFG="$2"; shift 2 ;;
    --cwd) CWD="$2"; shift 2 ;;
    --context) CONTEXT="$2"; shift 2 ;;
    --launch) LAUNCH=1; shift ;;
    --print-only) PRINT_ONLY=1; shift ;;
    --no-transplant) NO_TRANSPLANT=1; shift ;;
    --keep-source) KEEP_SOURCE=1; shift ;;
    --force) FORCE=1; shift ;;
    *) echo "lr-handoff: unknown arg $1" >&2; exit 2 ;;
  esac
done
[[ -n "$SID" ]] || { echo "lr-handoff: no --sid and CLAUDE_CODE_SESSION_ID unset" >&2; exit 2; }
# Reject an unknown effort HERE rather than let it reach the launcher. %q already makes the
# value inert as source, so this is not a quoting defence — it is a liveness one: the binary
# refuses an unrecognised --effort at startup, and that refusal would land in a freshly spawned
# pane on the transplanted session, i.e. after the transcript has already moved accounts.
case "$EFFORT" in
  ""|low|medium|high|xhigh|max) ;;
  *) echo "lr-handoff: --effort must be low|medium|high|xhigh|max (got '$EFFORT')" >&2; exit 2 ;;
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
  kind="general"; [[ "$MODEL" == "fable" ]] && kind="fable"
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
  printf '# HANDOFF-CONTEXT missing\nThe firing session did not write scope/decisions/next-actions.\nDerive them from audit.md + the transplanted transcript, and treat scope as UNRECONSTRUCTED (STOP-ASK before assuming).\n' > "$BUNDLE/HANDOFF-CONTEXT.md"
fi
if git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$CWD" status --porcelain > "$BUNDLE/git-status.txt" || true
  git -C "$CWD" log --oneline -15 > "$BUNDLE/git-log.txt" || true
fi

INGEST_PROMPT="/limit-recover ingest $BUNDLE"
jq -n \
  --arg sid "$SID" --arg source_cfg "$CFG" --arg target "$TARGET" --arg target_cfg "$TCFG" \
  --arg cwd "$CWD" --arg wt "$WT_TOP" --arg branch "$BRANCH" --arg head "$HEAD" \
  --arg ts "$TS" --arg model "$MODEL" --arg task_list "${CLAUDE_CODE_TASK_LIST_ID:-}" \
  --arg sha "$(jq -r '.transcript_sha256' "$BUNDLE/audit.json")" \
  --arg gaps "$(jq -r '.counts.gaps' "$BUNDLE/audit.json")" \
  --arg ingest "$INGEST_PROMPT" \
  '{sid:$sid, source_cfg:$source_cfg, target:$target, target_cfg:$target_cfg, cwd:$cwd,
    worktree:$wt, branch:$branch, head:$head, ts:$ts, model:$model, task_list:$task_list,
    transcript_sha256:$sha, gaps_at_handoff:($gaps|tonumber), ingest_prompt:$ingest}' \
  > "$BUNDLE/MANIFEST.json"

# --- transplant ------------------------------------------------------------
if [[ $NO_TRANSPLANT -ne 1 ]]; then
  TARGS=(--sid "$SID" --from "$CFG" --to "$TCFG")
  [[ -n "${CLAUDE_CODE_TASK_LIST_ID:-}" ]] && TARGS+=(--task-list "$CLAUDE_CODE_TASK_LIST_ID")
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
[[ "$MODEL" == "fable" ]] && FIRE_ARGV+=(--model claude-fable-5 --effort "${EFFORT:-high}")
# The opus path passes no --model, so lr-fire-resume derives model AND effort from the account
# label. An explicit --effort must still reach it, or the flag would be silently fable-only.
[[ "$MODEL" != "fable" && -n "$EFFORT" ]] && FIRE_ARGV+=(--effort "$EFFORT")
FIRE_ARGV+=(--prompt "$INGEST_PROMPT")
cat > "$LAUNCHER" <<EOF
#!/bin/bash
# Resume the handed-off session $(printf '%q' "$SID") on account $(printf '%q' "$TARGET") with the ingest prompt.
# Regenerable: bundle at $(printf '%q' "$BUNDLE")
exec $(printf '%q ' "${FIRE_ARGV[@]}")
EOF
chmod +x "$LAUNCHER"

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
  FIRED=""
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
  if [[ -n "${ITERM_SESSION_ID:-}" && $IN_KITTY -eq 1 ]]; then
    # A kitty window id is always an integer. A non-integer means the id came from a real-iTerm2
    # run; refuse the split rather than let --match fall through to the operator's ACTIVE window.
    case "$OWN_PANE" in
      ''|*[!0-9]*) FIRED="" ;;
      *) lrh_kitty launch --type=window --location=vsplit \
           --match "window_id:$OWN_PANE" --next-to "id:$OWN_PANE" --cwd=current \
           -- /bin/bash "$LAUNCHER" >/dev/null 2>&1 \
           && { FIRED="split"; command -v cc_log_pane_spawn >/dev/null 2>&1 && cc_log_pane_spawn split kitty "" "${PWD:-}" "lr-handoff vsplit anchor:$OWN_PANE"; } ;;
    esac
  elif [[ -n "${ITERM_SESSION_ID:-}" ]]; then
    command -v cc_log_pane_spawn >/dev/null 2>&1 && cc_log_pane_spawn split iterm2 "" "${PWD:-}" "lr-handoff osascript split-vertically anchor:$OWN_PANE"
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
        if id of s is "$OWN_PANE" then
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
    if [[ -n "$NEWPANE" ]] && osa_type_verified "$NEWPANE" "exec /bin/bash $LAUNCHER"; then
      FIRED="split"
    fi
  fi
  if [[ "$FIRED" == "split" ]]; then
    echo "lr-handoff: fired split pane (right of invoking pane) on '$TARGET' (manual fallback: $LAUNCHER)" >&2
  elif [[ $IN_KITTY -eq 1 ]]; then
    command -v cc_log_pane_spawn >/dev/null 2>&1 && cc_log_pane_spawn os-window kitty "" "${PWD:-}" "lr-handoff fallback os-window"
    lrh_kitty launch --type=os-window --cwd=current -- /bin/bash "$LAUNCHER" >/dev/null 2>&1 \
      || { echo "lr-handoff: kitty launch failed — run manually: $LAUNCHER" >&2; }
    echo "lr-handoff: no invoking pane / split failed — fired new kitty window on '$TARGET' (manual fallback: $LAUNCHER)" >&2
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
    if [[ -n "$WINPANE" ]] && osa_type_verified "$WINPANE" "exec /bin/bash $LAUNCHER"; then
      echo "lr-handoff: no invoking pane / split failed — fired new iTerm2 window on '$TARGET' (manual fallback: $LAUNCHER)" >&2
    else
      echo "lr-handoff: iTerm2 launch failed — run manually: $LAUNCHER" >&2
    fi
  fi
else
  command -v cursor >/dev/null 2>&1 && cursor "$LAUNCHER" >/dev/null 2>&1 || true
  echo "lr-handoff: launch script ready (not fired): $LAUNCHER" >&2
fi

echo "$BUNDLE"
