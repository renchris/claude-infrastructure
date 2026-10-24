#!/usr/bin/env python3
# per successful land: commits = rev-list --count base..head, on_main = head is ancestor of origin/main
# usage: python3 -I landcommits.py <repo> <lands.jsonl> <out.jsonl>
import json, subprocess, sys
repo, inp, outp = sys.argv[1:4]
out = open(outp, "w")
for l in open(inp):
    r = json.loads(l)
    if r["exit"] == 0 and r.get("head") and r.get("base"):
        c = subprocess.run(["git", "-C", repo, "rev-list", "--count", "%s..%s" % (r["base"], r["head"])], capture_output=True, text=True, timeout=30)
        a = subprocess.run(["git", "-C", repo, "merge-base", "--is-ancestor", r["head"], "origin/main"], capture_output=True, timeout=30)
        r["commits"] = int(c.stdout.strip() or -1)
        r["on_main"] = a.returncode == 0
    out.write(json.dumps(r) + "\n")
