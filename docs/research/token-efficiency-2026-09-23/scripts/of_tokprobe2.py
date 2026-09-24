#!/usr/bin/env python3
"""of_tokprobe2.py — two more count_tokens probes (same oracle as of_tokprobe.py):
pad_ws (runs of >=3 inner spaces collapsed to 2, trailing spaces dropped) on Bash samples that
contain table padding, and the 'Shell cwd was reset to <dir>' note repeated 300x.
Merges results into data/of_tokprobe.json."""
import json, os, re, random, sys
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import of_tokprobe as T, of_scan as S
random.seed(3)
tp = json.load(open(os.path.join(T.BASE, "data", "of_tokprobe.json")))
base = tp["baseline_tokens"]
bp = [t for t in T.load("bash_plain") if len(S.PADWS.findall(t)) >= 10]
random.shuffle(bp)
o = "\n".join(T.pack(bp))
c = S.PADWS.sub(lambda m: "  " if m.group(0).strip("\n") and not m.group(0).endswith("\n") and m.end() < len(o) and o[m.end()] != "\n" else "", o)
c = re.sub(r"(?<=\S) {3,}(?=\S)", "  ", o); c = re.sub(r" +$", "", c, flags=re.M)
res = {}
for k, (a, b) in {"pad_ws": (o, c), "cwd_reset": ("\n".join(["Shell cwd was reset to /Users/chrisren/Development/claude-infrastructure"] * 300), "")}.items():
    ta, _ = T.count(k + "_o", a)
    tb, _ = T.count(k + "_c", b) if b else (base, 0)
    dt = (ta - base) - (tb - base); dc = len(a) - len(b)
    res[k] = {"orig_chars": len(a), "clean_chars": len(b), "removed_chars": dc, "removed_tokens": dt, "tokens_per_removed_char": round(dt / dc, 4)}
    print(k, res[k])
tp.update(res)
json.dump(tp, open(os.path.join(T.BASE, "data", "of_tokprobe.json"), "w"), indent=1)
