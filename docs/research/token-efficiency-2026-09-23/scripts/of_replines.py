#!/usr/bin/env python3
"""of_replines.py — find repeated boilerplate lines in tool_result content (a sample survey).

Samples 800 transcript files (seed 5) from extract.sqlite's ctx table, and for every in-window
tool_result counts each line after normalising digits to N and hex runs to H. Reports the lines
whose total bytes (count x length) are largest per tool — candidates for per-item overhead
(headers, footers, banners, hints) that the pattern regexes in of_scan.py do not name.
Also measures grep-style repeated leading paths: bytes of a 'path:' prefix identical to the
previous line's (what a grouped `path` heading + line-only rows would save).

Prints only normalised line text (<=100 chars) and counts; writes data/of_replines.json.
"""

import json, os, random, re, sqlite3, sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import of_scan as S  # noqa

x = sqlite3.connect(os.path.join(BASE, "data", "extract.sqlite"))
files = [
    r[0]
    for r in x.execute("SELECT file FROM ctx WHERE n_resp_xdup < n_resp ORDER BY file")
]
random.seed(5)
files = random.sample(files, 800)
NUM = re.compile(r"\d+")
HEX = re.compile(r"\b[0-9a-f]{7,40}\b")
GREPP = re.compile(r"^([^\s:]+/[^\s:]+):(\d+[:\-])?")
cnt = defaultdict(Counter)
tot = Counter()
grep_rep = Counter()
grep_tot = Counter()
for fp in files:
    tool = {}
    with open(fp, "rb") as fh:
        for raw in fh:
            if b'"tool_use"' not in raw and b'"tool_result"' not in raw:
                continue
            try:
                r = json.loads(raw)
            except Exception:
                continue
            m = r.get("message") if isinstance(r, dict) else None
            if not isinstance(m, dict) or not isinstance(m.get("content"), list):
                continue
            if r.get("type") == "assistant":
                for b in m["content"]:
                    if isinstance(b, dict) and b.get("type") == "tool_use":
                        inp = b.get("input") if isinstance(b.get("input"), dict) else {}
                        tool[b.get("id")] = (
                            b.get("name") or "",
                            S.program_of(str(inp.get("command") or ""))
                            if b.get("name") == "Bash"
                            else "",
                        )
                continue
            if (r.get("timestamp") or "") < S.SINCE:
                continue
            for b in m["content"]:
                if not isinstance(b, dict) or b.get("type") != "tool_result":
                    continue
                nm, prog = tool.get(b.get("tool_use_id"), ("?", ""))
                text = S.rs_text(b.get("content"))
                tot[nm] += len(text)
                prev = None
                for ln in text.split("\n"):
                    if len(ln) >= 12:
                        k = HEX.sub("H", NUM.sub("N", ln))[:100]
                        cnt[nm][k] += len(ln) + 1
                    mm = GREPP.match(ln)
                    if mm:
                        grep_tot[prog or nm] += len(ln) + 1
                        p = mm.group(1)
                        if p == prev:
                            grep_rep[prog or nm] += len(p) + 1
                        prev = p
                    else:
                        prev = None
out = {
    "files": len(files),
    "tool_chars": dict(tot),
    "top_lines": {},
    "grep_repeated_path_bytes": dict(grep_rep.most_common(15)),
    "grep_line_bytes": {k: grep_tot[k] for k, _ in grep_rep.most_common(15)},
}
for nm in sorted(tot, key=lambda k: -tot[k])[:6]:
    # a line is boilerplate-like when its normalised form repeats >= 20 times
    top = [(k, v) for k, v in cnt[nm].most_common(400)]
    out["top_lines"][nm] = top[:40]
    print("==", nm, tot[nm])
    for k, v in top[:25]:
        print("%9d  %s" % (v, k))
print("grep repeated path bytes:", grep_rep.most_common(10))
with open(os.path.join(BASE, "data", "of_replines.json"), "w") as fh:
    json.dump(out, fh, indent=1)
