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

# === AUTO-MEMORY PATH CANON (2026-09-27) ===
# A memory write spelled through a SYMLINKED config dir (~/.claude-next/projects/…/memory/x.md,
# where projects/ or memory/ links into ~/.claude/projects/) raises a permission prompt that no
# allow rule, --add-dir or hook `allow` clears: CC's auto-memory carve-out matches the path AS
# SPELLED, and bin/cc-close-attrib pins autoMemoryDirectory to the REAL path. Rewriting file_path
# to the real path via `updatedInput` does clear it — headless A/B on 2.1.280, same spelling, one
# variable: no hook ⇒ permission_denials 1; this rewrite ⇒ 0 and the file written, for Write and
# for Read-then-Edit alike. It is the SAME file, so nothing is widened: the harness evaluates the
# path its own symlink check would have resolved anyway. No permissionDecision is set, so every
# other permission rule still runs, on the rewritten path.
# Lesson: docs/lessons/symlinked-auto-memory-dir-prompts-on-every-write.md. Kill switch
# CC_MEMPATH_CANON=off. Fails open: on any doubt the input is left untouched.
CANON_TI=""
EMITTED=0
_bbw_phys() { # <path> → the path with every symlinked ancestor resolved (the leaf may not exist)
  local probe="${1%/*}" rest="/${1##*/}" real
  while [ -n "$probe" ] && [ ! -d "$probe" ]; do
    rest="/${probe##*/}$rest"; probe="${probe%/*}"
  done
  [ -n "$probe" ] || return 1
  real="$(cd -P "$probe" 2>/dev/null && pwd -P)" && [ -n "$real" ] || return 1
  printf '%s' "${real%/}$rest"
}
if [ "${CC_MEMPATH_CANON:-on}" != off ]; then
  case "$TOOL:$FILE" in
    Write:/*/.claude*/projects/*/memory/*|Edit:/*/.claude*/projects/*/memory/*|MultiEdit:/*/.claude*/projects/*/memory/*)
      if _bbw_real="$(_bbw_phys "$FILE")" && [ "$_bbw_real" != "$FILE" ]; then
        case "$_bbw_real" in
          /*/.claude*/projects/*/memory/*)
            CANON_TI="$(printf '%s' "$INPUT" | jq -c --arg p "$_bbw_real" '.tool_input + {file_path: $p}' 2>/dev/null)" || CANON_TI=""
            [ -n "$CANON_TI" ] && FILE="$_bbw_real"
            ;;
        esac
      fi
      ;;
  esac
fi
# Every advisory below goes out through _bbw_out, which carries the rewrite along; a path that
# emits nothing still delivers it via the EXIT trap. Fed by a heredoc, never a pipeline, so
# EMITTED is set in THIS shell.
_bbw_out() {
  local body; body="$(cat)"
  EMITTED=1
  if [ -n "$CANON_TI" ]; then
    printf '%s' "$body" | jq -c --argjson ti "$CANON_TI" '.hookSpecificOutput.updatedInput = $ti' 2>/dev/null \
      && return 0
  fi
  printf '%s\n' "$body"
}
# shellcheck disable=SC2329  # invoked by the EXIT trap below
_bbw_rewrite_only() {
  [ -n "$CANON_TI" ] && [ "$EMITTED" -eq 0 ] || return 0
  jq -nc --argjson ti "$CANON_TI" '{hookSpecificOutput: {hookEventName: "PreToolUse", updatedInput: $ti}}'
}
trap _bbw_rewrite_only EXIT

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

# === NEW-TOPIC NEIGHBOURS (2026-09-28, truememory-2026-09-27.md §3.10) ===
# A Write that CREATES a memory topic or lesson is shown its two nearest existing files (IDF token
# overlap, hooks/lib/memory_neighbours.py; no threshold), because "grep MEMORY.md first" sees under
# a third of a store and real twins were written anyway. The context reaches the model WITH the tool
# result, after the file exists, hence the past tense. rm_friction: `rm <abs memory path>` is NOT
# auto-allowed by rm-safe-allowlist.sh (probe 2026-09-28: silent, so it prompts or goes to the
# classifier), so the advice leaves the duplicate for compact-memory's orphan sweep instead of an rm.
# Every exit logs to the IDL (own name, X2) AND ~/.claude/state/mem-neighbours.jsonl (X4). The lib
# resolves ONLY through the dereferenced self-path (X1). Kill switch CC_MEM_NEIGHBOURS=off.
_bbw_nlog() { # <disposition> <reason> — one row, to both stores
  local row
  row="$(jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg sid "$(printf '%s' "$INPUT" | jq -r '.session_id // "?"')" \
    --arg d "$1" --arg r "$2" --arg id "$NB_ID" --arg p "$FILE" --argjson t "$NB_TOP" \
    '{ts:$ts, hook:"backup-before-write:neighbours", sid:$sid, disposition:$d, reason:$r,
      tool_use_id:$id, path:$p, top:$t, rm_friction:"not-auto-allowed"}' 2>/dev/null)" || return 0
  mkdir -p "$HOME/.claude/state" "$(dirname "${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}")" 2>/dev/null
  printf '%s\n' "$row" >> "$HOME/.claude/state/mem-neighbours.jsonl" 2>/dev/null
  printf '%s\n' "$row" >> "${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}" 2>/dev/null; return 0
}
case "$TOOL:$FILE" in Write:*/archive/*|Write:*/MEMORY.md) ;; Write:*/memory/*.md|Write:*/docs/lessons/*.md)
  if [ ! -e "$FILE" ]; then
    NB_PY="$(dirname "$(_mib_deref "${BASH_SOURCE[0]}")")/lib/memory_neighbours.py"
    NB_ID="$(printf '%s' "$INPUT" | jq -r '.tool_use_id // "?"')"; NB_TOP='[]'; NB_RC=0
    if [ "${CC_MEM_NEIGHBOURS:-on}" = off ]; then _bbw_nlog abstained kill-switch
    elif [ ! -r "$NB_PY" ]; then _bbw_nlog abstained "neighbour-lib-missing:$NB_PY"
    elif ! command -v python3 >/dev/null 2>&1; then _bbw_nlog abstained neighbour-lib-missing:no-python3
    else
      NB_OUT="$(printf '%s' "$INPUT" | jq -r '.tool_input.content // ""' | python3 "$NB_PY" "$FILE" 2>/dev/null)" || NB_RC=$?
      NB_TOP="$(printf '%s' "$NB_OUT" | jq -c '.top // []' 2>/dev/null)"; [ -n "$NB_TOP" ] || NB_TOP='[]'
      if [ "$NB_RC" -eq 124 ]; then _bbw_nlog failed timeout
      elif [ "$NB_RC" -ne 0 ]; then _bbw_nlog failed "rc=$NB_RC"
      elif [ "$NB_TOP" = '[]' ]; then _bbw_nlog abstained empty-pool
      else
        _bbw_nlog fired top2
        # ≤400 chars: the new file's name is repeated as in the design, or "this file" when that
        # would overflow; a cut is the last resort. Neighbours in the same dir are shown bare.
        NB_MSG="$(jq -rn --arg x "$FILE" --argjson t "$NB_TOP" '($x | sub(".*/"; "")) as $b
          | ($x | sub("/[^/]*$"; "/")) as $d
          | ($t | map((.path | ltrimstr($d)) + " (" + (.score | tostring) + ")")) as $n
          | [$b, "this file"] | map(. as $r | "You just created \($b); its nearest existing "
            + (if ($n | length) > 1 then "files are \($n[0]) and \($n[1])" else "file is \($n[0])" end)
            + ". If \($r) restates one of them, move anything new into it and leave \($r) for compact-memory'"'"'s orphan sweep; if it corrects one, add superseded_by; if it is different, ignore this.")
          | (map(select(length <= 400)) + [.[1]])[0]')"
        [ "${#NB_MSG}" -le 400 ] || NB_MSG="${NB_MSG:0:397}..."
        _bbw_out <<<"$(jq -nc --arg c "$NB_MSG" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $c}}')"
      fi
    fi
  fi ;;
esac

# === INSTRUCTION BUDGET (2026-10-03, docs/plans/INSTRUCTION_BUDGET.md D7) ===
# Always-loaded instruction files (CLAUDE.md, .claude/CLAUDE.md, CLAUDE.local.md, unconditional
# .claude/rules/**, the user tier, and what they @import) load in full into every session: measured
# 180k-430k chars per session on 2026-10-03, against a loader limit of 150k (40k per file / 120k total
# on a 200k window). This refuses a write only when it GROWS a file, a conditional rule, or a tier
# past its budget; shrinking and same-size writes always pass, so the cure is never refused. The
# predicate, budgets and deny text live in ONE place, hooks/lib/instruction_budget.py +
# config/instruction-budget.json, which the land ratchet and the fleet auditor share.
#
# ABOVE the fast exit on purpose: creating a new rules file is a primary growth route, and the exit
# below lets every non-existent path through unjudged (the MEMORY INDEX BUDGET block sits after it
# and so never sees a create).
#
# The pre-screen is forkless: a `case` on the path name, then the published @import reachability
# set (cc-instruction-budget publish, from autonomy-sweep) read with a builtin. Only a hit pays for
# python. Fails open: no python3, no lib, any error or timeout inside the lib ⇒ the write proceeds and
# the lib logs an `abstained` IDL row. Enforcement is the config's `enforce` key (shadow while false).
IB_HIT=0
case "$FILE" in
  */CLAUDE.md|*/CLAUDE.*.md|*/.claude*/rules/*.md|*/rules.slim/*.md) IB_HIT=1 ;;
esac
if [ "$IB_HIT" = 0 ] && [ -n "$FILE" ] && [ -r "$HOME/.claude/state/instruction-budget/loaded-set.txt" ]; then
  IB_SET=""
  IFS= read -r -d '' IB_SET < "$HOME/.claude/state/instruction-budget/loaded-set.txt" || true
  case $'\n'"$IB_SET" in *$'\n'"$FILE"$'\n'*) IB_HIT=1 ;; esac
fi
if [ "$IB_HIT" = 1 ] && command -v python3 >/dev/null 2>&1; then
  IB_PY="$(dirname "$(_mib_deref "${BASH_SOURCE[0]}")")/lib/instruction_budget.py"
  [ -r "$IB_PY" ] || IB_PY="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/instruction_budget.py"
  if [ -r "$IB_PY" ]; then
    IB_OUT="$(printf '%s' "$INPUT" | python3 "$IB_PY" verdict 2>/dev/null)" || IB_OUT=""
    case "$IB_OUT" in
      *'"permissionDecision": "deny"'*)
        EMITTED=1  # a deny needs no rewrite: the write never happens
        printf '%s\n' "$IB_OUT"
        exit 0 ;;
    esac
  fi
fi

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
# (_mib_deref is defined above the new-topic neighbours branch, which needs it first.)
MIB_LIB="$(dirname "$(_mib_deref "${BASH_SOURCE[0]}")")/lib/memory-index-budget.sh"
[ -r "$MIB_LIB" ] || MIB_LIB="$(dirname "${BASH_SOURCE[0]}")/lib/memory-index-budget.sh"
[ -r "$MIB_LIB" ] || MIB_LIB="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/memory-index-budget.sh"
if [ -r "$MIB_LIB" ]; then
  # shellcheck source=lib/memory-index-budget.sh
  # shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
  . "$MIB_LIB"
  MIB_TI=$(echo "$INPUT" | jq -c '.tool_input // {}')
  if MIB_REASON="$(mib_verdict "$TOOL" "$FILE" "$MIB_TI")"; then
    EMITTED=1  # a deny needs no rewrite: the write never happens
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
    # ONCE PER (session, agent, plan file) (2026-10-04, claude-api audit hooks-a-09), the pattern
    # plan-agent-teams-default.sh already uses for PLAN DEFAULTS. The rules never change between
    # edits, and re-sending ~870 chars on every Edit was the bulk of this hook's context: 598 fires
    # and ~190K tokens in 7 days, 57% of them repeats inside one context. agent_id is part of the key
    # because an in-process subagent shares its lead's session_id but not its context. No session id
    # ⇒ no key ⇒ emit (fail toward the rule). The early exit still runs the _bbw_rewrite_only trap.
    # Write and OVERWRITE GUARD below stay per call: each one reports a fresh backup.
    _pg_id="$(printf '%s' "$INPUT" | jq -r 'if (.session_id // "") == "" then "" else "\(.session_id)|\(.agent_id // "")" end' 2>/dev/null || true)"
    if [ -n "$_pg_id" ]; then
      _pg_dir="${CC_PLAN_GUARD_STATE_DIR:-$HOME/.claude/state/plan-guard}"
      _pg_key="$(printf '%s|%s' "$_pg_id" "$FILE" | shasum 2>/dev/null | cut -c1-16)"
      if [ -n "$_pg_key" ]; then
        mkdir -p "$_pg_dir" 2>/dev/null || true
        find "$_pg_dir" -type f -mtime +7 -delete 2>/dev/null || true
        [ -f "$_pg_dir/$_pg_key" ] && exit 0
        : > "$_pg_dir/$_pg_key" 2>/dev/null || true
      fi
    fi
    _bbw_out <<EOF
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
  _bbw_out <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "OVERWRITE GUARD: You just OVERWROTE '${BASENAME}' (${LINES} lines before the write). Backup saved to ${BACKUP_FILE}. CRITICAL RULE: INTEGRATE new content — do NOT delete or restructure existing sections. Use Edit for targeted changes instead of Write.${PLAN_RULES} Restore if overwritten: ~/.claude/scripts/restore-file.sh ${FILE}"
  }
}
EOF
else
  # Backup failed (disk full, permissions) — warn but allow Write to proceed
  _bbw_out <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "WARNING: Backup of '${BASENAME}' FAILED (disk/permissions). Write will proceed WITHOUT backup. CRITICAL: Use Edit instead of Write to avoid losing existing content.${PLAN_RULES}"
  }
}
EOF
fi

exit 0
