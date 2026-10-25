#!/usr/bin/env python3
"""build_cases.py — the D4 population: every subagent Bash call over a window whose command is a
poll loop (plan § W7+ §2 D4 "Offline"). Read-only over transcripts.

WHO IS IN IT. A Bash tool_use inside a subagent transcript (…/<sid>/subagents/**/agent-<id>.jsonl)
whose command matches scan.py's POLL regex — an until/while loop that sleeps, `select(undef`, or
`time.sleep(` — timed by its assistant record. This is the census the design's 3,730 counts
(noise-floor d4events.py: n_28d=3730 over 1790398800 + 28 d, gap>300 s 326). POLL is the CENSUS
regex, not the hook's: the hook's own pattern is what the eval grades, so the population must not
be drawn by it.

DEDUPE. A session copied into another account's tree carries the same tool_use ids; the copy in
the file with the EARLIEST mtime owns the call (the cc-token-ledger rule: the original stops being
written when the session moves).

PER CASE (decision-time inputs first, outcomes after):
  input    tool_use_id, agent_id, sid, acct, t, cmd, timeout_ms (null when unset), bg, wf (a
           Workflow agent); rid and file locate the call (flow.census() restates the design's
           per-request count from them)
  outcome  rt     tool_result time − call time, s (null when the call never returned)
           gap    next request time − calling request time, s (null when none followed)
           ctx    the calling request's context; ncw — the next request's cache write
           reb    gap > 300 s: the 5-minute subagent cache had expired at the next request
           is_wait  the label: the call held the agent past a safe slice — rt ≥ 270 s, or with no
                  result, gap ≥ 270 s. It is an OUTCOME, read from the transcript, so it is
                  independent of the command text the hook judges.

usage: python3 -I build_cases.py --out CASES [--days 28] [--start EPOCH] [--end EPOCH]
Stdlib only, Python 3.9-safe.
"""

import argparse
import collections
import json
import os
import re
import sys
import time
from datetime import datetime

HOME = os.path.expanduser("~")
ROOTS = (
    ("next", ".claude-next"),
    ("next2", ".claude-secondary"),
    ("next3", ".claude-tertiary"),
    ("next4", ".claude-quaternary"),
)
POLL = re.compile(
    r"\b(until|while)\b[\s\S]{0,600}?\bsleep\b|select\(undef|time\.sleep\("
)
PREFILTER = (b"sleep", b"select(undef")
SLICE_S = 270.0
CACHE_S = 300.0
REF_START = (
    1790398800.0  # noise-floor d4events.py S: the census the design's 3,730 counts
)
REF_DAYS = 28.0


def roots():
    """(acct, projects dir) for the four accounts; CC_LEVER_EVAL_ROOTS="acct=dir,..." overrides."""
    env = os.environ.get("CC_LEVER_EVAL_ROOTS")
    if env:
        return [tuple(x.split("=", 1)) for x in env.split(",") if "=" in x]
    return [(a, os.path.join(HOME, d, "projects")) for a, d in ROOTS]


