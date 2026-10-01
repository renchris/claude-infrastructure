#!/usr/bin/env python3
"""heldout-candidates.py — build the candidate prompts `heldout.py seal` splits into the router's
tuning set and its sealed held-out set (REPORT.md §10 open items 12 and 13; wave B1 of
docs/plans/RESEARCH_PROGRAM_BUILD.md).

The three census scripts that measured the old regex print COUNTS and truncated examples, never the
prompts, and adv_opscope_bypass.py reads a /tmp list that a reboot wiped; so the prompts are mined
again here, from the same transcripts with the same patterns, into the strata of §10 item 12:

  regex-matched  a genuine prompt the old completeness pattern matches
                 (evidence/adversary/llm/ask_turns.py `Q`; it selected the 280 asks)
  regex-missed   a gap-seeking paraphrase the widened pattern misses (regex_recall.py `GAP` and not
                 `WIDE`), or the first genuine prompt after a done-claim that `WIDE` misses
                 (adversary/opscope/adv_opscope_bypass.py `CLAIM`, the 77 of 125)
  pushback       a short challenge with no location ("are you sure?", "really?", "no take-backs?")
  other          everything else, sampled — work orders, ideas, concerns, chatter (§10 item 11's
                 correct-label floor is measured on these)

  heldout-candidates.py [--transcripts GLOB]... [--days 60] [--cap 60] --out C.jsonl

Rows are {prompt, stratum, source}; source is "<session id prefix>@<timestamp>". The sample inside a
stratum is the first --cap prompts in sha256 order, so a re-run over the same transcripts picks the
same set. It prints counts per stratum and NEVER a prompt: the router's builder must not read the
candidates, half of which are about to be sealed (heldout.py's header, §7).
"""

from __future__ import annotations

import argparse
import glob
import hashlib
import json
import os
import re
import sys
import time
from pathlib import Path
from typing import Dict, Iterator, List, Optional, Tuple

# Verbatim from the census scripts, so a stratum means what the measurement meant.
Q = re.compile(
    r"100\.00\s*/\s*100\.00|100\s*/\s*100|are we (100%? )?(complete|done)|100% complete|absolute perfection",
    re.I,
)
WIDE = re.compile(
    Q.pattern + r"|100th|perfect|exhaust|take[- ]?back|nothing left|good to close", re.I
)
GAP = re.compile(
    r"anything (else )?(we'?re |we are |i'?m )?(missing|overlook|left)|what(?:'s| is| else is)? (still )?(missing|left|remaining)|any (more )?(gaps?|holes?|loose ends)|"
    r"what else (do|should|could|would|can)|fresh[- ]eyes|double[- ]check|are you (sure|certain|confident)|"
    r"left on the table|what would (make|bring|get)|can (anything|anyone|we) (beat|do better)|best possible|optimum|"
    r"is (this|that|it) (really )?(everything|all)|did we (miss|forget|cover)|what did (we|you) miss|"
    r"end[- ]?game|no[- ]take[- ]?backs?|fully (done|complete|covered)|truly (done|complete)|really (done|complete)",
    re.I,
)
CLAIM = re.compile(
    r"Good to close:\s*yes|✅ Complete|safe to close|exhaustively done|100\.00\s*/\s*100\.00 complete|Complete & live",
    re.I,
)
# Pushback: a SHORT challenge carrying no location. The location test is the router's concern
# route's discriminator (§4.1), so a challenge that names a file, line or row is not pushback.
PUSHBACK = re.compile(
    r"^\W*(are you (sure|certain|confident)|you sure|really\b|no[- ]?take[- ]?backs?|double[- ]check|"
    r"sure about (that|this)|is that (right|true|correct)|are we sure)",
    re.I,
)
LOCATION = re.compile(r"[\w./-]+:\d+|\bline \d+|\b(row|decision|check|item|step)\s?#?\d+\b|#\d+", re.I)
MACHINE = re.compile(
    r"^\s*(\[handoff |<teammate-message|<task-notification|<local-command-stdout>|<command-name>)"
    r"|HANDOFF-ENGAGE-[A-Za-z0-9._-]+"
)
PUSHBACK_MAX = 200


