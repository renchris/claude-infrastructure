#!/bin/bash
# UserPromptSubmit Hook — Memory Crystallization Nudge
#
# Periodic in-session reminder (every MEMORY_NUDGE_INTERVAL prompts, default 12)
# to persist DURABLE knowledge to MEMORY.md / a topic file, with the hermes-agent
# anti-capture list embedded. Fires while context is LIVE — UserPromptSubmit
# reaches the model MID-SESSION, while the context being nudged about is still in
# hand.
#
#   This used to read "the ONLY event whose additionalContext reaches the model
#   mid-session (Stop cannot inject; GH anthropics/claude-code#37559)". That is
#   STALE: measured 2026-08-08 on 2.1.220, Stop additionalContext DOES reach the
#   model (docs/research/final-response-shaping-2026-08-08.md). UserPromptSubmit
#   remains correct, and is now the stronger of two live options rather than the
#   only one — Stop fires when the turn is already over, and every model-facing
#   Stop channel forces an extra turn, so nudging there would arrive too late to
#   act on AND cost a round-trip.
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

# Deref through the live symlink (this file IS ~/.claude/hooks/memory-nudge.sh when invoked
# live) so a sibling binary resolves in the CHECKOUT, where it exists the moment the trunk
# fast-forwards — same load-bearing pattern as backup-before-write.sh's _mib_deref: an
# underefed dirname would miss a newly-ADDED sibling until a deploy links it, and fail open
# silently (MEMORY.md deployed-layer-bootstrap-circle / the LIVE_ADDS budget rule).
_mn_deref() {
  local p="$1" t n=0
  readlink -f "$p" 2>/dev/null && return 0
  while [ -L "$p" ] && [ "$n" -lt 20 ]; do
    t="$(readlink "$p")"
    case "$t" in /*) p="$t" ;; *) p="$(dirname "$p")/$t" ;; esac
    n=$(( n + 1 ))
  done
  printf '%s\n' "$p"
}

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

  # ── ACTUATE, then advise (2026-08-10). Twelve hand-compactions in 14 days proved advisory
  # text cannot hold this line: insertion is machine-speed (Edit appends, plus Bash `>>`
  # appends the PreToolUse byte-gate never sees — one caught live 2026-08-10T07:51Z), while
  # removal was human-speed. cc-memory-rotate mechanizes the operator-approved cold split
  # (2026-07-30, compact-memory.md § two-tier hot/cold); this hook fires fleet-wide on every
  # prompt, so whichever door grew the file, the next prompt anywhere rotates it back under
  # budget. Actuation runs on EVERY over-threshold prompt regardless of the nudge's damping
  # cadence below — advisory cadence and actuation are different duties. After this, the 🚨
  # branch means rotation COULD NOT clear it — an alarm that fires on breaches it could have
  # fixed itself carries no bits (MEMORY.md alarm-polarity-and-attention-budget).
  ROTATE_AT="${MEMORY_ROTATE_AT:-$(( LIMIT - 1500 ))}"
  ROTATE_NOTE=""
  if [ -n "$TOTAL" ] && [ "$TOTAL" -ge "$ROTATE_AT" ] 2>/dev/null; then
    RB="${MEMORY_ROTATE_BIN:-}"
    if [ -z "$RB" ]; then
      for c in "$(dirname "$(_mn_deref "${BASH_SOURCE[0]}")")/../bin/cc-memory-rotate" \
               "$CFG/bin/cc-memory-rotate"; do
        if [ -x "$c" ]; then RB="$c"; break; fi
      done
    fi
    PRE_TOTAL="$TOTAL"
    if [ -n "$RB" ] && [ -x "$RB" ]; then
      RV=$("$RB" "$MEM" 2>/dev/null) || RV="${RV:-verdict=error}"
      case "$RV" in
        verdict=rotated*|verdict=noop*)
          if [ "${RV#verdict=rotated}" != "$RV" ]; then
            ROTATE_NOTE=" AUTO-ROTATED to hold the read limit (${RV#verdict=rotated }): moved lines are VERBATIM in the cold record — restore = paste the line back."
          fi
          TOTAL=$(wc -c <"$MEM" 2>/dev/null | tr -d ' ') || TOTAL=""
          N=$(grep -c '^- \[' "$MEM" 2>/dev/null || echo 0)
          ;;
        *)
          # In the pressure band under the LIMIT an exhausted rotor is the designed steady
          # state (stage 2 arms only at breach) — not a failure; note it only when the index
          # is actually breached and rotation was its remedy.
          if [ "$PRE_TOTAL" -ge "$LIMIT" ] 2>/dev/null; then
            ROTATE_NOTE=" Auto-rotation ran and could NOT clear it (${RV:-no verdict})."
          fi
          ;;
      esac
    else
      if [ "$PRE_TOTAL" -ge "$LIMIT" ] 2>/dev/null; then
        ROTATE_NOTE=" Auto-rotation unavailable: cc-memory-rotate not resolvable from this hook."
      fi
    fi
  fi

  if [ -n "$TOTAL" ] && [ "${N:-0}" -gt 0 ] 2>/dev/null; then
    # Measure the ENTRY lines only: the file also carries a header/provenance block,
    # and folding that fixed cost into a per-entry average overstates every hook.
    ENTRY_B=$(grep '^- \[' "$MEM" | wc -c | tr -d ' ')
    PFX=$(grep '^- \[' "$MEM" | sed -E 's/^(- \[[^]]*\]\([^)]*\) — ).*/\1/' | wc -c | tr -d ' ')
    PFX_AVG=$(( PFX / N ))
    HOOK_AVG=$(( (ENTRY_B - PFX) / N ))
    # Cardinality ceiling: what the limit affords at a disciplined hook length.
    MAXN=$(( LIMIT / (PFX_AVG + HOOK_TARGET) ))
    # FILING FORM (2026-08-06, backlog 0b3a8b19d4d4). Sessions reading this advisory file the
    # condition as backlog work, and they put the live size in the TITLE — which is the cc-backlog
    # event key (project+title+source), so one standing condition minted 21 items instead of one
    # and the ledger's own done-guard never fired (004502cf59ab closed 21:28:01Z, its twin
    # 0fc2ae0d0140 claimed 21:34:01Z). Hand over the condition-keyed form in BOTH branches: those
    # mints happened at 20.5 KB and 22.5 KB — under this limit, off the harness's own product-side
    # "approaching the limit" reminder — so a form that only spoke when breached would miss most.
    FILING="FILING: if you file this as work it is ONE standing condition, not a new item per measurement — \`cc-backlog add --condition memory-index-over-budget --project <project> --title \"<the live size>\"\`. The size belongs in the title; putting it in the key is what minted 21 items for this one condition."
    if [ "$TOTAL" -ge "$LIMIT" ]; then
      OVER=$(( TOTAL - LIMIT ))
      # EXACT, not averaged. The old form (OVER / mean-line-cost) reads the index as
      # though every entry were mean-length; a real index is not, and its TAIL is
      # exactly where the estimate is applied. Measured 2026-08-08 against the live
      # store it announced 6 dropped entries where the exact count was 4 — a number
      # the operator sizes a compaction pass from. Count instead the entries whose
      # own start offset falls at/after the limit. LC_ALL=C so awk's length() is
      # BYTES: this is a byte limit and the index carries multibyte punctuation
      # (the same trap tests/memory-index-budget.bats pins for the gate).
      DROPPED=$(LC_ALL=C awk -v lim="$LIMIT" \
        '{ if (substr($0,1,3)=="- [" && off>=lim) n++; off+=length($0)+1 } END{ print n+0 }' \
        "$MEM" 2>/dev/null) || DROPPED=""
      # Over the limit means at least the final entry is cut, even when the overage
      # falls INSIDE that entry and no start offset is past the limit.
      case "$DROPPED" in ''|*[!0-9]*|0) DROPPED=1 ;; esac
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
      BUDGET_CTX="🚨 MEMORY INDEX OVER ITS READ LIMIT — ${TOTAL} B vs the ${LIMIT} B loader limit (over by ${OVER} B).${ROTATE_NOTE} The loader drops the TAIL silently: the NEWEST ${DROPPED} entries begin past the limit, so they did not load this session and no reader can tell. Anything you append now is written into the invisible tail. ${LEVER} BEFORE appending anything new: archive or shorten to get under ${LIMIT} B (run /compact-memory; its lossy half is PROPOSE-ONLY — show diffs, get approval). If you must record something now, apply ONE-IN-ONE-OUT: archive an entry in the same edit that adds one. ${FILING}"
    else
      HEADROOM=$(( LIMIT - TOTAL ))
      LINE_BUDGET=$(( HEADROOM - PFX_AVG ))
      [ "$LINE_BUDGET" -lt 0 ] && LINE_BUDGET=0
      SLOTS=$(( MAXN - N ))
      # RUNWAY vs CEILING. MAXN/SLOTS derive from HOOK_TARGET, so they answer
      # "how many entries WOULD fit if every one were rewritten to target" — a
      # rewrite, not room to add. The number a session actually needs is what
      # fits at the density this index is ALREADY written at. Measured
      # 2026-08-06 the two read 37 vs 11 (3.4x), and the inflated one had
      # already propagated into a backlog item's premise as "37 free
      # cardinality slots", framing a cardinality-bound index as length-bound.
      # Lead with the observed-density figure; keep the ceiling, marked conditional.
      LINE_COST=$(( PFX_AVG + HOOK_AVG + 1 ))
      [ "$LINE_COST" -gt 0 ] || LINE_COST=1
      FITS=$(( HEADROOM / LINE_COST ))
      BUDGET_CTX="MEMORY INDEX BUDGET (live): ${TOTAL}/${LIMIT} B across $N entries — ${HEADROOM} B of headroom: ~${FITS} entry slots left at the ${LINE_COST} B/line this index is ACTUALLY written at (${SLOTS} only if every existing entry were first rewritten to the ${HOOK_TARGET} B target — that is a rewrite, not runway). A new index line costs ~${PFX_AVG} B of prefix before a word of content, so keep its hook <= ${HOOK_TARGET} B (hard cap this append: ${LINE_BUDGET} B). Past ${LIMIT} B the loader drops the NEWEST entries silently.${ROTATE_NOTE} ${FILING}"
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
