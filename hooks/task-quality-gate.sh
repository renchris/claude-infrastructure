#!/bin/bash
# TaskCompleted hook — quality gate that runs typecheck in the teammate's worktree.
# Exit code 2 rejects the task and sends build errors back to the teammate.
# Exit code 0 allows the task to complete normally.
#
# Receives JSON on stdin with task details (task_id, task_subject, teammate_name, team_name).

set -uo pipefail

command -v jq &>/dev/null || exit 0

INPUT=$(cat)
TASK_SUBJECT=$(echo "$INPUT" | jq -r '.task_subject // empty')
TEAMMATE_NAME=$(echo "$INPUT" | jq -r '.teammate_name // empty')
TEAM_NAME=$(echo "$INPUT" | jq -r '.team_name // empty')

LOG_FILE="$HOME/.claude/logs/task-quality-gate.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [quality-gate] $1" >> "$LOG_FILE"
}

# Only run quality gate for team tasks (not standalone tasks)
[ -z "$TEAM_NAME" ] && exit 0

log "Quality gate for task: $TASK_SUBJECT (teammate: $TEAMMATE_NAME, team: $TEAM_NAME)"

# Phase 0 verification gate — forcing function for the 2026-04-17 routines-v1
# incident where Phase 0 was marked complete with zero worktrees. If the
# task subject contains "Phase 0", run verify-team.sh against the team and
# block completion if it fails.
if [[ "$TASK_SUBJECT" == *"Phase 0"* ]]; then
  PROJECT_DIR="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || echo "")"
  VERIFY_SCRIPT="$PROJECT_DIR/scripts/team/verify-team.sh"
  # Fallback to canonical location if we're not in the project root
  [[ -x "$VERIFY_SCRIPT" ]] || VERIFY_SCRIPT="$HOME/Development/reso-management-app/scripts/team/verify-team.sh"
  if [[ -x "$VERIFY_SCRIPT" ]]; then
    log "Phase 0 task detected — running verify-team.sh for $TEAM_NAME"
    VERIFY_OUTPUT=$("$VERIFY_SCRIPT" "$TEAM_NAME" 2>&1 || true)
    VERIFY_EXIT=$?
    if [ "$VERIFY_EXIT" -ne 0 ]; then
      log "PHASE 0 VERIFY FAILED for $TEAM_NAME (exit $VERIFY_EXIT) — blocking task"
      echo "QUALITY GATE FAILED: Phase 0 verification failed for team $TEAM_NAME. Fix worktrees / settings / branches before marking Phase 0 task complete:" >&2
      echo "" >&2
      echo "$VERIFY_OUTPUT" | tail -40 >&2
      exit 2
    fi
    log "Phase 0 verify passed for $TEAM_NAME"
  else
    log "verify-team.sh not found — skipping Phase 0 gate for $TEAM_NAME"
  fi
fi

# Find the teammate's working directory by checking recent worktrees
# Look for worktrees that match the teammate name.
# Test seam: TASK_QUALITY_GATE_WORKTREE_OVERRIDE injects the path directly (the git-worktree-list
# search below is CWD-relative and can't be exercised hermetically). Path-only — it changes WHICH
# directory is gated, never authorization.
WORKTREE_PATH="${TASK_QUALITY_GATE_WORKTREE_OVERRIDE:-}"
if [ -z "$WORKTREE_PATH" ]; then
  while IFS= read -r line; do
    WT_PATH=$(echo "$line" | awk '{print $1}')
    if echo "$WT_PATH" | grep -qi "$TEAMMATE_NAME" 2>/dev/null; then
      WORKTREE_PATH="$WT_PATH"
      break
    fi
  done < <(git worktree list 2>/dev/null)
fi

# Also check /tmp/worktree-* paths
if [ -z "$WORKTREE_PATH" ]; then
  for wt in /tmp/worktree-*; do
    if [ -d "$wt" ] && echo "$wt" | grep -qi "$TEAMMATE_NAME" 2>/dev/null; then
      WORKTREE_PATH="$wt"
      break
    fi
  done
fi

# If we can't find the worktree, allow task completion (don't block on lookup failure)
if [ -z "$WORKTREE_PATH" ] || [ ! -d "$WORKTREE_PATH" ]; then
  log "Could not find worktree for teammate $TEAMMATE_NAME — allowing task completion"
  exit 0
