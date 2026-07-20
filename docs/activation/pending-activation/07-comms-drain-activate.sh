#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 07-comms-drain  —  wire the 2-way-comms mailbox-drain hooks into the LIVE per-account settings.json
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: the two-way-session-comms build (TWO_WAY_SESSION_COMMS_PLAN.md Phase 1) delivers mail as
#   additionalContext on the harness's two RELIABLE boundaries. The TEMPLATE
#   (settings-templates/settings.example.json) is already wired; the LIVE per-account settings are not.
#   This script adds, to EVERY config dir that has a settings.json:
#
#     SessionStart       += ~/.claude/hooks/mailbox-drain.sh session-start   (timeout 5)
#     UserPromptSubmit   += ~/.claude/hooks/mailbox-drain.sh prompt          (timeout 5)
#
#   The two entry objects are COPIED VERBATIM out of the template at run time (never hand-retyped),
#   so the live wiring can not drift from settings.example.json. Each is appended as its own
#   {"hooks":[…]} group — a hook list is a list of groups, so appending never disturbs a sibling.
#
#   Step 0 also ensures the three live symlinks the wired path depends on exist
#   (hooks/mailbox-drain.sh, hooks/lib/mailbox-pending.sh, bin/cc-inbox-guard). ~/.claude/hooks is a
#   PER-FILE symlink dir, not a dir-symlink, so a deploy that misses a file leaves a wired hook whose
#   target is absent — an error on every single SessionStart. (If it is ever converted to a
#   dir-symlink, this step correctly detects that and does nothing.)
#
# WHY C10 (agent staged; operator runs): this mutates the live harness config of every account. The
#   agent never self-activates hooks — a bad write here breaks every session that starts afterwards.
#
# SAFETY: per-dir backup to <dir>/settings.json.pre-comms-drain.bak BEFORE any write · jq only, never
#   sed · post-write validation (parses AND both drain commands present) · a failed validation RESTORES
#   that dir's backup and ABORTS LOUD · already-wired dirs are SKIPPED (idempotent, no double-add).
#
# RUN IT:  CONFIRM=1 bash ~/.claude/autonomy/pending-activation/07-comms-drain-activate.sh
# Rollback: bash ~/.claude/autonomy/pending-activation/07-comms-drain-activate.sh --rollback
# Mark done: touch ~/.claude/autonomy/pending-activation/07-comms-drain-activate.sh.done
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail

REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
TEMPLATE="$REPO/settings-templates/settings.example.json"
LIVE="${CC_LIVE_DIR:-$HOME/.claude}"          # the dir the wired `~/.claude/…` paths actually resolve to
BAK_SUFFIX=".pre-comms-drain.bak"

# Config dirs to wire. Overridable as a space-separated list for tests (never point this at anything
# you are not willing to have edited).
DEFAULT_DIRS="$HOME/.claude $HOME/.claude-next $HOME/.claude-secondary $HOME/.claude-tertiary $HOME/.claude-quaternary"
CANDIDATE_DIRS="${CC_CONFIG_DIRS:-$DEFAULT_DIRS}"

SS_MATCH='mailbox-drain.sh session-start'
UP_MATCH='mailbox-drain.sh prompt'

echo "== 07-comms-drain =="
echo "repo: $REPO"

command -v jq >/dev/null 2>&1 || { echo "✗ jq required" >&2; exit 1; }

# ---- --rollback -----------------------------------------------------------------------------------
if [ "${1:-}" = "--rollback" ]; then
  echo "[rollback] restoring every $BAK_SUFFIX"
  n=0
  for d in $CANDIDATE_DIRS; do
    b="$d/settings.json$BAK_SUFFIX"
    [ -f "$b" ] || continue
    if jq -e . "$b" >/dev/null 2>&1; then
      cp -a "$b" "$d/settings.json" && rm -f "$b" && { echo "  ← $d/settings.json restored"; n=$((n+1)); }
    else
      echo "  ✗ $b does not parse — REFUSING to restore it. Fix by hand." >&2
    fi
  done
  [ "$n" -gt 0 ] && echo "✓ rolled back $n dir(s). The symlinks are left in place (inert when unwired)." \
                 || echo "· nothing to roll back."
  exit 0
fi

# ---- preflight ------------------------------------------------------------------------------------
[ -f "$TEMPLATE" ] || { echo "✗ template not found: $TEMPLATE (is the checkout on a trunk with the 2-way-comms commit? git -C $REPO pull --ff-only)" >&2; exit 1; }

# Copy the two entry objects VERBATIM out of the template — never retype them here.
SS_ENTRY="$(jq -c --arg m "$SS_MATCH" 'first(.hooks.SessionStart[]?.hooks[]? | select(.command? // "" | contains($m)))' "$TEMPLATE" 2>/dev/null)"
UP_ENTRY="$(jq -c --arg m "$UP_MATCH" 'first(.hooks.UserPromptSubmit[]?.hooks[]? | select(.command? // "" | contains($m)))' "$TEMPLATE" 2>/dev/null)"
for pair in "SessionStart:$SS_ENTRY" "UserPromptSubmit:$UP_ENTRY"; do
  key="${pair%%:*}"; val="${pair#*:}"
  [ -n "$val" ] && [ "$val" != "null" ] || { echo "✗ no mailbox-drain entry under .hooks.$key in $TEMPLATE — nothing to copy. STOP." >&2; exit 1; }
done

# The live set, verified at run time — never a hardcoded assumption about how many dirs exist.
DIRS=""
for d in $CANDIDATE_DIRS; do [ -f "$d/settings.json" ] && DIRS="$DIRS $d"; done
[ -n "$DIRS" ] || { echo "✗ no config dir with a settings.json found in: $CANDIDATE_DIRS" >&2; exit 1; }

