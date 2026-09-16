#!/usr/bin/env bash
# =============================================================================
#  kitty-drag-w4.sh — THE OPERATOR GATE for wave W4 (KITTY_DRAG_ACTION.md
#  § W4, plan lines 1254-1284).
#
#  W4 IS NOT AN AGENT WAVE.  It needs a human hand on a real mouse for about
#  sixty seconds, and this script's entire job is to make those sixty seconds
#  cost nothing else.  It launches a throwaway kitty, binds every candidate
#  chord SIMULTANEOUSLY so nothing has to be edited between tries, says in the
#  pane exactly what to press, watches the pane-adjacency graph itself, and
#  prints a VERDICT rather than data to interpret.
#
#  WHAT W4 ANSWERS:  Q9 (does it work end to end; is threshold-less
#  objectionable) · Q10 (does the graphics placement survive the relayout) ·
#  Q8 (is the dead band annoying in the hand) · Q12 (which chord).
#
#  ── 🚨 SAFETY: THIS SCRIPT MUST NEVER REACH THE OPERATOR'S OWN KITTY ───────
#  ~/.config/kitty/kitty.conf is a SYMLINK into the shared checkout, and the
#  live kitty runs a `kitten __watch_conf__` child that SIGUSR1s it ~100 ms
#  after ANY write to that directory (plan § 2).  A config line written there
#  arms his 11-13-pane terminal by itself.  Therefore, enforced as hard
#  refusals in preflight() below, not as intentions:
#
#    S1  This script writes NOTHING under ~/.config/kitty and NOTHING inside
#        the shared checkout.  Its whole world is $RUN_ROOT (default /tmp/kdw4).
#    S2  Its socket is /tmp/kdw4.sock — deliberately OUTSIDE the /tmp/kitty-*
#        glob that bin/cc-kitty-socket:48 scans and that
#        scripts/kitty-pane-title-overlay.py:683 chokes on when it finds more
#        than one.  A socket path matching /tmp/kitty-* is REFUSED.
#    S3  Every command that addresses kitty is prefixed
#        `env -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_WINDOW_ID`.  A bare
#        `kitten @ …` from an agent or operator shell inside kitty drives HIS
#        terminal.  Preflight refuses if that prefix is ever not in effect.
#    S4  THIS SCRIPT SENDS NO SIGNALS.  There is no kill, pkill, killall or
#        `kitten @ signal-child` anywhere in it.  Teardown is
#        `kitten @ close-window --match all` against OUR OWN socket, which
#        leaves the sandbox process idle with zero windows and makes the next
#        run a relaunch rather than a spawn.  Preflight additionally refuses
#        if our socket's inode is one of the live /tmp/kitty-<pid> sockets.
#    S5  It is SAFE TO RE-RUN.  A previous sandbox is reused (windows closed,
#        new ones opened); nothing is recursively deleted, so the script never
#        trips a destructive-command prompt in anyone's shell.
#
#  ── WHICH BINARY ──────────────────────────────────────────────────────────
#  Preference order: $KDW4_KITTY, then the v0.48.2 build tree, then the
#  operator's installed /Applications/kitty.app.  The fallback is announced
#  LOUDLY and by name.  Identity is proven with
#      kitty +runpy 'import kitty; print(kitty.__file__)'
#  and NEVER with --version: master at 1d67ecd still self-reports 0.48.2
#  (plan § W4 / scripts/kitty-drag-window.py header).
#
#  ── WHAT IT PRINTS A VERDICT ON, AND WHAT IT CANNOT ───────────────────────
#  LAYOUT (Q9/Q12): a real machine verdict.  scripts/kitty-pane-graph.py diffs
#  the pane-adjacency graph before and after, and it tests the member SET
#  before it tests the ORDER — because closing a pane makes its two neighbours
#  adjacent, so the naive order-first differ reports ordinary churn as a
#  REORDER.  W4's evidence is a HUMAN ACTION, the one thing a session may not
#  manufacture, so that false positive would fabricate exactly the proof
#  nobody else can check.  Controlled by tests/kitty-pane-graph.bats branch (b).
#
#  GRAPHICS (Q10): stated plainly rather than faked.  This script captures a
#  before frame, a burst spanning the gesture, and an after frame, all scoped
#  to the SANDBOX OS window by its platform_window_id so nothing else on the
#  operator's screen is photographed.  It reports how many frames it got and
#  hands over ONE command to view them.  It does NOT invent a pixel verdict:
#  "did the image survive" is a two-second look, and a manufactured answer to
#  it would be the same defect the witness rule exists to prevent.
#
#  ── USAGE ────────────────────────────────────────────────────────────────
#    scripts/kitty-drag-w4.sh                 # the real gate
#    scripts/kitty-drag-w4.sh --dry-run       # generate + validate, launch nothing
#    scripts/kitty-drag-w4.sh --watch-secs N  # gesture window, default 120
#    scripts/kitty-drag-w4.sh --no-screenshot # skip Q10 capture entirely
#    scripts/kitty-drag-w4.sh --wait-build N  # poll N s for the 0.48.2 tree
#    scripts/kitty-drag-w4.sh --teardown      # close the sandbox's windows
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
#  Constants
# ---------------------------------------------------------------------------
# Resolve $0 through its symlinks BEFORE deriving the repo root. ~/.claude/scripts/ is a per-file
# SYMLINK FARM into this checkout, so through the live layer `dirname "$0"/..` is ~/.claude — no
# tests/, no docs/, no .git — and this script would not fail, it would read the WRONG TREE and
# quietly bind the wrong kitten. Canonical loop from _resolve_self() in scripts/ship-land.sh; no
# `readlink -f`, which is GNU-only and this box is BSD. (This is the SECOND instance of this exact
# class in this one file — the kitten path had it too, where a build tree's launcher/kitty is a
# symlink into kitty.app/Contents/MacOS/.)
_kdw4_self="${BASH_SOURCE[0]}"
while [ -L "$_kdw4_self" ]; do
    _kdw4_d="$(cd "$(dirname "$_kdw4_self")" && pwd)"
    _kdw4_self="$(readlink "$_kdw4_self")"
    case "$_kdw4_self" in /*) ;; *) _kdw4_self="$_kdw4_d/$_kdw4_self" ;; esac
done
REPO="$(cd "$(dirname "$_kdw4_self")/.." && pwd)"
# Pane-spawn logging. EVERY in-tree spawn site must leave a row, because the log's whole value is
# the inference "a pane with NO row was spawned by something OUTSIDE this tree" — and one
# uninstrumented site downgrades that to "outside the tree, OR that one site", which is the exact
# ambiguity it exists to close. This script opens a real OS window, so it is a spawn site.
# shellcheck source=/dev/null
[ -r "${REPO}/scripts/lib/pane-spawn-log.sh" ] && . "${REPO}/scripts/lib/pane-spawn-log.sh" || true

KITTEN_PY="${REPO}/scripts/kitty-drag-window.py"
GRAPH_PY="${REPO}/scripts/kitty-pane-graph.py"

RUN_ROOT="${KDW4_ROOT:-/tmp/kdw4}"
SOCK="${KDW4_SOCK:-/tmp/kdw4.sock}"          # MUST NOT match /tmp/kitty-*
# One line per chord press, written by the kitten when KITTY_DRAG_LOG is set (opt-in; the
# deployed kitten writes nothing without it). This is what separates "no chord ever fired"
# from "a chord fired and the drag did not complete" — the pane-adjacency diff renders both
# as "no layout change", and two hand-driven runs produced a non-verdict for exactly that.
PRESS_LOG="${RUN_ROOT}/presses.log"
CFG_DIR="${RUN_ROOT}/config"
CACHE_DIR="${RUN_ROOT}/cache"
SHOT_DIR="${RUN_ROOT}/shots"

BUILD_482_CANDIDATES=(
    "/tmp/kitty-482/kitty/launcher/kitty"
    "${HOME}/kitty-482/kitty/launcher/kitty"
    "/private/tmp/kitty-482/kitty/launcher/kitty"
)
INSTALLED_KITTY="/Applications/kitty.app/Contents/MacOS/kitty"
LOGO_PNG="/Applications/kitty.app/Contents/Resources/kitty/logo/kitty.png"
BUILD_LOG="/tmp/kbuild/build.log"

WATCH_SECS=120
WAIT_BUILD=0
DO_SHOTS=1
DRY_RUN=0
TEARDOWN_ONLY=0

# ---------------------------------------------------------------------------
#  Output helpers
# ---------------------------------------------------------------------------
say()  { printf '%s\n' "$*"; }
head2() { printf '\n%s\n%s\n' "$*" "$(printf '%.0s=' $(seq 1 ${#1}))"; }
warn() { printf '\n!! %s\n' "$*" >&2; }
die()  { printf '\nREFUSED: %s\n' "$*" >&2; exit 2; }

# ---------------------------------------------------------------------------
#  Argument parsing
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)       DRY_RUN=1 ;;
        --no-screenshot) DO_SHOTS=0 ;;
        --teardown)      TEARDOWN_ONLY=1 ;;
        --watch-secs)    shift; WATCH_SECS="${1:-120}" ;;
        --wait-build)    shift; WAIT_BUILD="${1:-0}" ;;
        -h|--help)       sed -n '1,80p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
    shift
done

case "$WATCH_SECS" in ''|*[!0-9]*) die "--watch-secs wants an integer" ;; esac
case "$WAIT_BUILD" in ''|*[!0-9]*) die "--wait-build wants an integer" ;; esac

# ---------------------------------------------------------------------------
#  S1-S5 PREFLIGHT.  Hard refusals, before anything is created or launched.
# ---------------------------------------------------------------------------
preflight() {
    # S2 — the socket must live outside the glob bin/cc-kitty-socket scans.
    case "$SOCK" in
        /tmp/kitty-*|/private/tmp/kitty-*)
            die "socket '$SOCK' is inside the /tmp/kitty-* glob that
         bin/cc-kitty-socket:48 scans. A sandbox socket there would be
         mistaken for the operator's live terminal. Pick another path." ;;
    esac
    case "$SOCK" in
        /*) : ;;
        *) die "socket path must be absolute, got '$SOCK'" ;;
    esac
    # Unix socket paths cap near 104 bytes on Darwin.
    if [ "${#SOCK}" -ge 100 ]; then
        die "socket path is ${#SOCK} chars; Darwin caps sun_path near 104"
    fi

    # S1 — never write into the operator's kitty config or the shared checkout.
    for forbidden in "${HOME}/.config/kitty" "${HOME}/Development/claude-infrastructure"; do
        case "${RUN_ROOT}/" in
            "${forbidden}"/*) die "RUN_ROOT '$RUN_ROOT' is inside '$forbidden'" ;;
        esac
    done
    if [ -e "${HOME}/.config/kitty/kitty.conf" ]; then
        local target
        target="$(readlink "${HOME}/.config/kitty/kitty.conf" 2>/dev/null || true)"
        [ -n "$target" ] && say "  note: ~/.config/kitty/kitty.conf -> ${target}"
        say "        (this script never writes there; see S1 in the header)"
    fi

    # S4 — refuse if our socket path collides with a LIVE kitty's socket.
    local s pid
    for s in /tmp/kitty-*; do
        [ -S "$s" ] || continue
        pid="${s##*/kitty-}"
        if [ "$s" = "$SOCK" ]; then
            die "'$SOCK' IS a live kitty control socket (pid ${pid})"
        fi
    done

    # S3 — the three KITTY_ vars must never reach a kitty we launch or address.
    #      They are dropped by kit()/klaunch(); this proves the drop works.
    local leaked
    # shellcheck disable=SC2016  # the single quotes are the POINT: the probe
    # must be expanded by the env -u SUBSHELL, not by this shell, or it would
    # read our own values and certify the drop without ever testing it.
    leaked="$(env -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_WINDOW_ID \
              sh -c 'echo "${KITTY_LISTEN_ON:-}${KITTY_PID:-}${KITTY_WINDOW_ID:-}"')"
    if [ -n "$leaked" ]; then
        die "the env -u prefix did not clear KITTY_LISTEN_ON/KITTY_PID/KITTY_WINDOW_ID
         (leaked: '$leaked'). Refusing rather than risk addressing the
         operator's terminal."
    fi
    if [ -n "${KITTY_LISTEN_ON:-}${KITTY_PID:-}" ]; then
        say "  note: this shell is inside kitty (KITTY_PID=${KITTY_PID:-?});"
        say "        every kitty command below drops that, by S3."
    fi

    [ -f "$KITTEN_PY" ] || die "the W2 kitten is missing: $KITTEN_PY"
    [ -f "$GRAPH_PY" ]  || die "the verdict reader is missing: $GRAPH_PY"
    command -v python3 >/dev/null 2>&1 || die "python3 not on PATH"
}

