"""cc_say — Python twin of lib/cc-say.sh (lr-wake 2026-10-18, RC8). Same contract, same log.

    say(kind, verdict, fact="", action="", detail="")  -> prints ONE line to stderr (rc-free)
    say_detail(verdict, detail="")                      -> log record only (gray row if verbose)
    width()                                             -> the cell budget lines are fitted to
    cells(s)                                            -> display width (wide glyphs count 2)

The line is `glyph verdict · fact · ▶ action`, at most 56 cells, explicit truecolor, never SGR-2,
never `\\e[0m` when CC_SAY_TARGET=sm. The action is never cut: when the whole verdict cannot sit
beside it, it moves to its own row (`  ▶ action`). Environment knobs are the shell helper's:
CC_SAY_TOOL, CC_SAY_DETAIL, CC_SAY_VERBOSE, CC_SAY_COLOR, NO_COLOR, CC_SAY_WIDTH, CC_SAY_TARGET,
CC_SAY_LOG (`off` disables), CC_SAY_SID, CC_SAY_PANE. Import it by path; it has no dependencies
and no side effects at import.
"""

from __future__ import annotations

import json
import os
import sys
import time
import unicodedata
from typing import TextIO

_KINDS: dict[str, tuple[str, str]] = {
    "ok": ("✓", "107;243;133"),
    "fail": ("✗", "255;107;107"),
    "warn": ("⚠", "255;193;7"),
    "judge": ("◆", "255;193;7"),
    "wait": ("⏸", "150;150;160"),
    "run": ("⟳", "150;150;160"),
    "foot": ("─", "125;133;144"),
    "info": ("─", "150;150;160"),
}
_META = "150;150;160"
_ACT = "138;180;248"


def width() -> int:
    raw = os.environ.get("CC_SAY_WIDTH") or os.environ.get("COLUMNS") or "56"
    try:
        w = int(raw)
    except ValueError:
        w = 56
    if (
        w == 0
    ):  # zsh exports COLUMNS=0 with no terminal: unknown, not zero wide (as cc-say.sh)
        w = 56
    return max(12, min(56, w))


def cells(s: str) -> int:
    n = 0
    for ch in s:
        if unicodedata.combining(ch) or ch == "️":
            continue
        n += 2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1
    return n


def cut(s: str, maxw: int) -> str:
    if cells(s) <= maxw:
        return s
    if maxw <= 0:
        return ""
    if maxw == 1:
        return "…"
    # the same steps as cc_say_cut in cc-say.sh, so the twins cut identically
    k = min(maxw - 1, len(s))
    out = ""
    while k > 0:
        out = s[:k]
        if out.endswith(" ") or out.endswith(" ·"):
            k -= 1
            continue
        if cells(out) <= maxw - 1:
            break
        k -= 1
    b, take = "", False
    if " · " in out:  # a whole-fact boundary, when it keeps >= 2/3 of the row
        b = out.rsplit(" · ", 1)[0]
        take = cells(b) * 3 >= maxw * 2
    if (
        not take and s[len(out) : len(out) + 1] != " " and " " in out
    ):  # else a word boundary
        b = out.rsplit(" ", 1)[0]
        take = cells(b) * 3 >= maxw * 2
    if take:
        out = b
    return out + "…"


def _color_on(stream: TextIO) -> bool:
    if os.environ.get("NO_COLOR") or os.environ.get("CC_SAY_COLOR") == "0":
        return False
    if os.environ.get("CC_SAY_COLOR") == "1" or os.environ.get("CC_SAY_TARGET") == "sm":
        return True
    try:
        return stream.isatty()
    except (AttributeError, ValueError):
        return False


def _reset() -> str:
    return (
        "\033[38;2;153;153;153m"
        if os.environ.get("CC_SAY_TARGET") == "sm"
        else "\033[39m"
    )


def _log(kind: str, verdict: str, fact: str, action: str, detail: str) -> None:
    path = os.environ.get("CC_SAY_LOG") or os.path.expanduser(
        "~/.claude/logs/pane-say.jsonl"
    )
    if path == "off":
        return
    rec = {
        "ts": int(time.time()),
        "tool": os.environ.get("CC_SAY_TOOL")
        or os.path.basename(sys.argv[0] if sys.argv else ""),
        "sid": os.environ.get("CC_SAY_SID") or os.environ.get("CLAUDE_SESSION_ID", ""),
        "pane": os.environ.get("CC_SAY_PANE") or os.environ.get("KITTY_WINDOW_ID", ""),
        "kind": kind,
        "verdict": verdict,
        "fact": fact,
        "action": action,
        "detail": detail,
    }
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
    except OSError:
        pass


def render(
    kind: str, verdict: str, fact: str = "", action: str = "", color: bool = False
) -> list[str]:
    """The fitted line(s), without printing — what say() writes."""
    w = width()
    glyph, rgb = _KINDS.get(kind, _KINDS["info"])
    tail = f" · ▶ {action}" if action else ""
    room = w - cells(tail)
    own = False
    if action and cells(f"{glyph} {verdict}") > room:
        own, room, tail = True, w, ""
    vw = cells(f"{glyph} {verdict}")
    if vw > room:
        verdict, fact = cut(verdict, room - 2), ""
    elif fact:
        m = room - vw - 3
        fact = cut(fact, m) if m >= 8 else ""
    r = _reset()
    if color:
        e = "\033["
        line = f"{e}38;2;{rgb}m{glyph} {verdict}{r}"
        if fact:
            line += f"{e}38;2;{_META}m · {fact}{r}"
        if tail:
            line += f"{e}38;2;{_META}m · {r}{e}38;2;{_ACT}m▶{r} {action}"
    else:
        line = (
            f"{glyph} {verdict}"
            + (f" · {fact}" if fact else "")
            + (f" · ▶ {action}" if tail else "")
        )
    lines = [line]
    if own:
        lines.append(f"  \033[38;2;{_ACT}m▶{r} {action}" if color else f"  ▶ {action}")
    return lines


def _vrow(text: str, color: bool) -> str:
    body = cut(text, width() - 2)
    return f"  \033[38;2;{_META}m{body}{_reset()}" if color else f"  {body}"


def say(
    kind: str,
    verdict: str,
    fact: str = "",
    action: str = "",
    detail: str = "",
    stream: TextIO | None = None,
) -> None:
    out = stream if stream is not None else sys.stderr
    detail = detail or os.environ.get("CC_SAY_DETAIL", "")
    _log(kind, verdict, fact, action, detail)
    color = _color_on(out)
    try:
        for line in render(kind, verdict, fact, action, color):
            out.write(line + "\n")
        if os.environ.get("CC_SAY_VERBOSE") == "1" and detail:
            out.write(_vrow(detail, color) + "\n")
        out.flush()
    except (OSError, ValueError):
        pass


def say_detail(verdict: str, detail: str = "", stream: TextIO | None = None) -> None:
    _log("detail", verdict, "", "", detail)
    if os.environ.get("CC_SAY_VERBOSE") == "1":
        out = stream if stream is not None else sys.stderr
        try:
            out.write(
                _vrow(verdict + (f" · {detail}" if detail else ""), _color_on(out))
                + "\n"
            )
            out.flush()
        except (OSError, ValueError):
            pass
