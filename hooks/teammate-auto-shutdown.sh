#!/bin/bash
# TeammateIdle hook — graceful auto-shutdown with work preservation.
# Fires (LEAD-side) when a teammate goes idle after finishing its turn.
#
# Design — checkpoint-first, defer-until-quiesced, then close the EXACT pane:
#   1. CHECKPOINT FIRST via teammate-checkpoint.sh (synthetic TeammateIdle
#      payload). Preserves tracked + untracked work to refs/checkpoints/<m>/<ts>
#      and refs/wip/<m>/LAST. Uses git plumbing — bypasses pre-commit hooks.
#   2. FALLBACK to /tmp/<team>-<member>-<ts>.patch if the checkpoint fails
#      for any reason (corrupt repo, permission issue). Hook still exits 0.
#   3. DEFER on dirty tree — if git status shows uncommitted work, skip the
#      reap this cycle. TeammateIdle fires 3-4× per teammate; we wait until
#      the teammate actually quiesces (this IS the final-idle gate). Max
#      defers: 3 (backstop). After that, reap but checkpoint first.
#   4. COOPERATIVE MARKER — if <worktree>/.teammate-busy exists, defer
#      unconditionally. Teammate writes it before multi-turn work.
#   5. CLOSE THE EXACT PANE, then remove the worktree. The pane id is read
#      from the team config.json member field `tmuxPaneId` (an iTerm2 session
#      UUID under the it2 backend, or a tmux %N id), looked up across ALL
#      team roots — CC writes $CLAUDE_CONFIG_DIR/teams/<team>/, so a team led
#      from a *2 launcher (claude-next2 / claude-fable2 → ~/.claude-secondary)
#      lives ONLY under ~/.claude-secondary/teams (memory:
#      teammate-shutdown-secondary-config-dir-2026-06-09) — and closed with
#      `it2 session close -f -s <id>` — which the ~/.claude/bin/it2 shim
#      reroutes to a python iterm2 close with force=True (it2 0.2.3 never
#      propagates -f to the API, and iTerm2's non-forced close prompts on
#      running-job panes REGARDLESS of the never-prompt profile; memory:
#      it2-session-close-force-modal-2026-06-09) — or `tmux kill-pane -t <id>`.
#
# WHY NOT `kill -TERM $PPID` (the retired mechanism): a TeammateIdle hook runs
# on the LEAD as  lead-claude → /bin/sh -c → bash, so $PPID is the /bin/sh shim,
# already dead by the time the backgrounded kill fired — the signal then hit a
# PID-RECYCLED process (intermittently the lead or an unrelated shell). That is
# exactly the observed "closes too early / inconsistent" regression. Targeting
# the recorded pane id is deterministic and hits only the teammate's pane.
#
# Uses JSON {"continue": false} with exit 0 to stop the teammate's turn.
#
# Kill switch: export TEAMMATE_SHUTDOWN_DISABLED=1
# Tuning:      export TEAMMATE_MAX_DEFERS=<N>   (default 3)

set -uo pipefail

if [[ "${TEAMMATE_SHUTDOWN_DISABLED:-0}" == "1" ]]; then
  exit 0
fi

readonly MAX_DEFERS="${TEAMMATE_MAX_DEFERS:-3}"
readonly HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_DIR="$HOME/.claude/logs"
readonly WATCHDOG_DIR="$HOME/.claude/watchdog"

# Team-state roots. CC writes $CLAUDE_CONFIG_DIR/teams/<team>/ — the *2 launchers
# (claude-next2 / claude-fable2 / cc-next2) run on ~/.claude-secondary, whose
# teams/ is a REAL isolated dir; ~/.claude-next/teams is a symlink into
# ~/.claude/teams, so these two roots cover every launcher (same pair as
# verify-team.sh). Order is a tie-break only — pane resolution prefers whichever
# root recorded a non-empty tmuxPaneId for this member.
readonly TEAM_ROOTS=("$HOME/.claude-secondary/teams" "$HOME/.claude/teams")

mkdir -p "$LOG_DIR" "$WATCHDOG_DIR" 2>/dev/null || true
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_DIR/teammate-lifecycle.log" 2>/dev/null || true
}

# --- Pane-close primitives ------------------------------------------------------
# Resolve the it2 CLI. Calling the SHIM (~/.claude/bin/it2, first in PATH) here
# is REQUIRED, not incidental: it rewrites `session split` (injects the
# Claude-Teammate no-prompt profile) AND `session close -f -s <id>` (reroutes
# to a python iterm2 force=True close). The real CLI's `close -f` does NOT
# propagate force to the API and pops iTerm2's running-job confirmation modal
# on every live teammate pane (memory: it2-session-close-force-modal-2026-06-09).
_it2_bin() { command -v it2 2>/dev/null || echo "$HOME/.claude/bin/it2"; }