# ---------------------------------------------------------------------------
#  Binary selection.  Announced by name; identity proven with +runpy.
# ---------------------------------------------------------------------------
KITTY_BIN=""
KITTY_SRC=""
KITTEN_BIN=""

select_binary() {
    local deadline cand
    if [ -n "${KDW4_KITTY:-}" ]; then
        [ -x "${KDW4_KITTY}" ] || die "KDW4_KITTY='${KDW4_KITTY}' is not executable"
        KITTY_BIN="${KDW4_KITTY}"; KITTY_SRC="KDW4_KITTY override"
        return 0
    fi
    deadline=$(( $(date +%s) + WAIT_BUILD ))
    while :; do
        for cand in "${BUILD_482_CANDIDATES[@]}"; do
            if [ -x "$cand" ]; then
                KITTY_BIN="$cand"; KITTY_SRC="the v0.48.2 build tree"
                return 0
            fi
        done
        [ "$(date +%s)" -ge "$deadline" ] && break
        sleep 2
    done
    [ -x "$INSTALLED_KITTY" ] || die "no usable kitty: the 0.48.2 build tree is absent
         (looked in: ${BUILD_482_CANDIDATES[*]}) and '$INSTALLED_KITTY' is missing."
    KITTY_BIN="$INSTALLED_KITTY"
    KITTY_SRC="THE INSTALLED APP — the 0.48.2 build tree was NOT found"
    warn "FALLBACK BINARY IN USE."
    warn "  wanted : ${BUILD_482_CANDIDATES[0]}   (absent)"
    warn "  using  : ${INSTALLED_KITTY}"
    if [ -r "$BUILD_LOG" ]; then
        warn "  build log tail ($BUILD_LOG):"
        tail -3 "$BUILD_LOG" 2>/dev/null | sed 's/^/           /' >&2 || true
    fi
    warn "  This is the operator's SHIPPED 0.48.2, which is a legitimate W4"
    warn "  target -- route A is config-only and needs no patched build. It is"
    warn "  announced because the answer is about THIS binary and no other."
}

