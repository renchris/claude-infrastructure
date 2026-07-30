#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 22-qos-rewrite  —  wire the Bash-boundary batch-demotion hook into the live settings (row 13, M7)
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: (1) symlink hooks/qos-rewrite.sh into the live ~/.claude/hooks/ layer (brand-new file —
#   never auto-linked). The patterns file needs NO deploy: the hook resolves $0 PHYSICALLY, so
#   ../config/qos-batch.patterns lands in the checkout (shared-lib-source-ladder memory honored
#   by construction). (2) append a PreToolUse/Bash hook entry {command: ~/.claude/hooks/
#   qos-rewrite.sh, timeout: 10} to EVERY config dir that has a settings.json with a Bash
#   PreToolUse matcher — jq only, per-dir backup, idempotent, restore-on-failure. --undo restores.
#
# WHY: the PATH shim covers only PATH-spelled bats (~70% ceiling, MACHINE_CAPACITY_V2.md §9.4);
#   agents type absolute paths and run non-bats batch (pytest 0.67 cores at PRI 31, du at PRI 46).
#   The Bash TOOL boundary cannot be spelled around. Rewrite semantics probe-verified on live
#   2.1.219 AND doc-confirmed on 2.1.114 (§11.2): updatedInput without permissionDecision rewrites
#   the executed command and leaves the permission flow untouched. The hook FAILS OPEN (exit 0,
#   no output) on any internal error — it can never block a Bash call (row 6 constraint).
#
# WHY C10: settings.json is the live permission/hook surface of every account — operator loads it.
# Kill after wiring: CC_QOS_REWRITE=off (env, per session or globally), or --undo (full restore).
# Mark done:  touch <this file>.done
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
SRC="$REPO/hooks/qos-rewrite.sh"
DEST="$HOME/.claude/hooks/qos-rewrite.sh"
HOOK_CMD="\$HOME/.claude/hooks/qos-rewrite.sh"
HOOK_MATCH="qos-rewrite.sh"
BAK_SUFFIX=".pre-qos-rewrite.bak"
CANDIDATE_DIRS="${CC_CFG_DIRS:-$HOME/.claude $HOME/.claude-secondary $HOME/.claude-next $HOME/.claude-tertiary $HOME/.claude-quaternary}"

command -v jq >/dev/null 2>&1 || { echo "✗ jq required" >&2; exit 1; }

if [ "${1:-}" = "--undo" ]; then
  n=0
  for d in $CANDIDATE_DIRS; do
    b="$d/settings.json$BAK_SUFFIX"
    [ -f "$b" ] || continue
    if jq -e . "$b" >/dev/null 2>&1; then
      cp -a "$b" "$d/settings.json" && rm -f "$b" && { echo "  ← $d/settings.json restored"; n=$((n+1)); }
    fi
  done
  rm -f "$DEST"
  echo "undo: $n settings restored; live hook symlink removed."
  exit 0
fi

echo "== 22-qos-rewrite =="
[ -f "$SRC" ] || { echo "✗ missing in checkout: $SRC (land M7 first)" >&2; exit 1; }
[ -f "$REPO/config/qos-batch.patterns" ] || { echo "✗ missing $REPO/config/qos-batch.patterns" >&2; exit 1; }

DIRS=""
for d in $CANDIDATE_DIRS; do [ -f "$d/settings.json" ] && DIRS="$DIRS $d"; done
[ -n "$DIRS" ] || { echo "✗ no config dir with a settings.json found" >&2; exit 1; }

echo "Plan:"
echo "  [0] smoke: pipe a synthetic PreToolUse JSON through $SRC — must emit a valid rewrite for"
echo "      an absolute-path bats command and NOTHING for a non-batch command"
echo "  [1] symlink $SRC → $DEST"
for d in $DIRS; do
  if jq -e --arg m "$HOOK_MATCH" '[.hooks.PreToolUse[]?.hooks[]?.command? // empty] | any(contains($m))' "$d/settings.json" >/dev/null 2>&1; then
    echo "  ·  $d/settings.json — already wired, WILL SKIP"
  elif ! jq -e '.hooks.PreToolUse[]? | select(.matcher=="Bash")' "$d/settings.json" >/dev/null 2>&1; then
    echo "  ·  $d/settings.json — no Bash PreToolUse matcher, WILL SKIP (this dir does not run the Bash chain)"
  else
    echo "  +  $d/settings.json — append to the Bash PreToolUse chain (backup → settings.json$BAK_SUFFIX)"
  fi
done

if [ "${CONFIRM:-0}" != 1 ]; then
  echo
  echo "(dry run — re-run with CONFIRM=1 to apply; '--undo' reverts everything:)"
  _pfx=""; [ -n "${CC_REPO+set}" ] && _pfx="CC_REPO=$REPO "
  echo "    CONFIRM=1 ${_pfx}bash $HOME/.claude/autonomy/pending-activation/22-qos-rewrite-activate.sh"
  exit 0
fi

echo "[0] smoke"
out=$(printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"timeout 90 /opt/homebrew/bin/bats tests/x.bats"}}' | bash "$SRC")
printf '%s' "$out" | jq -e '.hookSpecificOutput.updatedInput.command | contains("cc-bats")' >/dev/null \
  || { echo "✗ smoke: absolute-path bats was NOT rewritten — NOT activating" >&2; exit 1; }
out2=$(printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git status"}}' | bash "$SRC")
[ -z "$out2" ] || { echo "✗ smoke: non-batch command produced output — NOT activating" >&2; exit 1; }
echo "  · smoke GREEN (rewrites batch, silent on non-batch)"

echo "[1] symlink"
if [ -e "$DEST" ] && [ ! -L "$DEST" ]; then echo "✗ $DEST is a real file — refusing" >&2; exit 1; fi
ln -sfn "$SRC" "$DEST"; echo "  · $DEST → $(readlink "$DEST")"

echo "[2] settings"
ENTRY=$(jq -cn --arg c "$HOOK_CMD" '{type:"command", command:$c, timeout:10}')
for d in $DIRS; do
  S="$d/settings.json"
  if jq -e --arg m "$HOOK_MATCH" '[.hooks.PreToolUse[]?.hooks[]?.command? // empty] | any(contains($m))' "$S" >/dev/null 2>&1; then
    echo "  ·  $S already wired — skip"; continue
  fi
  jq -e '.hooks.PreToolUse[]? | select(.matcher=="Bash")' "$S" >/dev/null 2>&1 || { echo "  ·  $S no Bash matcher — skip"; continue; }
  B="$S$BAK_SUFFIX"; cp -a "$S" "$B"
  tmp=$(mktemp)
  if jq --argjson e "$ENTRY" '(.hooks.PreToolUse[] | select(.matcher=="Bash") | .hooks) += [$e]' "$S" > "$tmp" \
     && jq empty "$tmp" >/dev/null 2>&1 \
     && jq -e --arg m "$HOOK_MATCH" '[.hooks.PreToolUse[]?.hooks[]?.command? // empty] | any(contains($m))' "$tmp" >/dev/null 2>&1; then
    mv "$tmp" "$S"; echo "  +  $S wired (backup: $B)"
  else
    rm -f "$tmp"; cp -a "$B" "$S"
    echo "  ✗ jq edit FAILED on $S — RESTORED, file unchanged. ABORTING." >&2; exit 1
  fi
done

echo "DONE. New sessions pick it up at next start; verify in any fresh session:"
echo "  Bash: /opt/homebrew/bin/bats --version   → child census must show pri<=10"
echo "Then:  touch $HOME/.claude/autonomy/pending-activation/22-qos-rewrite-activate.sh.done"
