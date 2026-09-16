#!/usr/bin/env python3
# ============================================================================
#  kitty-drag-window.py — DELIVERABLE A, the config-only prototype kitten
#  (KITTY_DRAG_ACTION.md wave W2; research § 3.3 + ruling Q2)
#
#  WHAT IT IS.  A kitty `no_ui` custom kitten that ARMS A WINDOW DRAG from an
#  arbitrary mouse chord, so a press anywhere in a pane's CONTENT AREA can do
#  what kitty today only does from a press inside its own drawn title bar.
#  It is the config-only route: no patched kitty, no rebuild, one file plus one
#  `mouse_map` line.
#
#  ── TARGET BUILD ──────────────────────────────────────────────────────────
#  kitty **v0.48.2** — the operator's shipped /Applications/kitty.app build,
#  and the tree at /private/tmp/kitty-482 (git 2cb1d95 "version 0.48.2").
#  It is NOT written against master (1d67ecd), and the difference is load
#  bearing in exactly one place, spelling (ii):
#      0.48.2  request_callback_with_thumbnail("start_window_drag", osw, wid)
#              -> C signature "sK|KpdI"   (6 args)   state.c:1781
#      master  request_callback_with_thumbnail(..., no_scaling)
#              -> C signature "sK|KpdIp"  (7 args)   state.c:2017
#      master also adds Boss.request_thumbnail(), which is ABSENT from 0.48.2.
#  We call the 6-arg 0.48.2 spelling with 3 positional args and never touch
#  Boss.request_thumbnail.  Never verify your build with `--version`: master
#  at 1d67ecd still self-reports 0.48.2.  Use instead:
#      kitty +runpy 'import kitty; print(kitty.__file__)'
#
#  ── THE SWITCH: WHICH ARMING SPELLING ─────────────────────────────────────
#  One flag, passed on the `mouse_map` line, selects between the two designs
#  ruled in Q2.  `--spelling=preserving` is the default.
#
#    --spelling=preserving   (i) THRESHOLD-PRESERVING.  Installs a wrapper on
#        `boss.handle_window_title_bar_mouse` (a plain instance attribute on a
#        class with no __slots__, which C re-resolves by PyObject_GetAttr on
#        EVERY event, mouse.c:935 -> state.h:543 call_boss), captures the FIRST
#        delivered (x, y) PIXEL pair as the drag origin, and calls
#        `set_window_being_dragged(wid, False, x, y)`.  kitty's own stock
#        threshold arithmetic at tabs.py:1855-1863 then does the rest, so
#        `drag_threshold` keeps working and a press with no movement does NOT
#        begin a drag.  Measured on the shipped 0.48.2 (V25, reproduced by this
#        file's own --selftest): 3 px no trip, 4 px no trip, 9 px TRIPS,
#        against drag_threshold 5.
#        Residual, small and real: because our band is not in kitty's hit test,
#        the PRESS itself is never routed to the title-bar handler, so the
#        captured origin is the pointer at the first MOTION event after the
#        press — about one motion sample at gesture onset, where hand velocity
#        is near zero.
#
#    --spelling=free         (ii) THRESHOLD-FREE.  Calls
#        `set_window_being_dragged(wid, True, 0, 0)` and then
#        `request_callback_with_thumbnail("start_window_drag", osw_id, wid)` —
#        the identical call kitty itself makes at v0.48.2 tabs.py:1862 once its
#        own threshold has been crossed.  The drag begins ON THE PRESS with no
#        dead zone.  Because nothing reads .x/.y once drag_started is True, the
#        (0, 0) coordinates are dead state and their coordinate space is
#        irrelevant.  This spelling deliberately IGNORES `drag_threshold`,
#        which documents itself as "A value of zero disables all dragging" —
#        that is the objection Q2 records against it, and the reason W4 puts
#        both spellings under a human hand before one is chosen.
#
#  ── THE FOUR GUARDS, AND WHY EACH ONE EXISTS ──────────────────────────────
#  G1  THE FOUR-PARAMETER HANDLER SIGNATURE, WINDOW ID **THIRD**.
#      `kittens/runner.py:95` binds the arg list first —
#      `partial(handle_result, [kitten] + orig_args)` — and `Boss` then calls
#      `end_kitten.handle_result(None, w.id, self)` (boss.py:2325).  So the
#      file-level signature is (args, answer, target_window_id, boss).  Writing
#      the plausible (args, wid, boss) raises TypeError at PRESS time, and
#      `Boss.combine` (boss.py:1923-1927) converts that into
#      show_error('Key action failed', ...) — A POPUP ON EVERY PRESS, with no
#      visible stack trace to diagnose it by.
#  G2  THE FILE MUST STILL DEFINE main().
#      `import_kitten_main_module` does a bare `g['main']` subscript
#      (runner.py:65) BEFORE anything looks at `no_ui`.  A handler-only file
#      therefore raises KeyError at press time and opens an error overlay;
#      the handler never runs at all (measured, V27).  main() here is
#      deliberately unreachable in the no_ui path and says so if ever run.
#  G3  GUARD THE None FROM current_mouse_position().
#      It returns Py_RETURN_NONE on a window-lookup miss (v0.48.2 state.c:1745
#      / master state.c:1979).  A naive `pos['cell_y'] < rows` then raises
#      TypeError -> the same "Key action failed" popup on EVERY press (V28).
#      Note also that it is CELL resolution only — {cell_x, cell_y,
#      in_left_half_of_cell} — so a row-band gate is all route A can express.
#  G4  REFUSE TO ARM WHEN drag_threshold == 0.
#      kitty's promotion test is `if threshold and dist_sq > threshold**2`
#      (v0.48.2 tabs.py:1860).  At 0 it can NEVER pass, so spelling (i) would
#      set window_being_dragged and nothing would ever promote it — and there
#      is NO C-side clear of that flag anywhere in either tree (positive
#      controlled against the tab equivalent zero_at_ptr(&tab_being_dragged) at
#      v0.48.2 mouse.c:951).  The ONLY mouse-driven clear is a **LEFT**
#      release, below the `if button != GLFW_MOUSE_BUTTON_LEFT: return` at
#      tabs.py:1866.  A flag left set routes every mouse event in every OS
#      window to the title-bar handler — killing selection, URL detection,
#      border resize and click dispatch fleet-wide — and the next bare pointer
#      move past drag_threshold starts a REAL system drag with no button held.
#      That is one keystroke from a wedge, so we decline instead.
#
#  ── BIND **LEFT** ONLY, AND NEVER HARDCODE A MOD INTEGER ──────────────────
#  The clear above is LEFT-only, so any chord bound on another button arms a
#  flag that no release can clear.  A no_ui kitten is not told which button
#  fired it, so this is a CONFIG-SIDE obligation and it is stated here because
#  this file is where a reader looks:
#
#      mouse_map ctrl+shift+left press ungrabbed kitten kitty-drag-window.py --spelling=preserving
#
#  And kitty's GLFW mods are NOT stock GLFW — SHIFT 0x1, ALT 0x2, CONTROL 0x4,
#  SUPER 0x8 (glfw/glfw3.h:487,492,497,502).  This file never writes a mod or
#  button integer: every one it uses is imported by NAME from
#  kitty.fast_data_types, which is the source of truth for the running build.
#
#  ── THE EXACT SANDBOX INVOCATION THAT PROVED IT ───────────────────────────
#  Reproducible from scratch; it writes nothing outside /tmp/kdw2 and never
#  addresses the operator's kitty (every command drops KITTY_LISTEN_ON /
#  KITTY_PID / KITTY_WINDOW_ID, uses its own KITTY_CONFIG_DIRECTORY, and puts
#  its socket OUTSIDE the /tmp/kitty-* glob that bin/cc-kitty-socket scans).
#
#    mkdir -p /tmp/kdw2/config /tmp/kdw2/cache /tmp/kdw2/logs
#    printf 'allow_remote_control yes\nlisten_on unix:/tmp/kdw2.sock\n%s\n' \
#      'confirm_os_window_close 0' > /tmp/kdw2/config/kitty.conf
#    env -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_WINDOW_ID \
#        KITTY_CONFIG_DIRECTORY=/tmp/kdw2/config KITTY_CACHE_DIRECTORY=/tmp/kdw2/cache \
#      /private/tmp/kitty-482/kitty/launcher/kitty \
#        --listen-on unix:/tmp/kdw2.sock --instance-group kdw2 \
#        2>/tmp/kdw2/logs/kitty.stderr &
#
#    # which build am I actually running?  NEVER --version.
#    env -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_WINDOW_ID \
#      /private/tmp/kitty-482/kitty/launcher/kitty +runpy \
#      'import kitty; print(kitty.__file__)'
#
#    # the proof: run this file's selftest THROUGH the real kitten dispatch
#    env -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_WINDOW_ID \
#      /private/tmp/kitty-482/kitty/launcher/kitten @ --to unix:/tmp/kdw2.sock \
#      kitten /Users/chrisren/Development/.worktrees/kitty-drag-impl/scripts/kitty-drag-window.py --selftest
#
#  --selftest is SANDBOX-ONLY scaffolding.  It stubs
#  kitty.tabs.request_callback_with_thumbnail with a recorder so that NO real
#  platform drag-and-drop can start, synthesises the exact C delivery
#  mouse.c:935 makes (`boss.handle_window_title_bar_mouse(osw, wid, x, y,
#  button, mods, action)`), prints get_window_being_dragged() BEFORE and AFTER
#  each spelling, and ALWAYS clears the flag in a finally block.  It is never
#  reached unless --selftest is passed explicitly.
#
#  ── WHAT THIS FILE CANNOT DO (route A's hard limits, research § 3.4) ──────
#  * It cannot change the pointer shape — there is no per-region shape API.
#  * It cannot DECLINE a press: Boss.kitten (boss.py:2405-2406) discards
#    run_kitten_with_metadata's return, so `dispatch_action`'s passthrough is
#    always None and the press is ALWAYS consumed.  A guard here makes the
#    ACTION inert; it does not give the chord's default back to the program.
#    Never gate SAFETY on this file's return value.
#  * It cannot read active_drag_in_window / tracked_drag_in_window /
#    active_drag_resize — no Python getter exists for any of them.
#  * It pays a file read + compile + exec on EVERY press (runner.py:53-66,
#    no cache): measured 0.1945 ms per invocation.
# ============================================================================