# Close one teammate pane by its recorded id. Idempotent: closing an
# already-gone pane fails with "not found" (the caller logs it as such).
# iTerm2 session UUIDs are never recycled, so a stale id can only no-op — it
# can never hit the wrong pane. Stderr is captured into CLOSE_ERR so the
# caller can tell "already gone" from a real failure (RPC error, timeout).
CLOSE_ERR=""
close_pane() {
  local pane="$1"
  [[ -n "$pane" ]] || return 1
  if [[ "$pane" =~ ^%[0-9]+$ ]]; then
    CLOSE_ERR=$(tmux kill-pane -t "$pane" 2>&1 >/dev/null)   # tmux backend: synchronous, no prompt
  else
    CLOSE_ERR=$("$(_it2_bin)" session close -f -s "$pane" 2>&1 >/dev/null)  # shim → python force=True
  fi
}

INPUT=$(cat)
TEAMMATE_NAME=$(echo "$INPUT" | jq -r '.teammate_name // "unknown"' 2>/dev/null)
TEAM_NAME=$(echo "$INPUT" | jq -r '.team_name // "unknown"' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)

# Resolve the worktree. Conventions + edge cases:
#   /tmp/wt-<team>-<member>        newer
#   /tmp/worktree-<team>-<member>  legacy
#   /tmp/worktree-<member>         single-segment
# AND: the team slug in the worktree path may differ from team_name (e.g.,
# plan branches named 'feat/ui-sh-v2' while team_name is 'ui-sh-100p-v2'),
# AND: the member name may be auto-incremented (quality-keeper → quality-keeper-2).
#
# Strategy: try exact matches first, then fall back to a glob-based search.
WORKTREE=""

# Build candidate member names: full, and with trailing "-N" stripped.
MEMBER_CANDIDATES=("$TEAMMATE_NAME")
if [[ "$TEAMMATE_NAME" =~ ^(.+)-[0-9]+$ ]]; then
  MEMBER_CANDIDATES+=("${BASH_REMATCH[1]}")
fi

# (#16) Resolve member→worktree from the team MANIFEST first — the legacy
# /tmp globs below cannot match branch-named worktrees like
# ~/Development/.worktrees/wt-journal-gate, so a Track-R teammate would be
# reaped with WORKTREE="" → no checkpoint → lost work (re-gate N1).
PAYLOAD_CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo '')
PAYLOAD_CWD="${PAYLOAD_CWD#/private}"

