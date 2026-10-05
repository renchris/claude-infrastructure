#!/usr/bin/env python3
"""fixture_signer.py <row> [--evidence X] [--because Y] — the operator's signing path, for fixtures.

Runs bin/cc-signoff itself (argument parsing, the evidence rule, the content pin, the registry
hand-off), with ONE thing replaced: the ancestry walk reports an operator's terminal, because a
test suite is usually run by an agent and the real walk would (rightly) refuse it. The chain it
records starts with "fixture-signer", so a record it wrote says what wrote it.

It refuses unless CC_RESEARCH_HOME and CC_RESEARCH_REGISTRY both point away from the live store
(~/.claude/autonomy/research of the real user, whatever HOME says): it can never sign a real program.
"""

from __future__ import annotations

import os
import pwd
import runpy
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / "scripts" / "lib"))
import operator_sign  # noqa: E402

CHAIN = [{"pid": 0, "comm": c, "depth": i} for i, c in enumerate(("fixture-signer", "zsh", "kitty"))]


def fixture_only() -> None:
    live = os.path.realpath(Path(pwd.getpwuid(os.getuid()).pw_dir) / ".claude" / "autonomy" / "research")
    for var in ("CC_RESEARCH_HOME", "CC_RESEARCH_REGISTRY"):
        val = os.environ.get(var)
        real = os.path.realpath(val) if val else ""
        if not val or real == live or real.startswith(live + os.sep):
            print(f"fixture_signer: REFUSED — {var} is unset or points at the live research store; "
                  "this signer is for fixtures only", file=sys.stderr)
            sys.exit(2)


if __name__ == "__main__":
    fixture_only()
    operator_sign.ancestry = lambda pid=None: list(CHAIN)
    sys.argv = ["cc-signoff"] + sys.argv[1:]
    runpy.run_path(str(REPO / "bin" / "cc-signoff"), run_name="__main__")
