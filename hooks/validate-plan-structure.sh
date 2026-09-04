#!/bin/bash
# PostToolUse hook — plan-structure lint for plan files. Two concerns:
#
#   1. STATUS SCHEMA (blocking, G-P14-6). Every hand-authored plan MUST carry a
#      YAML frontmatter `status:` key, one of:
#         status: open | in-progress | complete | superseded
#      A NEW authored plan (untracked in git, else mtime-fresh) LACKING a valid
#      status FAILS the hook (exit 2). Pre-existing plans only WARN (never
#      retro-break the corpus). The ExitPlanMode global sink (~/.claude/plans) is
#      machine-authored and never gated. A truthful status is what lets
#      find-plan.sh --list-open classify open vs. done work.
#
#   2. PHASE 0 / AGENT TEAMS (non-blocking warn). Agent Teams are the DEFAULT for
#      implementation work; warn if an impl plan omits Phase 0 orchestration.
#
# Env overrides (tests): CC_PLANS_DIR, CC_PLAN_NEW_AGE_S.

set -uo pipefail

command -v jq &>/dev/null || exit 0

PLANS_DIR="${CC_PLANS_DIR:-$HOME/.claude/plans}"

# has_valid_status <file> → 0 if frontmatter carries status: <one of the 4 values>.
#
# THE GREP DRAINS (`grep -iE … >/dev/null`, not `grep -qiE …`) and that is load-bearing, not style.
# This pipeline is the FINAL command of the function, so its status IS what `! has_valid_status` at
# the bottom of this file reads — the ec9a43a9 scar moved one frame up. `-q` exits on the match, sed
# takes SIGPIPE on its next write, and `set -o pipefail` (line 20) promotes that 141: the hook would
# then REFUSE a plan whose status line is plainly present. Latent today only because a frontmatter
# block fits the 64 KiB pipe buffer, and nothing announces that crossing.
# (scripts/pipefail-sigpipe-lint.sh, THIRTEENTH CORRECTION — this is the one site it revealed.)
#
# `done` is an ACCEPTED ALIAS, deliberately not an ADVERTISED one — the two messages below still
# name only the canonical four, exactly as `completed` and `in_progress` are accepted here and never
# recommended. Accepting it WITHOUT teaching find-plan.sh's plan_status() the same word would be the
# worst of both: this gate waves the plan through while the enumerator still reads `unknown`, which
# is precisely how STOP_CHAIN_WAVE2.md declared itself finished and re-dispatched anyway. The three
# copies (here, find-plan.sh, setup-plan-symlinks.sh's one-pass awk) move together or not at all.
has_valid_status() {
  local f="$1"
  head -1 "$f" 2>/dev/null | grep -qx -- '---' || return 1
  sed -n '2,/^---$/p' "$f" 2>/dev/null \
    | grep -iE '^status:[[:space:]]*(open|in-progress|in_progress|complete|completed|done|superseded)([[:space:]]|$)' >/dev/null
}

# is_new_plan <file> → 0 if the file is NEW (git-untracked, else mtime-fresh).
# Pre-existing (git-tracked, or old on disk) ⇒ returns 1 (warn-only, never block).
is_new_plan() {
  local f="$1" dir; dir=$(dirname "$f")
  if git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$dir" ls-files --error-unmatch "$f" >/dev/null 2>&1 && return 1  # tracked
    return 0                                                                  # untracked
  fi
  local now mt age
  now=$(date +%s); mt=$(stat -f %m "$f" 2>/dev/null || echo 0)
  age=$(( now - mt ))
  [ "$age" -lt "${CC_PLAN_NEW_AGE_S:-300}" ]
}

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_result.filePath // empty')

[ -z "$FILE" ] && exit 0
[ ! -f "$FILE" ] && exit 0

