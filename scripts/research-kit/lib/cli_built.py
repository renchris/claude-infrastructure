"""cli_built.py — cc-research built finding|mutate|contact|soak|show — the Stage 9 instruments (REPORT.md §11)."""

from __future__ import annotations

import argparse
from typing import Any

import kit


def not_built(a: argparse.Namespace) -> int:
    raise kit.KitError("cc-research built is not implemented")


def add_verbs(sub: Any) -> None:
    p = sub.add_parser("built", help="method v1.2")
    p.add_argument("rest", nargs=argparse.REMAINDER)
    p.set_defaults(fn=not_built)
