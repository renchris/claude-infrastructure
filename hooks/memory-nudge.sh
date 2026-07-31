#!/bin/bash
# UserPromptSubmit Hook — Memory Crystallization Nudge
#
# Periodic in-session reminder (every MEMORY_NUDGE_INTERVAL prompts, default 12)
# to persist DURABLE knowledge to MEMORY.md / a topic file, with the hermes-agent
# anti-capture list embedded. Fires while context is LIVE — UserPromptSubmit is
# the only event whose additionalContext reaches the model mid-session (Stop
# cannot inject; GH anthropics/claude-code#37559).
#
# Adapted from hermes-agent agent/background_review.py (nudge_interval=10), minus
# the autonomous write: this NUDGES, the model decides + the human reviews.
#
# APPEND-TIME BUDGET (2026-07-31). The index is loaded with a hard read limit
# (24.4 KiB = 24985 B); past it the loader SILENTLY DROPS THE TAIL — the NEWEST
# entries, i.e. a rule written today may never load again, and no reader can tell.
# Three manual compaction passes each re-inflated within days because nothing
# measured the budget at the moment of APPEND; the "<=200-char" line in the nudge
# below was prose with no measurement behind it (hooks measured 203 B avg on
# 2026-07-31 — the advisory was simply ignored). So this hook now MEASURES the
# live index every time it speaks and hands the model a byte budget it can act on,
# plus the cardinality ceiling that a byte budget alone cannot express.
# Every figure is computed at runtime: a hardcoded one decays against its subject.
set -euo pipefail

INTERVAL="${MEMORY_NUDGE_INTERVAL:-12}"
[ "$INTERVAL" -gt 0 ] 2>/dev/null || exit 0

INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
[ -z "$SID" ] && exit 0
# Defensive: session_id is a harness UUID; refuse anything with path/shell chars
case "$SID" in *[!a-zA-Z0-9_-]*) exit 0 ;; esac

# Counter lives under the config dir actually in play — a hardcoded ~/.claude
# splits the count from the session when CLAUDE_CONFIG_DIR points elsewhere.
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STATE_DIR="${MEMORY_NUDGE_STATE_DIR:-$CFG/state}"
mkdir -p "$STATE_DIR" 2>/dev/null || true
# Prune stale per-session counters (>1 day). -mtime +1 is BSD-safe (unlike -mmin).
find "$STATE_DIR" -name 'nudge-*.count' -mtime +1 -delete 2>/dev/null || true

CF="$STATE_DIR/nudge-${SID}.count"
COUNT=$(cat "$CF" 2>/dev/null || echo 0)
COUNT=$((COUNT + 1))
printf '%s' "$COUNT" > "$CF"

# ── Locate the index this session actually loads ──────────────────────────────
# Slug = project root with '/' and '.' folded to '-'. For a linked worktree the
# harness keys on the MAIN worktree, so resolve through the git COMMON dir; a
# cwd-keyed slug is the fallback for a non-repo cwd.
slugify() { printf '%s' "$1" | tr '/.' '--'; }

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")
[ -n "$CWD" ] && [ -d "$CWD" ] || CWD="$PWD"