fi

log "Found worktree: $WORKTREE_PATH"

# --- G-P6-10: repo-aware completion gate --------------------------------------------------------
# The TypeScript typecheck below is INERT for claude-infrastructure's OWN work: shell scripts, no
# node_modules, so the check at the tsc path just skips — infra self-work had no completion gate.
# Detect the worktree's repo and, when it is the infra repo (or any node_modules-less shell repo),
# run the shell analog to tsc: shellcheck + `bash -n` on the CHANGED shell files, plus the bats
# tests bound to them. Mirrors scripts/ship-land.sh's gate tooling (shellcheck + bash -n + bats).

is_shell_file() {  # $1=path → 0 if shell (*.sh/*.bash or a shell shebang), else 1
  case "$1" in *.sh|*.bash) return 0 ;; esac
  [ -f "$1" ] || return 1
  local first=""
  IFS= read -r first < "$1" 2>/dev/null || true
  case "$first" in '#!'*sh*) return 0 ;; esac
  return 1
}

infra_repo() {  # 0 if $WORKTREE_PATH is the infra repo (or a node_modules-less shell repo)
  case "${TASK_QUALITY_GATE_FORCE_INFRA:-}" in 1|true|yes) return 0 ;; esac
  local common="" main=""
  common=$(git -C "$WORKTREE_PATH" rev-parse --git-common-dir 2>/dev/null) || common=""
  if [ -n "$common" ]; then
    case "$common" in /*) ;; *) common="$WORKTREE_PATH/$common" ;; esac   # --git-common-dir may be relative
    main=$(cd "$common/.." 2>/dev/null && pwd) || main=""
    case "$main" in */claude-infrastructure) return 0 ;; esac
  fi
  # Fallback: no package.json but a shell surface (tests/*.bats OR hooks/*.sh) present.
  if [ ! -f "$WORKTREE_PATH/package.json" ] && \
     { ls "$WORKTREE_PATH"/tests/*.bats >/dev/null 2>&1 || ls "$WORKTREE_PATH"/hooks/*.sh >/dev/null 2>&1; }; then
    return 0
  fi
  return 1
}

run_infra_gate() {  # runs from $WORKTREE_PATH; exits 0 (pass/skip) or 2 (fail)
  local trunk="${TASK_QUALITY_GATE_TRUNK:-origin/main}"
  cd "$WORKTREE_PATH" || { log "infra gate: cd failed — allowing"; exit 0; }

  # Changed = committed-vs-trunk (when trunk resolves) + staged + unstaged + untracked, deletions
  # EXCLUDED (--diff-filter=d) so a removed .sh is never handed to shellcheck (the ship-land
  # deletion-bug class: backlog b452d75bfd84 / 1bc4a75a4f7f). The `-e` guard below re-checks.
  local list=""; list="$(mktemp "${TMPDIR:-/tmp}/tqg-changed.XXXXXX")"
  {
    if git rev-parse --verify -q "$trunk" >/dev/null 2>&1; then
      git diff --name-only --diff-filter=d "$trunk"...HEAD 2>/dev/null
    fi
    git diff --name-only --diff-filter=d 2>/dev/null
    git diff --name-only --diff-filter=d --cached 2>/dev/null
    git ls-files --others --exclude-standard 2>/dev/null
  } | LC_ALL=C sort -u > "$list"

  local shellfiles=() batsfiles=() p base
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ -e "$p" ] || continue                    # skip deletions / vanished paths (belt-and-suspenders)
    is_shell_file "$p" && shellfiles+=("$p")
    case "$p" in tests/*.bats) batsfiles+=("$p") ;; esac
  done < "$list"
  rm -f "$list"

  # Map each changed script → its sibling bats (tests/<name>.bats), so changing a hook runs its test.
  if [ "${#shellfiles[@]}" -gt 0 ]; then
    for p in "${shellfiles[@]}"; do
      base="$(basename "$p")"; base="${base%.sh}"; base="${base%.bash}"
      [ -f "tests/$base.bats" ] && batsfiles+=("tests/$base.bats")
    done
  fi

  if [ "${#shellfiles[@]}" -eq 0 ] && [ "${#batsfiles[@]}" -eq 0 ]; then
    log "infra gate: no changed shell/bats files — allowing"
    exit 0
  fi

  local rc=0 summary="" out="" bexit=0
  if [ "${#shellfiles[@]}" -gt 0 ]; then
    log "infra gate: shellcheck + bash -n on ${#shellfiles[@]} shell file(s)"
    if ! out="$(shellcheck "${shellfiles[@]}" 2>&1)"; then
      rc=1; summary="${summary}"$'\n'"[shellcheck]"$'\n'"${out}"
    fi
    for p in "${shellfiles[@]}"; do
      if ! out="$(bash -n "$p" 2>&1)"; then
        rc=1; summary="${summary}"$'\n'"[bash -n ${p}]"$'\n'"${out}"
      fi
    done
  fi

  if [ "${#batsfiles[@]}" -gt 0 ]; then
    local uniq="" runbats=()
    uniq="$(printf '%s\n' "${batsfiles[@]}" | LC_ALL=C sort -u)"
    while IFS= read -r p; do [ -n "$p" ] && [ -f "$p" ] && runbats+=("$p"); done <<< "$uniq"
    if [ "${#runbats[@]}" -gt 0 ]; then
      log "infra gate: bats on ${#runbats[@]} test file(s)"
      if command -v timeout >/dev/null 2>&1; then
        out="$(timeout 120 bats "${runbats[@]}" 2>&1)"; bexit=$?
      else
        out="$(bats "${runbats[@]}" 2>&1)"; bexit=$?
      fi
      if [ "$bexit" -eq 124 ]; then
        log "infra gate: bats timed out (120s) — not blocking on timeout (mirrors the tsc timeout policy)"
      elif [ "$bexit" -ne 0 ]; then
        rc=1; summary="${summary}"$'\n'"[bats]"$'\n'"$(printf '%s' "$out" | tail -30)"
      fi
    fi
  fi

  if [ "$rc" -ne 0 ]; then
    log "INFRA GATE FAILED in $WORKTREE_PATH"
    {
      echo "QUALITY GATE FAILED: infra checks failed in $WORKTREE_PATH (shellcheck / bash -n / bats). Fix before marking the task complete:"
      printf '%s\n' "$summary" | tail -60
    } >&2
    exit 2
  fi
  log "INFRA GATE PASSED in $WORKTREE_PATH"
  exit 0
}

if infra_repo; then
  run_infra_gate                               # exits 0 (pass/skip) or 2 (fail) — never falls through
fi
# Not infra → fall through to the TypeScript typecheck path (reso-management-app).

# Run typecheck in the worktree
TYPECHECK_OUTPUT=""
TYPECHECK_EXIT=0
cd "$WORKTREE_PATH" || exit 0

# Check if pnpm/node_modules exist (worktree may not have dependencies)
if [ ! -d "node_modules" ] && [ ! -L "node_modules" ]; then
  log "No node_modules in worktree — skipping typecheck"
  exit 0
fi

# Run typecheck with a timeout (60 seconds)
TYPECHECK_OUTPUT=$(timeout 60 npx tsc --noEmit 2>&1) || TYPECHECK_EXIT=$?

if [ "$TYPECHECK_EXIT" -ne 0 ] && [ "$TYPECHECK_EXIT" -ne 124 ]; then
  # Typecheck failed — extract first 20 error lines
  ERROR_SUMMARY=$(echo "$TYPECHECK_OUTPUT" | grep "error TS" | head -20)
  ERROR_COUNT=$(echo "$TYPECHECK_OUTPUT" | grep -c "error TS" || echo "0")

  log "TYPECHECK FAILED ($ERROR_COUNT errors) in $WORKTREE_PATH"

  # Exit code 2 rejects the task completion
  echo "QUALITY GATE FAILED: TypeScript typecheck found $ERROR_COUNT error(s) in $WORKTREE_PATH. Fix these before marking the task complete:" >&2
  echo "" >&2
  echo "$ERROR_SUMMARY" >&2
  exit 2
fi

if [ "$TYPECHECK_EXIT" -eq 124 ]; then
  log "Typecheck timed out (60s) — allowing task completion"
  exit 0
fi

log "TYPECHECK PASSED in $WORKTREE_PATH"
exit 0