from typing import Any

# kitty's DOCUMENTED decorator (v0.48.2 docs/kittens/custom.rst:177-179).  It
# returns a HandleResult whose own __call__ is
#     (self, args, data, target_window_id, boss)      kittens/tui/handler.py:335
# i.e. upstream's own signature is the four-parameter one, window id THIRD.
# The equivalent `handle_result.no_ui = True` also works — create_kitten_handler
# only does getattr(handle_result, 'no_ui', False) at runner.py:99 — but the
# decorator is the documented spelling and is what W5's upstream reviewer will
# expect.  Cost: this import runs on every press (runner.py:53-66 re-execs the
# file, no cache), but kittens.tui.handler is already in sys.modules after the
# first one, so it is a dict lookup thereafter.
from kittens.tui.handler import result_handler

# ---------------------------------------------------------------------------
# G2: import_kitten_main_module does a BARE g['main'] subscript (runner.py:65)
# before it ever looks at no_ui.  Without this def, every press raises KeyError
# and opens an error overlay.  It is unreachable on the no_ui path.
# ---------------------------------------------------------------------------
def main(args: list[str]) -> None:
    raise SystemExit(
        'kitty-drag-window.py is a no_ui kitten: it is dispatched from a '
        'mouse_map line and has no command-line UI.  It is present only '
        'because kittens/runner.py:65 subscripts g["main"] unconditionally.'
    )


