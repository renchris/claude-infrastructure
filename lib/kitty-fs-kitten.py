#!/usr/bin/env python3
# kitty-fs-kitten.py — the kitty-side half of bin/kitty-fullscreen-guard (2026-10-15 crash fix,
# docs/research/kitty-crash-2026-10-15/README.md § Chosen fix). It runs ONLY kitty's own API plus ONE
# ctypes read (fsfix, below): no blocking, nothing that waits on kitty's main loop (the exit
# transition needs that loop).
#
# CHANGED 2026-10-16 (was "no ctypes"): every reply carries `pid` (this kitty process) and `fsfix`,
# whether the RUNNING kitty carries our fullscreen-destroy fix with the upstream backport. The marker
# is the empty ObjC class GLFWFsFixV2, which only the rebuilt bundle registers; GLFWDeferredClose is
# NOT the marker, because the bundle staged on 2026-10-16 has it but lacks the backport (corrections
# F2). objc_getClass is a read of the runtime's class table: no message send, no main-loop wait.
# restype MUST be c_void_p and the test MUST be bool(): with c_void_p an absent class comes back as
# None, and `None != 0` is True, which would read stock kitty as fixed; the default c_int restype
# truncates the pointer (F3). ctypes is in kitty's bundled python (`kitty +runpy` imports it). Any
# failure reports None, which the guard treats as "not fixed" — there is no lsof fallback (F3).
#
# Invoked as `kitty @ --to <addr> kitten --match id:<wid> <this file> query|toggle|act <action...>`.
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
import os
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


FSFIX_MARKER = b"GLFWFsFixV2"
_LIBOBJC = "/usr/lib/libobjc.A.dylib"


def fsfix() -> "bool | None":
    """True iff this process has the ObjC class GLFWFsFixV2 registered; None if the read failed."""
    try:
        import ctypes

        L = ctypes.CDLL(_LIBOBJC)
        L.objc_getClass.restype = ctypes.c_void_p
        L.objc_getClass.argtypes = [ctypes.c_char_p]
        return bool(L.objc_getClass(FSFIX_MARKER))
    except Exception:  # noqa: BLE001 — reported as None (= enforce), never raised into kitty
        return None


def main(args: list[str]) -> None:
    pass


def _panes(tab: Any) -> int:
    # Panes = window GROUPS: an overlay (a kitten UI over a pane) shares its pane's group and goes
    # when the pane goes, so counting raw windows would call a lone pane-with-overlay "not last".
    windows = getattr(tab, "windows", None)
    n = getattr(windows, "num_groups", None)
    return int(n) if isinstance(n, int) else len(tab)


def _pane_wids(tab: Any, wid: int) -> tuple[list[int], int]:
    """→ (one window id per pane, the pane id holding <wid>), counted exactly as _panes() counts:
    a group's id is its first (base) window, so an overlay over a pane maps to that pane. If the
    groups cannot be listed the length falls short of _panes(), and the guard treats the reply as
    unavailable."""
    windows = getattr(tab, "windows", None)
    if isinstance(getattr(windows, "num_groups", None), int):
        ids, mine = [], wid
        for g in getattr(windows, "groups", None) or ():
            ws = list(getattr(g, "windows", None) or ())
            if ws:
                ids.append(int(ws[0].id))
                if any(getattr(x, "id", None) == wid for x in ws):
                    mine = int(ws[0].id)
        return ids, mine
    return [int(w.id) for w in tab], wid


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
    # The guard's claim gate (bin/kitty-fullscreen-guard § CLAIMS). Never raised into kitty: a
    # failure omits the keys, which the guard reads as "unavailable".
    pane_wids: "list[int] | None" = []
    pane_wid = wid
    try:
        for t in tabs:
            ids, mine = _pane_wids(t, wid)
            pane_wids += ids
            if t is tab:
                pane_wid = mine
    except Exception:  # noqa: BLE001
        pane_wids = None
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
        **(
            {"pane_wids": pane_wids, "pane_wid": pane_wid}
            if pane_wids is not None
            else {}
        ),
        # Does removing <scope> empty the OS window? (`os-window` always does.)
        "last_for": {
            "pane": panes_in_os_window == 1,
            "tab": len(tabs) == 1,
            "os-window": True,
        },
        # The guard's relax-on-fix inputs (bin/kitty-fullscreen-guard § RELAX ON THE FIX): this
        # kitty's pid keys the guard's per-process fsfix cache, which --any-fs reads when remote
        # control is down.
        "pid": os.getpid(),
        "fsfix": fsfix(),
    }


def act(boss: Any, wid: int, action: list[str]) -> dict[str, Any]:
    """Run a native action on <wid> in the SAME main-loop call that checks it is still the target.

    `kitty @ action --self` is not enough after the guard's wait (up to ~9 s): bare `detach_window`
    and the `ask` chooser's New-OS-Window / New-tab branches move `boss.active_window`, not the
    dispatch window (boss.py:3318 `window = window or self.active_window`), and a window that died
    in the wait makes `--self` fall back to the active window outright (rc/base.py:376-377). So the
    act refuses unless <wid> still exists AND is still the active window; then the action's
    "active window" IS the guarded pane."""
    w = boss.window_id_map.get(wid)
    if w is None:
        return {"error": f"window {wid} is gone"}
    if getattr(boss, "active_window", None) is not w:
        return {"error": "focus-moved", "wid": wid}
    try:
        consumed = boss.combine(" ".join(action), w, raise_error=True)
    except Exception as e:  # noqa: BLE001 — reported to the guard, never raised into kitty
        return {"error": f"action failed: {e}", "wid": wid}
    return {"wid": wid, "acted": bool(consumed)}


@result_handler(no_ui=True)
def handle_result(
    args: list[str], answer: str, target_window_id: int, boss: Any
) -> str:
    if args[1:2] == ["act"]:
        return json.dumps(act(boss, target_window_id, args[2:]), separators=(",", ":"))
    info = describe(boss, target_window_id)
    if "error" not in info and "toggle" in args[1:]:
        if toggle_fullscreen is None:
            info = {"error": "toggle_fullscreen unavailable"}
        else:
            res = toggle_fullscreen(info["os_window_id"])
            info["toggled_into_fullscreen"] = res if isinstance(res, bool) else None
    return json.dumps(info, separators=(",", ":"))