prove_identity() {
    say "  binary : ${KITTY_BIN}"
    say "  source : ${KITTY_SRC}"
    say "  proof  : kitty +runpy 'import kitty; print(kitty.__file__)'   (never --version:"
    say "           master at 1d67ecd still self-reports 0.48.2)"
    local out
    if out="$(env -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_WINDOW_ID \
              "$KITTY_BIN" +runpy 'import kitty; print(kitty.__file__)' 2>&1)"; then
        say "           -> ${out}"
    else
        warn "+runpy identity probe failed: ${out}"
    fi
}

# ---------------------------------------------------------------------------
#  Remote control, always with the env -u prefix (S3).
# ---------------------------------------------------------------------------
kit() {
    env -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_WINDOW_ID \
        "$KITTEN_BIN" @ --to "unix:${SOCK}" "$@"
}

sandbox_alive() { kit ls >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
#  The sandbox config: ALL SIX BINDINGS LIVE AT ONCE.
#
#  Three Q12 chord candidates x two Q2 arming spellings.  A kitty mouse_map key
#  is (button, mods, trigger-count, grab-mode), so six distinct chords are
#  needed to hold six bindings simultaneously; the spelling is selected by the
#  EXTRA `opt` modifier and nothing else, which keeps the chord axis and the
#  spelling axis independent for the operator's hand.
#
#  Q12 candidates (plan § 4 Q12, ruled `cmd+shift+left press` with W4 free to
#  overturn it):
#      cmd+shift+left press    -- the ruling. FREE in both grab modes, keeps
#                                 `cmd+left click -> mouse_handle_click link`
#                                 (config/kitty.conf:772) alive.
#      cmd+left press          -- best ergonomics, but in PRODUCTION it kills
#                                 that link binding, because arm 7 swallows the
#                                 release so the `click` is never synthesised.
#                                 Free to try here: the sandbox has no link map.
#      cmd+left doublepress    -- the real fourth option. `doublepress` is a
#                                 PRESS-family trigger (count 2, utils.py:60),
#                                 so it fires synchronously and does NOT wait
#                                 for click_interval; it would keep both the
#                                 single modifier AND the link click.
#
#  ALL BINDINGS ARE ON **LEFT**, and that is a safety requirement, not a
#  preference: the ONLY mouse-driven clear of `window_being_dragged` is a LEFT
#  release (v0.48.2 tabs.py:1866). A chord on any other button arms a flag no
#  release can clear -- see G4 in scripts/kitty-drag-window.py.
#
#  `drag_threshold 5` is pinned explicitly: at 0 the kitten DECLINES by design
#  (G4), and the whole point of comparing the two spellings is the dead band.
# ---------------------------------------------------------------------------
write_config() {
    mkdir -p "$CFG_DIR" "$CACHE_DIR" "$SHOT_DIR"
    cat > "${CFG_DIR}/kitty.conf" <<CONF
# kitty-drag-w4 SANDBOX CONFIG -- generated, disposable, never deployed.
# Written by scripts/kitty-drag-w4.sh. Lives only under ${RUN_ROOT}.
allow_remote_control yes
listen_on unix:${SOCK}
confirm_os_window_close 0
enabled_layouts splits
drag_threshold 5
window_padding_width 6
tab_bar_style powerline
macos_quit_when_last_window_closed no

# ============ SPELLING (i) THRESHOLD-PRESERVING -- dead band KEPT ===========
# kitty's own drag_threshold arithmetic (tabs.py:1855-1863) still decides when
# the drag promotes, so a press that does not move is a no-op.
mouse_map cmd+shift+left     press       ungrabbed kitten ${KITTEN_PY} --spelling=preserving
mouse_map cmd+left           press       ungrabbed kitten ${KITTEN_PY} --spelling=preserving
mouse_map cmd+left           doublepress ungrabbed kitten ${KITTEN_PY} --spelling=preserving

# ============ SPELLING (ii) THRESHOLD-FREE -- drag starts ON the press ======
# Same three chords plus opt. Calls request_callback_with_thumbnail directly,
# the identical call kitty makes at tabs.py:1862 once ITS threshold is crossed.
mouse_map opt+cmd+shift+left press       ungrabbed kitten ${KITTEN_PY} --spelling=free
mouse_map opt+cmd+left       press       ungrabbed kitten ${KITTEN_PY} --spelling=free
mouse_map opt+cmd+left       doublepress ungrabbed kitten ${KITTEN_PY} --spelling=free
CONF
    say "  config : ${CFG_DIR}/kitty.conf  (6 bindings, all live at once)"
}

write_instructions() {
    cat > "${RUN_ROOT}/INSTRUCTIONS.txt" <<'TXT'

  ============================================================
   W4 OPERATOR GATE  --  about 60 seconds, then walk away
  ============================================================

   This is a SANDBOX kitty. Nothing here touches your real
   terminal, your config, or your panes.

   There are TWO panes, stacked. DRAG THE BOTTOM ONE ONTO THE
   TOP ONE. Press inside the pane's CONTENT -- not on a title
   bar; having no title bar is the whole point.

   TRY THESE, ONE PER LINE. Press, move, release.

     1.  cmd + shift + LEFT-drag       <- the ruled default
     2.  cmd + LEFT-drag
     3.  cmd + LEFT double-press, hold on the 2nd, drag

   Those three have the DEAD BAND: kitty's drag_threshold, so
   a press that does not move does nothing. Now add opt for
   the same three WITHOUT the dead band -- the drag starts on
   the press itself:

     4.  opt + cmd + shift + LEFT-drag
     5.  opt + cmd + LEFT-drag
     6.  opt + cmd + LEFT double-press, hold, drag

   WORKING LOOKS LIKE: the pane lifts under the cursor and the
   two panes trade places when you let go.

   NOT WORKING LOOKS LIKE: nothing moves, or an error overlay
   appears in the pane.

   QUESTIONS THE HAND ANSWERS, AND NOTHING ELSE CAN:
     Q9   does it work at all, and is no-dead-band objectionable?
     Q8   is the dead band annoying in 1-3?
     Q12  which of the three chords do you actually want?
     Q10  does the kitty logo below stay put after the swap?

   When you are done, go back to the terminal you launched this
   from. It has already read the verdict and is waiting to print
   it. You do not need to judge the layout yourself.

  ============================================================
TXT
}

# ---------------------------------------------------------------------------
#  Sandbox lifecycle.  NO SIGNALS ANYWHERE (S4).
# ---------------------------------------------------------------------------
teardown_windows() {
    if sandbox_alive; then
        kit close-window --match all >/dev/null 2>&1 || true
        say "  sandbox windows closed (process left idle; S4 sends no signals)"
    else
        say "  no live sandbox on ${SOCK}"
    fi
}

launch_sandbox() {
    if sandbox_alive; then
        say "  reusing the existing sandbox on ${SOCK} (re-run safe)"
        kit close-window --match all >/dev/null 2>&1 || true
        sleep 0.4
        kit launch --type=os-window --cwd="$RUN_ROOT" \
            sh -c "cat '${RUN_ROOT}/INSTRUCTIONS.txt'; exec \$SHELL" >/dev/null
        command -v cc_log_pane_spawn >/dev/null 2>&1 && \
            cc_log_pane_spawn os-window kitty "" "$RUN_ROOT" "kitty-drag-w4 sandbox reuse sock:${SOCK}" || true
    else
        [ -S "$SOCK" ] && rm -f "$SOCK"
        env -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_WINDOW_ID \
            KITTY_CONFIG_DIRECTORY="$CFG_DIR" KITTY_CACHE_DIRECTORY="$CACHE_DIR" \
            KITTY_DRAG_LOG="$PRESS_LOG" \
            "$KITTY_BIN" --listen-on "unix:${SOCK}" --instance-group kdw4 \
            --directory "$RUN_ROOT" \
            sh -c "cat '${RUN_ROOT}/INSTRUCTIONS.txt'; exec \$SHELL" \
            >"${RUN_ROOT}/kitty.stderr" 2>&1 &
        command -v cc_log_pane_spawn >/dev/null 2>&1 && \
            cc_log_pane_spawn os-window kitty "" "$RUN_ROOT" "kitty-drag-w4 sandbox launch sock:${SOCK} bin:${KITTY_BIN}" || true
        local _i
        for _i in $(seq 1 60); do
            sandbox_alive && break
            sleep 0.25
        done
        unset _i
        sandbox_alive || die "the sandbox never came up on ${SOCK};
         see ${RUN_ROOT}/kitty.stderr"
    fi
    # The second, stacked pane. hsplit gives a top/bottom pair, measured:
    # neighbors {'bottom':[2]} / {'top':[1]}.
    kit launch --location=hsplit --cwd="$RUN_ROOT" >/dev/null
    sleep 0.4
    say "  sandbox : two stacked panes up on ${SOCK}"
}

# The Q10 subject: a real kitty graphics placement in the bottom pane.
place_graphic() {
    [ -r "$LOGO_PNG" ] || { warn "Q10: no logo image at ${LOGO_PNG}; the bottom pane
     will carry no graphic, so Q10 cannot be judged from these frames."; return 0; }
    local bottom
    bottom="$(kit ls 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin)
ids=[w["id"] for o in d for t in o["tabs"] for w in t["windows"]]
print(max(ids) if ids else "")' 2>/dev/null || true)"
    [ -n "$bottom" ] || return 0
    kit send-text --match "id:${bottom}" \
        "clear; kitten icat --align left '${LOGO_PNG}'
" >/dev/null 2>&1 || warn "Q10: could not send the icat line to pane ${bottom}"
    sleep 0.6
    say "  Q10    : kitty logo placed in pane ${bottom} (bottom)"
}

# ---------------------------------------------------------------------------
#  Verdict machinery
# ---------------------------------------------------------------------------
snapshot_to() { kit ls > "$1" 2>/dev/null; }

platform_window_id() {
    kit ls 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin)
print(d[0].get("platform_window_id","") if d else "")' 2>/dev/null || true
}

SHOT_N=0
shoot() {   # shoot <label>
    [ "$DO_SHOTS" = 1 ] || return 0
    [ -x /usr/sbin/screencapture ] || return 0
    SHOT_N=$((SHOT_N + 1))
    local f
    f="$(printf '%s/%03d-%s.png' "$SHOT_DIR" "$SHOT_N" "$1")"
    if [ -n "${PWID:-}" ]; then
        /usr/sbin/screencapture -x -o -l "$PWID" "$f" >/dev/null 2>&1 || true
    fi
    [ -s "$f" ] || { SHOT_N=$((SHOT_N - 1)); rm -f "$f" 2>/dev/null || true; return 1; }
    return 0
}

watch_for_gesture() {
    local before="$1" after="$2" deadline now tmp changed=0
    deadline=$(( $(date +%s) + WATCH_SECS ))
    tmp="${RUN_ROOT}/poll.json"
    say ""
    say "  watching the pane graph for ${WATCH_SECS}s ... go and do the gesture."
    while :; do
        now="$(date +%s)"
        [ "$now" -ge "$deadline" ] && break
        sleep 0.35
        snapshot_to "$tmp" || continue
        shoot "burst" || true
        if ! python3 "$GRAPH_PY" diff "$before" "$tmp" --expect NO-CHANGE \
             >/dev/null 2>&1; then
            cp "$tmp" "$after"
            changed=1
            shoot "first-change" || true
            sleep 1.2              # let the relayout settle, then pin the end state
            snapshot_to "$after" || true
            shoot "after" || true
            break
        fi
    done
    if [ "$changed" = 0 ]; then
        snapshot_to "$after" || true
        shoot "after-timeout" || true
    fi
    return 0
}

print_verdict() {
    local before="$1" after="$2"
    head2 "VERDICT"
    python3 "$GRAPH_PY" diff "$before" "$after" || true
    local v
    v="$(python3 "$GRAPH_PY" diff "$before" "$after" 2>/dev/null \
         | sed -n 's/^verdict=//p' | tail -1)"
    say ""
    if [ -s "$PRESS_LOG" ]; then
        say "  PRESSES: $(wc -l < "$PRESS_LOG" | tr -d " ") chord press(es) reached the kitten:"
        sed 's/^/          /' "$PRESS_LOG" | tail -12
    else
        say "  PRESSES: NONE — the kitten was never invoked, so no bound chord fired."
        say "           That is a finding about the BINDING or the press, not about the drag:"
        say "           re-check the modifiers, and that you pressed inside the pane CONTENT."
    fi
    say ""
    case "$v" in
        REORDERED)
            # ATTRIBUTION, STATED RATHER THAN ASSUMED. The differ proves the LAYOUT CHANGED
            # between two snapshots. It cannot prove WHAT changed it: a layout chord
            # (move_to_screen_edge, neighboring_window, a detach) reorders panes just as a drag
            # does, and would render this identical verdict. The instrument's whole purpose is to
            # supply the one proof a session must not manufacture, so it must not quietly upgrade
            # "a pane moved" into "the chord moved it" -- that is the same fabrication the set-test
            # ordering exists to prevent, committed one level up, in prose instead of in code.
            say "  Q9  : A PANE MOVED between the two snapshots -- which is what this"
            say "        instrument can prove. Read it as YES for route A *provided*"
            say "        the ONLY thing you did in the window was press the chord."
            say "        If you also used a layout chord, resized, or detached, the"
            say "        move is UNATTRIBUTED: re-run and press nothing else." ;;
        NO-CHANGE)
            say "  Q9  : NO GESTURE OBSERVED. The layout is byte-identical, so"
            say "        either nothing was pressed or no chord armed a drag."
            say "        Re-run; if a chord produced an ERROR OVERLAY in the pane,"
            say "        that is the finding -- capture it and stop." ;;
        SET-CHANGED)
            say "  Q9  : INCONCLUSIVE -- a pane was opened or closed during the"
            say "        window, so no adjacency change can be attributed to a"
            say "        move. This is the witness rule refusing to guess."
            say "        Re-run without opening or closing panes." ;;
        *)
            say "  Q9  : NO VERDICT -- the differ could not read its own inputs."
            say "        That is an instrument fault, not a layout answer." ;;
    esac
    say ""
    if [ "$DO_SHOTS" = 1 ] && [ "$SHOT_N" -gt 0 ]; then
        say "  Q10 : ${SHOT_N} frame(s) captured, scoped to the sandbox window only."
        say "        The before/after pair is what answers 'did the graphic survive'."
        say ""
        say "  ▶ Run this:"
        say ""
        say "  \`open ${SHOT_DIR}\`"
    elif [ "$DO_SHOTS" = 1 ]; then
        say "  Q10 : NO FRAMES CAPTURED -- /usr/sbin/screencapture produced nothing."
        say "        On macOS that is Screen Recording permission, not a bug here:"
        say "        System Settings > Privacy & Security > Screen Recording, grant"
        say "        it to the terminal you ran this from, then re-run. Q10 is"
        say "        UNANSWERED until then; nothing below infers it."
    else
        say "  Q10 : SKIPPED (--no-screenshot). Q10 is UNANSWERED."
    fi
    say ""
    say "  Q8/Q12: yours, and only yours -- which chord felt right, and whether"
    say "          the dead band on 1-3 was better or worse than its absence on"
    say "          4-6. No instrument can read that off a socket."
}