# --------------------------------------------------------------------------
# Argument parsing.  Deliberately hand-rolled: argparse in a per-press hot
# path costs more than the whole rest of this file, and the grammar is three
# flags.  `args[0]` is the kitten name that runner.py:95 prepends.
# --------------------------------------------------------------------------
_SPELLINGS = ('preserving', 'free')


def _parse(args: list[str]) -> dict[str, Any]:
    opts: dict[str, Any] = {'spelling': 'preserving', 'rows': 0, 'selftest': False}
    for a in list(args)[1:]:
        if a.startswith('--spelling='):
            v = a.split('=', 1)[1]
            if v not in _SPELLINGS:
                raise ValueError(f'--spelling must be one of {_SPELLINGS}, got {v!r}')
            opts['spelling'] = v
        elif a.startswith('--rows='):
            opts['rows'] = int(a.split('=', 1)[1])
        elif a == '--selftest':
            opts['selftest'] = True
        elif a in ('--preserving', '--free'):
            opts['spelling'] = a[2:]
    return opts


# ===========================================================================
#  THE ARMING PRIMITIVES
# ===========================================================================
#
# _THUMBNAIL_CALL is an indirection, not decoration.  Spelling (ii) really does
# start a platform drag-and-drop; --selftest replaces this global with a
# recorder so a sandbox proof cannot put a real drag on the operator's desktop.
# The kitten module is re-exec'd on every press (runner.py:53-66, no cache), so
# this global cannot leak across presses even in principle.
_THUMBNAIL_CALL = None   # None => resolve the real 0.48.2 symbol at call time

_WRAPPER_MARKER = 'kitty-drag-window/threshold-preserving/v1'


