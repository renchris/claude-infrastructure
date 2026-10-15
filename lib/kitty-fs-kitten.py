#!/usr/bin/env python3
# kitty-fs-kitten.py — the kitty-side half of bin/kitty-fullscreen-guard (2026-10-15 crash fix,
# docs/research/kitty-crash-2026-10-15/README.md § Chosen fix). It runs ONLY kitty's own API: no
# ctypes, no blocking, nothing that waits on kitty's main loop (the exit transition needs that loop).
#
# Invoked as `kitty @ --to <addr> kitten --match id:<wid> <this file> query|toggle`.
# - `--match` resolves exactly: a missing pane is a MatchError (rc/base.py:381-384), never the active
#   window, which is why targeting goes through a kitten and not `action --match` (ignored in 0.48.2).
# - A no-UI kitten's handle_result runs synchronously in the boss (boss.py:2325-2326, args =
#   [kitten path] + our args via kittens/runner.py `partial(handle_result, [kitten] + orig_args)`),
#   and a str return value is printed on the client's stdout (rc/kitten.py:43-44 →
#   tools/cmd/at/main.go:297-298, trailing whitespace trimmed). So we return one JSON line.
# - `toggle` calls fast_data_types.toggle_fullscreen, NOT boss.toggle_fullscreen: the boss wrapper
#   returns None (boss.py:1351-1356) while the C call returns True when it ENTERED fullscreen, False
#   when it left, None when the OS window is gone (glfw.c:1359-1368, 2471-2478). The guard needs it.
import json
from typing import Any

from kittens.tui.handler import result_handler

try:
    from kitty.fast_data_types import toggle_fullscreen
    from kitty.utils import platform_window_id
except (
    Exception
):  # outside kitty: handle_result reports the failure instead of import-crashing
    toggle_fullscreen = None
    platform_window_id = None


def main(args: list[str]) -> None:
    pass


def _panes(tab: Any) -> int:
    # Panes = window GROUPS: an overlay (a kitten UI over a pane) shares its pane's group and goes
    # when the pane goes, so counting raw windows would call a lone pane-with-overlay "not last".
    windows = getattr(tab, "windows", None)
    n = getattr(windows, "num_groups", None)
    return int(n) if isinstance(n, int) else len(tab)


def describe(boss: Any, wid: int) -> dict[str, Any]:
    w = boss.window_id_map.get(wid)
    if w is None:
        return {"error": f"window {wid} not in window_id_map"}
    tab = w.tabref() if callable(getattr(w, "tabref", None)) else None
    if tab is None:
        tab = boss.tab_for_id(w.tab_id)
    os_window_id = getattr(tab, "os_window_id", None) or getattr(
        w, "os_window_id", None
    )
    tm = boss.os_window_map.get(os_window_id) if os_window_id else None
    if tab is None or tm is None:
        return {"error": f"window {wid} has no tab/os window"}
    tabs = list(tm)
    panes_in_os_window = sum(_panes(t) for t in tabs)
    pwid = None
    if platform_window_id is not None:
        try:
            pwid = platform_window_id(os_window_id)
        except Exception:
            pwid = None
    return {
        "wid": wid,
        "os_window_id": os_window_id,
        "platform_window_id": pwid,
        "panes_in_os_window": panes_in_os_window,
        "tabs_in_os_window": len(tabs),
        "panes_in_tab": _panes(tab),
        # Does removing <scope> empty the OS window? (`os-window` always does.)
        "last_for": {
            "pane": panes_in_os_window == 1,
            "tab": len(tabs) == 1,
            "os-window": True,
        },
    }


@result_handler(no_ui=True)
def handle_result(
    args: list[str], answer: str, target_window_id: int, boss: Any
) -> str:
    info = describe(boss, target_window_id)
    if "error" not in info and "toggle" in args[1:]:
        if toggle_fullscreen is None:
            info = {"error": "toggle_fullscreen unavailable"}
        else:
            res = toggle_fullscreen(info["os_window_id"])
            info["toggled_into_fullscreen"] = res if isinstance(res, bool) else None
    return json.dumps(info, separators=(",", ":"))
