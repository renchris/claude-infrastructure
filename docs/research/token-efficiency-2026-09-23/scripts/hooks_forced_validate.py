#!/usr/bin/env python3
"""Hand-validation aid for the forced-turn classifier in hooks_cost.py.
Draws a stratified sample (seeded) of forced turns per heuristic class, and prints for each:
hook, class, #responses, tool names, Bash heads, and the first ~220 chars of the span's
assistant text (so a reader can judge: substantive / re-format close / poll-rearm / nothing).
Usage: python3 hooks_forced_validate.py [per_class=5] [seed=7]
"""

import json
import random
import sqlite3
import sys

BASE = "/Users/chrisren/Development/.worktrees/wt-feat-token-efficiency-2026-09-23/docs/research/token-efficiency-2026-09-23"
per = int(sys.argv[1]) if len(sys.argv) > 1 else 5
rng = random.Random(int(sys.argv[2]) if len(sys.argv) > 2 else 7)
S = json.load(open(f"{BASE}/data/hooks_forced_samples.json"))
x = sqlite3.connect(f"file:{BASE}/data/extract.sqlite?mode=ro", uri=True)
by = {}
for s in S:
    by.setdefault(s["cls"], []).append(s)
for cls, L in sorted(by.items()):
    for s in rng.sample(L, min(per, len(L))):
        ids = [
            r[0]
            for r in x.execute(
                "SELECT msg_id FROM resp WHERE file=? AND xdup=0 AND seq>? ORDER BY seq LIMIT ?",
                (s["file"], s["s"], s["n_resp"]),
            )
        ]
        want, text = set(ids), []
        for line in open(s["file"]):
            if '"assistant"' not in line:
                continue
            r = json.loads(line)
            m = r.get("message") or {}
            if r.get("type") == "assistant" and m.get("id") in want:
                for b in m.get("content") or []:
                    if b.get("type") == "text" and b.get("text", "").strip():
                        text.append(b["text"].strip().replace("\n", " "))
        t = " || ".join(text)
        print(
            f"[{cls}] {s['hooks'][0][:22]} n_resp={s['n_resp']} ${s['usd']} tools={s['tools'][:6]}"
        )
        if s["bash"]:
            print("    bash:", [b[:60] for b in s["bash"][:3]])
        print("    text:", t[:220] + (" …" if len(t) > 220 else ""))