def _install_origin_wrapper(boss: Any, wid: int) -> str:
    """Spelling (i).  Install (idempotently) a wrapper on
    boss.handle_window_title_bar_mouse and mark `wid` as awaiting an origin.

    WHY A WRAPPER AND NOT A DIRECT CALL.  The origin kitty's threshold needs is
    an OS-window PIXEL pair, and there is NO PULL ACCESSOR for it anywhere in
    either ref (whole-C-tree grep: 89 Py_BuildValue sites in 0.48.2, zero
    mentioning mouse_x/mouse_y/global_x/global_y).  The coordinates arrive only
    by PUSH, as the arguments of
        call_boss(handle_window_title_bar_mouse, "KKddiii",
                  osw->id, w->id, osw->mouse_x, osw->mouse_y, ...)
    at v0.48.2 mouse.c:935.  Boss has no __slots__ and PyObject_CallMethod
    re-resolves the attribute by PyObject_GetAttr on every event, so a plain
    instance attribute intercepts the real pixels.

    WHY WE ALSO SET A SENTINEL FIRST.  mouse.c:930 only delivers at all when
        button > -1 || global_state.window_being_dragged.id
    so with the flag clear, NO motion event is ever routed here and the wrapper
    would never fire.  The caller therefore arms a sentinel (0, 0) immediately
    afterwards; the wrapper's whole job is to REWRITE that sentinel with the
    true pixels on the first delivered motion and RETURN WITHOUT CALLING
    THROUGH, so kitty's threshold test at tabs.py:1856-1863 never sees the
    sentinel.  Letting the sentinel reach that test is the measured failure
    (V25 ARM A): first motion at (600, 400) vs origin (0, 0) trips instantly.
    """
    from kitty.fast_data_types import set_window_being_dragged

    cur = getattr(boss, 'handle_window_title_bar_mouse', None)
    if getattr(cur, 'kdw_marker', None) == _WRAPPER_MARKER:
        # Ours already; a second wrapper would stack a new closure on every
        # press for the life of the process.  Just re-arm the capture.
        cur.kdw_state['pending_wid'] = wid
        return 'rearmed'

    orig = cur

    def wrapper(os_window_id: int, window_id: int, x: float, y: float,
                button: int, modifiers: int, action: int) -> Any:
        st = wrapper.kdw_state
        pending = st.get('pending_wid')
        if button == -1:                      # -1 is kitty's motion sentinel
            if pending:
                st['pending_wid'] = None
                st['last_origin'] = (float(x), float(y))
                set_window_being_dragged(pending, False, float(x), float(y))
                return None
        else:
            # ANY button event retires a stale capture.  Without this the
            # wrapper stays hungry after a declined press and would hijack the
            # origin of kitty's OWN title-bar drag (whose press arms the flag
            # at tabs.py:1872, after which motion IS delivered here), silently
            # resetting that drag's threshold origin to the current pointer.
            # Bounds staleness to the gap between our press and the next
            # delivered motion.
            st['pending_wid'] = None
        return orig(os_window_id, window_id, x, y, button, modifiers, action)

    wrapper.kdw_marker = _WRAPPER_MARKER
    wrapper.kdw_state = {'pending_wid': wid, 'last_origin': None, 'orig': orig}
    boss.handle_window_title_bar_mouse = wrapper
    return 'installed'


def _arm(boss: Any, wid: int, spelling: str, rows: int) -> str:
    """Do the four guards, then arm.  Returns a short reason string; the
    return value is DIAGNOSTIC ONLY — Boss.kitten (boss.py:2405-2406) throws
    away run_kitten_with_metadata's result, so nothing here can decline a
    press.  Never gate safety on it."""
    from kitty.fast_data_types import (
        get_options, set_window_being_dragged, request_callback_with_thumbnail,
    )

    def decline(reason: str) -> str:
        # A declined press must not leave the wrapper hungry (see wrapper).
        h = getattr(boss, 'handle_window_title_bar_mouse', None)
        if getattr(h, 'kdw_marker', None) == _WRAPPER_MARKER:
            h.kdw_state['pending_wid'] = None
        return f'declined:{reason}'

    w = boss.window_id_map.get(wid)
    if w is None:
        return decline('no-such-window')

    # ---- G3: current_mouse_position() returns None on a window-lookup miss
    #      (v0.48.2 state.c:1745).  Cell resolution only.
    if rows > 0:
        pos = w.current_mouse_position()
        if pos is None:
            return decline('no-mouse-position')
        if pos['cell_y'] >= rows:
            return decline('outside-band')

    # ---- G4: drag_threshold == 0.  For (i) the promotion test
    #      `if threshold and dist_sq > threshold*threshold` (tabs.py:1860) can
    #      never pass, so the flag would be set with no way to promote it and
    #      only a LEFT release to clear it.  For (ii) the flag WOULD promote,
    #      but `drag_threshold` documents itself as "A value of zero disables
    #      all dragging" and an action that silently ignores a documented
    #      option is a defect in its own right.  Both spellings decline.
    if int(get_options().drag_threshold) == 0:
        return decline('drag-threshold-is-zero')

    if spelling == 'preserving':
        how = _install_origin_wrapper(boss, wid)
        # The sentinel is what makes mouse.c:930 start delivering motion at
        # all.  The wrapper rewrites it before kitty's threshold sees it.
        set_window_being_dragged(wid, False, 0.0, 0.0)
        return f'armed:preserving:{how}'

    if spelling == 'free':
        set_window_being_dragged(wid, True, 0.0, 0.0)
        call = _THUMBNAIL_CALL or request_callback_with_thumbnail
        # 0.48.2 spelling: 6-arg "sK|KpdI" (state.c:1781), 3 given positionally.
        # This is the identical call kitty makes at v0.48.2 tabs.py:1862.
        # Do NOT use Boss.request_thumbnail — master-only, absent here.
        call('start_window_drag', w.os_window_id, wid)
        return 'armed:free'

    return decline(f'unknown-spelling:{spelling}')


