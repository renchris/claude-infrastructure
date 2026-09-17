"""Zero-shift pane title bands for a kitty that has not been rebuilt.

WHAT THIS IS. kitty's own window title bar is a row of cells: turning it on takes a text row from
every pane, which is a pty resize, a SIGWINCH to every child and a visible jump of everything below
it. That cost is the whole reason the title chord has been rebuilt three times in this repo. The
fix in `docs/patches/kitty-window-title-band.patch` is a C patch that draws the title OUTSIDE the
cell grid, and it is the right answer -- but C cannot be loaded into a running kitty, and the
operator's terminal holds live agent sessions that a restart would kill. This module is the half of
that fix which CAN be installed into a running kitty: it is pure Python, it reaches every pane of
every tab of every OS window of the instance it is injected into, and it is reversible in one call.

WHAT IT DOES. It wraps `Window.set_geometry` so that a visible title bar is drawn OVER the pane's
first row instead of being allocated a row of its own:

  * the content keeps every row it had, so `screen.resize()` is never reached, `current_pty_size`
    is unchanged and no child is signalled (kitty/window.py:1076-1085 in v0.48.2);
  * the title bar's own rect is still handed to C, so the bar still renders -- and because it is
    drawn after the content for the same window (kitty/child-monitor.c:906-915) it covers row 1
    rather than displacing it;
  * the bar is its own one-line Screen with no scrollback, drawn every frame at a fixed pixel rect,
    so unlike a graphics-protocol overlay it cannot scroll away, cannot be freed by a screen clear,
    and needs no re-assert timer.

AND IT KEEPS THE BAR HIT-TESTED, which is what makes it draggable. That part turns on one fact
about kitty's C layer: `Window.padding` is written by exactly one function and read by exactly four
-- the four mouse edge functions in kitty/mouse.c:249-267 -- and by NO rendering path. So it is a
pure hit-test inset that Python can set. Pushing the top inset back by one cell moves
`window_top()` to the band's lower edge, which takes the band out of `contains_mouse()` and lets
`mouse_region()` reach its title-bar arm for exactly that strip. Everything downstream is stock
kitty: the hand cursor at mouse.c:1133, the drag at mouse.c:1362 -> tabs.py, and a title-bar drop
meaning "swap panes".

  The inset is applied by passing a negative number to a setter that parses "I". CPython's `I`
  converts without overflow checking, so -cell_height arrives as 2**32 - cell_height and
  `geometry.top - padding.top` wraps back to `top + cell_height` in unsigned arithmetic. That is a
  deliberate use of defined unsigned wraparound, and it is confined to this shim: the C patch does
  the same job with an explicit rect and no arithmetic tricks.

WHAT IT DOES NOT DO. The text is still terminal cells, so it is the cell font -- the system
sans-serif face needs the C patch. This shim is the bridge until then, not a replacement for it.

HOW IT IS LOADED, two ways, both wanted:
  * at startup, by `watcher <this file>` in kitty.conf, so a restarted kitty has it;
  * into a RUNNING kitty, with
        kitty @ launch --type=overlay --watcher <this file> sh -c 'sleep 0.2'
    `--type=background` does NOT work: a background launch creates no Window, so kitty never
    reaches load_watch_modules (kitty/launch.py:520-542). Watcher modules are memoised by PATH
    (launch.py:523), so re-injecting an edited file needs a new path, not the same one.

Turn the bands on and off with `window_title_bar_min_windows` (0/1), which is what
scripts/kitty-pane-title-toggle.sh already swaps. Bars held up by that option survive a drag,
because the post-drop cleanup clears only the per-tab force_show flag -- which is exactly the
"a no-op drag must leave the title up" requirement.

Self-disabling: if the running kitty already has the native band (the C patch's
`window_title_bar_overlay` option), this module does nothing at all, so the two can never fight.
"""

import os
import traceback

_ORIGINAL_ATTR = "_kitty_title_band_original_set_geometry"
import os as _os  # noqa: E402
# Honour the same override the deploy script uses, so a sandbox run logs to its own
# file instead of the shared store that records the live kitty's state.
_LOG = _os.environ.get("KITTY_TITLE_BAND_LOG") or "/tmp/kitty-title-band-watcher.log"