# Primary: the team manifest, located via the SHARED git-common-dir (resolves
# to the same main repo root from a teammate worktree OR the lead root — the
# untracked .claude/team-briefs/ lives only in that root).
resolve_from_manifest() {
  local seed="$1" common root manifest count i name wt m
  [[ -n "$seed" && -e "$seed" ]] || return 1
  command -v yq >/dev/null 2>&1 || return 1
  common=$(git -C "$seed" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  root="${common%/.git}"
  manifest="$root/.claude/team-briefs/$TEAM_NAME/manifest.yaml"
  [[ -f "$manifest" ]] || return 1
  count=$(yq eval '.members | length' "$manifest" 2>/dev/null) || return 1
  [[ "$count" =~ ^[0-9]+$ ]] || return 1
  for (( i=0; i<count; i++ )); do
    name=$(yq eval ".members[$i].name" "$manifest" 2>/dev/null)
    for m in "${MEMBER_CANDIDATES[@]}"; do
      if [[ "$name" == "$m" ]]; then
        wt=$(yq eval ".members[$i].worktree" "$manifest" 2>/dev/null)
        wt="${wt/#\~/$HOME}"
        if [[ -n "$wt" && -d "$wt" ]]; then printf '%s\n' "$wt"; return 0; fi
      fi
    done
  done
  return 1
}
if MANIFEST_WT=$(resolve_from_manifest "$PAYLOAD_CWD"); then
  WORKTREE="$MANIFEST_WT"
fi

# Fallback: a global TSV (<member>\t<worktree>) persisted by create-team.sh —
# keyed only by team, so it needs no project path from the payload. Scan every
# team root: create-team.sh writes under ~/.claude/teams, but a secondary-led
# team's state may exist only under ~/.claude-secondary/teams.
if [[ -z "$WORKTREE" ]]; then
  for _root in "${TEAM_ROOTS[@]}"; do
    TSV="$_root/$TEAM_NAME/worktrees.tsv"
    [[ -f "$TSV" ]] || continue
    for m in "${MEMBER_CANDIDATES[@]}"; do
      cand=$(awk -F'\t' -v want="$m" '$1==want{print $2; exit}' "$TSV" 2>/dev/null || echo '')
      cand="${cand/#\~/$HOME}"
      if [[ -n "$cand" && -d "$cand" ]]; then WORKTREE="$cand"; break 2; fi
    done
  done
fi

# Legacy /tmp exact-match attempt (only if manifest/TSV didn't resolve)
if [[ -z "$WORKTREE" ]]; then
  for m in "${MEMBER_CANDIDATES[@]}"; do
    for candidate in \
      "/tmp/wt-${TEAM_NAME}-${m}" \
      "/tmp/worktree-${TEAM_NAME}-${m}" \
      "/tmp/worktree-${m}"; do
      if [[ -d "$candidate" ]]; then
        WORKTREE="$candidate"
        break 2
      fi
    done
  done
fi

# Glob fallback: match any /tmp/wt-*-<member> or /tmp/worktree-*-<member>.
# This catches the case where the team slug in the path != team_name
# (e.g., /tmp/wt-ui-sh-v2-quality-keeper vs team_name=ui-sh-100p-v2).
if [[ -z "$WORKTREE" ]]; then
  shopt -s nullglob
  for m in "${MEMBER_CANDIDATES[@]}"; do
    for candidate in /tmp/wt-*-"${m}" /tmp/worktree-*-"${m}"; do
      if [[ -d "$candidate" ]]; then
        WORKTREE="$candidate"
        break 2
      fi
    done
  done
  shopt -u nullglob
fi

# Rule 4 — cooperative busy marker
if [[ -n "$WORKTREE" && -f "$WORKTREE/.teammate-busy" ]]; then
  log "defer $TEAMMATE_NAME (team=$TEAM_NAME): .teammate-busy marker present"
  # Do NOT emit {"continue": false}; let the teammate keep working.
  exit 0
fi

# Rule 3 — defer on dirty tree, bounded by MAX_DEFERS
DEFER_COUNTER="$WATCHDOG_DIR/defer-$SESSION_ID-$TEAMMATE_NAME.count"
DEFER_COUNT=0
[[ -f "$DEFER_COUNTER" ]] && DEFER_COUNT=$(cat "$DEFER_COUNTER" 2>/dev/null || echo 0)

TREE_DIRTY=false
if [[ -n "$WORKTREE" ]]; then
  if git -C "$WORKTREE" status --porcelain 2>/dev/null | grep -q .; then
    TREE_DIRTY=true
  fi
fi

if $TREE_DIRTY && (( DEFER_COUNT < MAX_DEFERS )); then
  DEFER_COUNT=$((DEFER_COUNT + 1))
  echo "$DEFER_COUNT" > "$DEFER_COUNTER"
  log "defer $TEAMMATE_NAME ($DEFER_COUNT/$MAX_DEFERS): dirty tree"
  # Snapshot what's there so we don't lose work if they never quiesce.
  "$HOOK_DIR/teammate-checkpoint.sh" <<<"{\"hook_event_name\":\"TeammateIdle\",\"session_id\":\"$SESSION_ID\",\"cwd\":\"$WORKTREE\",\"team_name\":\"$TEAM_NAME\",\"teammate_name\":\"$TEAMMATE_NAME\"}" \
    2>/dev/null || true
  # Do NOT emit {"continue": false}; let the teammate keep working.
  exit 0
fi

# Clear defer counter — we're proceeding to reap
rm -f "$DEFER_COUNTER" 2>/dev/null || true

log "Auto-shutdown idle teammate: $TEAMMATE_NAME (team: $TEAM_NAME)"

# Rule 1 + 2 — CHECKPOINT FIRST, then fallback patch if checkpoint failed.
# This must happen BEFORE git worktree remove.
CHECKPOINT_OK=false
if [[ -n "$WORKTREE" ]]; then
  if "$HOOK_DIR/teammate-checkpoint.sh" <<<"{\"hook_event_name\":\"TeammateIdle\",\"session_id\":\"$SESSION_ID\",\"cwd\":\"$WORKTREE\",\"team_name\":\"$TEAM_NAME\",\"teammate_name\":\"$TEAMMATE_NAME\"}" 2>/dev/null; then
    CHECKPOINT_OK=true
    log "  ✓ final checkpoint written for $WORKTREE"
  else
    log "  ✗ checkpoint failed for $WORKTREE — writing fallback patch"
  fi

  # Regardless of checkpoint success, also emit a patch if tree is dirty
  # (belt-and-suspenders — the teammate always has a recoverable trace)
  if git -C "$WORKTREE" status --porcelain 2>/dev/null | grep -q .; then
    PATCH="/tmp/${TEAM_NAME}-${TEAMMATE_NAME}-$(date -u +%Y%m%dT%H%M%SZ).patch"
    {
      echo "# Auto-patch from teammate-auto-shutdown.sh"
      echo "# Team: $TEAM_NAME  Member: $TEAMMATE_NAME"
      echo "# Worktree: $WORKTREE"
      echo "# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "# Checkpoint status: $($CHECKPOINT_OK && echo 'written' || echo 'failed — rely on this patch')"
      echo "# --- status ---"
      git -C "$WORKTREE" status --porcelain 2>/dev/null || true
      echo "# --- diff HEAD (tracked changes only) ---"
      git -C "$WORKTREE" diff HEAD 2>/dev/null || true
    } > "$PATCH" 2>/dev/null
    log "  ✓ fallback patch: $PATCH"
  fi
fi

# Rule 5 — close the teammate's pane, then remove its worktree.
# Resolve the pane id + canonical member name from the team config.json across
# TEAM_ROOTS — a secondary-led team's config lives ONLY under
# ~/.claude-secondary/teams (the tier0 lingering-pane bug, 2026-06-09). The
# member name may be auto-incremented, so match against MEMBER_CANDIDATES.
# Prefer the root whose config recorded a non-empty tmuxPaneId: a stale
# same-named team dir in the other root must never shadow the live one.
PANEID=""
MEMBER_NAME="$TEAMMATE_NAME"
for _root in "${TEAM_ROOTS[@]}"; do
  CONFIG="$_root/$TEAM_NAME/config.json"
  [[ -f "$CONFIG" ]] || continue
  RESOLVED=$(jq -r --args \
    '.members[]? | select(.name as $n | $ARGS.positional | index($n)) | "\(.name)\t\(.tmuxPaneId // "")"' \
    "${MEMBER_CANDIDATES[@]}" < "$CONFIG" 2>/dev/null | head -1)
  if [[ -n "$RESOLVED" && "$RESOLVED" == *$'\t'* ]]; then
    MEMBER_NAME="${RESOLVED%%$'\t'*}"
    PANEID="${RESOLVED#*$'\t'}"
    [[ -z "$MEMBER_NAME" ]] && MEMBER_NAME="$TEAMMATE_NAME"
    [[ -n "$PANEID" ]] && break
  fi
done

# Forensic confirmation of the retired `kill -TERM $PPID` bug (logs only; no kill
# fires). On the next real team run, grep teammate-lifecycle.log for "PPID-forensic"
# to confirm $PPID was the dead/recycled /bin/sh shim, never the teammate pane.
log "  PPID-forensic: \$PPID=$PPID cmd=[$(ps -p "$PPID" -o command= 2>/dev/null | tr -d '\n' || echo 'dead/recycled')] pane=[$PANEID] member=$MEMBER_NAME"

# Stop the teammate's current turn — JSON on stdout with exit 0.
echo '{"continue": false, "stopReason": "Idle teammate auto-shutdown (work preserved in refs/wip/LAST + /tmp/*.patch; pane closed via it2/tmux)"}'

# Detached close so the hook itself returns within its 5s timeout. Ordering:
#   brief grace for CC to flush the {"continue":false} response → close the EXACT
#   pane → remove the worktree. Work is already checkpointed above, so removing
#   the worktree here cannot lose work.
(
  sleep 3
  if [[ -n "$PANEID" ]]; then
    close_pane "$PANEID"
    CP_RC=$?
    CP_ERR="${CLOSE_ERR//$'\n'/ ; }"
    if (( CP_RC == 0 )); then
      log "  ✓ closed pane $PANEID ($MEMBER_NAME)"
    elif [[ "$CP_ERR" == *"not found"* || "$CP_ERR" == *"find pane"* ]]; then
      log "  ~ pane $PANEID ($MEMBER_NAME) already gone (${CP_ERR:-not found})"
    else
      log "  ✗ pane close FAILED (rc=$CP_RC) for $PANEID ($MEMBER_NAME): ${CP_ERR:-<no stderr>}"
    fi
  else
    log "  ! no pane id resolved for $MEMBER_NAME — left for CC session-end cleanup"
  fi
  if [[ -n "$WORKTREE" ]]; then
    MAIN_REPO=$(git -C "$WORKTREE" rev-parse --git-common-dir 2>/dev/null | sed 's|/\.git$||')
    if [[ -n "$MAIN_REPO" && -d "$MAIN_REPO" ]]; then
      git -C "$MAIN_REPO" worktree remove "$WORKTREE" --force 2>/dev/null \
        && log "  ✓ worktree removed: $WORKTREE"
    fi
  fi
) >/dev/null 2>&1 &

exit 0
