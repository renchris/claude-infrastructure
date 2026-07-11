#!/bin/bash
# lr-handoff.sh — package a limit-interrupted session for zero-loss continuation
# on another account: audit + salvage bundle + transcript transplant + launch.
#
# Usage: lr-handoff.sh [--target next|next2|next3|next4|auto] [--model opus|fable]
#                      [--sid SID] [--config-dir DIR] [--cwd PATH]
#                      [--context FILE] [--launch|--print-only]
#                      [--no-transplant] [--keep-source] [--force]
#
# Defaults: sid/config from the live session env; --target auto routes via
# claude-accounts; --print-only writes /tmp/lr-launch-<sid8>.sh instead of firing.
# Output: bundle dir path on the last stdout line. Exit 0 ok, 2 error.
set -euo pipefail

LR="$HOME/.claude/scripts/limit-recover"
TARGET="auto" MODEL="opus" SID="${CLAUDE_CODE_SESSION_ID:-}" CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CWD="$(pwd)" CONTEXT="" LAUNCH=0 PRINT_ONLY=0 NO_TRANSPLANT=0 KEEP_SOURCE=0 FORCE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
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
CFG="${CFG/#\~/$HOME}"

# --- account routing -------------------------------------------------------
acct_to_cfg() {
  case "$1" in
    next) echo "$HOME/.claude-next" ;;
    next2) echo "$HOME/.claude-secondary" ;;
    next3) echo "$HOME/.claude-tertiary" ;;
    next4) echo "$HOME/.claude-quaternary" ;;
    *) echo "" ;;
  esac
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

# --- launch ----------------------------------------------------------------
FIRE_MODEL=""; [[ "$MODEL" == "fable" ]] && FIRE_MODEL="--model claude-fable-5 --effort high"
LAUNCHER="/tmp/lr-launch-${SID:0:8}.sh"
cat > "$LAUNCHER" <<EOF
#!/bin/bash
# Resume the handed-off session $SID on account '$TARGET' with the ingest prompt.
# Regenerable: bundle at $BUNDLE
exec "$LR/lr-fire-resume.sh" "$TARGET" "${WT_TOP:-$CWD}" "$SID" \\
  ${BRANCH:+--branch "$BRANCH"} $FIRE_MODEL \\
  --prompt "$INGEST_PROMPT"
EOF
chmod +x "$LAUNCHER"

if [[ $LAUNCH -eq 1 && $PRINT_ONLY -ne 1 ]]; then
  # Split a pane to the RIGHT of the invoking pane (⌘D equivalent) so the recovered
  # session lands beside its recovery operator. New window ONLY when there is no
  # invoking pane (headless/cron) or the split fails. Validated live 2026-07-11.
  OWN_PANE="${ITERM_SESSION_ID##*:}"
  FIRED=""
  if [[ -n "${ITERM_SESSION_ID:-}" ]]; then
    FIRED=$(osascript 2>/dev/null <<OSA || true
tell application "iTerm2"
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        if id of s is "$OWN_PANE" then
          tell s to split vertically with default profile command "/bin/bash $LAUNCHER"
          return "split"
        end if
      end repeat
    end repeat
  end repeat
  return ""
end tell
OSA
)
  fi
  if [[ "$FIRED" == "split" ]]; then
    echo "lr-handoff: fired split pane (right of invoking pane) on '$TARGET' (manual fallback: $LAUNCHER)" >&2
  else
    osascript >/dev/null 2>&1 <<OSA || { echo "lr-handoff: iTerm2 launch failed — run manually: $LAUNCHER" >&2; }
tell application "iTerm2"
  create window with default profile command "/bin/bash $LAUNCHER"
end tell
OSA
    echo "lr-handoff: no invoking pane / split failed — fired new iTerm2 window on '$TARGET' (manual fallback: $LAUNCHER)" >&2
  fi
else
  command -v cursor >/dev/null 2>&1 && cursor "$LAUNCHER" >/dev/null 2>&1 || true
  echo "lr-handoff: launch script ready (not fired): $LAUNCHER" >&2
fi

echo "$BUNDLE"
