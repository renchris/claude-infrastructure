#!/bin/bash
# TaskCompleted hook — quality gate that runs typecheck in the teammate's worktree.
# Exit code 2 rejects the task and sends build errors back to the teammate.
# Exit code 0 allows the task to complete normally.
#
# Receives JSON on stdin with task details (task_id, task_subject, teammate_name, team_name).

set -uo pipefail

# PATH hardening — scripts/unattended-path-lint.sh governs this line.
# A hook inherits the PATH of the Claude Code process that fired it, and that PATH is a function of
# how the SESSION was started — not of anything this file or settings.json declares (settings.json
# sets no PATH at all). An operator-launched session carries Homebrew; a spawned one may not. This
# gate calls shellcheck, bats and npx by bare name and never checks for 127, so on a session without
# Homebrew each returns "command not found", rc=1, and the gate REJECTS the task with a bogus body —
# a blocking hook failing loudly for a reason that has nothing to do with the code it is judging.
#
# APPEND, never prepend: a session that already reaches these tools keeps its own resolution order
# untouched, so this can only ever ADD reach. ~/.claude/bin leads the appended segment so `bats`
# still lands on the cc-bats QoS chokepoint rather than the raw Homebrew binary behind it.
PATH="$PATH:$HOME/.claude/bin:/opt/homebrew/bin:/usr/local/bin"
export PATH

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
    # `VERIFY_OUTPUT=$(cmd || true); VERIFY_EXIT=$?` CANNOT FAIL: `|| true` makes the
    # assignment itself succeed, so $? was always 0 and the rejection branch below was
    # unreachable — a verify-team.sh exiting non-zero over missing worktrees logged
    # "verify passed" and let the Phase 0 task complete. The if-form keeps the command's
    # own status while still not tripping errexit.
    if VERIFY_OUTPUT=$("$VERIFY_SCRIPT" "$TEAM_NAME" 2>&1); then
      VERIFY_EXIT=0
    else
      VERIFY_EXIT=$?
    fi
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

  # .bats shellcheck — the same coverage hole as ship-land's gate, and the same fix. is_shell_file()
  # above cannot match `#!/usr/bin/env bats`, so the shellcheck pass has never seen a test file here
  # either. bats files deliberately do NOT join $shellfiles: `bash -n` fails on all 189 of them, and
  # this function hands every shellfile to both tools. Own-scope is LINE-scoped and derived from the
  # trunk range, so only lines this work actually wrote can block; pre-existing findings stay
  # advisory (143 of 189 suites carry one). No range ⇒ empty own-set ⇒ nothing blocks, never a
  # whole-tree strict run.
  if [ "${#batsfiles[@]}" -gt 0 ] && command -v shellcheck >/dev/null 2>&1; then
    # cwd is $WORKTREE_PATH (cd'd at the top of this function), so the tree being gated is judged by
    # its OWN lint — same reasoning as ship-land resolving its ratchets repo-root-relative.
    local scl="scripts/bats-shellcheck-lint.sh" bown="" scout=""
    if [ -x "$scl" ]; then
      if git rev-parse --verify -q "$trunk" >/dev/null 2>&1; then
        bown="$("$scl" --own-lines "$trunk...HEAD" 2>/dev/null || true)"
      fi
      if ! scout="$(CC_BATS_SC_OWN="$bown" "$scl" tests 2>&1)"; then
        rc=1; summary="${summary}"$'\n'"[bats-shellcheck]"$'\n'"${scout}"
      fi
    fi
  fi

  # unguarded-kill ratchet — the same class ship-land's gate now blocks, at the earlier chokepoint,
  # so an author learns it here rather than at the land. A kill whose stderr is silenced but whose
  # exit status is not: once the child is REAPED it returns 1 and bats' errexit aborts the body, so a
  # test that passed on its own merits goes red under load. Strict and whole-corpus (the baseline is
  # zero), so no own-set is derived here — unlike the shellcheck block above, this one has nothing to
  # grandfather. Unconditional on batsfiles: the class can be introduced by any land, and the scan is
  # ~0.2s over the whole corpus.
  if [ -x "scripts/bats-kill-guard-lint.sh" ]; then
    local kgout=""
    if ! kgout="$(scripts/bats-kill-guard-lint.sh tests 2>&1)"; then
      rc=1; summary="${summary}"$'\n'"[bats-kill-guard]"$'\n'"${kgout}"
    fi
  fi

  if [ "${#batsfiles[@]}" -gt 0 ]; then
    local uniq="" runbats=()
    uniq="$(printf '%s\n' "${batsfiles[@]}" | LC_ALL=C sort -u)"
    while IFS= read -r p; do [ -n "$p" ] && [ -f "$p" ] && runbats+=("$p"); done <<< "$uniq"
    if [ "${#runbats[@]}" -gt 0 ]; then
      log "infra gate: bats on ${#runbats[@]} test file(s)"
      # `</dev/null` — DEFENCE IN DEPTH HERE, NOT A HANG FIX, and the difference was MEASURED rather
      # than assumed (2026-08-06). The class is real: bats INHERITS stdin into every test, so a suite
      # stubbing a stdin-consuming binary with an unconditional `cat` waits forever for an EOF that
      # never comes (5e460544; ce13bd08 fixed the landing runners). But THIS caller is the one
      # exception in that sweep, because `INPUT=$(cat)` at the top of the file already consumes fd 0
      # to EOF. Both branches measured:
      #   · writer closes (how the harness invokes a hook) → the drain returns and fd 0 stays at EOF,
      #     so a second reader gets rc 0 immediately. bats would inherit a benign already-EOF fd.
      #   · writer never closes → the hook wedges at `INPUT=$(cat)` on line 12 and NEVER REACHES HERE
      #     (whole-hook rc 124). The hang exists, but it is upstream of bats; a redirect at this site
      #     could not have prevented it, and moving fd 0 here cannot disturb line 12 either.
      # It is still worth the token: it makes the property UNCONDITIONAL instead of contingent on a
      # drain thirty lines away that a refactor may move or make conditional, and it closes the one
      # shape the drain does not — a TTY stdin, which EOFs on Ctrl-D and then happily yields more,
      # so a stub `cat` blocks on the terminal. Recorded explicitly so the next reader does not
      # "harden" the wrong line: if this hook ever hangs on stdin, look at line 12, not at bats.
      if command -v timeout >/dev/null 2>&1; then
        out="$(timeout 120 bats "${runbats[@]}" </dev/null 2>&1)"; bexit=$?
      else
        out="$(bats "${runbats[@]}" </dev/null 2>&1)"; bexit=$?
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
