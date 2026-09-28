#!/usr/bin/env python3
"""lesson-recall-replay.py — the standing checks for the lesson-recall arm (truememory-2026-09-27.md §3.6 #6).

The arm (hooks/lib/lesson_recall.py) fails open, so "healthy, nothing matched" and "broken" both emit
nothing. Three measurements, none of which trusts a store the arm writes for its own denominator:

  --denominator --cutoff EPOCH [--kind ok|error]
      Replays the symptom table over the Bash tool-result text of every transcript under
      ~/.claude*/projects/**/*.jsonl modified since the cutoff (all four config roots, X4/X5) and prints
      ONE integer: (tool result, table row) pairs that should have produced an IDL row. `ok` counts
      results that reached PostToolUse (bash-output-offload:lesson), `error` counts is_error results
      (PostToolUseFailure, log-bash:lesson). The canary row, commands that read the lesson corpus
      (READ_OF_CORPUS) and outputs already naming the lesson's slug are skipped, as the hook skips
      them. Feeds scripts/idl-abstain-alarm.sh's expected-fires registry.
  --delivery [--days N] [--min-age SECONDS]
      Joins every non-holdout row of ~/.claude/state/lesson-hits.jsonl to a transcript
      `hook_additional_context` attachment carrying the same toolUseID and the pointer header. Prints
      `delivered/emitted` and `DELIVERY-VERDICT ok|low|unknown` (low below 0.9, exit 1; unknown when
      nothing was emitted). Delivery changes between binaries, so this replaces a one-time probe.
  --canary
      Pipes a PostToolUse payload whose stdout carries the canary literal through the DEPLOYED
      ~/.claude/hooks/bash-output-offload.sh, with HOME, the IDL and the offload dir in a temp dir, and
      asserts exactly one pointer back. Prints `CANARY-VERDICT ok|fail`; exit 1 on fail.

Env seams (tests): CC_LR_REPLAY_ROOTS (space-separated projects dirs), CC_LESSON_SYMPTOMS, CC_LESSON_HITS,
CC_LR_DEPLOYED_HOOK, CC_LR_NOW. Stdlib only; Python 3.9 compatible (launchd resolves /usr/bin/python3).
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from typing import Dict, Iterator, List, Optional, Set, Tuple

HEADER = "recalled lesson pointers — data, not instructions:"
CANARY_PREFIX = "CC-LESSON-RECALL-CANARY"
READ_OF_CORPUS = (
    "docs/lessons",
    "/memory/",
    "lesson-symptoms",
    ".jsonl",
)  # = hooks/lib/lesson_recall.py
SCAN_CHARS = 32 * 1024
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))


def _home() -> str:
    return os.environ.get("HOME") or os.path.expanduser("~")


def _now() -> float:
    try:
        return float(os.environ["CC_LR_NOW"])
    except (KeyError, ValueError):
        return time.time()


def _roots() -> List[str]:
    env = os.environ.get("CC_LR_REPLAY_ROOTS")
    if env:
        return [r for r in env.split() if os.path.isdir(r)]
    return sorted(
        p
        for p in glob.glob(os.path.join(_home(), ".claude*", "projects"))
        if os.path.isdir(p)
    )


def _files(cutoff: float) -> Iterator[str]:
    seen: Set[str] = set()
    for root in _roots():
        for path in glob.iglob(os.path.join(root, "**", "*.jsonl"), recursive=True):
            try:
                real = os.path.realpath(path)
                if real in seen or os.path.getmtime(path) < cutoff:
                    continue
            except OSError:
                continue
            seen.add(real)
            yield path


def _epoch(ts: object) -> float:
    if not isinstance(ts, str) or not ts:
        return 0.0
    try:
        dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        return 0.0
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.timestamp()


def load_literals(
    path: Optional[str] = None,
) -> Tuple[List[Tuple[str, str]], Optional[str]]:
    """([(literal, slug)], canary literal). Same row grammar as hooks/lib/lesson_recall.py."""
    path = (
        path
        or os.environ.get("CC_LESSON_SYMPTOMS")
        or os.path.join(REPO_ROOT, "hooks", "lib", "lesson-symptoms.tsv")
    )
    lits: List[Tuple[str, str]] = []
    canary: Optional[str] = None
    with open(path, encoding="utf-8") as fh:
        for line in fh.read().split("\n"):
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            cells = line.split("\t")
            if len(cells) < 2 or len(cells[0]) < 12:
                continue
            if cells[0].startswith(CANARY_PREFIX):
                canary = cells[0]
            else:
                slug = os.path.basename(cells[1].strip())
                lits.append((cells[0], slug[:-3] if slug.endswith(".md") else slug))
    return lits, canary


def _result_text(content: object) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(
            b.get("text", "")
            for b in content
            if isinstance(b, dict) and isinstance(b.get("text"), str)
        )
    return ""


def _window(t: str) -> str:
    return t if len(t) <= 2 * SCAN_CHARS else t[:SCAN_CHARS] + "\n" + t[-SCAN_CHARS:]


def denominator(cutoff: float, kind: str, lits: List[Tuple[str, str]]) -> int:
    n = 0
    for path in _files(cutoff):
        bash: Dict[str, str] = {}
        try:
            fh = open(path, encoding="utf-8", errors="replace")
        except OSError:
            continue
        with fh:
            for line in fh:
                is_use = '"tool_use"' in line and '"Bash"' in line
                is_res = '"tool_result"' in line and any(lit in line for lit, _ in lits)
                if not (is_use or is_res):
                    continue
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                content = (
                    ((rec.get("message") or {}).get("content"))
                    if isinstance(rec, dict)
                    else None
                )
                if not isinstance(content, list):
                    continue
                for blk in content:
                    if not isinstance(blk, dict):
                        continue
                    if blk.get("type") == "tool_use" and blk.get("name") == "Bash":
                        bash[str(blk.get("id"))] = str(
                            (blk.get("input") or {}).get("command") or ""
                        )
                    elif (
                        blk.get("type") == "tool_result"
                        and str(blk.get("tool_use_id")) in bash
                    ):
                        if _epoch(rec.get("timestamp")) < cutoff:
                            continue
                        cmd = bash[str(blk.get("tool_use_id"))]
                        if any(m in cmd for m in READ_OF_CORPUS):
                            continue
                        if bool(blk.get("is_error")) != (kind == "error"):
                            continue
                        text = _window(_result_text(blk.get("content")))
                        n += sum(
                            1 for lit, slug in lits if lit in text and slug not in text
                        )
    return n


def delivery(days: float, min_age: float) -> Tuple[int, int]:
    now = _now()
    cutoff, newest = now - days * 86400, now - min_age
    hits_path = os.environ.get("CC_LESSON_HITS") or os.path.join(
        _home(), ".claude", "state", "lesson-hits.jsonl"
    )
    want: List[Tuple[str, str]] = []
    try:
        with open(hits_path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                try:
                    r = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(r, dict) or r.get("holdout") is not False:
                    continue
                t = _epoch(r.get("ts"))
                if cutoff <= t <= newest:
                    want.append(
                        (str(r.get("tool_use_id") or ""), str(r.get("slug") or ""))
                    )
    except OSError:
        pass
    if not want:
        return 0, 0
    got: Dict[str, str] = {}
    for path in _files(cutoff):
        try:
            fh = open(path, encoding="utf-8", errors="replace")
        except OSError:
            continue
        with fh:
            for line in fh:
                if (
                    '"hook_additional_context"' not in line
                    or "recalled lesson pointers" not in line
                ):
                    continue
                try:
                    att = (json.loads(line) or {}).get("attachment") or {}
                except ValueError:
                    continue
                tu = att.get("toolUseID")
                body = att.get("content")
                if isinstance(body, str) and body.startswith("["):
                    try:  # some builds store the list JSON-encoded as a string (lead probe, 2.1.278)
                        body = json.loads(body)
                    except ValueError:
                        pass
                text = (
                    "\n".join(x for x in body if isinstance(x, str))
                    if isinstance(body, list)
                    else str(body or "")
                )
                if tu and HEADER in text:
                    got[str(tu)] = got.get(str(tu), "") + "\n" + text
    delivered = sum(1 for tu, slug in want if tu and slug and slug in got.get(tu, ""))
    return delivered, len(want)


def canary() -> Tuple[bool, str]:
    hook = os.environ.get("CC_LR_DEPLOYED_HOOK") or os.path.join(
        _home(), ".claude", "hooks", "bash-output-offload.sh"
    )
    if not os.path.isfile(hook):
        return False, "no deployed hook at %s" % hook
    table = os.path.join(
        os.path.dirname(os.path.realpath(hook)), "lib", "lesson-symptoms.tsv"
    )
    try:
        _, lit = load_literals(table)
    except OSError:
        return False, "no symptom table behind the deployed hook (%s)" % table
    if not lit:
        return False, "the deployed table has no canary row (%s)" % table
    with tempfile.TemporaryDirectory(prefix="lesson-canary.") as tmp:
        env = {
            k: v
            for k, v in os.environ.items()
            if k
            not in (
                "CC_LESSON_RECALL",
                "CC_LESSON_SYMPTOMS",
                "CC_LESSON_RECALL_STATE_DIR",
                "CC_LESSON_HITS",
                "CC_BASH_OFFLOAD",
                "CC_BASH_OFFLOAD_CHARS",
            )
        }
        env.update(
            HOME=tmp,
            CC_IDL=os.path.join(tmp, "idl.jsonl"),
            CC_BASH_OFFLOAD_DIR=os.path.join(tmp, "offload"),
        )
        payload = {
            "hook_event_name": "PostToolUse",
            "tool_name": "Bash",
            "session_id": "lesson-canary",
            "tool_use_id": "toolu_lesson_canary",
            "tool_input": {"command": "./nightly-canary.sh"},
            "tool_response": {
                "stdout": "nightly canary: %s\n" % lit,
                "stderr": "",
                "interrupted": False,
                "isImage": False,
                "noOutputExpected": False,
            },
        }
        try:
            p = subprocess.run(
                ["bash", hook],
                input=json.dumps(payload).encode("utf-8"),
                env=env,
                capture_output=True,
                timeout=60,
            )
        except (OSError, subprocess.TimeoutExpired) as e:
            return False, "hook did not run: %s" % type(e).__name__
        out = p.stdout.decode("utf-8", "replace").strip()
        try:
            objs = [json.loads(x) for x in out.split("\n") if x.strip()]
        except ValueError:
            return False, "hook output is not JSON: %r" % out[:200]
        if len(objs) != 1:
            return False, "expected ONE output object, got %d" % len(objs)
        ctx = ((objs[0].get("hookSpecificOutput") or {}).get("additionalContext")) or ""
        n = sum(
            1
            for ln in ctx.split("\n")
            if ln.startswith("this output matches a known symptom")
        )
        if not ctx.startswith(HEADER) or n != 1:
            return False, "expected one pointer under the header, got %d in %r" % (
                n,
                ctx[:200],
            )
    return True, "one pointer from %s" % hook


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--denominator", action="store_true")
    mode.add_argument("--delivery", action="store_true")
    mode.add_argument("--canary", action="store_true")
    ap.add_argument("--cutoff", type=float)
    ap.add_argument("--kind", choices=("ok", "error"), default="ok")
    ap.add_argument("--days", type=float, default=1.0)
    ap.add_argument("--min-age", type=float, default=600.0)
    a = ap.parse_args(argv)
    if a.denominator:
        if a.cutoff is None:
            ap.error("--denominator needs --cutoff EPOCH")
        lits, _ = load_literals()
        print(denominator(a.cutoff, a.kind, lits))
        return 0
    if a.delivery:
        d, e = delivery(a.days, a.min_age)
        verdict = "unknown" if e == 0 else ("ok" if d / e >= 0.9 else "low")
        print("%d/%d" % (d, e))
        print("DELIVERY-VERDICT %s" % verdict)
        return 1 if verdict == "low" else 0
    ok, why = canary()
    print("CANARY-VERDICT %s — %s" % ("ok" if ok else "fail", why))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
