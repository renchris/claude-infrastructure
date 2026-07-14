#!/bin/bash
# Ultra-Minimal Actionable Status Line
#
# Shows context usage based on remaining_percentage (per-conversation INPUT tokens).
#
# LIMITATION: Claude's red warning counts INPUT + OUTPUT tokens, but the statusline
# JSON only exposes INPUT tokens per-conversation. This means:
# - Heavy OUTPUT sessions (lots of code generation) may trigger warning earlier
#   than this statusline predicts
# - The warning % and statusline % may diverge in output-heavy sessions
#
# Offset approximation accounts for (absolute tokens, scaled to the REAL window size):
# - Output token buffer: ~64k
# - Auto-compact buffer: ~13k
# - Warning threshold:   ~20k
# ≈97k reserved → 48 points on a 200k window, ~9 points on a 1M window. The offset was
# previously the FIXED constant 48 (200k-era) — on 1M-window models it overstated usage
# ~2.3×: 37%-real rendered "86%", and a 47%-real lead was relieved as "95% context"
# (2026-07-13, doc_classifier W3). Window size now read from payload
# .context_window.context_window_size (present ≥2.1.207; fallback 200k).
#
# See: docs/reference/CLAUDE_CODE_CONTEXT_CALCULATION.md
#
# Color thresholds:
#   - <60% used: gray (healthy)
#   - 60-90% used: default (approaching)
#   - >90% used: red (warning likely visible)

GRAY='\033[38;5;245m'
MUTED_RED='\033[38;5;167m'
NEXT_ACCENT='\033[38;5;75m'
RESET='\033[0m'

# Reserved-space tokens converted to an offset % against the LIVE window size in the
# context-% block below (97k = 64k output + 13k auto-compact + 20k warning).
RESERVED_TOKENS=97000

INPUT=$(cat)
OUTPUT=""
# Left-anchored parallel-instance glyph (set below). Prepended at the final echo so
# it sits at the START of the line and survives narrow-terminal ellipsis truncation.
GLYPH_PREFIX=""

# Directory + Commit ID + branch.
#
# MECE de-duplication: worktrees are named `wt-<branch>` (scripts/new-worktree.sh),
# so the directory ALREADY encodes the branch. Printing the branch as a separate
# segment then repeats the same identifier (dir `wt-cc-002950-92749` + branch
# `cc-002950-92749`) — a Pyramid/MECE violation. When the dir is the branch's
# worktree folder, show it ONCE (dirty marker folded onto the dir) and drop the
# duplicate branch segment. Non-worktree checkouts keep the original
# `DIR (COMMIT)  BRANCH*` format, where dir (repo) and branch are distinct signals.
DIR=$(basename "$(pwd)")
COMMIT=$(git rev-parse --short HEAD 2>/dev/null)
BRANCH=$(git branch --show-current 2>/dev/null)

DIRTY=""
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    DIRTY="*"
fi

# A feature branch carries signal; main/master/detached does not.
SHOW_BRANCH=""
if [ -n "$BRANCH" ] && [ "$BRANCH" != "main" ] && [ "$BRANCH" != "master" ]; then
    SHOW_BRANCH=1
fi

# Redundant when the dir is the branch's worktree folder (`wt-<branch>`) or is
# named exactly for the branch.
REDUNDANT=""
if [ -n "$SHOW_BRANCH" ] && { [ "$DIR" = "wt-${BRANCH}" ] || [ "$DIR" = "$BRANCH" ]; }; then
    REDUNDANT=1
fi

if [ -n "$REDUNDANT" ]; then
    OUTPUT="${DIR}${DIRTY}"
else
    OUTPUT="${DIR}"
fi

if [ -n "$COMMIT" ]; then
    OUTPUT="${OUTPUT} (${COMMIT})"
fi

if [ -n "$SHOW_BRANCH" ] && [ -z "$REDUNDANT" ]; then
    OUTPUT="${OUTPUT}  ${BRANCH}${DIRTY}"
fi

# Effort level (payload .effort.level — present on 2.1.170+ when the model
# supports effort; silently absent on older tracks). Live observability for
# the launcher-injected default and in-session /effort changes.
if [ -n "$INPUT" ] && command -v jq &>/dev/null; then
    EFFORT=$(echo "$INPUT" | jq -r '.effort.level // empty' 2>/dev/null)
    if [ -n "$EFFORT" ]; then
        # ` · ` separator (matches the effort↔context% delimiter) so all three
        # top-level groups — location, effort, context% — read as uniform, MECE
        # segments instead of mixing a double-space here with a middot there.
        OUTPUT="${OUTPUT} · ${EFFORT}"
    fi
fi