# === PLAN FILE DETECTION (must match backup-before-write.sh exactly) ===
# IS_AUTHORED = hand-authored namespace (status-gated). The global sink is a plan
# but machine-authored (ExitPlanMode) → IS_PLAN only, never status-gated.
IS_PLAN=false; IS_AUTHORED=false
case "$FILE" in
  "$PLANS_DIR"/*.md)                             IS_PLAN=true ;;
  *"/.claude-plans/"*.md)                        IS_PLAN=true; IS_AUTHORED=true ;;
  *"/docs/plans/"*.md)                           IS_PLAN=true; IS_AUTHORED=true ;;
  docs/plans/*.md)                               IS_PLAN=true; IS_AUTHORED=true ;;
  *"/AGENT_TEAM_IMPLEMENTATION_PLAN"*.md)        IS_PLAN=true; IS_AUTHORED=true ;;
esac

[ "$IS_PLAN" = false ] && exit 0

# === STATUS SCHEMA GATE (blocking for NEW authored plans; else warn) ===
if [ "$IS_AUTHORED" = true ] && ! has_valid_status "$FILE"; then
  BN=$(basename "$FILE")
  if is_new_plan "$FILE"; then
    echo "❌ PLAN STATUS REQUIRED [${BN}]: new plan is missing a valid 'status:' frontmatter key. Add YAML frontmatter at the top: status: open|in-progress|complete|superseded (use 'open' for active work). This keeps the mission-ledger enumerator (find-plan.sh --list-open) truthful — G-P14-6." >&2
    exit 2
  fi
  # Pre-existing plan: warn only (never retro-break the corpus).
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "⚠️ PLAN STATUS [${BN}]: no valid 'status:' frontmatter (open|in-progress|complete|superseded). Pre-existing plan — not blocked; add a status: line so find-plan.sh --list-open can classify it (open vs. done)."
  }
}
EOF
  exit 0
fi

# === PHASE 0 CHECK ===
# Warn if file has 2+ sections (any structured plan with multiple tasks)
SECTION_COUNT=$(grep -c "^## \|^### " "$FILE" 2>/dev/null || echo "0")
[ "$SECTION_COUNT" -lt 2 ] && exit 0

# Check if this looks like an implementation plan (has phases, tasks, or implementation keywords)
IS_IMPL=false
if grep -qEi "Phase [1-9]|Implementation|Wave [1-9]|Task [1-9]|Sprint|Milestone" "$FILE" 2>/dev/null; then
  IS_IMPL=true
fi

HAS_PHASE0=false
grep -qEi "Phase 0|Agent Team Orchestration|Team Orchestration|Pre-Flight Checklist|Team Roster" \
  "$FILE" 2>/dev/null && HAS_PHASE0=true

# EXECUTION LOCUS (added 2026-08-07). Phase 0 answered "who does the work" but never
# "WHERE does it run", so its only delegation unit — in-session teammates — routes every
# teammate's output back into the LEAD's context. A plan can obey the Agent-Teams rule
# perfectly and still burn the lead's window on implementation detail. The locus line is
# what makes a dispatched handoff session (locus S) the declared default. SSOT for the
# rule + rationale: skills/plan-conventions/SKILL.md § Execution locus.
HAS_LOCUS=false
grep -qEi "Execution Locus|locus S|dispatched session|handoff-fire|lead-inline" \
  "$FILE" 2>/dev/null && HAS_LOCUS=true

BASENAME=$(basename "$FILE")

if [ "$IS_IMPL" = true ] && [ "$HAS_PHASE0" = false ]; then
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "⚠️ AGENT TEAMS REQUIRED [${BASENAME}]: This implementation plan has NO Phase 0 / Agent Team Orchestration. Per CLAUDE.md: Agent Teams are the DEFAULT for all implementation work (9/10 sessions). Add Phase 0 as the FIRST section with: EXECUTION LOCUS PER WAVE (S = dispatched handoff session — the DEFAULT; T = in-session teammates; L = lead-inline — T and L each need one line of justification), team roster, task dependency graph, worktree assignments, spawn wave order, and the LEAD's context budget + succession point. Only omit for purely research/exploration plans with no code changes. Use the plan-update skill 'Phase 0' template."
  }
}
EOF
elif [ "$IS_IMPL" = true ] && [ "$HAS_LOCUS" = false ]; then
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "⚠️ EXECUTION LOCUS MISSING [${BASENAME}]: Phase 0 is present but no wave declares WHERE it runs, so every wave defaults to the lead's own context — the one resource a long-horizon plan cannot refill. Add an Execution Locus row per wave: S = dispatched session (\`handoff-fire.sh --prompt-file <brief> --worktree <br> --notify-back <lead-uuid> --goal '<measurable end state> — proven by <the command the session runs and prints>; do not <constraint>'\`, the DEFAULT, needs no justification — --goal is the default on every wave fire, since the goal evaluator is tool-less and judges only what the session PRINTS) | T = in-session teammates (their output lands in the LEAD's window — justify in one line) | L = lead-inline (justify in one line). Also state the lead's context budget + succession point. Rule: skills/plan-conventions/SKILL.md § Execution locus."
  }
}
EOF
fi

exit 0
