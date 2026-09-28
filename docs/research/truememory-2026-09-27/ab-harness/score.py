#!/usr/bin/env python3
"""score.py <ab-runs-root> <config-dir>...  — score the gap-3 A/B from transcripts (read-only).

Per run: invoked cc-memory-search (Bash clause) | any memory search (grep/rg/Grep/find/ls over $RUN/mem,
MEMORY.md, docs/lessons) | opened a gold file | first-pull call index | write tasks: created a NEW
file in $RUN/mem (duplicate) vs edited the gold twin.
Pre-registered decision (see /tmp/tm-research/gap-3.md §5):
  line-arm cc-memory-search rate >= 30% AND one-sided Fisher p < 0.05 vs noline  -> prose consumer counts
  line-arm rate < 10%                                                            -> substrate-only
  otherwise                                                                      -> extend to 30/arm
"""

import glob, json, os, re, sys
from math import comb

root, cfgs = sys.argv[1], sys.argv[2:]
tasks = {
    l.split("\t")[0]: l.rstrip("\n").split("\t")
    for l in open(os.path.join(os.path.dirname(__file__), "tasks.tsv"))
}
SPLIT = re.compile(r"\n|;|&&|\|\||\||\$\(|`")
SEARCH = re.compile(r"^\s*(grep|egrep|rg|find|ls)\b")


def transcript_for(fx):
    slug = re.sub(r"[^A-Za-z0-9]", "-", os.path.realpath(fx))
    for c in cfgs:
        hits = glob.glob(os.path.join(c, "projects", slug, "*.jsonl"))
        if hits:
            return max(hits, key=os.path.getsize)
    return None


def fisher_one(a, n1, c, n2):
    K, N = a + c, n1 + n2
    return sum(comb(n1, x) * comb(n2, K - x) for x in range(a, min(n1, K) + 1)) / comb(
        N, K
    )


rows = []
for rd in sorted(glob.glob(os.path.join(root, "*", "*-r*"))):
    task = os.path.basename(os.path.dirname(rd))
    arm = open(os.path.join(rd, "out", "arm")).read().strip()
    t = tasks[task]
    gold = t[4].split("|")
    mem = os.path.join(rd, "mem")
    tr = transcript_for(os.path.join(rd, "fx"))
    r = {
        "task": task,
        "kind": t[1],
        "arm": arm,
        "ccms": 0,
        "memsearch": 0,
        "gold_read": 0,
        "first_pull": None,
        "new_files": [],
        "gold_edited": 0,
        "transcript": tr,
    }
    if tr:
        i = 0
        for line in open(tr, errors="replace"):
            if '"tool_use"' not in line:
                continue
            for c in (json.loads(line).get("message") or {}).get("content") or []:
                if not (isinstance(c, dict) and c.get("type") == "tool_use"):
                    continue
                i += 1
                inp = c.get("input") or {}
                blob = json.dumps(inp)
                pulled = False
                if c["name"] == "Bash":
                    for cl in SPLIT.split(inp.get("command", "")):
                        if re.search(r"(^|[\s/])cc-memory-search\b", cl):
                            r["ccms"] = 1
                            pulled = True
                        if SEARCH.search(cl) and (
                            mem in cl
                            or "MEMORY.md" in cl
                            or "docs/lessons" in cl
                            or "/memory" in cl
                        ):
                            r["memsearch"] = 1
                            pulled = True
                elif c["name"] in ("Grep", "Glob") and (
                    mem in blob or "MEMORY.md" in blob or "docs/lessons" in blob
                ):
                    r["memsearch"] = 1
                    pulled = True
                if any(g in blob for g in gold) and c["name"] in ("Read", "Bash"):
                    r["gold_read"] = 1
                    pulled = True
                if c["name"] in ("Edit", "MultiEdit") and any(
                    inp.get("file_path", "").endswith("/" + g) for g in gold
                ):
                    r["gold_edited"] = 1
                if pulled and r["first_pull"] is None:
                    r["first_pull"] = i
    before = {l.split()[1] for l in open(os.path.join(rd, "out", "mem.before.sha256"))}
    after_p = os.path.join(rd, "out", "mem.after.sha256")
    if os.path.exists(after_p):
        r["new_files"] = sorted({l.split()[1] for l in open(after_p)} - before)
    rows.append(r)

with open(os.path.join(root, "scored.jsonl"), "w") as f:
    for r in rows:
        f.write(json.dumps(r) + "\n")
for kind in ("read", "write", None):
    sel = [r for r in rows if kind is None or r["kind"] == kind]
    L = [r for r in sel if r["arm"] == "line"]
    N = [r for r in sel if r["arm"] == "noline"]
    if not L or not N:
        continue
    a, c = sum(r["ccms"] for r in L), sum(r["ccms"] for r in N)
    print(
        f"{kind or 'ALL'}: cc-memory-search line {a}/{len(L)} noline {c}/{len(N)}  p1={fisher_one(a, len(L), c, len(N)):.4f}"
        f" | any mem search {sum(r['memsearch'] for r in L)}/{len(L)} vs {sum(r['memsearch'] for r in N)}/{len(N)}"
        f" | gold read {sum(r['gold_read'] for r in L)} vs {sum(r['gold_read'] for r in N)}"
        + (
            f" | dup created {sum(bool(r['new_files']) and not r['gold_edited'] for r in L)} vs {sum(bool(r['new_files']) and not r['gold_edited'] for r in N)}"
            if kind == "write"
            else ""
        )
    )
