#!/usr/bin/env python3
# kitty-equalize.py — ⌘⇧E: give every pane in a tab an equal share, whatever the tab's layout.
#
# `layout_action equalize` exists only in the Splits layout (kitty 0.48.2 splits.py:884). In every
# other layout the base Layout.layout_action returns None, and Tab.layout_action then rings the bell
# and does not relayout (tabs.py:648-653) — so in a `horizontal` tab the chord "did nothing". Splits
# must keep `equalize`, because Splits.remove_all_biases sets every pair to 0.5, which in a nested
# chain of 3+ panes is 50/25/25 rather than equal. Every other layout resets through
# Tab.reset_window_sizes, which for Horizontal/Vertical clears biased_map: truly equal columns.
from typing import Any

from kittens.tui.handler import result_handler


def main(args: list[str]) -> None:
    pass


def pick_tab(boss: Any, target_window_id: int) -> Any:
    # The tab holding the invoking window, so `kitty @ action --self kitten …` from a script equalizes
    # that pane's tab rather than whichever tab happens to be focused.
    w = boss.window_id_map.get(target_window_id)
    tab = boss.tab_for_id(w.tab_id) if w is not None else None
    return tab if tab is not None else boss.active_tab


@result_handler(no_ui=True)
def handle_result(
    args: list[str], answer: str, target_window_id: int, boss: Any
) -> None:
    tab = pick_tab(boss, target_window_id)
    if tab is None:
        return
    if tab.current_layout.name == "splits":
        tab.layout_action("equalize", ())
    else:
        tab.reset_window_sizes()