# ===========================================================================
#  G1 — THE HANDLER.  FOUR parameters, window id THIRD.
#
#  runner.py:95   partial(handle_result, [kitten] + orig_args)   <- args bound
#  boss.py:2325   end_kitten.handle_result(None, w.id, self)     <- 3 more
#  => (args, answer, target_window_id, boss)
#
#  Writing (args, wid, boss) raises TypeError at PRESS time and Boss.combine
#  (boss.py:1923-1927) renders it as show_error('Key action failed', ...) —
#  a popup on every press, no stack trace.  DO NOT "simplify" this signature.
# ===========================================================================
@result_handler(no_ui=True)
def handle_result(args: list[str], answer: str, target_window_id: int, boss: Any) -> Any:
    try:
        opts = _parse(args)
    except Exception as e:
        # A malformed mouse_map line must never become a popup on every press.
        return f'kitty-drag-window: bad arguments: {e}'
    if opts['selftest']:
        return _selftest(target_window_id, boss, opts, answer)
    return _arm(boss, target_window_id, opts['spelling'], opts['rows'])



# ===========================================================================
#  --selftest — SANDBOX SCAFFOLDING ONLY.  Never reached without the flag.
#  Returns a JSON string, which kitty/rc/kitten.py:41-43 prints to the remote
#  control client's stdout, so the proof needs no file and no log scraping.
# ===========================================================================
_MISSING = object()


