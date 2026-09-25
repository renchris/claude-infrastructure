#!/usr/bin/env python3
"""drain-stale-replay.py [hours=24] — replay CC_DRAIN_STALE_FORWARD_H over every real inbox (wave 2, item 3).

For every forwarded line in ~/.claude/mailbox/*.md, the age that matters is the ORIGIN stamp's age at
the moment the line was DELIVERED (its first, forwarding stamp): that is what mailbox-drain.sh's flag
compares against `now` when it renders the line. A line older than H at delivery is one the flag would
summarise to its stamps, sender, the first 100 chars and a grep pointer. This prints how many such lines
exist, their size, and WHAT they are (by sender and by a coarse message kind), so the decision can rest
on whether anything the flag would summarise is a peer request a session must act on.
Read-only; prints markdown.
"""

import glob, os, re, sys
from collections import Counter
from datetime import datetime

H = float(sys.argv[1]) if len(sys.argv) > 1 else 24.0
BOX = os.path.expanduser("~/.claude/mailbox")
pat = re.compile(r"^((?:\S+ \[forwarded:[^\]]*\] )+)(\S+) (\[[^\]]*\] )?(.*)$")
first = re.compile(r"^(\S+) \[forwarded:")


def ts(s):
    try:
        return datetime.strptime(s, "%Y-%m-%dT%H:%M:%S%z")
    except ValueError:
        return None


def kind(msg):
    for k, rx in (
        ("HANDOFF-PING (peer report)", r"HANDOFF-PING"),
        ("WAKE-PATH-DOWN/CLASS (watcher notice)", r"WAKE-PATH-(DOWN|CLASS)"),
        ("SUPERVISOR PAGE", r"SUPERVISOR PAGE"),
        ("CONTEXT n% FULL", r"CONTEXT \d+% FULL"),
        ("lr-fleet / recovery verdict", r"lr-fleet|RECOVERED|verdict="),
        ("handoff / recycle notice", r"HANDOFF-|RECYCLE|recycle"),
        ("custody / completion", r"custody|COMPLETION|completion-push"),
    ):
        if re.search(rx, msg):
            return k
    return "other"


rows = []
for f in sorted(glob.glob(f"{BOX}/*.md")):
    try:
        lines = open(f, encoding="utf-8", errors="replace").read().split("\n")
    except OSError:
        continue
    for raw in lines:
        m = pat.match(raw)
        if not m:
            continue
        d = ts(first.match(raw).group(1)) if first.match(raw) else None
        o = ts(m.group(2))
        if not d or not o:
            continue
        age = (d - o).total_seconds() / 3600.0
        rows.append(
            (
                age,
                len(raw),
                (m.group(3) or "[?]").strip(),
                kind(m.group(4)),
                os.path.basename(f),
            )
        )

stale = [r for r in rows if r[0] > H]
print(
    f"# Stale-forward replay, H = {H:g} h (measured {datetime.now().astimezone():%Y-%m-%d %H:%M %Z})\n"
)
print(
    f"- inboxes scanned: {len(glob.glob(f'{BOX}/*.md'))}; forwarded lines: {len(rows)}; "
    f"older than {H:g} h at delivery: **{len(stale)}** ({100 * len(stale) / max(len(rows), 1):.1f}%)"
)
print(
    f"- chars in those lines: {sum(r[1] for r in stale):,} of {sum(r[1] for r in rows):,} forwarded chars; "
    f"median stale age at delivery {sorted(r[0] for r in stale)[len(stale) // 2] if stale else 0:.0f} h\n"
)
print("| kind of stale forwarded line | lines | chars |\n|---|---:|---:|")
kc, kch = Counter(r[3] for r in stale), Counter()
for r in stale:
    kch[r[3]] += r[1]
for k, n in kc.most_common():
    print(f"| {k} | {n} | {kch[k]:,} |")
print("\n| sender (top 10) | lines |\n|---|---:|")
for s, n in Counter(r[2] for r in stale).most_common(10):
    print(f"| {s} | {n} |")