MEM="${MEMORY_INDEX_PATH:-}"
if [ -z "$MEM" ]; then
  ROOT=""
  if GCD=$(cd "$CWD" 2>/dev/null && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
     && [ -n "$GCD" ]; then
    ROOT=$(dirname "$GCD")
  fi
  # Try each base in BOTH its logical and physical form: git reports a fully
  # resolved path while the harness keys on the cwd it was handed, and on macOS
  # /var vs /private/var share no prefix — one spelling silently finds nothing.
  for cand in "$ROOT" "$CWD"; do
    [ -n "$cand" ] || continue
    phys=$(cd "$cand" 2>/dev/null && pwd -P) || phys=""
    for base in "$cand" "$phys"; do
      [ -n "$base" ] || continue
      p="$CFG/projects/$(slugify "$base")/memory/MEMORY.md"
      [ -f "$p" ] && { MEM="$p"; break 2; }
    done
  done
fi

# ── Measure (fail-safe: a side-car must never fail wider than itself) ─────────
LIMIT="${MEMORY_INDEX_LIMIT:-24985}"   # 24.4 KiB harness read limit
HOOK_TARGET="${MEMORY_HOOK_TARGET:-115}"  # the compact-memory 'one governing rule' length
BUDGET_CTX=""
if [ -n "$MEM" ] && [ -f "$MEM" ]; then
  TOTAL=$(wc -c <"$MEM" 2>/dev/null | tr -d ' ') || TOTAL=""
  N=$(grep -c '^- \[' "$MEM" 2>/dev/null || echo 0)
  if [ -n "$TOTAL" ] && [ "${N:-0}" -gt 0 ] 2>/dev/null; then
    # Measure the ENTRY lines only: the file also carries a header/provenance block,
    # and folding that fixed cost into a per-entry average overstates every hook.
    ENTRY_B=$(grep '^- \[' "$MEM" | wc -c | tr -d ' ')
    PFX=$(grep '^- \[' "$MEM" | sed -E 's/^(- \[[^]]*\]\([^)]*\) — ).*/\1/' | wc -c | tr -d ' ')
    PFX_AVG=$(( PFX / N ))
    HOOK_AVG=$(( (ENTRY_B - PFX) / N ))
    # Cardinality ceiling: what the limit affords at a disciplined hook length.
    MAXN=$(( LIMIT / (PFX_AVG + HOOK_TARGET) ))
    if [ "$TOTAL" -ge "$LIMIT" ]; then
      OVER=$(( TOTAL - LIMIT ))
      DROPPED=$(( (OVER / (PFX_AVG + HOOK_AVG)) + 1 ))
      # Which lever can actually reach the target? Say so — do not make the reader derive it.
      RECOVER=0
      [ "$HOOK_AVG" -gt "$HOOK_TARGET" ] && RECOVER=$(( N * (HOOK_AVG - HOOK_TARGET) ))
      if [ "$RECOVER" -ge "$OVER" ]; then
        LEVER="hook LENGTH is the binding lever: hooks average ${HOOK_AVG} B against the ${HOOK_TARGET} B one-governing-rule target, so shortening the $N existing hooks recovers ~${RECOVER} B — more than the ${OVER} B needed, and it deletes no rules."
      elif [ "$RECOVER" -gt 0 ]; then
        LEVER="BOTH levers are needed: shortening all $N hooks from ${HOOK_AVG} B to the ${HOOK_TARGET} B target recovers only ~${RECOVER} B of the ${OVER} B needed, so archive under the DURABILITY criterion for the remainder (ceiling is ~${MAXN} entries; the index holds $N)."
      else
        LEVER="hooks are already at ${HOOK_AVG} B (at/under the ${HOOK_TARGET} B target), so shortening CANNOT reach the limit — this is CARDINALITY: the index holds $N entries against a ceiling of ~${MAXN}. Archiving under the DURABILITY criterion is the only non-lossy lever."
      fi
      BUDGET_CTX="🚨 MEMORY INDEX OVER ITS READ LIMIT — ${TOTAL} B vs the ${LIMIT} B loader limit (over by ${OVER} B). The loader drops the TAIL silently, so roughly the NEWEST ${DROPPED} entries did not load this session and no reader can tell. Anything you append now is written into the invisible tail. ${LEVER} BEFORE appending anything new: archive or shorten to get under ${LIMIT} B (run /compact-memory; its lossy half is PROPOSE-ONLY — show diffs, get approval). If you must record something now, apply ONE-IN-ONE-OUT: archive an entry in the same edit that adds one."
    else
      HEADROOM=$(( LIMIT - TOTAL ))
      LINE_BUDGET=$(( HEADROOM - PFX_AVG ))
      [ "$LINE_BUDGET" -lt 0 ] && LINE_BUDGET=0
      SLOTS=$(( MAXN - N ))
      BUDGET_CTX="MEMORY INDEX BUDGET (live): ${TOTAL}/${LIMIT} B across $N entries — ${HEADROOM} B of headroom, ~${SLOTS} entry slots left before the ~${MAXN}-entry ceiling. A new index line costs ~${PFX_AVG} B of prefix before a word of content, so keep its hook <= ${HOOK_TARGET} B (hard cap this append: ${LINE_BUDGET} B). Past ${LIMIT} B the loader drops the NEWEST entries silently."
    fi
  fi
fi

# Fire on the FIRST prompt and every Nth after. An over-limit index is a live,
# actionable fault, so it speaks up immediately rather than waiting for the
# periodic slot; when the index is healthy this stays on the periodic cadence.
OVERFLOW=0
case "$BUDGET_CTX" in '🚨'*) OVERFLOW=1 ;; esac
if [ "$OVERFLOW" -eq 1 ]; then
  [ "$COUNT" -eq 1 ] || [ $((COUNT % INTERVAL)) -eq 0 ] || exit 0
else
  [ $((COUNT % INTERVAL)) -eq 0 ] || exit 0
fi

NUDGE="MEMORY CHECK (periodic): if this session surfaced a DURABLE, generalizable rule, a decision (+ its why), a confirmed constraint, or user feedback that is NOT already in MEMORY.md, persist it now — append one index line to MEMORY.md and create the topic file with frontmatter. SKIP (do not encode as a permanent rule): transient errors, environment/worktree-specific one-offs, lucky paths, negative tool-claims (verify before encoding), anything already indexed. Nothing durable this session? Ignore this."

# Build with jq: the message interpolates measured values, and shell quoting is
# not JSON quoting — a hand-rolled heredoc would be a quoting bug waiting to land.
jq -cn --arg ctx "${BUDGET_CTX:+$BUDGET_CTX }$NUDGE" \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'
exit 0
