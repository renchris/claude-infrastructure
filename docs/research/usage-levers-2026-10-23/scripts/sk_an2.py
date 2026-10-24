#!/usr/bin/env python3
"""Skeptic analysis 2: default-slot eligibility with my own classifier; tool tally outside lean's set;
b13 share; saving under alternative weightings."""

import json, collections, re

rows = [json.loads(l) for l in open("/tmp/usage-audit/skeptic-subagents/sk_rows.jsonl")]
keep = set(json.load(open("/tmp/usage-audit/skeptic-subagents/sk_keep.json")))
rows = [r for r in rows if r["path"] in keep and r["first_in_window"]]
LEAN_TOOLS = {
    "Read",
    "Grep",
    "Glob",
    "Bash",
    "Write",
    "Edit",
    "WebFetch",
    "WebSearch",
    "StructuredOutput",
}
# workflow run names: read wf_*.json beside the session
wfname = {}
import glob, os

for acct, root in [
    ("next", "~/.claude-next/projects"),
    ("next2", "~/.claude-secondary/projects"),
    ("next3", "~/.claude-tertiary/projects"),
    ("next4", "~/.claude-quaternary/projects"),
]:
    root = os.path.realpath(os.path.expanduser(root))
    for p in glob.glob(root + "/*/*/workflows/wf_*.json"):
        try:
            if os.stat(p).st_mtime < __import__("time").time() - 9 * 86400:
                continue
            d = json.load(open(p))
        except Exception:
            continue
        wfname[os.path.basename(p)[:-5]] = (
            d.get("workflowName") or "?",
            d.get("script") or "",
        )

dflt = [r for r in rows if r["agentType"] == "workflow-subagent"]
lean = [r for r in rows if r["agentType"] == "workflow-lean"]
print("default slots (dedup, first req in window):", len(dflt), "| lean:", len(lean))
nonlean = collections.Counter()
for r in dflt:
    for t in r["tools"]:
        if t not in LEAN_TOOLS:
            nonlean[t] += 1
print(
    "default slots using a tool outside lean's set (slots per tool):",
    dict(nonlean.most_common(25)),
)
SANDBOX = re.compile(
    r"(/tmp/|/private/tmp|\$TMPDIR|mktemp|\$SB|\$ROOT|\$R/|sandbox|scratch)", re.I
)


def cls(r):
    if r["skills"]:
        return "skill"
    if r["mcps"]:
        return "mcp"
    if any(t in r["tools"] for t in ("Agent", "Task")):
        return "agent-tool"
    if r["gitcmds"]:
        if all(SANDBOX.search(c) for c in r["gitcmds"]):
            return "git-mut-sandbox-looking"
        return "git-mut-other"
    other = [t for t in r["tools"] if t not in LEAN_TOOLS]
    if other:
        return "other-nonlean-tool:" + ",".join(sorted(other))[:60]
    return "eligible"


c = collections.Counter()
fam = collections.Counter()
fam_elig = collections.Counter()
for r in dflt:
    k = cls(r)
    c[k] += 1
    nm = (
        wfname.get(r["wf"], ("<no wf record>", ""))[0]
        if r["wf"]
        else "<not in workflow dir>"
    )
    f = re.sub(r"\d+", "NN", nm)
    fam[f] += 1
    if k == "eligible":
        fam_elig[f] += 1
print("my classes:", dict(c.most_common(30)))
print("default slots by workflow family (top 12):", fam.most_common(12))
print("eligible default slots by family (top 6):", fam_elig.most_common(6))
b13 = [r for r in dflt if wfname.get(r["wf"], ("", ""))[0].startswith("b13-round")]
print(
    "b13 default slots:",
    len(b13),
    "by acct:",
    collections.Counter(r["acct"] for r in b13),
)
# first-request timing of b13 default slots per day
print(
    "b13 default slots per UTC day:",
    sorted(collections.Counter(r["first_ts"][:10] for r in b13).items()),
)
print(
    "all default slots per UTC day:",
    sorted(collections.Counter(r["first_ts"][:10] for r in dflt).items()),
)

# saving under weightings, eligible tier, using their model shape but my own data
LEAN_P50 = sorted(sum(r["first"][:3]) for r in lean)[len(lean) // 2]


def sav(r, wcc, wcr):
    d = max(
        0, sum(r["first"][:3]) - LEAN_P50
    )  # no brief correction here (conservative upper bound on delta)
    return d * wcc + d * wcr * max(0, r["nreq"] - 1)


def Wt(t, wcc, wcr):
    return t[0] + t[1] * wcc + t[2] * wcr + t[3] * 5


# denominators: the other agent's totals.json (main+sub) and my sub-only totals
tot = json.load(open("/tmp/usage-audit/lever-subagents/totals.json"))
elig = [r for r in dflt if cls(r) == "eligible"]
for name, wcc, wcr in [
    ("API ratios cc1.25 cr0.1", 1.25, 0.1),
    ("cache read free cr0", 1.25, 0.0),
    ("cache read = input cr1", 1.0, 1.0),
]:
    s = sum(sav(r, wcc, wcr) for r in elig)
    s_b13 = sum(
        sav(r, wcc, wcr)
        for r in elig
        if wfname.get(r["wf"], ("", ""))[0].startswith("b13-round")
    )
    den = 0
    for a, v in tot.items():
        for part in ("main", "sub"):
            den += Wt(v[part], wcc, wcr) if isinstance(v[part], list) else 0
    print(
        f"[{name}] eligible n={len(elig)} saving={s / 1e6:.1f}M (b13 {s_b13 / 1e6:.1f}M) denom(main+sub,their totals)={den / 1e6:.0f}M share={100 * s / den if den else float('nan'):.2f}% b13 share={100 * s_b13 / den if den else float('nan'):.2f}%"
    )
