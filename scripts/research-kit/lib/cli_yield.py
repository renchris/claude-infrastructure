"""cli_yield.py — cc-research yield show|find — the yield stop of stages 3 and 5 (REPORT.md §12.1)."""

from __future__ import annotations

import argparse
from typing import Any

import kit


def not_built(a: argparse.Namespace) -> int:
    raise kit.KitError("cc-research yield is not implemented")


def add_verbs(sub: Any) -> None:
    p = sub.add_parser("yield", help="method v1.2")
    p.add_argument("rest", nargs=argparse.REMAINDER)
    p.set_defaults(fn=not_built)
