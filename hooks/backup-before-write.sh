#!/bin/bash
# PreToolUse hook for Write|Edit|MultiEdit — auto-backup, overwrite guard, plan conventions
# Matches: Write/MultiEdit (backup + warn) and Edit on plan files (inject plan conventions)
# Creates timestamped backups in ~/.claude/backups/ with sidecar path files
#
# Hardened Mar 19 2026 — fixes from 15-agent deep research:
#   - Nanosecond timestamps (prevent agent team race conditions)
#   - Explicit symlink following (-L flag)
#   - Relative path detection for docs/plans/
#   - Graceful backup failure (warn, don't block Write)
#   - jq dependency check

# Don't use set -e — backup failures must not block tool execution
set -uo pipefail

# === JQ CHECK ===
if ! command -v jq &>/dev/null; then
  exit 0  # Silent pass-through if jq unavailable — never block writes
fi

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Fast exit: no file path or file doesn't exist
[ -z "$FILE" ] && exit 0
[ ! -f "$FILE" ] && exit 0

BASENAME=$(basename "$FILE")
LINES=$(wc -l < "$FILE" | tr -d ' ')

# === MEMORY INDEX BUDGET (2026-08-06, backlog 07b0cbf4905a) ===
# The one branch of this hook that can refuse a write. Everything else here ends `exit 0` with an
# advisory `additionalContext` — it backs up and it warns. That is exactly the shape that has failed
# for the MEMORY.md read limit twelve times: `hooks/memory-nudge.sh` measures the budget correctly
# and only ADVISES, so the index was compacted twelve times between 07-25 and 08-06 and went back
# over every time, and the ledger opened four items for one condition. A rule enforced anywhere but
# where the act happens is detection, not a gate (MEMORY.md enforcement-must-live-at-the-chokepoint).
#
# It lives HERE, in a hook already wired into the PreToolUse Write|Edit|MultiEdit chain and already
# symlinked into ~/.claude/hooks/, so it needs no settings.json edit (C10) and cannot become a
# pending-activation that never gets run — eleven of those are currently rotting, which is the
# measured cost of the alternative.
#
# THE LIB PATH IS DEREFED FIRST, and that is load-bearing rather than tidy. Invoked live this file
# IS ~/.claude/hooks/backup-before-write.sh — a symlink into the checkout — while ~/.claude/hooks/lib/
# holds PER-FILE symlinks, so a NEW lib has no mirror there until a deploy creates one. An underefed
# `dirname "$BASH_SOURCE"` would miss the lib and fail open SILENTLY: the gate would read as landed
# while being inert, the exact shape of MEMORY.md self-deploying-fix-inert-for-its-own-deploy.
# Dereferencing lands us in the checkout, where the lib exists the moment the trunk fast-forwards.
_mib_deref() { # <path> → the real file behind any symlink chain (readlink -f, BSD-safe fallback)
  local p="$1" t n=0
  readlink -f "$p" 2>/dev/null && return 0
  while [ -L "$p" ] && [ "$n" -lt 20 ]; do
    t="$(readlink "$p")"
    case "$t" in /*) p="$t" ;; *) p="$(dirname "$p")/$t" ;; esac
    n=$(( n + 1 ))
  done
  printf '%s\n' "$p"
}
MIB_LIB="$(dirname "$(_mib_deref "${BASH_SOURCE[0]}")")/lib/memory-index-budget.sh"
[ -r "$MIB_LIB" ] || MIB_LIB="$(dirname "${BASH_SOURCE[0]}")/lib/memory-index-budget.sh"
[ -r "$MIB_LIB" ] || MIB_LIB="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/memory-index-budget.sh"
if [ -r "$MIB_LIB" ]; then
  # shellcheck source=lib/memory-index-budget.sh
  # shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
  . "$MIB_LIB"
  MIB_TI=$(echo "$INPUT" | jq -c '.tool_input // {}')
  if MIB_REASON="$(mib_verdict "$TOOL" "$FILE" "$MIB_TI")"; then
    jq -nc --arg r "$MIB_REASON" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $r
      }
    }'
    exit 0
  fi
fi

# === PLAN FILE DETECTION ===
# 5-pattern hybrid: personal plans, project symlinks, project docs (absolute + relative), master plan
IS_PLAN=false
case "$FILE" in
  "$HOME/.claude/plans/"*.md)                    IS_PLAN=true ;;  # Personal plans (absolute)
  *"/.claude-plans/"*.md)                        IS_PLAN=true ;;  # Project symlinks (absolute)
  *"/docs/plans/"*.md)                           IS_PLAN=true ;;  # Project plan docs (absolute)
  docs/plans/*.md)                               IS_PLAN=true ;;  # Project plan docs (relative)
  *"/AGENT_TEAM_IMPLEMENTATION_PLAN"*.md)        IS_PLAN=true ;;  # Master plan (any location)
esac

# === PLAN CONVENTIONS (injected for both Write AND Edit on plan files) ===
PLAN_RULES=""
if [ "$IS_PLAN" = true ]; then
  PLAN_RULES=" PLAN UPDATE RULES: (1) COMPLETED sections: mark DONE, compact to key learnings + commit hashes only — remove step-by-step details. (2) UPCOMING sections: keep comprehensive and expansive — file paths, line ranges, decision context, trade-offs. (3) Phase 0 MANDATORY: first upcoming section must be Agent Team Orchestration, and its FIRST field is the EXECUTION LOCUS PER WAVE — S = dispatched handoff session (the DEFAULT, no justification needed) | T = in-session teammates (output lands in the LEAD's context — justify) | L = lead-inline (justify) — then team size, roles, task dependencies, worktree assignments, spawn wave order, and the LEAD's context budget + succession point. (4) NEVER delete: historical decisions, 'Why:' explanations, learnings, or known issues — these compound across sessions."
fi

# === EDIT TOOL: plan context only, no backup needed ===
if [ "$TOOL" = "Edit" ]; then
  if [ "$IS_PLAN" = true ]; then
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "PLAN GUARD: Editing plan file '${BASENAME}' (${LINES} lines).${PLAN_RULES}"
  }
}
EOF
  fi
  # Non-plan Edit: silent pass-through (no output = no context injection)
  exit 0
fi

# === WRITE / MULTIEDIT TOOL: backup + warn ===

BACKUP_DIR="$HOME/.claude/backups"

# === IDENTITY-CLASS SOURCES NEVER ENTER THE SHARED STORE (backlog 2bcc6b4d8468) ===
# ~/.claude/backups is a REAL dir that every other config dir reaches through a symlink, so a
# backup written here by ANY account lands in the layer all four read. That is harmless for the
# work files this store exists for -- and it was an auth leak for the identity family: five
# `.claude.json.backup.*` carrying `oauthAccount` for three DIFFERENT accounts were found sitting
# in the shared dir (ACCOUNT_AGNOSTIC_AGENT_STATE.md, "what the completeness critic found"). It is
# the exact inverse of the defect that plan repaired: `.claude.json` is isolated at the config-dir
# root, and the same bytes then walk into the shared layer under a path no isolate entry covers.
#
# THE SPLIT IS BY CONTENT CLASS, NOT BY STORE. Isolating `backups` wholesale would have been the
# mis-classification this repo already measured and reverted once: lib/config-mirror.zsh's `tasks`
# note ("a task board is WORK state, not ACCOUNT state ... splitting four ways along an axis the
# operator does not think in is pure loss") applies verbatim to the 145 repo-file backups in here,
# which are work state and SHOULD stay reachable from every account. Only the identity family is
# account state, so only the identity family is routed out.
#
# The destination is the account's OWN config dir, and `backups-identity` is in every isolate set
# in lib/config-mirror.zsh -- without that entry the mirror auto-shares any new ~/.claude subdir
# into all four accounts and would re-create this leak the first time account 1 wrote one.
#
# The auto-prune below keys on $BACKUP_DIR, so the private store inherits keep-10-per-source and
# cannot grow without bound. scripts/prune-backups.sh's 30-day arm does NOT reach it: deleting
# auth material on a clock is a purge, and this row holds purges for an operator call.
case "$BASENAME" in
  .claude.json|.claude.json.*|.credentials.json|.credentials.json.*|mcp-needs-auth-cache.json)
    BACKUP_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/backups-identity" ;;
esac

mkdir -p "$BACKUP_DIR" 2>/dev/null || true

# Nanosecond timestamp prevents race conditions with parallel agent teams
TIMESTAMP=$(date +%Y%m%d-%H%M%S)-$$
# macOS date doesn't support %N — use PID as unique suffix (guaranteed unique per process)
BACKUP_FILE="${BACKUP_DIR}/${BASENAME}__${TIMESTAMP}.bak"
PATH_FILE="${BACKUP_DIR}/${BASENAME}__${TIMESTAMP}.path"

# Copy existing file before Write overwrites it
# -L: explicitly follow symlinks (back up real content, not symlink)
# Graceful failure: warn but don't block the Write
if cp -L "$FILE" "$BACKUP_FILE" 2>/dev/null; then
  echo "$FILE" > "$PATH_FILE" 2>/dev/null || true

  # === AUTO-PRUNE: keep the last 10 backups PER SOURCE PATH (audit 09 D-8) ===
  # Keyed by the `.path` sidecar identity, NOT the basename. Under the old basename bucket every
  # repo's CLAUDE.md / SKILL.md / README.md / page.tsx shared ONE 10-slot bucket, so a busy repo
  # could evict another repo's ONLY backup — the exact loss this guard exists to prevent. The
  # sidecar already recorded the identity; the prune just ignored it.
  # Ordering now comes from ONE sort over the whole matched set: the old
  # `find -print0 | xargs -0 ls -t | tail -n +11` re-sorted per xargs BATCH, so past a batch
  # boundary it deleted from the wrong end. Backup names embed a fixed-width stamp
  # (<basename>__YYYYmmdd-HHMMSS-PID), so a lexical reverse sort IS newest-first — and unlike
  # mtime it stays deterministic when several backups land inside the same second.
  KEEP_PER_SOURCE=10
  SAME_SOURCE=""
  for pf in "$BACKUP_DIR/${BASENAME}__"*.path; do
    [ -f "$pf" ] || continue
    [ "$(cat "$pf" 2>/dev/null)" = "$FILE" ] || continue
    SAME_SOURCE="${SAME_SOURCE}${pf}
"
  done
  if [ -n "$SAME_SOURCE" ]; then
    printf '%s' "$SAME_SOURCE" | sort -r | tail -n "+$((KEEP_PER_SOURCE + 1))" \
      | while IFS= read -r old_path; do
          [ -n "$old_path" ] || continue
          rm -f "${old_path%.path}.bak" "$old_path"
        done
  fi

  # === WARN AI ===
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "OVERWRITE GUARD: You are about to OVERWRITE '${BASENAME}' (${LINES} lines). Backup saved to ${BACKUP_FILE}. CRITICAL RULE: INTEGRATE new content — do NOT delete or restructure existing sections. Use Edit for targeted changes instead of Write.${PLAN_RULES} Restore if overwritten: ~/.claude/scripts/restore-file.sh ${FILE}"
  }
}
EOF
else
  # Backup failed (disk full, permissions) — warn but allow Write to proceed
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "WARNING: Backup of '${BASENAME}' FAILED (disk/permissions). Write will proceed WITHOUT backup. CRITICAL: Use Edit instead of Write to avoid losing existing content.${PLAN_RULES}"
  }
}
EOF
fi

exit 0
