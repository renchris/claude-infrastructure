#!/usr/bin/env python3
"""r2-agg.py [runs-dir] — rank 2 workaround experiment (wave 2, item 5).

Per run (base = memory in the first user message; sys = memory appended to the system prompt for the
main and, via CLAUDE_CODE_ENABLE_APPEND_SUBAGENT_PROMPT, for subagents): the main's first request and
each subagent's first request (cache_read / cache_creation), the tree's total cache writes, requests,
cost, and whether any spawn was refused by the capacity gate (such runs measure nothing about siblings).
"""

import glob, json, os, statistics as st, sys

R = sys.argv[1] if len(sys.argv) > 1 else "/private/tmp/tokeff-w2/r2exp/runs"


def first_usage(path):
    msgs = {}
    for line in open(path, errors="replace"):
        try:
            r = json.loads(line)
        except ValueError:
            continue
        if r.get("type") == "assistant":
            m = r.get("message", {})
            if m.get("id") not in msgs:
                msgs[m.get("id")] = (r["timestamp"], m.get("usage") or {})
            else:
                msgs[m.get("id")] = (
                    msgs[m.get("id")][0],
                    m.get("usage") or msgs[m.get("id")][1],
                )
    seq = sorted(msgs.values(), key=lambda x: x[0])
    tot_cw = sum(u.get("cache_creation_input_tokens", 0) for _, u in seq)
    return (seq[0][1] if seq else {}), tot_cw, len(seq)


rows = []
for run in sorted(glob.glob(f"{R}/*-r*")):
    name = os.path.basename(run)
    arm = name.rsplit("-r", 1)[0]
    try:
        res = json.load(open(f"{run}/result.json"))
    except (OSError, ValueError):
        continue
    sid = res.get("session_id", "")
    tx = next(
        iter(glob.glob(os.path.expanduser(f"~/.claude*/projects/*/{sid}.jsonl"))), None
    )
    if not tx:
        continue
    refused = "MACHINE CAPACITY" in open(tx, errors="replace").read()
    mu, mcw, mreq = first_usage(tx)
    subs = sorted(glob.glob(f"{tx[:-6]}/subagents/*.jsonl"))
    su = [first_usage(s) for s in subs]
    rows.append(
        dict(
            name=name,
            arm=arm,
            refused=refused,
            n_sub=len(subs),
            main_read=mu.get("cache_read_input_tokens", 0),
            main_write=mu.get("cache_creation_input_tokens", 0),
            sub_read=[u.get("cache_read_input_tokens", 0) for u, _, _ in su],
            sub_write=[u.get("cache_creation_input_tokens", 0) for u, _, _ in su],
            tree_cw=mcw + sum(c for _, c, _ in su),
            cost=res.get("total_cost_usd", 0),
        )
    )

print(
    "| run | refused | subagents | main first read / write | subagent first reads | subagent first writes | tree cache writes | tree $ |"
)
print("|---|---|---:|---|---|---|---:|---:|")
for r in rows:
    print(
        f"| {r['name']} | {r['refused']} | {r['n_sub']} | {r['main_read']:,} / {r['main_write']:,} | "
        f"{', '.join(f'{x:,}' for x in r['sub_read'])} | {', '.join(f'{x:,}' for x in r['sub_write'])} | "
        f"{r['tree_cw']:,} | {r['cost']:.3f} |"
    )
for arm in ("base", "sys"):
    ok = [r for r in rows if r["arm"] == arm and not r["refused"] and r["n_sub"] >= 3]
    if ok:
        print(
            f"\n**{arm}** (n={len(ok)} unrefused runs with 3 subagents): tree cache writes {st.mean(r['tree_cw'] for r in ok):,.0f}, "
            f"subagent first-request write {st.mean(x for r in ok for x in r['sub_write']):,.0f} / read "
            f"{st.mean(x for r in ok for x in r['sub_read']):,.0f}, main first write {st.mean(r['main_write'] for r in ok):,.0f} / read "
            f"{st.mean(r['main_read'] for r in ok):,.0f}, tree ${st.mean(r['cost'] for r in ok):.3f}"
        )
