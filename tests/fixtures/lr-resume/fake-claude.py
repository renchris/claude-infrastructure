#!/usr/bin/env python3
"""A stand-in for the claude binary that renders the resume-return menu and RECORDS what was sent.

This is what makes the fallback arm testable end to end. lr-fire-resume.sh ends in `exec expect`,
so the only way to prove the arm answers correctly is to put something on the other end of the pty
that behaves like the real select and writes down what it received. It is deliberately a state
machine, not a transcript: pressing Down has to actually MOVE the selector and repaint, or the
readback would confirm against a frame the keystroke never changed — which is exactly the vacuous
pass this control exists to rule out.

Env:
  LR_TEST_WIDTH   terminal width to render at
  LR_TEST_KEYLOG  file to append one line per received keystroke
  LR_TEST_LABELS  \\x1f-separated option labels
  LR_TEST_SILENT  if set, render NOTHING (models the menu being suppressed at the source)
"""

import os
import select
import sys
import time

import tty

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render_select import render  # noqa: E402  (sibling module, resolved above)

WIDTH = int(os.environ.get("LR_TEST_WIDTH", "80"))
KEYLOG = os.environ["LR_TEST_KEYLOG"]
LABELS = os.environ["LR_TEST_LABELS"].split("\x1f")


def log(msg: str) -> None:
    with open(KEYLOG, "a") as fh:
        fh.write(msg + "\n")


def paint(pointer: int) -> None:
    sys.stdout.write(render(WIDTH, pointer, LABELS))
    sys.stdout.flush()


def main() -> int:
    # Recorded on EVERY run, suppressed or not: the suppression must be asserted POSITIVELY, from
    # the value the spawned process actually received, never inferred from the absence of a menu.
    log(
        "ENV:CLAUDE_CODE_RESUME_THRESHOLD_MINUTES="
        + os.environ.get("CLAUDE_CODE_RESUME_THRESHOLD_MINUTES", "<unset>")
    )
    if os.environ.get("LR_TEST_SILENT"):
        # The source-suppression path: no menu is ever drawn. The session announces that it came up
        # on the FULL transcript, which is the positive assertion the ledger needs — "no menu
        # appeared" is also what a hang looks like, so absence alone proves nothing.
        log("RESUMED-AS-IS")
        sys.stdout.write("\r\n? for shortcuts\r\n")
        sys.stdout.flush()
        return 0

    # RAW MODE, exactly as the real TUI does it. Without it the pty stays canonical: the terminal
    # driver holds every keystroke until a newline and echoes it back, so an arrow key never
    # arrives and the echo pollutes the stream the readback is matching against. Found by this
    # suite failing on its first run — a stand-in that cannot receive the keystroke would have
    # made the arm look broken.
    tty.setraw(sys.stdin.fileno())
    pointer = 0
    paint(pointer)

    def getch() -> str:
        b = os.read(0, 1)
        return b.decode("utf-8", "replace") if b else ""

    while True:
        ch = getch()
        if not ch:
            return 0
        if ch == "\x1b":
            seq = getch() + getch()
            if seq == "[B":
                pointer = min(pointer + 1, len(LABELS) - 1)
                log("DOWN")
                paint(pointer)
            elif seq == "[A":
                pointer = max(pointer - 1, 0)
                log("UP")
                paint(pointer)
            else:
                log("ESC:" + seq)
        elif ch in ("\r", "\n"):
            log(f"SUBMIT:{pointer}:{LABELS[pointer]}")
            if not os.environ.get("LR_TEST_REPAINT_AFTER_SUBMIT"):
                return 0
            # ONE more frame after the answer, with the selector back on option 1 — which is
            # ordinary Ink behaviour: the dialog repaints on its way out. Anything the arm sends
            # from here lands in the COMPOSER of the resumed session, not in a menu. Keys are
            # logged, never acted on, so the test can see a re-entry that should not have happened.
            paint(0)
            deadline = time.time() + 6
            while time.time() < deadline:
                r, _, _ = select.select([0], [], [], 0.5)
                if r:
                    extra = os.read(0, 1)
                    if not extra:
                        break
                    log("AFTER-SUBMIT:" + repr(extra))
            return 0
        else:
            log("KEY:" + repr(ch))


if __name__ == "__main__":
    sys.exit(main())
