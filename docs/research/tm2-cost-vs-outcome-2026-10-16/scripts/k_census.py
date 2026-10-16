#!/usr/bin/env python3
"""k_census.py — raw, deduped token census per SESSION and HOUR, for attribution by k_attrib.py.

Same billing semantics as bin/cc-quota-price `census()` (read its docstring): one billed response
per message.id (fallback requestId, then file#line); the FIRST record fixes timestamp and input
classes; output is the MAX output_tokens over the message's records. Agent output is a LOWER
BOUND (agent transcripts often never write the final record). Window: responses at or after
2026-09-27T00:00Z, files modified at or after it — the same floor as
`bin/cc-quota-price --census --since 2026-09-27`, which this reproduces to within the responses
written while the two scans ran.

A session is a main transcript <root>/<proj>/<sid>.jsonl plus every file under
<root>/<proj>/<sid>/ (subagents, workflow agents). Per session it keeps: the first recorded cwd,
the FIRST non-meta user message (the brief, hook lines left in; k_attrib.py strips them), how many
lines mention the program worktree path, and token sums per (UTC hour, model).

Usage (from the repo root; ~15 min at load ~400):
  python3 -I docs/research/tm2-cost-vs-outcome-2026-10-16/scripts/k_census.py
Writes data/k_raw.json.
"""

import glob, json, os, sys
from collections import defaultdict
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(os.path.dirname(HERE), "data")
HOME = os.path.expanduser("~")
ROOTS = [  # ~/.claude-next/projects is a symlink to ~/.claude/projects: never listed twice
    (os.path.join(HOME, ".claude", "projects"), "next"),
    (os.path.join(HOME, ".claude-secondary", "projects"), "next2"),
    (os.path.join(HOME, ".claude-tertiary", "projects"), "next3"),
    (os.path.join(HOME, ".claude-quaternary", "projects"), "next4"),
]
SUSPECT = b"/.worktrees/tm2-plan"


def ep(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


SINCE = ep("2026-09-27T00:00:00Z")


def user_text(d):
    if d.get("type") != "user" or d.get("isMeta"):
        return None
    m = d.get("message")
    if not isinstance(m, dict):
        return None
    c = m.get("content")
    if isinstance(c, str):
        t = c
    elif isinstance(c, list):
        t = "\n".join(
            b.get("text", "")
            for b in c
            if isinstance(b, dict) and b.get("type") == "text"
        )
    else:
        return None
    t = t.strip()
    if not t or t.startswith("<local-command") or t.startswith("<command-name>/clear"):
        return None
    return t


def main():
    files = defaultdict(list)  # (acct, proj, sid) -> [(path, is_sub)]
    for root, acct in ROOTS:
        for f in glob.iglob(os.path.join(root, "**", "*.jsonl"), recursive=True):
            try:
                if os.stat(f).st_mtime < SINCE:
                    continue
            except OSError:
                continue
            rel = os.path.relpath(f, root).split(os.sep)
            sub = len(rel) > 2
            sid = rel[1] if sub else rel[1][:-6]
            files[(acct, rel[0], sid)].append((f, sub))
    sys.stderr.write(
        f"k_census: {sum(len(v) for v in files.values())} files in {len(files)} sessions\n"
    )

    seen, counted = set(), {}
    recs = []  # [skey, ts, model, input, output, cc, cr]
    meta = {"files": 0, "records": 0, "deduped": 0, "repeats": 0}
    sess = {}
    for skey, flist in files.items():
        flist.sort(key=lambda x: (x[1], x[0]))  # main transcript first
        cwd, brief, susp = None, None, 0
        for f, sub in flist:
            meta["files"] += 1
            try:
                fh = open(f, "rb")
            except OSError:
                continue
            with fh:
                for lineno, line in enumerate(fh):
                    if SUSPECT in line:
                        susp += 1
                    need_meta = cwd is None or (brief is None and not sub)
                    has_usage = b'"usage"' in line
                    if not has_usage and not need_meta:
                        continue
                    try:
                        d = json.loads(line)
                    except (ValueError, UnicodeDecodeError):
                        continue
                    if need_meta:
                        if cwd is None and isinstance(d.get("cwd"), str):
                            cwd = d["cwd"]
                        if brief is None and not sub:
                            t = user_text(d)
                            if t:
                                brief = t[:3000]
                    if not has_usage:
                        continue
                    m = d.get("message")
                    if not isinstance(m, dict) or not isinstance(m.get("usage"), dict):
                        continue
                    u = m["usage"]
                    meta["records"] += 1
                    key = m.get("id") or d.get("requestId") or f"{f}#{lineno}"
                    if key in seen:
                        meta["repeats"] += 1
                        i = counted.get(key)
                        if i is not None:
                            o = int(u.get("output_tokens") or 0)
                            if o > recs[i][4]:
                                recs[i][4] = o
                        continue
                    seen.add(key)
                    counted[key] = None
                    try:
                        t = ep(d.get("timestamp"))
                    except Exception:
                        continue
                    if t < SINCE:
                        continue
                    counted[key] = len(recs)
                    meta["deduped"] += 1
                    recs.append(
                        [
                            skey,
                            t,
                            m.get("model") or "unknown",
                            int(u.get("input_tokens") or 0),
                            int(u.get("output_tokens") or 0),
                            int(u.get("cache_creation_input_tokens") or 0),
                            int(u.get("cache_read_input_tokens") or 0),
                        ]
                    )
        sess[skey] = {
            "acct": skey[0],
            "proj": skey[1],
            "sid": skey[2],
            "cwd": cwd or "",
            "brief": brief or "",
            "suspect_lines": susp,
            "hours": {},
        }
    for skey, t, model, i, o, cc, cr in recs:
        h = sess[skey]["hours"].setdefault(
            f"{int(t // 3600) * 3600}|{model}", [0, 0, 0, 0, 0]
        )
        h[0] += 1
        h[1] += i
        h[2] += o
        h[3] += cc
        h[4] += cr
    os.makedirs(DATA, exist_ok=True)
    with open(os.path.join(DATA, "k_raw.json"), "w") as fh:
        json.dump(
            {
                "since": "2026-09-27T00:00:00Z",
                "meta": meta,
                "sessions": [s for s in sess.values() if s["hours"]],
            },
            fh,
        )
    tot = [sum(r[k] for r in recs) for k in (3, 4, 5, 6)]
    sys.stderr.write(
        f"k_census: responses={len(recs)} input={tot[0]} output={tot[1]} "
        f"cache_creation={tot[2]} cache_read={tot[3]}\n"
    )


if __name__ == "__main__":
    main()