def genuine(c: object) -> Optional[str]:
    """The census scripts' genuine-prompt filter (regex_recall.py), plus the machine envelopes."""
    if not isinstance(c, str):
        return None
    s = c.strip()
    if (
        not s
        or s.startswith("<")
        or s.startswith("[")
        or "Workflow harness" in s
        or len(s) > 1500
        or s.startswith("TASK")
        or "Scope (frozen)" in s
        or MACHINE.search(s)
    ):
        return None
    return s


def prompts(files: List[str]) -> Iterator[Tuple[str, str, bool]]:
    """(prompt, source, follows_a_done_claim) for every genuine prompt, in file order."""
    for f in files:
        last_claim = False
        sid = Path(f).stem[:8]
        try:
            fh = open(f, "rb")
        except OSError:
            continue
        with fh:
            for line in fh:
                try:
                    r = json.loads(line)
                except ValueError:
                    continue
                if r.get("type") == "assistant":
                    for b in (r.get("message") or {}).get("content") or []:
                        if isinstance(b, dict) and b.get("type") == "text" and CLAIM.search(b.get("text", "")):
                            last_claim = True
                    continue
                if r.get("type") != "user" or r.get("isMeta") or r.get("isSidechain"):
                    continue
                s = genuine((r.get("message") or {}).get("content"))
                if s is None:
                    continue
                yield s, f"{sid}@{str(r.get('timestamp', ''))[:19]}", last_claim
                last_claim = False


def stratum(s: str, after_claim: bool) -> str:
    if len(s) <= PUSHBACK_MAX and PUSHBACK.search(s) and not LOCATION.search(s) and not Q.search(s):
        return "pushback"
    if Q.search(s):
        return "regex-matched"
    if not WIDE.search(s) and (GAP.search(s) or after_claim):
        return "regex-missed"
    return "other"


def build(files: List[str], cap: int) -> Dict[str, List[Dict[str, str]]]:
    seen = set()
    by: Dict[str, List[Dict[str, str]]] = {k: [] for k in ("regex-matched", "regex-missed", "pushback", "other")}
    for s, src, after in prompts(files):
        k = s[:200]
        if k in seen:
            continue
        seen.add(k)
        by[stratum(s, after)].append({"prompt": s, "stratum": stratum(s, after), "source": src})
    for k in by:
        by[k].sort(key=lambda c: hashlib.sha256(c["prompt"].encode()).hexdigest())
        del by[k][cap:]
    return by


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(prog="heldout-candidates.py")
    ap.add_argument("--transcripts", action="append",
                    help="glob of transcript files (default ~/.claude*/projects/*/*.jsonl)")
    ap.add_argument("--days", type=float, default=60.0, help="only transcripts modified this recently")
    ap.add_argument("--cap", type=int, default=60, help="prompts kept per stratum")
    ap.add_argument("--out", required=True)
    a = ap.parse_args(argv)
    globs = a.transcripts or [os.path.expanduser("~/.claude*/projects/*/*.jsonl")]
    cut = time.time() - a.days * 86400
    files = sorted({f for g in globs for f in glob.glob(os.path.expanduser(g)) if os.path.getmtime(f) >= cut})
    by = build(files, a.cap)
    rows = [c for k in by for c in by[k]]
    Path(a.out).write_text("".join(json.dumps(c, sort_keys=True) + "\n" for c in rows))
    counts = {k: len(v) for k, v in by.items()}
    print(f"{len(files)} transcript(s); candidates per stratum {json.dumps(counts, sort_keys=True)} -> {a.out}")
    empty = [k for k, n in counts.items() if n == 0]
    if empty:
        print(f"heldout-candidates.py: no {', '.join(empty)} candidate; heldout.py seal will refuse", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
