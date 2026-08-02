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

# --- ONE payload read (audit 06 §5.2) ---------------------------------------------
# This script rendered at 0.15-0.37 Hz *per pane* and spent 109 ms of CPU each time, of
# which the dominant term was **eight separate `echo "$INPUT" | jq` pipelines** — sixteen
# processes to read six scalars out of one JSON object. They are now one `jq … | @tsv`
# plus a `read`. The four blocks below consume these variables and are otherwise
# untouched, so the rendered line is byte-identical (tests/statusline-identity.bats
# diffs this script's output against the pre-slim version on fixture payloads).
# The remaining jq calls are the two that genuinely need jq: the telemetry EMIT (it
# writes JSON) and the memoized pid read from the prior telemetry file.
# The separator is US (0x1f), NOT a tab. `read` COLLAPSES runs of IFS *whitespace*, so with
# IFS=$'\t' an absent middle field silently shifts every later field left by one — a payload
# with no `used_percentage` then read remaining_percentage AS used_percentage and rendered 70%
# where the real answer was 78%. A non-whitespace IFS keeps empty fields positional.
PAY_SID=""; PAY_TPATH=""; PAY_EFFORT=""; PAY_USED=""; PAY_REMAINING=""; PAY_WINDOW=""
if [ -n "$INPUT" ] && command -v jq &>/dev/null; then
    IFS=$'\x1f' read -r PAY_SID PAY_TPATH PAY_EFFORT PAY_USED PAY_REMAINING PAY_WINDOW <<< "$(
        printf '%s' "$INPUT" | jq -r '[
            (.session_id // ""),
            (.transcript_path // ""),
            (.effort.level // ""),
            (.context_window.used_percentage // ""),
            (.context_window.remaining_percentage // ""),
            (.context_window.context_window_size // "")
        ] | map(tostring) | join("\u001f")' 2>/dev/null
    )"
fi

# --- Telemetry export (session self-knowledge; SESSION_AUTONOMY_PLAN 2026-07-14) ----
# Persist the payload's context/identity fields so the SESSION ITSELF (and peers /
# supervisors / the orchestrator) can read live context % programmatically — /context
# is TUI-only, and the operator was hand-running /context + /accounts to tell sessions
# when to hand off. Reader: ~/.claude/bin/cc-context. Best-effort: never blocks rendering.
# ⚠️ The file is NOT "always fresh" (this comment used to claim it was, and a sweep ACTED on
# that claim). The statusline renders on UI updates, so a session doing many short steps stays
# fresh — but a session inside ONE long operation, or genuinely hung, renders ZERO times and its
# telemetry goes arbitrarily stale WHILE ALIVE (observed: a live respawn at 78m stale). Hence the
# `pid` field below: AGE alone can never distinguish a stall from a healthy long turn.
# Telemetry-v2 (SESSION_AUTONOMY §3.1): ATOMIC write (.tmp+rename, so a concurrent
# cc-context/cc-board reader never catches a half-written file) · sid computed ONCE and
# SKIP-on-empty (a transient parse miss must not collide N sessions on unknown.json) ·
# carry config_dir (transcript prefix before /projects/) as the cc-context×claude-accounts
# quota-join key. Fail-safe: on jq failure the PRIOR good file survives (old `>` truncated
# it to empty). Best-effort throughout: never blocks rendering.
if [ -n "$INPUT" ] && command -v jq &>/dev/null; then
    # CC_TELEMETRY_DIR is the seam bin/cc-context, bin/cc-board and bin/cc-value already
    # honour; the writer was the only side still hardcoding the path.
    TDIR="${CC_TELEMETRY_DIR:-/tmp/cc-telemetry}"
    # 0700, set at CREATE time only. These rows carry live session ids, cwds and pids, and the dir
    # sat 0755 inside mode-1777 /tmp — any local uid could enumerate every live session, which is
    # precisely what made the generated-launcher names predictable (codex-security 2026-07-29,
    # finding 2). Creating it 0700 closes the enumeration; the chmod is inside the `[ -d ]` guard
    # because this runs on EVERY TUI redraw and an unconditional chmod would add a fork per render.
    #
    # The PATH is deliberately NOT moved, though the finding suggested it. Three measured blockers:
    # bin/cc-ctx-audit keys on a DIFFERENT env var (CC_CTX_TELEMETRY_DIR), so changing this default
    # moves 7 of 8 sites and silently strands the 8th; /tmp's reboot-wipe is the ONLY bound on
    # lead-supervisor's DEAD-page population (gc_stale refuses to reap stranded-dead rows), so a
    # durable dir turns that into a permanent re-firing page; and this writer is a copy-deployed
    # real file while every reader is a symlink, so a path change goes live on the readers first
    # and blinds the spine in between. Mode, not location, is what "world-readable" asked for.
    [ -d "$TDIR" ] || { mkdir -p "$TDIR" 2>/dev/null && chmod 700 "$TDIR" 2>/dev/null; }
    _sid="$PAY_SID"
    # -O is a bash builtin (no fork): refuse to publish into a directory this uid does not own,
    # so a pre-created foreign /tmp/cc-telemetry cannot harvest the rows.
    [ -O "$TDIR" ] || _sid=""
    if [ -n "$_sid" ]; then
        _tp="$PAY_TPATH"
        _cfg="${_tp%%/projects/*}"
        if [ -z "$_cfg" ] || [ "$_cfg" = "$_tp" ]; then _cfg="${CLAUDE_CONFIG_DIR:-}"; fi
        # pid (P9/P3) — the OWNING claude process, so a reader can `kill -0` it. WITHOUT this,
        # telemetry AGE is the only liveness signal, and age cannot tell a stalled session from a
        # healthy one inside a single long operation: BOTH render zero times (proved 2026-07-14 —
        # a respawn sat RUNNING 1h25m with 78m-stale telemetry). A bare $PPID is the known trap
        # (the statusline runs under a shell shim), so walk the ancestry to the real `claude`
        # process — the proven recipe from hooks/session-register.sh:43-47. MEMOIZED: reuse the
        # prior file's pid while it is still alive, so the ps-walk runs once per session and not
        # on every render (this is a hot path).
        _pid=$(jq -r '.pid // empty' "$TDIR/${_sid}.json" 2>/dev/null)
        if [ -z "$_pid" ] || ! kill -0 "$_pid" 2>/dev/null; then
            _walk="$PPID"; _pid=""; _i=0
            while [ -n "$_walk" ] && [ "$_walk" -gt 1 ] 2>/dev/null && [ "$_i" -lt 10 ]; do
                _c=$(ps -o comm= -p "$_walk" 2>/dev/null | sed 's|.*/||')
                case "$_c" in claude|claude.exe|claude-*) _pid="$_walk"; break ;; esac
                _walk=$(ps -o ppid= -p "$_walk" 2>/dev/null | tr -d ' '); _i=$((_i+1))
            done
        fi
        _tmp="$TDIR/.${_sid}.$$.tmp"
        if echo "$INPUT" | jq -c --arg cfg "$_cfg" --arg pid "$_pid" '{ts: (now|floor), session_id, cwd,
            config_dir: $cfg, model: .model.id, effort: .effort.level,
            pid: (if $pid == "" then null else ($pid|tonumber) end),
            window: .context_window.context_window_size,
            used_pct: .context_window.used_percentage,
            remaining_pct: .context_window.remaining_percentage,
            input_tokens: .context_window.total_input_tokens,
            exceeds_200k: .exceeds_200k_tokens}' > "$_tmp" 2>/dev/null; then
            mv -f "$_tmp" "$TDIR/${_sid}.json" 2>/dev/null || rm -f "$_tmp" 2>/dev/null
        else
            rm -f "$_tmp" 2>/dev/null
        fi
    fi
fi
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
#
# Four git invocations became two (audit 06 §5.2). `git branch --show-current` and the two
# `git diff --quiet` probes — the latter two each walking the index — collapse into ONE
# `git status --porcelain=v2`, which reports branch and worktree state together.
#   · --untracked-files=no  preserves the old semantics exactly (git diff never counted
#     untracked files as dirty) AND skips the most expensive part of a status walk.
#   · `1`/`2`/`u` records are the tracked changes the two diffs used to detect: staged,
#     unstaged, renamed, unmerged. `?`/`!` cannot appear with -uno.
#   · porcelain v2 says `(detached)` where `--show-current` prints nothing; mapped back.
# `git rev-parse --short HEAD` STAYS a separate call on purpose: porcelain v2's
# `# branch.oid` is the full 40-hex, and abbreviating it here would hardcode a length that
# core.abbrev is free to change — which is exactly the byte-identity this refactor promises.
# It is also the cheap one: no index walk.
DIR=$(basename "$(pwd)")
COMMIT=$(git rev-parse --short HEAD 2>/dev/null)

BRANCH=""
DIRTY=""
GIT_STATUS=$(git status --porcelain=v2 --branch --no-ahead-behind --untracked-files=no 2>/dev/null)
if [ -n "$GIT_STATUS" ]; then
    while IFS= read -r _line; do
        case "$_line" in
            '# branch.head '*) BRANCH="${_line#\# branch.head }" ;;
            '1 '*|'2 '*|'u '*) DIRTY="*" ;;
        esac
    done <<< "$GIT_STATUS"
    [ "$BRANCH" = "(detached)" ] && BRANCH=""
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
    EFFORT="$PAY_EFFORT"
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
        TPATH="$PAY_TPATH"
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
    # n -> NEGATIVE-circled glyph (filled disc, knocked-out numeral). Two ranges, NOT
    # one contiguous block: 1-10 = U+278A..U+2793 (dingbat negative circled sans-serif),
    # 11-20 = U+24EB..U+24F4 (negative circled 11..20). Do NOT "tidy" this back to the
    # contiguous outline set ①..⑳ (U+2460..U+2473) — that was the original and it is
    # unreadable in kitty. Measured 2026-08-02 with kitty's own renderer
    # (`kitty +launch`, kitty_tests.fonts.render_string, Monaco 14pt @144dpi, cell 17x37px):
    #   Monaco has no U+2460 range, so CoreText substitutes a FULL-WIDTH CJK face
    #   (PingFang SC, advance 14.0pt vs Monaco's 8.4pt cell). U+2460's East Asian Width
    #   is Ambiguous => kitty allots ONE cell and downsamples the glyph ~0.62x to fit.
    #   The ring collapses to a 1px hairline and the numeral inside it to ~4 logical px.
    #   iTerm2 does not do that squeeze — it draws fallback glyphs at natural size and
    #   lets them overflow — which is why this only became unreadable on the kitty move.
    #   Ink measured: ①..⑳ height 18px @ density 0.29-0.49 (hairline ring, low ink);
    #                 ➊..⓴ height 17-18px @ density 0.67-0.72 (solid disc).
    # The fix is the GLYPH, not terminal config: the downsample is inherent to kitty and
    # no installed font has a narrow (1-cell-advance) circled digit, so a kitty
    # `symbol_map` cannot rescue the outline set. Putting the ink in the DISC and knocking
    # the numeral out survives the downsample — it reads at any size, in both terminals.
    if [ -n "$NIDX" ] && [ "$NIDX" -ge 1 ] 2>/dev/null; then
        GLYPHS=(➊ ➋ ➌ ➍ ➎ ➏ ➐ ➑ ➒ ➓ ⓫ ⓬ ⓭ ⓮ ⓯ ⓰ ⓱ ⓲ ⓳ ⓴)
        if [ "$NIDX" -le 20 ]; then NGLYPH="${GLYPHS[$((NIDX-1))]}"; else NGLYPH="($NIDX)"; fi
        # Accent the instance and pin it to the LEFT edge (prepended at the final
        # echo). RESET after the glyph so the following segment keeps its own color
        # (default in the no-context path, or the GRAY the context-% block prepends).
        GLYPH_PREFIX="${NEXT_ACCENT}${NGLYPH}${RESET}  "
    fi
fi

# Context % — EXACT /context parity when the payload exposes used_percentage (CC ≥2.1.207).
# Verified 2026-07-14: payload used_percentage=45 vs transcript last-usage occupancy
# 444,452 tok = 44.4% of the 1M window (0.6-pt delta = integer rounding + one turn of
# drift). The GH #17959 / #12520 "statusline cannot reproduce /context" limitation is
# SUPERSEDED by context_window.{used_percentage, current_usage, context_window_size}.
# Fallback for older payloads: the window-aware reserved-space ESTIMATE (margins, not
# precision — the exact effective-context params were never exposed in that era).
if [ -n "$INPUT" ] && command -v jq &>/dev/null; then
    USED="$PAY_USED"
    REMAINING="$PAY_REMAINING"
    WINDOW="$PAY_WINDOW"

    if [ -n "$USED" ] && [ "$USED" != "null" ]; then
        PCT="${USED%%.*}"                              # /context-parity display
    elif [ -n "$REMAINING" ] && [ "$REMAINING" != "null" ]; then
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