# ---------------------------------------------------------------------------
#  Dry run: build and validate everything, launch nothing.
# ---------------------------------------------------------------------------
dry_run() {
    head2 "DRY RUN -- nothing is launched, nothing is photographed"
    write_config
    write_instructions
    say ""
    say "--- generated ${CFG_DIR}/kitty.conf ---"
    sed 's/^/    /' "${CFG_DIR}/kitty.conf"
    say ""
    local n
    n="$(grep -c '^mouse_map ' "${CFG_DIR}/kitty.conf" || true)"
    say "  mouse_map lines: ${n}  (want 6 = 3 chords x 2 spellings)"
    [ "$n" = "6" ] || die "expected 6 mouse_map lines, generated ${n}"
    if grep -n '^mouse_map ' "${CFG_DIR}/kitty.conf" | grep -v 'left ' >/dev/null 2>&1; then
        die "a binding is not on LEFT; only a LEFT release clears window_being_dragged"
    fi
    say "  every binding is on LEFT: OK (the only mouse-driven clear is a LEFT release)"
    say ""
    say "  verdict reader selfcheck (synthetic, no kitty):"
    local tb ta
    tb="${RUN_ROOT}/dry_before.json"; ta="${RUN_ROOT}/dry_after.json"
    printf '%s\n' '[{"id":1,"tabs":[{"id":1,"windows":[{"id":1,"neighbors":{"bottom":[2]}},{"id":2,"neighbors":{"top":[1]}}]}]}]' > "$tb"
    printf '%s\n' '[{"id":1,"tabs":[{"id":1,"windows":[{"id":1,"neighbors":{"top":[2]}},{"id":2,"neighbors":{"bottom":[1]}}]}]}]' > "$ta"
    python3 "$GRAPH_PY" diff "$tb" "$ta" --expect REORDERED | sed 's/^/    /'
    say ""
    say "  DRY RUN CLEAN. Re-run without --dry-run to put it under a hand."
}

