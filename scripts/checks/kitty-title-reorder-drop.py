# kitty-title-reorder-drop.py — drop pane SRC on pane DST's title bar, inside a SANDBOX kitty.
#
# A no_ui kitten, run over remote control by scripts/checks/kitty-title-reorder-sandbox.sh:
#
#     kitten @ --to unix:<sandbox socket> kitten <this file> <src_window_id> <dst_window_id>
#
# WHY THIS PATH AND NOT A MOUSE. A real title-bar drag ends in kitty's platform drag-and-drop, whose
# drop callback is TabManager.on_window_drop(x, y, window_id) (stock 0.48.2 kitty/tabs.py:2026). This
# kitten arms the window-being-dragged state the way kitty-drag-window.py does and calls that same
# callback with the centre of DST's title bar, so everything after the drop is kitty's own code: the
# title-bar hit test (which needs show_title_bar, i.e. the ⌘⇧B toggle having raised the bars) and
# Tab.swap_windows. It sends NO synthetic mouse event, so nothing on the operator's screen moves.
# Never aim it at the operator's kitty: the driver only ever passes a sandbox socket.
import json
from typing import Any

from kittens.tui.handler import result_handler


def main(args: list[str]) -> None:
    raise SystemExit("no_ui kitten: run it with `kitten @ kitten`, see the header")


@result_handler(no_ui=True)
def handle_result(
    args: list[str], answer: Any, target_window_id: int, boss: Any
) -> str:
    from kitty.fast_data_types import (
        cell_size_for_window,
        set_window_being_dragged,
        viewport_for_window,
    )

    out: dict[str, Any] = {}
    try:
        src_id, dst_id = int(args[1]), int(args[2])
        src, dst = boss.window_id_map.get(src_id), boss.window_id_map.get(dst_id)
        if src is None or dst is None:
            out["error"] = f"no such window: src={src_id} dst={dst_id}"
            return json.dumps(out)
        tm = boss.os_window_map.get(dst.os_window_id)
        if tm is None:
            out["error"] = "no tab manager for the destination OS window"
            return json.dumps(out)
        central = viewport_for_window(dst.os_window_id)[0]
        _, ch = cell_size_for_window(dst.os_window_id)
        g = dst.geometry
        # Centre of DST's title bar, in OS-window pixels. window_title_bar is `top` in kitty.conf.
        x = central.left + (g.left + g.right) // 2
        y = central.top + g.top + max(1, ch // 2)
        out["show_title_bar"] = {
            "src": bool(getattr(src, "show_title_bar", False)),
            "dst": bool(getattr(dst, "show_title_bar", False)),
        }
        out["drop_at"] = [int(x), int(y)]
        tab_bar = viewport_for_window(dst.os_window_id)[1]
        out["frames"] = {
            "central": [central.left, central.top, central.right, central.bottom],
            "tab_bar": [tab_bar.left, tab_bar.top, tab_bar.right, tab_bar.bottom],
            "cell_h": ch,
            "windows": {
                w.id: [
                    w.geometry.left,
                    w.geometry.top,
                    w.geometry.right,
                    w.geometry.bottom,
                ]
                for w in (dst.tabref() or [])
            },
        }
        set_window_being_dragged(src_id, True, 0.0, 0.0)
        try:
            tm.on_window_drop(int(x), int(y), src_id)
        finally:
            set_window_being_dragged()
        tab = dst.tabref()
        # LIST order, kept for diagnosis only: the splits layout swaps panes in its tree and leaves
        # this list alone, so the driver reads the visual order off `kitten @ ls` neighbors instead.
        out["list_order_after"] = [w.id for w in tab] if tab is not None else []
        out["ok"] = True
    except (
        Exception
    ) as e:  # report, never raise: an exception here would open an error overlay
        out["error"] = f"{type(e).__name__}: {e}"
    return json.dumps(out)