def _selftest(target_window_id: int, boss: Any, opts: dict[str, Any], answer: Any) -> str:
    import json
    import traceback
    global _THUMBNAIL_CALL

    out: dict[str, Any] = {'stage': 'enter', 'guards': {}, 'arms': {}}
    saved_handler: Any = _MISSING
    saved_tabs_rcwt: Any = _MISSING
    try:
        import kitty
        import kitty.tabs as T
        from kitty.fast_data_types import (
            GLFW_MOUSE_BUTTON_LEFT, GLFW_MOD_ALT, GLFW_MOD_CONTROL,
            GLFW_MOD_SHIFT, GLFW_MOD_SUPER, dnd_test_set_mouse_pos,
            get_options, get_window_being_dragged, set_window_being_dragged,
        )

        # ---- build identity.  NEVER --version: master 1d67ecd also says 0.48.2
        out['build_kitty_file'] = kitty.__file__
        out['str_version'] = __import__('kitty.constants', fromlist=['x']).str_version

        # ---- G1/G2 are proven by arrival: this code is running at all, which
        #      means g['main'] existed (runner.py:65) and the 4-arg partial
        #      call bound cleanly (boss.py:2325).
        out['guards']['G1_signature'] = {
            'target_window_id': target_window_id,
            'type': type(target_window_id).__name__,
            'answer': repr(answer),
        }
        out['guards']['G2_main_defined'] = callable(main)

        # ---- mods read from the build, never hardcoded
        out['glfw_mods_from_source'] = {
            'SHIFT': GLFW_MOD_SHIFT, 'ALT': GLFW_MOD_ALT,
            'CONTROL': GLFW_MOD_CONTROL, 'SUPER': GLFW_MOD_SUPER,
            'MOUSE_BUTTON_LEFT': GLFW_MOUSE_BUTTON_LEFT,
        }

        w = boss.window_id_map.get(target_window_id)
        if w is None:
            out['fatal'] = 'no window for target_window_id'
            return json.dumps(out, indent=1, default=str)
        osw_id = w.os_window_id
        out['wid'] = w.id
        out['os_window_id'] = osw_id
        out['drag_threshold'] = get_options().drag_threshold

        # ---- NOTHING BELOW MAY START A REAL PLATFORM DRAG.  Two call sites
        #      reach one: our own spelling (ii), and kitty's OWN promotion at
        #      tabs.py:1862 when spelling (i) crosses the threshold.  Stub both.
        trips: list[Any] = []
        saved_tabs_rcwt = T.request_callback_with_thumbnail
        T.request_callback_with_thumbnail = lambda *a, **k: trips.append(('tabs', a))
        _THUMBNAIL_CALL = lambda *a, **k: trips.append(('kitten', a))

        # ---- save/restore the handler so ARM A runs genuinely unwrapped even
        #      if a prior chord press already installed our wrapper.
        saved_handler = boss.__dict__.get('handle_window_title_bar_mouse', _MISSING)
        out['wrapper_present_at_entry'] = (
            getattr(saved_handler, 'kdw_marker', None) == _WRAPPER_MARKER
        )

        def C(x: float, y: float, button: int = -1, mods: int = 0, action: int = 0) -> None:
            """Exactly what v0.48.2 mouse.c:935 does:
            call_boss(handle_window_title_bar_mouse, "KKddiii",
                      osw->id, w->id, osw->mouse_x, osw->mouse_y,
                      button, modifiers, action)"""
            boss.handle_window_title_bar_mouse(
                osw_id, w.id, float(x), float(y), button, mods, action)

        def state() -> list[Any]:
            return list(get_window_being_dragged())

        # ================= G3: the None from current_mouse_position =========
        g3: dict[str, Any] = {}
        g3['live_read'] = w.current_mouse_position()
        dnd_test_set_mouse_pos(w.id, 5, 0, 100, 4)
        g3['after_place_row0'] = w.current_mouse_position()
        g3['band_rows1_row0_accepts'] = _arm_dry(boss, w.id, rows=1)
        dnd_test_set_mouse_pos(w.id, 5, 9, 100, 240)
        g3['after_place_row9'] = w.current_mouse_position()
        g3['band_rows1_row9_declines'] = _arm_dry(boss, w.id, rows=1)
        # the genuine None arm: a window id that does not exist
        from kitty.fast_data_types import get_mouse_data_for_window
        g3['negative_control_none'] = get_mouse_data_for_window(
            osw_id, w.tab_id, w.id + 99999)
        out['guards']['G3_mouse_position'] = g3

        # ================= G4: drag_threshold == 0 ==========================
        o = get_options()
        real_threshold = o.drag_threshold
        g4: dict[str, Any] = {'real_threshold': real_threshold}
        try:
            object.__setattr__(o, 'drag_threshold', 0)
            g4['with_threshold_0_preserving'] = _arm(boss, w.id, 'preserving', 0)
            g4['with_threshold_0_free'] = _arm(boss, w.id, 'free', 0)
            g4['state_after_declines'] = state()
        finally:
            object.__setattr__(o, 'drag_threshold', real_threshold)
        g4['restored_threshold'] = get_options().drag_threshold
        out['guards']['G4_threshold_zero'] = g4

        # ================= ARM A (CONTROL): the naive route =================
        # Sentinel origin (0,0) with NO wrapper: kitty's own threshold compares
        # the first delivered motion against (0,0) and trips instantly.  This
        # arm must FAIL for ARM B's pass to carry information.
        if 'handle_window_title_bar_mouse' in boss.__dict__:
            del boss.__dict__['handle_window_title_bar_mouse']
        trips.clear()
        set_window_being_dragged(w.id, False, 0.0, 0.0)
        before_a = state()
        C(600.0, 400.0)
        out['arms']['A_control_naive_sentinel'] = {
            'before': before_a, 'after': state(), 'trips': len(trips),
            'expect': 'drag_started True and trips 1 — the failure mode',
        }
        set_window_being_dragged()

        # ================= ARM B: spelling (i) threshold-preserving =========
        trips.clear()
        before_b = state()
        armed_b = _arm(boss, w.id, 'preserving', 0)
        seq: list[dict[str, Any]] = []
        C(600.0, 400.0)  # first motion -> wrapper captures the true origin
        seq.append({'step': 'capture(600,400)', 'state': state(), 'trips': len(trips)})
        C(603.0, 400.0)  # 3 px  -> UNDER drag_threshold 5
        seq.append({'step': 'move 3px', 'state': state(), 'trips': len(trips)})
        C(600.0, 404.0)  # 4 px  -> UNDER
        seq.append({'step': 'move 4px', 'state': state(), 'trips': len(trips)})
        C(609.0, 400.0)  # 9 px  -> OVER, must trip
        seq.append({'step': 'move 9px', 'state': state(), 'trips': len(trips)})
        out['arms']['B_preserving'] = {
            'before': before_b, 'arm_returned': armed_b, 'sequence': seq,
            'after': state(), 'trips_total': len(trips),
            'expect': '3px/4px no trip, 9px trips, origin (600,400) not (0,0)',
        }
        set_window_being_dragged()

        # ================= ARM C: spelling (ii) threshold-free ==============
        trips.clear()
        before_c = state()
        armed_c = _arm(boss, w.id, 'free', 0)
        out['arms']['C_free'] = {
            'before': before_c, 'arm_returned': armed_c, 'after': state(),
            'thumbnail_calls': [list(t[1]) for t in trips], 'trips': len(trips),
            'expect': 'drag_started True immediately + exactly one thumbnail call',
        }
        set_window_being_dragged()

        # ================= LEFT-only clear, positive + negative control =====
        clears: dict[str, Any] = {}
        for name, btn in (('LEFT', GLFW_MOUSE_BUTTON_LEFT), ('MIDDLE', 2), ('RIGHT', 1)):
            set_window_being_dragged(w.id, False, 10.0, 20.0)
            # action 0 == GLFW_RELEASE
            C(10.0, 20.0, button=btn, mods=0, action=0)
            clears[name] = state()
        set_window_being_dragged()
        out['left_only_clear'] = clears
        out['final_state'] = state()
        out['ok'] = True
    except Exception:
        out['error'] = traceback.format_exc()
    finally:
        try:
            from kitty.fast_data_types import set_window_being_dragged as _clr
            _clr()                       # never leave the wedge armed
        except Exception:
            pass
        _THUMBNAIL_CALL = None
        if saved_tabs_rcwt is not _MISSING:
            import kitty.tabs as _T
            _T.request_callback_with_thumbnail = saved_tabs_rcwt
        if saved_handler is _MISSING:
            boss.__dict__.pop('handle_window_title_bar_mouse', None)
        else:
            boss.handle_window_title_bar_mouse = saved_handler
    return json.dumps(out, indent=1, default=str)


