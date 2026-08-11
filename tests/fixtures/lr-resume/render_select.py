#!/usr/bin/env python3
"""Render one frame of Claude Code's numbered select at a given terminal width.

WHY THIS EXISTS. The defect under test is width-dependence, so the controls have to run at real
narrow widths against real rendered bytes. Claude Code's resume-return menu cannot be captured
directly: it is gated on a server-side flag that is off for an unauthenticated process, so a
headless probe resumes straight past it. What CAN be captured is the SAME select component (`jr`
in the 2.1.220 bundle — the theme picker and the resume menu both render through it), and those
captures are checked in beside this file.

So this renderer is a MODEL, and it is never trusted on its own: `lr-resume-answer-width.bats`
pins it against the real captures first (same options, same widths, same matcher verdicts) and
only then uses it to render the resume menu's own labels. A generator that has not been replayed
against the real artifact can pass vacuously.

Modelled from the real width-8 capture, byte for byte:

    \\x1b[4G\\x1b[38;2;153;153;153m1.\\x1b[39mAut     <- ordinal at col 4, label starts inline
    \\x1b[4G\\x1b[38;2;153;153;153m \\x1b[6G\\x1b[39mo   <- continuation indented to col 6
    \\x1b[2G\\x1b[38;2;177;185;249m❯\\x1b[4G...2.\\x1b[38;2;78;186;101mDar   <- pointer at col 2

The SGR run between the ordinal and the label is the load-bearing detail: it is why a literal
phrase match fails even in an 80-column pane, not merely a narrow one.

Usage: render-select.py <width> <pointer-index-0-based> <label>...
"""

import sys

GREY = "\x1b[38;2;153;153;153m"
SEL = "\x1b[38;2;177;185;249m"
LBL = "\x1b[38;2;78;186;101m"
OFF = "\x1b[39m"


def wrap(text: str, width: int) -> list[str]:
    """Ink's hard wrap: break on a space when one fits, else mid-word."""
    width = max(1, width)
    out, rest = [], text
    while rest:
        if len(rest) <= width:
            out.append(rest)
            break
        cut = rest.rfind(" ", 0, width + 1)
        if cut <= 0:
            cut = width
            out.append(rest[:cut])
            rest = rest[cut:]
        else:
            out.append(rest[:cut])
            rest = rest[cut + 1 :]
    return out or [""]


def cols(text: str, start: int) -> str:
    """Emit an intra-label space as a CURSOR-COLUMN move, which is what Ink actually does.

    This is the detail that decides the whole bug. Stripping the escapes out of the real width-40
    capture yields "4.Darkmode(colorblind-friendly)" — the spaces are GONE, because Ink positioned
    the cursor instead of writing them. That is why the literal `Dark mode (colorblind-friendly)`
    is absent even in an 80-column pane: the phrase a human reads is never contiguous on the wire.
    A model that emitted real spaces would let the naive literal match, and the control proving the
    old arm is broken would silently stop proving it.
    """
    out, col = [], start
    for ch in text:
        if ch == " ":
            out.append(f"\x1b[{col + 1}G")
        else:
            out.append(ch)
        col += 1
    return "".join(out)


def render(width: int, pointer: int, labels: list[str]) -> str:
    first_w = max(1, width - 6)
    cont_w = max(1, width - 6)
    frame = []
    for i, label in enumerate(labels):
        chunks = wrap(label, first_w)
        head = chunks[0]
        tail: list[str] = []
        for chunk in chunks[1:]:
            tail.extend(wrap(chunk, cont_w))
        mark = f"{SEL}❯" if i == pointer else " "
        frame.append(f"\x1b[2G{mark}\x1b[4G{GREY}{i + 1}.{LBL}{cols(head, 6)}{OFF}\r\n")
        for chunk in tail:
            frame.append(f"\x1b[6G{LBL}{cols(chunk, 6)}{OFF}\r\n")
    return "".join(frame)


if __name__ == "__main__":
    w = int(sys.argv[1])
    p = int(sys.argv[2])
    sys.stdout.write(render(w, p, sys.argv[3:]))