def _log(msg: str) -> None:
    # A watcher runs with no tty: a traceback here goes nowhere and a failure reads as "the chord
    # did nothing". This round has been lost to exactly that before, so failures are written down.
    try:
        with open(_LOG, "a") as fh:
            fh.write(msg.rstrip() + "\n")
    except Exception:
        pass


def _native_band_available() -> bool:
    """True when this kitty already draws the band itself, in which case the shim must stand down."""
    try:
        from kitty.fast_data_types import get_options

        # The option EXISTING is the test, not its value: a kitty that has the native band must own
        # the feature whether it is currently on or off, or the two would fight over the same rect.
        return hasattr(get_options(), "window_title_bar_overlay")
    except Exception:
        return False


def _band_geometry(window, new_geometry, cell_height):
    """The band's rect: one cell at the top (or bottom) of the pane's own content area."""
    from kitty.fast_data_types import get_options
    from kitty.types import WindowGeometry

    g = new_geometry
    if get_options().window_title_bar == "bottom":
        top = g.bottom - cell_height
    else:
        top = g.top
    return WindowGeometry(
        left=g.left, top=top, right=g.right, bottom=top + cell_height, xnum=0, ynum=1
    )


def _patched_set_geometry(self, new_geometry):
    from kitty.fast_data_types import (
        cell_size_for_window,
        get_options,
        set_window_padding,
        set_window_title_bar_render_data,
    )

    wanted = bool(getattr(self, "show_title_bar", False)) and new_geometry.ynum > 1
    # Run kitty's own set_geometry with the bar switched OFF. That is what keeps this shim small:
    # every line of content layout, resizing and render-data plumbing stays kitty's, and the only
    # thing we add is the band. It also guarantees the no-bar path, i.e. no stolen row, no
    # screen.resize(), no pty resize and no SIGWINCH.
    from kitty.window import Window

    original = getattr(Window, _ORIGINAL_ATTR, None)
    if original is None:  # uninstalled underneath us; nothing sane left to do
        return
    self.show_title_bar = False
    try:
        original(self, new_geometry)
    finally:
        self.show_title_bar = wanted

    if not wanted:
        return
    try:
        cell_width, cell_height = cell_size_for_window(self.os_window_id)
        if not cell_height or new_geometry.bottom <= new_geometry.top + cell_height:
            return  # a pane that is not at least one cell taller than the band would be all band
        if self._title_bar_screen is None:
            from kitty.window_title_bar import WindowTitleBarScreen

            self._title_bar_screen = WindowTitleBarScreen(
                self.os_window_id, cell_width, cell_height
            )
        tb = _band_geometry(self, new_geometry, cell_height)
        self._title_bar_screen.layout(tb)
        set_window_title_bar_render_data(
            self.os_window_id,
            self.tab_id,
            self.id,
            self._title_bar_screen.screen,
            tb.left,
            tb.top,
            tb.right,
            tb.bottom,
        )
        tab = self.tabref() if callable(getattr(self, "tabref", None)) else None
        self.update_title_bar(
            is_active=bool(tab is not None and tab.active_window is self)
        )

        # The hit-test inset. Negative on the edge the band occupies, so contains_mouse() stops one
        # cell short of it and mouse_region() can reach its title-bar arm for that strip. No render
        # path reads padding, so this moves no pixels -- measured as zero changed pixels.
        at_top = get_options().window_title_bar != "bottom"
        set_window_padding(
            self.os_window_id,
            self.tab_id,
            self.id,
            self.effective_padding("left"),
            self.effective_padding("top") - (cell_height if at_top else 0),
            self.effective_padding("right"),
            self.effective_padding("bottom") - (0 if at_top else cell_height),
        )
    except Exception:
        # Never let the band take the layout down with it: a pane that lays out without a title is
        # a missing feature, a pane that raises inside set_geometry is a broken terminal.
        _log(
            "band failed for window %s:\n%s"
            % (getattr(self, "id", "?"), traceback.format_exc())
        )


_TABBAR_ATTR = "_kitty_title_band_original_tab_bar_visible"
_DROPMOVE_ATTR = "_kitty_title_band_original_on_window_drop_move"