# ---------------------------------------------------------------------------
#  main
# ---------------------------------------------------------------------------
head2 "kitty-drag-w4 -- the W4 operator gate"
say "  repo   : ${REPO}"
say "  run dir: ${RUN_ROOT}"
say "  socket : ${SOCK}"
preflight

if [ "$DRY_RUN" = 1 ]; then
    dry_run
    exit 0
fi

select_binary
# The kitten does NOT always sit beside the kitty binary, and assuming it does made this script
# exit rc 2 the moment a real build tree appeared. An installed /Applications/kitty.app has
# kitty and kitten as literal siblings in Contents/MacOS/; a BUILD TREE's kitty/launcher/kitty
# is a SYMLINK into that same kitty.app/Contents/MacOS/, so the symlink's own directory holds
# kitty and no kitten. Resolve the link first, then fall back to the literal sibling.
_kdw4_resolved="$KITTY_BIN"
while [ -L "$_kdw4_resolved" ]; do
    _kdw4_t="$(readlink "$_kdw4_resolved")"
    case "$_kdw4_t" in
        /*) _kdw4_resolved="$_kdw4_t" ;;
        *)  _kdw4_resolved="$(cd "$(dirname "$_kdw4_resolved")" && pwd)/$_kdw4_t" ;;
    esac
done
KITTEN_BIN="$(dirname "$_kdw4_resolved")/kitten"
[ -x "$KITTEN_BIN" ] || KITTEN_BIN="$(dirname "$KITTY_BIN")/kitten"
[ -x "$KITTEN_BIN" ] || die "no kitten beside the kitty binary or its resolved target: ${KITTEN_BIN}"
say "  kitten : ${KITTEN_BIN}"
prove_identity

if [ "$TEARDOWN_ONLY" = 1 ]; then
    teardown_windows
    exit 0
fi

write_config
write_instructions
launch_sandbox
place_graphic

PWID="$(platform_window_id)"
BEFORE="${RUN_ROOT}/before.json"
AFTER="${RUN_ROOT}/after.json"
snapshot_to "$BEFORE" || die "could not read the baseline pane graph"
shoot "before" || warn "Q10: the before frame did not capture (see the Q10 note below)"

head2 "GO -- the sandbox window is up and says what to press"
python3 "$GRAPH_PY" snapshot --ls "$BEFORE" --out "${RUN_ROOT}/before.graph.json" \
    | sed 's/^/  /'

watch_for_gesture "$BEFORE" "$AFTER"
print_verdict "$BEFORE" "$AFTER"

say ""
say "  the sandbox is still up. close it with:"
say "      ${BASH_SOURCE[0]} --teardown"
