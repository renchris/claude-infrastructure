#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════
# 27-relay-verbatim  —  wire hooks/relay-verbatim.sh into PostToolUse(Bash) in every config dir
# ═══════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: adds, to every config dir that has a settings.json:
#
#     PostToolUse (matcher "Bash") += ~/.claude/hooks/relay-verbatim.sh   (timeout 5)
#
# WHY: 2026-08-01 — `/accounts` ran `claude-accounts --readout`, the table rendered perfectly, and
#   the model then summarised it into three bullets. The operator lost every reset time. The rule
#   "Paste that output" had lived in commands/accounts.md since 2026-07-11 as ONE soft line,
#   competing against a just-tightened conciseness rule in CLAUDE.md. Prose lost to prose. This
#   hook fires on the RENDER itself, so the reminder lands in the same turn as the output it
#   governs and does not depend on which doc line the model weighted.
#
# WHY C10 (agent stages, operator runs): it mutates the live harness config of every account.
#
# SAFETY: per-dir backup BEFORE any write · jq only, never sed · post-write validation (parses AND
#   the command is present); a failed validation RESTORES the backup and ABORTS LOUD · already-wired
#   dirs are SKIPPED (idempotent). The hook itself exits 0 on every path and only speaks for three
#   literal renderer commands, so a mis-wire degrades to silence, never to noise.
#
# RUN IT:  CONFIRM=1 bash ~/.claude/autonomy/pending-activation/27-relay-verbatim-activate.sh
# Rollback: bash ~/.claude/autonomy/pending-activation/27-relay-verbatim-activate.sh --rollback
# Mark done: touch ~/.claude/autonomy/pending-activation/27-relay-verbatim-activate.sh.done
# ───────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail

REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
LIVE="${CC_LIVE_DIR:-$HOME/.claude}"
BAK_SUFFIX=".pre-relay-verbatim.bak"
MATCH='relay-verbatim.sh'
ENTRY='{"type":"command","command":"~/.claude/hooks/relay-verbatim.sh","timeout":5}'

DEFAULT_DIRS="$HOME/.claude $HOME/.claude-next $HOME/.claude-secondary $HOME/.claude-tertiary $HOME/.claude-quaternary"
CANDIDATE_DIRS="${CC_CONFIG_DIRS:-$DEFAULT_DIRS}"

echo "== 27-relay-verbatim =="
command -v jq >/dev/null 2>&1 || { echo "✗ jq required" >&2; exit 1; }

if [ "${1:-}" = "--rollback" ]; then
  n=0
  for d in $CANDIDATE_DIRS; do
    b="$d/settings.json$BAK_SUFFIX"; [ -f "$b" ] || continue
    if jq -e . "$b" >/dev/null 2>&1; then
      cp -a "$b" "$d/settings.json" && rm -f "$b" && { echo "  ← $d/settings.json restored"; n=$((n+1)); }
    else
      echo "  ✗ $b does not parse — REFUSING to restore. Fix by hand." >&2
    fi
  done
  [ "$n" -gt 0 ] && echo "✓ rolled back $n dir(s)." || echo "· nothing to roll back."
  exit 0
fi

[ -f "$REPO/hooks/relay-verbatim.sh" ] || { echo "✗ not in checkout: $REPO/hooks/relay-verbatim.sh — is the fix landed?" >&2; exit 1; }

DIRS=""
for d in $CANDIDATE_DIRS; do [ -f "$d/settings.json" ] && DIRS="$DIRS $d"; done
[ -n "$DIRS" ] || { echo "✗ no config dir with a settings.json in: $CANDIDATE_DIRS" >&2; exit 1; }

echo
echo "Will do:"
echo "  0  ensure live symlink: hooks/relay-verbatim.sh"
for d in $DIRS; do
  if jq -e --arg m "$MATCH" '[.hooks.PostToolUse[]?.hooks[]?.command? // empty] | any(contains($m))' "$d/settings.json" >/dev/null 2>&1; then
    echo "  ·  $d/settings.json — already wired, WILL SKIP"
  else
    echo "  +  $d/settings.json — append to PostToolUse(Bash)  (backup → settings.json$BAK_SUFFIX)"
  fi