# Parallel-instance indicator — which claude-next<n> launcher this session is,
# as a circled glyph ①..⑳ (stable claude/cc shows nothing). LEFT-anchored: rendered
# as GLYPH_PREFIX at the very start of the line (prepended at the final echo) so the
# number is always visible even when a narrow terminal truncates the line with an
# ellipsis — the old right-end placement was the first thing to get clipped.
#
# n is resolved in priority order, so FUTURE instances need ≤1 line of upkeep:
#   1. $CLAUDE_INSTANCE_N — explicit, naming-independent escape hatch. Set it in
#      a new alias (e.g. claude-next5='… CLAUDE_INSTANCE_N=5 claude-next') and
#      ANY config-dir name works with ZERO edits here.
#   2. The config-dir Latin-ordinal map below (the existing ~/.zshrc convention):
#      claude-next→.claude-next(1), -next2→.claude-secondary(2),
#      -next3→.claude-tertiary(3), -next4→.claude-quaternary(4), then
#      quinary(5)/senary(6)/septenary(7)/octonary(8)/nonary(9)/denary(10).
#      Adding the 11th+ instance = add one case line (or just use route 1).
# Config dir comes from payload .transcript_path (its prefix before /projects/),
# with $CLAUDE_CONFIG_DIR as fallback.
if [ -n "$INPUT" ] && command -v jq &>/dev/null; then
    NIDX=""
    # Route 1: explicit override — accepted only if numeric (else ignored, so a
    # malformed value falls through to the dir map rather than blanking the glyph).
    if [ -n "${CLAUDE_INSTANCE_N:-}" ] && [ "${CLAUDE_INSTANCE_N}" -ge 1 ] 2>/dev/null; then
        NIDX="$CLAUDE_INSTANCE_N"
    fi
    if [ -z "$NIDX" ]; then
        TPATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
        CFG="${TPATH%%/projects/*}"
        if [ -z "$CFG" ] || [ "$CFG" = "$TPATH" ]; then CFG="$CLAUDE_CONFIG_DIR"; fi
        case "$CFG" in
            */.claude-next)       NIDX=1 ;;
            */.claude-secondary)  NIDX=2 ;;
            */.claude-tertiary)   NIDX=3 ;;
            */.claude-quaternary) NIDX=4 ;;
            */.claude-quinary)    NIDX=5 ;;
            */.claude-senary)     NIDX=6 ;;
            */.claude-septenary)  NIDX=7 ;;
            */.claude-octonary)   NIDX=8 ;;
            */.claude-nonary)     NIDX=9 ;;
            */.claude-denary)     NIDX=10 ;;
        esac
    fi
    # n -> circled glyph (①..⑳ are contiguous U+2460..U+2473); plain (n) beyond.
    if [ -n "$NIDX" ] && [ "$NIDX" -ge 1 ] 2>/dev/null; then
        GLYPHS=(① ② ③ ④ ⑤ ⑥ ⑦ ⑧ ⑨ ⑩ ⑪ ⑫ ⑬ ⑭ ⑮ ⑯ ⑰ ⑱ ⑲ ⑳)
        if [ "$NIDX" -le 20 ]; then NGLYPH="${GLYPHS[$((NIDX-1))]}"; else NGLYPH="($NIDX)"; fi
        # Accent the instance and pin it to the LEFT edge (prepended at the final
        # echo). RESET after the glyph so the following segment keeps its own color
        # (default in the no-context path, or the GRAY the context-% block prepends).
        GLYPH_PREFIX="${NEXT_ACCENT}${NGLYPH}${RESET}  "
    fi
fi

# Context % - Using remaining_percentage (per-conversation INPUT only)
if [ -n "$INPUT" ] && command -v jq &>/dev/null; then
    REMAINING=$(echo "$INPUT" | jq -r '.context_window.remaining_percentage // empty' 2>/dev/null)
    WINDOW=$(echo "$INPUT" | jq -r '.context_window.context_window_size // empty' 2>/dev/null)

    if [ -n "$REMAINING" ] && [ "$REMAINING" != "null" ]; then
        REMAINING="${REMAINING%%.*}"   # tolerate float payloads
        # Scale the reserved-space buffers to the REAL window: 48 points on 200k
        # (bit-identical to the old fixed constant), ~9 on 1M. Unknown window → 200k.
        WINDOW="${WINDOW%%.*}"
        { [ -n "$WINDOW" ] && [ "$WINDOW" -gt 0 ] 2>/dev/null; } || WINDOW=200000
        BUFFER_OFFSET=$(( RESERVED_TOKENS * 100 / WINDOW ))
        EFFECTIVE_REMAINING=$((REMAINING - BUFFER_OFFSET))
        [ "$EFFECTIVE_REMAINING" -lt 0 ] && EFFECTIVE_REMAINING=0
        [ "$EFFECTIVE_REMAINING" -gt 100 ] && EFFECTIVE_REMAINING=100

        # Convert to "used %" for display
        PCT=$((100 - EFFECTIVE_REMAINING))
    fi

    if [ -n "$PCT" ] && [ "$PCT" -gt 0 ] 2>/dev/null; then
        if [ "$PCT" -ge 90 ]; then
            OUTPUT="${GRAY}${OUTPUT} ·${RESET} ${MUTED_RED}${PCT}%${RESET}"
        elif [ "$PCT" -ge 60 ]; then
            OUTPUT="${GRAY}${OUTPUT} ·${RESET} ${PCT}%"
        else
            OUTPUT="${GRAY}${OUTPUT} · ${PCT}%${RESET}"
        fi
    fi
fi

echo -e "${GLYPH_PREFIX}${OUTPUT}${RESET}"