def ep(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except (ValueError, AttributeError):
        return None


def subagent_files(root, S):
    """→ [(path, mtime)] for subagent transcripts written since S."""
    out = []
    for dp, _dn, fn in os.walk(root, followlinks=True):
        if "/subagents" not in dp:
            continue
        for f in fn:
            if not (f.startswith("agent-") and f.endswith(".jsonl")):
                continue
            p = os.path.join(dp, f)
            try:
                mt = os.stat(p).st_mtime
            except OSError:
                continue
            if mt >= S:
                out.append((p, mt))
    return out


def scan_file(path):
    """One pass. → (requests [(ts, ctx, cw, rid)], calls [dict], results {tool_use_id: ts})."""
    try:
        with open(path, "rb") as fh:
            data = fh.read()
    except OSError:
        return [], [], {}
    if not any(m in data for m in PREFILTER):
        return [], [], {}
    reqs, calls, res = [], [], {}
    for line in data.splitlines():
        head = line[:1500]
        if b'"tool_result"' in line and (
            b'"type":"user"' in head or b'"type": "user"' in head
        ):
            try:
                j = json.loads(line)
            except ValueError:
                continue
            t = ep(j.get("timestamp", ""))
            c = (j.get("message") or {}).get("content")
            for b in c if isinstance(c, list) else ():
                if (
                    isinstance(b, dict)
                    and b.get("type") == "tool_result"
                    and b.get("tool_use_id")
                ):
                    res.setdefault(b["tool_use_id"], t)
            continue
        if b'"usage"' not in line or b'"assistant"' not in head:
            continue
        try:
            j = json.loads(line)
        except ValueError:
            continue
        m = j.get("message") or {}
        u = m.get("usage")
        if (
            j.get("type") != "assistant"
            or not isinstance(u, dict)
            or m.get("model") == "<synthetic>"
        ):
            continue
        rid = j.get("requestId") or m.get("id")
        t = ep(j.get("timestamp", ""))
        if not reqs or reqs[-1][3] != rid:
            cw = u.get("cache_creation_input_tokens") or 0
            ctx = (
                (u.get("input_tokens") or 0)
                + cw
                + (u.get("cache_read_input_tokens") or 0)
            )
            reqs.append((t, ctx, cw, rid))
        for b in m.get("content") or ():
            if not (
                isinstance(b, dict)
                and b.get("type") == "tool_use"
                and b.get("name") == "Bash"
            ):
                continue
            bi = b.get("input") or {}
            cmd = str(bi.get("command", ""))
            if not POLL.search(cmd):
                continue
            to = bi.get("timeout")
            calls.append(
                dict(
                    tool_use_id=b.get("id"),
                    t=t,
                    cmd=cmd,
                    ri=len(reqs) - 1,
                    timeout_ms=int(to) if isinstance(to, (int, float)) else None,
                    bg=bool(bi.get("run_in_background")),
                )
            )
    return reqs, calls, res


def build(S, E, now=None):
    """→ (cases, meta). Raises OSError naming the root when a projects root cannot be read."""
    now = now or time.time()
    found = {}  # tool_use_id -> (file mtime, case)
    roots_read = {}
    for acct, root in roots():
        if not os.path.isdir(root):
            raise OSError("projects root unreadable: %s (%s)" % (acct, root))
        files = subagent_files(root, S)
        roots_read[acct] = len(files)
        for p, mt in files:
            reqs, calls, res = scan_file(p)
            parts = p.split("/subagents/")[0].rstrip("/").split("/")
            sid, aid = parts[-1], os.path.basename(p)[len("agent-") : -len(".jsonl")]
            for c in calls:
                t = c["t"]
                if t is None or not (S <= t < E) or not c["tool_use_id"]:
                    continue
                ri = c.pop("ri")
                ctx, nxt = reqs[ri][1], reqs[ri + 1] if ri + 1 < len(reqs) else None
                gap = (nxt[0] - reqs[ri][0]) if nxt and nxt[0] and reqs[ri][0] else None
                tr = res.get(c["tool_use_id"])
                rt = (tr - t) if tr is not None else None
                held = rt if rt is not None else gap
                g = dict(
                    c,
                    case_id=c["tool_use_id"],
                    agent_id=aid,
                    sid=sid,
                    acct=acct,
                    rid=reqs[ri][3],
                    file=p,
                    wf="/workflows/" in p,
                    rt=rt,
                    gap=gap,
                    ctx=ctx,
                    ncw=nxt[2] if nxt else None,
                    reb=bool(gap is not None and gap > CACHE_S),
                    is_wait=bool(held is not None and held >= SLICE_S),
                )
                prev = found.get(g["case_id"])
                if prev is None or mt < prev[0]:
                    found[g["case_id"]] = (mt, g)
    cases = sorted(
        (g for _mt, g in found.values()), key=lambda g: (g["t"], g["case_id"])
    )
    meta = dict(
        schema=2,
        flow="d4_pollloop",
        start=S,
        end=E,
        window_s=E - S,
        built_at=now,
        roots=roots_read,
        cases=len(cases),
        gap_over_300=sum(1 for g in cases if g["reb"]),
        is_wait=sum(1 for g in cases if g["is_wait"]),
        by_acct=dict(collections.Counter(g["acct"] for g in cases)),
    )
    return cases, meta


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--days", type=float, default=REF_DAYS)
    ap.add_argument("--end", type=float, default=None)
    ap.add_argument("--start", type=float, default=None)
    ap.add_argument("--out", required=True)
    a = ap.parse_args(argv)
    if a.start is not None:
        S = a.start
        E = a.end if a.end is not None else S + a.days * 86400
    else:
        E = a.end if a.end is not None else time.time()
        S = E - a.days * 86400
    cases, meta = build(S, E)
    tmp = a.out + ".tmp%d" % os.getpid()
    with open(tmp, "w") as fh:
        for g in cases:
            fh.write(json.dumps(g, separators=(",", ":")) + "\n")
    os.replace(tmp, a.out)
    with open(a.out + ".meta", "w") as fh:
        json.dump(meta, fh, sort_keys=True)
    print(json.dumps(meta, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