done
echo

if [ "${CONFIRM:-0}" != 1 ]; then
  echo "(dry run — re-run with CONFIRM=1 to apply:)"
  echo "    CONFIRM=1 bash $HOME/.claude/autonomy/pending-activation/27-relay-verbatim-activate.sh"
  exit 0
fi

# ---- 0: live symlink ---------------------------------------------------------------------------
# ~/.claude/hooks is a PER-FILE symlink dir, so a wired hook whose target was never linked errors
# on every Bash tool call. Idempotent re-assert.
echo "[0] live symlink under $LIVE"
if [ -L "$LIVE/hooks" ]; then
  echo "  = $LIVE/hooks is a dir-symlink ($(readlink "$LIVE/hooks")) — per-file links not applicable"
else
  src="$REPO/hooks/relay-verbatim.sh" dest="$LIVE/hooks/relay-verbatim.sh"
  if [ -e "$dest" ]; then echo "  = $dest"
  else
    mkdir -p "$(dirname "$dest")"
    ln -sfn "$src" "$dest" && echo "  → $dest (linked)" || { echo "  ✗ failed to link $dest" >&2; exit 1; }
  fi
fi

# ---- 1: wire each settings.json ----------------------------------------------------------------
echo "[1] settings.json"
wired=0; skipped=0
for d in $DIRS; do
  S="$d/settings.json"
  if jq -e --arg m "$MATCH" '[.hooks.PostToolUse[]?.hooks[]?.command? // empty] | any(contains($m))' "$S" >/dev/null 2>&1; then
    echo "  = $S (already wired)"; skipped=$((skipped+1)); continue
  fi
  B="$S$BAK_SUFFIX"
  cp -a "$S" "$B" || { echo "  ✗ backup failed — refusing to touch $S" >&2; exit 1; }

  tmp="$S.relay-verbatim-tmp.$$"
  # Append into the EXISTING Bash group when there is one; otherwise create that group. Never
  # disturb a sibling group — a hook list is a list of groups and other matchers share the array.
  if ! jq --argjson e "$ENTRY" \
        '.hooks //= {}
         | .hooks.PostToolUse //= []
         | if ([.hooks.PostToolUse[] | select(.matcher == "Bash")] | length) > 0
           then .hooks.PostToolUse |= map(if .matcher == "Bash" then .hooks += [$e] else . end)
           else .hooks.PostToolUse += [{"matcher":"Bash","hooks":[$e]}] end' \
        "$S" > "$tmp" 2>/dev/null; then
    rm -f "$tmp"; cp -a "$B" "$S"
    echo "  ✗ jq edit FAILED on $S — RESTORED from $B, file UNCHANGED. ABORTING." >&2; exit 1
  fi

  if jq empty "$tmp" >/dev/null 2>&1 \
     && jq -e --arg m "$MATCH" '[.hooks.PostToolUse[]?.hooks[]?.command? // empty] | any(contains($m))' "$tmp" >/dev/null 2>&1; then
    mv -f "$tmp" "$S" || { rm -f "$tmp"; echo "  ✗ could not replace $S — UNCHANGED (backup at $B)" >&2; exit 1; }
    echo "  → $S (wired)"; wired=$((wired+1))
  else
    rm -f "$tmp"; cp -a "$B" "$S"
    echo "  ✗ VALIDATION FAILED for $S — RESTORED from $B. ABORTING." >&2; exit 1
  fi
done

echo
echo "✓ wired $wired dir(s), skipped $skipped."
echo "  Verify:  printf '%s' '{\"tool_input\":{\"command\":\"claude-accounts --readout\"},\"tool_response\":{\"stdout\":\"x\"}}' | $LIVE/hooks/relay-verbatim.sh"
echo "  Mark done: touch $HOME/.claude/autonomy/pending-activation/27-relay-verbatim-activate.sh.done"
