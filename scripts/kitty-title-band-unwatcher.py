"""Undo scripts/kitty-title-band-watcher.py in a RUNNING kitty, restoring stock behaviour.

    kitty @ launch --type=overlay --watcher <this file> sh -c 'sleep 0.2'

This is a separate file rather than a flag because of how kitty loads watchers: the module is run
by path and memoised by path (kitty/launch.py:520-542), so there is no way to pass it an argument
and no way to re-run an already-loaded path. A second file is the whole mechanism.

It does not need to find the watcher's module object. The shim deliberately parks the original
method on the Window CLASS, so the undo is a class attribute lookup and nothing else -- which also
means this works against a shim injected from any path, by any session, at any earlier time.

Restoring the method is not enough on its own: the shim also pushes a hit-test inset into
`set_window_padding`, and only a relayout puts that back, because the original `set_geometry` is
what calls `update_effective_padding()`. So the relayout below is load-bearing, not cosmetic.
"""

_ORIGINAL_ATTR = "_kitty_title_band_original_set_geometry"
_LOG = "/tmp/kitty-title-band-watcher.log"


def _log(msg: str) -> None:
    try:
        with open(_LOG, "a") as fh:
            fh.write(msg.rstrip() + "\n")
    except Exception:
        pass


def on_load(boss, data) -> None:
    try:
        from kitty.window import Window

        original = getattr(Window, _ORIGINAL_ATTR, None)
        if original is None:
            _log("unwatcher: nothing to undo, the shim is not installed")
            return
        Window.set_geometry = original
        try:
            delattr(Window, _ORIGINAL_ATTR)
        except AttributeError:
            pass
        from kitty.tabs import TabManager

        for attr, name in (
            ("_kitty_title_band_original_tab_bar_visible", "tab_bar_should_be_visible"),
            ("_kitty_title_band_original_on_window_drop_move", "on_window_drop_move"),
        ):
            saved = getattr(TabManager, attr, None)
            if saved is not None:
                setattr(TabManager, name, saved)
                try:
                    delattr(TabManager, attr)
                except AttributeError:
                    pass
        n = 0
        for tm in boss.all_tab_managers:
            for tab in tm:
                try:
                    tab.relayout()
                    n += 1
                except Exception:
                    pass
        import os

        _log(
            "uninstalled pid=%d (unwatcher: restored stock set_geometry, relaid out %d tab(s))"
            % (os.getpid(), n)
        )
    except Exception:
        import traceback

        _log("unwatcher failed:\n" + traceback.format_exc())