def _arm_dry(boss: Any, wid: int, rows: int) -> str:
    """Run ONLY the band half of _arm's guards, with no side effect, so the
    selftest can exercise G3 without arming anything."""
    w = boss.window_id_map.get(wid)
    if w is None:
        return 'declined:no-such-window'
    pos = w.current_mouse_position()
    if pos is None:
        return 'declined:no-mouse-position'
    if rows > 0 and pos['cell_y'] >= rows:
        return 'declined:outside-band'
    return 'would-arm'


# ===========================================================================
#  MEASURED — the proof, run 2026-09-16 in the sandbox described in the header
# ===========================================================================
#  Build actually under test, read from INSIDE the running instance (never
#  --version):  kitty.__file__ = /private/tmp/kitty-482/kitty/__init__.py,
#  str_version = 0.48.2, git 2cb1d95 "version 0.48.2".  drag_threshold = 5.
#  Sandbox kitty stderr for the WHOLE session: 0 bytes.  No traceback anywhere.
#
#  THE CONFIG LINE BINDS LEFT ONLY, AND THE MODS COME FROM kitty's OWN PARSER
#    load_config('/tmp/kdw2/config/kitty.conf').mousemap ->
#      MouseEvent(button=0, mods=5, repeat_count=1, grabbed=False)
#        = 'kitten .../kitty-drag-window.py --spelling=preserving'
#    button 0 == GLFW_MOUSE_BUTTON_LEFT;  mods 5 == SHIFT 0x1 | CONTROL 0x4,
#    i.e. kitty's numbering, NOT stock GLFW's (where CONTROL would be 0x2).
#    Read from the build at run time: SHIFT 1 ALT 2 CONTROL 4 SUPER 8 LEFT 0.
#
#  GUARDS — each with the control that proves it is not decorative.  The three
#  negative controls are sibling files in /tmp/kdw2, dispatched through the
#  SAME path; the error text below is what Boss.combine converts into
#  show_error('Key action failed', ...) on the mouse path, because window.py:1402
#  calls combine with raise_error defaulting to False (rc/action.py:69 passes
#  raise_error=True, which is why the remote client saw the raw text).
#    G1  ours          -> handler ran, target_window_id=1 (int), answer=None
#        neg_g1_wrongsig.py, def handle_result(args, wid, boss):
#                      -> Error: handle_result() takes 3 positional arguments
#                                but 4 were given
#    G2  ours          -> main defined
#        neg_g2_nomain.py, handler-only file
#                      -> Error: 'main'          (the bare g['main'] KeyError)
#    G3  ours          -> pointer parked at cell_y 0 with --rows=1 : would-arm
#                         pointer parked at cell_y 9 with --rows=1 : declined
#                         get_mouse_data_for_window(osw, tab, wid+99999): None
#        neg_g3_nonone.py, unguarded pos['cell_y']
#                      -> Error: 'NoneType' object is not subscriptable
#    G4  drag_threshold forced to 0 ->
#          preserving : declined:drag-threshold-is-zero
#          free       : declined:drag-threshold-is-zero
#          window_being_dragged after both declines: (0, False, 0.0, 0.0)
#          threshold restored to 5 afterwards
#
#  ARM A — CONTROL, the naive route (sentinel origin, NO wrapper).  This arm
#  must FAIL or ARM B's pass carries no information:
#      before (1, False, 0.0, 0.0) -> first motion at (600,400)
#      after  (1, True,  0.0, 0.0)   thumbnail trips 1   <- trips instantly
#
#  ARM B — SPELLING (i) THRESHOLD-PRESERVING, get_window_being_dragged()
#  before and after, against drag_threshold 5:
#      before                     (0, False,   0.0,   0.0)
#      _arm(...) returned         armed:preserving:installed
#      capture (600,400)          (1, False, 600.0, 400.0)   trips 0
#      move 3 px                  (1, False, 600.0, 400.0)   trips 0
#      move 4 px                  (1, False, 600.0, 400.0)   trips 0
#      move 9 px                  (1, TRUE,  600.0, 400.0)   trips 1
#  i.e. kitty's stock threshold is preserved exactly, and the origin is the
#  real delivered pixel pair, not the (0, 0) sentinel.
#
#  ARM C — SPELLING (ii) THRESHOLD-FREE:
#      before                     (0, False, 0.0, 0.0)
#      _arm(...) returned         armed:free
#      after                      (1, TRUE,  0.0, 0.0)
#      thumbnail calls            [('start_window_drag', 1, 1)]   exactly one
#  and, separately, with the REAL C symbol instead of the recorder and only
#  Boss.start_window_drag stubbed (so the platform DND could not begin):
#      request_callback_with_thumbnail('start_window_drag', 1, 1)
#        -> accepted 3 positional args, no TypeError
#        -> C called back Boss.start_window_drag(os_window_id=1, window_id=1,
#                                      pixels=254400 bytes, width=318, height=200)
#  which is the 0.48.2 "sK|KpdI" arity exercised for real.  Controls on the
#  same run: Boss.request_thumbnail False (master-only, as expected) ·
#  Boss.start_window_drag True (positive control) ·
#  Boss.definitely_not_real_xyz False (negative control).
#
#  LEFT-ONLY CLEAR, positive and negative controls in one sweep — arm
#  (1, False, 10.0, 20.0) then deliver a RELEASE of each button:
#      LEFT   -> (0, False,  0.0,  0.0)     cleared
#      MIDDLE -> (1, False, 10.0, 20.0)     untouched
#      RIGHT  -> (1, False, 10.0, 20.0)     untouched
#  This is why the mouse_map line must bind LEFT: on any other button the flag
#  is armed with nothing able to clear it.
#
#  PRODUCTION PATH (not the selftest) through the real mouse_map dispatch
#  `kitten @ action "kitten <this file> --spelling=preserving"`, rc 0:
#      state (1, False, 0.0, 0.0), wrapper marker installed, pending_wid 1
#      armed twice in a row -> still exactly one wrapper (idempotent)
#      with --rows=1 and the pointer at cell_y 9 -> state stayed (0, False, 0, 0)
#
#  🚨 WHAT WAS **NOT** DRIVEN, stated rather than hidden:
#  * NO REAL MOUSE PRESS.  There is no headless lever for a button press;
#    `dnd_test_set_mouse_pos` is the only pointer lever and it writes
#    w->mouse_pos alone (dnd.c:2457-2468), touching no drag_source field.  The
#    motion events above were synthesised by calling
#    boss.handle_window_title_bar_mouse(osw, wid, x, y, button, mods, action)
#    directly — byte-for-byte the call v0.48.2 mouse.c:935 makes via
#    call_boss(..., "KKddiii").  The dispatch half WAS driven for real, through
#    Boss.combine -> dispatch_action -> Boss.kitten -> run_kitten_with_metadata;
#    what is simulated is the mouse event, not the kitten machinery.
#  * NO REAL PLATFORM DRAG-AND-DROP.  Both call sites that can start one
#    (ours in spelling (ii), and kitty's own promotion at tabs.py:1862 when
#    spelling (i) crosses the threshold) were stubbed for every measurement.
#    An unstubbed spelling (ii) would begin a macOS NSDraggingSession with no
#    button held, on the operator's live desktop.  That is W4's hand-gate, not
#    a thing to run headlessly.
#  * `kitten @ action` reaches combine with raise_error=True, so it reports the
#    exception text; the mouse path uses the default False and therefore shows
#    the popup instead.  The exception is measured; the popup is read off
#    boss.py:1925-1927.
# ===========================================================================
#
#  ADDENDUM — SECOND, INDEPENDENT REPLICATION AFTER SWITCHING TO THE
#  DOCUMENTED @result_handler(no_ui=True) DECORATOR.
#  The first run above used the equivalent `handle_result.no_ui = True`
#  (what create_kitten_handler actually reads, runner.py:99).  Switching to the
#  documented decorator changed nothing, and the re-run landed on a FRESH OS
#  window (id 2 instead of id 1), so it is a genuine second replication rather
#  than a repeat of one state:
#      G1 target_window_id 2 (int), answer None      G2 main defined True
#      G3 row0 would-arm · row9 declined:outside-band · neg-ctrl None
#      G4 both spellings declined:drag-threshold-is-zero, state (0,False,0,0)
#      ARM A control   (2,False,0,0) -> (2,True,0,0)  trips 1
#      ARM B  capture (600,400) (2,False,600,400) trips 0
#             3 px             (2,False,600,400) trips 0
#             4 px             (2,False,600,400) trips 0
#             9 px             (2,TRUE, 600,400) trips 1
#      ARM C  (0,False,0,0) -> (2,TRUE,0,0), thumbnail [('start_window_drag',2,2)]
#      LEFT (0,False,0,0) · MIDDLE (2,False,10,20) · RIGHT (2,False,10,20)
#      production `action "kitten <this file> --spelling=preserving"` rc 0 ->
#             (2,False,0,0), wrapper installed, pending_wid 2
#      sandbox kitty stderr across every run above: 0 bytes.
# ===========================================================================
