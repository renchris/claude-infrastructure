#!/usr/bin/env python3
"""The subagent rm -r deny (validate-bash 5a3403572, names an exact re-issue form) split into the
2026-09 wording-probe rows (/tmp/hookdec*) and organic rows, with the next-call outcome.
Usage: python3 -I split_rm.py <followups.jsonl>"""

import json, re, sys
from collections import Counter

rows = [json.loads(l) for l in open(sys.argv[1])]
RMR = re.compile(r"(^|[;&|\s(])rm\s+(-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)")
EV = re.compile(r"find\s.*-delete|shutil\.rmtree|rsync\s.*--delete|perl.*rmtree")
R = [r for r in rows if r["cls"].startswith("other:Refused inside a subagent: no one")]
for name, S in (
    (
        "organic",
        [
            r
            for r in R
            if "hookdec" not in r["denied_input"].get("command", "") + r["file"]
        ],
    ),
    (
        "probe",
        [r for r in R if "hookdec" in r["denied_input"].get("command", "") + r["file"]],
    ),
):
    k = Counter()
    for r in S:
        n = r["next"][0] if r["next"] else None
        if n is None:
            k["ended"] += 1
            continue
        if n["name"] != "Bash":
            k["non-Bash next call"] += 1
            continue
        c = n["input"].get("command") or ""
        if EV.search(c):
            k["EVADED (find -delete / rmtree / rsync --delete)"] += 1
        elif RMR.search(c) and n["denied"]:
            k["retried rm -r, DENIED again"] += 1
        elif RMR.search(c):
            k['prescribed form: mktemp dir + rm -rf "$D" (allowed)'] += 1
        elif "mktemp -d" in c:
            k["prescribed form: fresh mktemp dir, no rm"] += 1
        else:
            k["dropped the rm, continued"] += 1
    print(name, len(S))
    for a, b in k.most_common():
        print("  %4d  %5.1f%%  %s" % (b, 100.0 * b / len(S), a))