echo
echo "Will do:"
echo "  0  ensure live symlinks: hooks/mailbox-drain.sh · hooks/lib/mailbox-pending.sh · bin/cc-inbox-guard"
for d in $DIRS; do
  if jq -e '[.hooks[]?[]?.hooks[]?.command? // empty] | any(contains("mailbox-drain"))' "$d/settings.json" >/dev/null 2>&1; then
    echo "  ·  $d/settings.json — already wired, WILL SKIP"
  else
    echo "  +  $d/settings.json — add SessionStart + UserPromptSubmit drain entries (backup → settings.json$BAK_SUFFIX)"
  fi
done
echo

if [ "${CONFIRM:-0}" != 1 ]; then
  echo "(dry run — re-run with CONFIRM=1 to apply:)"
  echo "    CONFIRM=1 bash $HOME/.claude/autonomy/pending-activation/07-comms-drain-activate.sh"
  exit 0
fi

# ---- 0: live symlinks -----------------------------------------------------------------------------
echo "[0] live symlinks under $LIVE"
if [ -L "$LIVE/hooks" ]; then
  echo "  = $LIVE/hooks is a dir-symlink ($(readlink "$LIVE/hooks")) — per-file links not applicable"
else
  for rel in hooks/mailbox-drain.sh hooks/lib/mailbox-pending.sh bin/cc-inbox-guard; do
    src="$REPO/$rel" dest="$LIVE/$rel"
    [ -e "$src" ] || { echo "  ✗ missing in checkout: $src" >&2; exit 1; }
    if [ -e "$dest" ]; then echo "  = $dest"; continue; fi
    mkdir -p "$(dirname "$dest")"
    if ln -sfn "$src" "$dest"; then echo "  → $dest (linked)"; else echo "  ✗ failed to link $dest" >&2; exit 1; fi
  done
fi

# ---- 1: wire each settings.json -------------------------------------------------------------------
echo "[1] settings.json"
wired=0; skipped=0
for d in $DIRS; do
  S="$d/settings.json"
  if jq -e '[.hooks[]?[]?.hooks[]?.command? // empty] | any(contains("mailbox-drain"))' "$S" >/dev/null 2>&1; then
    echo "  = $S (already wired)"; skipped=$((skipped+1)); continue
  fi
  B="$S$BAK_SUFFIX"
  cp -a "$S" "$B" || { echo "  ✗ backup failed — refusing to touch $S" >&2; exit 1; }

  tmp="$S.comms-drain-tmp.$$"
  if ! jq --argjson ss "$SS_ENTRY" --argjson up "$UP_ENTRY" \
        '.hooks //= {}
         | .hooks.SessionStart      = ((.hooks.SessionStart      // []) + [{"hooks":[$ss]}])
         | .hooks.UserPromptSubmit  = ((.hooks.UserPromptSubmit  // []) + [{"hooks":[$up]}])' \
        "$S" > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    cp -a "$B" "$S"
    echo "  ✗ jq edit FAILED on $S (malformed JSON?) — RESTORED from $B, file UNCHANGED. ABORTING." >&2
    exit 1
  fi

  # Validate the CANDIDATE before it becomes the live file: must parse AND carry both drain commands.
  if jq empty "$tmp" >/dev/null 2>&1 \
     && jq -e --arg m "$SS_MATCH" '[.hooks.SessionStart[]?.hooks[]?.command? // empty]     | any(contains($m))' "$tmp" >/dev/null 2>&1 \
     && jq -e --arg m "$UP_MATCH" '[.hooks.UserPromptSubmit[]?.hooks[]?.command? // empty] | any(contains($m))' "$tmp" >/dev/null 2>&1; then
    mv -f "$tmp" "$S" || { rm -f "$tmp"; echo "  ✗ could not replace $S — UNCHANGED (backup at $B)" >&2; exit 1; }
    echo "  → $S (wired: SessionStart + UserPromptSubmit)"; wired=$((wired+1))
  else
    rm -f "$tmp"
    cp -a "$B" "$S"
    echo "  ✗ VALIDATION FAILED for $S — RESTORED from $B. Nothing wired in this dir. ABORTING." >&2
    echo "    (rollback the dirs already done:  bash $0 --rollback)" >&2
    exit 1
  fi
done

# ---- summary + verify -----------------------------------------------------------------------------
echo
echo "== summary =="
echo "  wired:   $wired"
echo "  skipped: $skipped (already wired)"
echo
echo "== verify =="
if [ -x "$LIVE/bin/cc-inbox-guard" ]; then
  "$LIVE/bin/cc-inbox-guard" --selftest 2>&1 | tail -2
else
  echo "  · cc-inbox-guard not executable at $LIVE/bin/cc-inbox-guard — check step 0"
fi
echo
echo "✓ drain hooks ACTIVE. They take effect in NEWLY started sessions (SessionStart) and on the next"
echo "  prompt of any session started after this point — already-running panes keep their old wiring."
echo
echo "  Smoke it: open a new session, then from another pane:  cc-announce  /  cc-notify <pane> \"ping\""
echo "  The line should arrive as additionalContext (not keystrokes) on that session's next boundary."
echo
echo "  Mark this activation done:"
echo "      touch $HOME/.claude/autonomy/pending-activation/07-comms-drain-activate.sh.done"
echo
# ROLLBACK (one-liner): bash ~/.claude/autonomy/pending-activation/07-comms-drain-activate.sh --rollback
echo "ROLLBACK: bash $HOME/.claude/autonomy/pending-activation/07-comms-drain-activate.sh --rollback"
