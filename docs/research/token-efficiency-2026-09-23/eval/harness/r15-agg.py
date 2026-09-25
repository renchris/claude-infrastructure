#!/usr/bin/env python3
"""r15-agg.py [runs-dir] — aggregate r15-probe.sh runs (wave 2, item 4).

For each run: find the main session's transcript by session_id (result.json), then its subagent
transcripts (<session>/subagents/**). For the subagent, group assistant records by message.id (usage
from the last record), order by first timestamp, and report: API requests, gaps > 300 s between
consecutive requests, requests that missed the cache (cache_read < 50% of the previous request's
prompt and cache_creation >= 50% of it), total cache_creation, and the Bash calls it made (did it
background the benchmark; longest foreground call). Correct = the main's final text equals the
expected RESULT number. Prints a markdown table and per-arm means.
"""

import glob, json, os, sys
from datetime import datetime

R = sys.argv[1] if len(sys.argv) > 1 else "/private/tmp/tokeff-w2/r15probe/runs"


def t(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


def find_tx(sid):
    for base in glob.glob(os.path.expanduser("~/.claude*/projects")):
        hits = glob.glob(f"{base}/*/{sid}.jsonl")
        if hits:
            return hits[0]
    return None


rows = []
for run in sorted(glob.glob(f"{R}/*-r*")):
    name = os.path.basename(run)
    if " " in name or not os.path.exists(f"{run}/result.json"):
        continue
    arm = name.rsplit("-r", 1)[0]
    try:
        res = json.load(open(f"{run}/result.json"))
    except (ValueError, OSError):
        rows.append((name, arm, None))
        continue
    exp = open(f"{run}/expected").read().strip()
    correct = exp in (res.get("result") or "")
    tx = find_tx(res.get("session_id", ""))
    subs = glob.glob(f"{tx[:-6]}/subagents/**/*.jsonl", recursive=True) if tx else []
    msgs, order, tools = {}, [], {}
    for f in subs:
        for line in open(f, errors="replace"):
            try:
                r = json.loads(line)
            except ValueError:
                continue
            if r.get("type") == "assistant":
                m = r.get("message", {})
                mid = m.get("id")
                if mid not in msgs:
                    order.append(mid)
                    msgs[mid] = {"ts": t(r["timestamp"]), "u": {}}
                msgs[mid]["u"] = m.get("usage") or msgs[mid]["u"]
                for c in m.get("content") or []:
                    if (
                        isinstance(c, dict)
                        and c.get("type") == "tool_use"
                        and c.get("name") == "Bash"
                    ):
                        tools[c["id"]] = {
                            "ts": t(r["timestamp"]),
                            "bg": bool((c.get("input") or {}).get("run_in_background")),
                            "cmd": (c.get("input") or {}).get("command", "")[:60],
                        }
            elif r.get("type") == "user":
                for c in (r.get("message") or {}).get("content") or []:
                    if (
                        isinstance(c, dict)
                        and c.get("type") == "tool_result"
                        and c.get("tool_use_id") in tools
                    ):
                        tools[c["tool_use_id"]]["dur"] = (
                            t(r["timestamp"]) - tools[c["tool_use_id"]]["ts"]
                        )
    seq = sorted((msgs[k] for k in order), key=lambda x: x["ts"])
    gaps = misses = 0
    cw = 0
    for i, m in enumerate(seq):
        u = m["u"]
        cw += u.get("cache_creation_input_tokens", 0)
        if i:
            p = seq[i - 1]["u"]
            prev = (
                p.get("input_tokens", 0)
                + p.get("cache_read_input_tokens", 0)
                + p.get("cache_creation_input_tokens", 0)
            )
            if m["ts"] - seq[i - 1]["ts"] > 300:
                gaps += 1
            if (
                prev
                and u.get("cache_read_input_tokens", 0) < 0.5 * prev
                and u.get("cache_creation_input_tokens", 0) >= 0.5 * prev
            ):
                misses += 1
    fg = [v.get("dur", 0) for v in tools.values() if not v["bg"]]
    rows.append(
        (
            name,
            arm,
            dict(
                correct=correct,
                reqs=len(seq),
                gaps=gaps,
                misses=misses,
                cw=cw,
                bg=sum(v["bg"] for v in tools.values()),
                maxfg=max(fg) if fg else 0,
                cost=res.get("total_cost_usd", 0),
            ),
        )
    )

print(
    "| run | correct | subagent requests | gaps >300 s | cache misses | cache_creation | bg Bash | longest fg Bash s | tree $ |"
)
print("|---|---|---:|---:|---:|---:|---:|---:|---:|")
for name, arm, d in rows:
    if d is None:
        print(f"| {name} | no result | | | | | | | |")
        continue
    print(
        f"| {name} | {d['correct']} | {d['reqs']} | {d['gaps']} | {d['misses']} | {d['cw']:,} | {d['bg']} | {d['maxfg']:.0f} | {d['cost']:.3f} |"
    )
for arm in ("without", "with"):
    ds = [d for n, a, d in rows if a == arm and d]
    if ds:
        mean = lambda k: sum(d[k] for d in ds) / len(ds)
        print(
            f"\n**{arm}** (n={len(ds)}): correct {sum(d['correct'] for d in ds)}/{len(ds)}, misses {mean('misses'):.2f}, "
            f"gaps {mean('gaps'):.2f}, requests {mean('reqs'):.1f}, cache_creation {mean('cw'):,.0f}, tree ${mean('cost'):.3f}"
        )
