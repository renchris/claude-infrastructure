#!/usr/bin/env python3
"""Classify the next call after each real subagent deny (rows from deny_followups.py).
Usage: python3 -I classify_followups.py <followups.jsonl> [examples_out.txt]
Wait-type denies (built-in sleep block, /goal gate): what shape did the agent's NEXT call take, and
did it take one of the shapes the deny TOLD it to take?
rm -r deny: did the next Bash adopt the prescribed `mktemp -d … rm -rf "$D"` form, drop the rm, retry
the forbidden form, or evade (find -delete / rmtree / rsync --delete)?"""

import json, re, sys
from collections import Counter, defaultdict

rows = [json.loads(l) for l in open(sys.argv[1])]
LOOP = re.compile(r"(^|[;&|\s(])(while|until|for)\s.*sleep\s", re.S)
SLEEP_N = re.compile(r"(^|[;&|\s(])(/bin/)?sleep\s+([0-9]+)")
RMR = re.compile(r"(^|[;&|\s(])rm\s+(-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)")
EVADE = re.compile(
    r"find\s.*-delete|shutil\.rmtree|rsync\s.*--delete|os\.removedirs|rm -r.*\.sh|perl.*rmtree"
)


def wait_shape(n):
    if n is None:
        return "ended (no further call)"
    nm, inp = n["name"], n["input"]
    if nm == "Bash":
        c = inp.get("command") or ""
        to = inp.get("timeout")
        bg = bool(inp.get("run_in_background"))
        long_to = isinstance(to, (int, float)) and to > 270000
        if LOOP.search(c):
            s = "loop"
        elif any(int(m.group(3)) >= 20 for m in SLEEP_N.finditer(c)):
            s = "sleep>=20"
        elif SLEEP_N.search(c):
            s = "sleep<20"
        elif "cc-await-ping" in c:
            s = "cc-await-ping"
        else:
            s = "other"
        return "Bash %s %s %s" % (
            "bg" if bg else "fg",
            s,
            "to>270000" if long_to else "to<=270000/none",
        )
    return nm


def summarize(cls, told):
    R = [r for r in rows if r["cls"] == cls]
    if not R:
        return
    print("=" * 100)
    print(
        "%s: %d unique denies in %d agent files"
        % (cls, len(R), len({r["file"] for r in R}))
    )
    k = Counter()
    told_n = 0
    wait_kept = 0
    re_denied = 0
    long_fg = 0
    for r in R:
        n = r["next"][0] if r["next"] else None
        s = wait_shape(n)
        k[s] += 1
        if told(n):
            told_n += 1
        if (
            s.startswith("Bash")
            and ("loop" in s or "sleep" in s or "cc-await" in s)
            or s in ("Monitor", "TaskOutput", "BashOutput")
        ):
            wait_kept += 1
        if n and n.get("denied"):
            re_denied += 1
        if (
            s.startswith("Bash fg")
            and ("loop" in s or "sleep>=20" in s)
            and "to>270000" in s
        ):
            long_fg += 1
    for a, b in k.most_common():
        print("  %4d  %s" % (b, a))
    print(
        "  -> next call took a shape the deny told it to: %d/%d (%.0f%%)"
        % (told_n, len(R), 100.0 * told_n / len(R))
    )
    print(
        "  -> next call is still a wait (loop/sleep/Monitor/awaiter): %d/%d"
        % (wait_kept, len(R))
    )
    print("  -> next call was itself denied again: %d/%d" % (re_denied, len(R)))
    print(
        "  -> next call is a LONG foreground wait (tool timeout > 270000; what W3 would deny): %d/%d"
        % (long_fg, len(R))
    )
    # agents that got the same class twice or more
    per = Counter(r["file"] for r in R)
    print(
        "  -> agent files with >=2 denies of this class: %d of %d"
        % (sum(1 for v in per.values() if v >= 2), len(per))
    )


def told_sleep(n):
    # 'use Monitor with an until-loop' or 'use run_in_background: true'
    return n is not None and (
        n["name"] == "Monitor"
        or (n["name"] == "Bash" and bool(n["input"].get("run_in_background")))
    )


def told_goal(n):
    # not a backgrounded parker; the named cure is cc-await-ping --idle-scoped or session-continue
    if n is None:
        return False
    c = n["input"].get("command") or ""
    return n["name"] == "Bash" and ("--idle-scoped" in c or "session-continue" in c)


def not_bg_parker(n):
    if n is None:
        return True
    return not (
        n["name"] == "Bash"
        and n["input"].get("run_in_background")
        and LOOP.search(n["input"].get("command") or "")
    )


summarize("builtin-sleep-block", told_sleep)
summarize("goal-gate", told_goal)
G = [r for r in rows if r["cls"] == "goal-gate"]
print(
    "  -> goal-gate: next call is NOT another backgrounded poll loop (obeys the prohibition): %d/%d"
    % (sum(not_bg_parker(r["next"][0] if r["next"] else None) for r in G), len(G))
)

# ---------------- rm -r deny ----------------
RM = [r for r in rows if r["cls"].startswith("other:Refused inside a subagent: no one")]
print("=" * 100)
print(
    'subagent rm -r deny (prescribed form: D=$(mktemp -d /tmp/<name>.XXXXXX) ... rm -rf "$D" in one command): %d unique denies, %d agent files'
    % (len(RM), len({r["file"] for r in RM}))
)
k = Counter()
ex = defaultdict(list)
for r in RM:
    nb = [n for n in r["next"] if n["name"] == "Bash"]
    n0 = r["next"][0] if r["next"] else None
    if n0 is None:
        cat = "ended (no further call)"
    elif n0["name"] != "Bash":
        cat = "next call not Bash (%s)" % n0["name"]
    else:
        c = n0["input"].get("command") or ""
        if EVADE.search(c):
            cat = "EVADE (find -delete / rmtree / rsync --delete)"
        elif "mktemp -d" in c and RMR.search(c):
            cat = "ADOPTED prescribed mktemp+rm form" + (
                " (denied again)" if n0["denied"] else ""
            )
        elif RMR.search(c):
            cat = "RETRIED rm -r (other form)" + (
                " (denied again)" if n0["denied"] else " (allowed)"
            )
        elif "mktemp -d" in c:
            cat = "mktemp, no rm (dropped deletion, fresh dir)"
        else:
            cat = "dropped the rm, continued"
    k[cat] += 1
    if len(ex[cat]) < 3:
        ex[cat].append(
            (
                r["denied_input"].get("command", "")[:200],
                (n0 or {}).get("input", {}).get("command", "")[:200] if n0 else "",
            )
        )
for a, b in k.most_common():
    print("  %4d  %s" % (b, a))
den2 = sum(1 for r in RM if r["next"] and r["next"][0]["denied"])
print("  -> next call denied again (any hook): %d/%d" % (den2, len(RM)))
per = Counter(r["file"] for r in RM)
print(
    "  -> agent files with >=2 rm denies: %d of %d"
    % (sum(1 for v in per.values() if v >= 2), len(per))
)
if len(sys.argv) > 2:
    with open(sys.argv[2], "w") as fo:
        for cat, L in ex.items():
            fo.write("### %s\n" % cat)
            for a, b in L:
                fo.write(
                    "DENIED: %s\nNEXT:   %s\n\n"
                    % (a.replace("\n", " "), b.replace("\n", " "))
                )