def _patched_tab_bar_should_be_visible(self):
    """Do not reveal the tab bar for the duration of a WINDOW drag.

    Stock kitty reveals it so the dragged window can be dropped on a tab or on the new-tab button.
    Revealing it takes pixels out of the central area, which resizes every window in that OS window
    and signals every child -- twice per drag, once on reveal and once on hide. That is the very
    reflow the band exists to avoid, and with the band up every window is already a visible,
    hit-tested drop target. A TAB drag is a different gesture with no other drop target, so it still
    reveals it."""
    from kitty.tabs import TabManager

    original = getattr(TabManager, _TABBAR_ATTR, None)
    if original is None:
        return False
    if self.tab_being_dropped is None and getattr(self, "window_drag_over_me", False):
        saved = self.window_drag_over_me
        self.window_drag_over_me = False
        try:
            return original.fget(self)
        finally:
            self.window_drag_over_me = saved
    return original.fget(self)


def _patched_on_window_drop_move(self, window_id=0, is_dest=False, x=0, y=0):
    """Track the drag-over flag but skip the tab-bar relayout it normally triggers."""
    from kitty.tabs import TabManager

    original = getattr(TabManager, _DROPMOVE_ATTR, None)
    if original is None:
        return None
    hidden, self.tab_bar_hidden = self.tab_bar_hidden, True
    try:
        return original(self, window_id=window_id, is_dest=is_dest, x=x, y=y)
    finally:
        self.tab_bar_hidden = hidden


def install() -> bool:
    """Idempotent across copies. The saved original lives on the Window CLASS, not in this module's
    globals, because kitty memoises watcher modules BY PATH (kitty/launch.py:523): re-injecting an
    edited copy from a new path runs a NEW module object, whose globals are empty, and a
    module-global guard would then wrap the already-wrapped method a second time."""
    from kitty.window import Window

    if _native_band_available():
        _log("native window_title_bar_overlay present; shim standing down")
        return False
    if getattr(Window, _ORIGINAL_ATTR, None) is not None:
        _log("already installed")
        return True
    setattr(Window, _ORIGINAL_ATTR, Window.set_geometry)
    Window.set_geometry = _patched_set_geometry
    try:
        from kitty.tabs import TabManager

        if getattr(TabManager, _TABBAR_ATTR, None) is None:
            setattr(TabManager, _TABBAR_ATTR, TabManager.tab_bar_should_be_visible)
            TabManager.tab_bar_should_be_visible = property(_patched_tab_bar_should_be_visible)
            setattr(TabManager, _DROPMOVE_ATTR, TabManager.on_window_drop_move)
            TabManager.on_window_drop_move = _patched_on_window_drop_move
    except Exception:
        # The band is the feature; the drag-time tab-bar reflow is a refinement. Losing the
        # refinement must never cost the feature.
        _log("tab-bar suppression not installed:\n" + traceback.format_exc())
    # Name the process. The log is one shared file and a sandbox run writes to it too, so a bare
    # "installed" cannot tell a caller whether THIS kitty is patched -- which is exactly what a
    # status report is asked for.
    _log("installed pid=%d" % os.getpid())
    return True


def uninstall() -> bool:
    """Restore stock kitty. The relayout that follows runs the original set_geometry, which calls
    update_effective_padding() and so puts the hit-test inset back too."""
    from kitty.window import Window

    orig = getattr(Window, _ORIGINAL_ATTR, None)
    if orig is None:
        return False
    Window.set_geometry = orig
    try:
        delattr(Window, _ORIGINAL_ATTR)
    except AttributeError:
        pass
    try:
        from kitty.tabs import TabManager

        tb = getattr(TabManager, _TABBAR_ATTR, None)
        if tb is not None:
            TabManager.tab_bar_should_be_visible = tb
            delattr(TabManager, _TABBAR_ATTR)
        dm = getattr(TabManager, _DROPMOVE_ATTR, None)
        if dm is not None:
            TabManager.on_window_drop_move = dm
            delattr(TabManager, _DROPMOVE_ATTR)
    except Exception:
        _log("tab-bar suppression not removed:\n" + traceback.format_exc())
    _log("uninstalled pid=%d" % os.getpid())
    return True


def relayout_everything(boss) -> int:
    """Re-run layout for every tab so the change takes effect on windows that already exist."""
    n = 0
    for tm in boss.all_tab_managers:
        for tab in tm:
            try:
                tab.relayout()
                n += 1
            except Exception:
                _log("relayout failed:\n" + traceback.format_exc())
    return n


def on_load(boss, data) -> None:
    try:
        if install():
            relayout_everything(boss)
    except Exception:
        _log("on_load failed:\n" + traceback.format_exc())
