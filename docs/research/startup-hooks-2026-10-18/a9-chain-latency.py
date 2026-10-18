"""A9: wall time a tool call spends in its hook chains, from transcript timestamps (read-only).

Usage: python3 -I a9-chain-latency.py <file-list> <since-iso>

PreToolUse chain proxy: for each tool_use id, (latest PreToolUse hook attachment timestamp carrying
that toolUseID) - (timestamp of the assistant record holding the tool_use block). Hooks of one event
run in parallel and CC writes their attachments when the event's hooks settle, so this approximates
the chain's wall time. Only tool calls where at least one PreToolUse hook PRINTED are measurable
(KNOWN BIAS: silent hooks leave no record); smart-bash-allowlist prints on most allowed Bash calls,
so Bash coverage is high.
PostToolUse chain proxy: (latest PostToolUse hook attachment with that toolUseID) - (timestamp of the
user record carrying the tool_result for that id). Same bias.
Stop proxy: per Stop (toolUseID shared by its hook records), max(durationMs) over hook_success /
hook_cancelled records -- a lower bound on the Stop chain's wall time.
"""

import json
import sys
from collections import defaultdict
from datetime import datetime

flist, since = sys.argv[1], sys.argv[2]


def t(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


pre = defaultdict(list)  # tool name -> [ms]
post = defaultdict(list)
stop = []
ups = []
for path in open(flist):
    path = path.strip()
    try:
        fh = open(path, errors="replace")
    except OSError:
        continue
    use_ts, use_name, res_ts = {}, {}, {}
    pre_last, post_last = {}, {}
    stop_max = defaultdict(int)
    ups_max = defaultdict(int)
    with fh:
        for ln in fh:
            if not ('"tool_use"' in ln or '"tool_result"' in ln or '"hook_' in ln):
                continue
            try:
                r = json.loads(ln)
            except ValueError:
                continue
            ts = r.get("timestamp") or ""
            if ts < since:
                continue
            ty = r.get("type")
            if ty == "assistant":
                for b in (r.get("message") or {}).get("content") or []:
                    if isinstance(b, dict) and b.get("type") == "tool_use":
                        use_ts[b.get("id")] = t(ts)
                        use_name[b.get("id")] = b.get("name")
                continue
            if ty == "user":
                c = (r.get("message") or {}).get("content")
                if isinstance(c, list):
                    for b in c:
                        if isinstance(b, dict) and b.get("type") == "tool_result":
                            res_ts[b.get("tool_use_id")] = t(ts)
                continue
            a = r.get("attachment")
            if not isinstance(a, dict):
                continue
            ev = a.get("hookEvent")
            tid = a.get("toolUseID")
            if ev == "PreToolUse" and tid:
                pre_last[tid] = max(pre_last.get(tid, 0), t(ts))
            elif ev == "PostToolUse" and tid:
                post_last[tid] = max(post_last.get(tid, 0), t(ts))
            elif ev == "Stop" and tid and isinstance(a.get("durationMs"), (int, float)):
                stop_max[tid] = max(stop_max[tid], a["durationMs"])
            elif (
                ev == "UserPromptSubmit"
                and tid
                and isinstance(a.get("durationMs"), (int, float))
            ):
                ups_max[tid] = max(ups_max[tid], a["durationMs"])
    for tid, x in pre_last.items():
        if tid in use_ts and x >= use_ts[tid]:
            pre[use_name[tid]].append((x - use_ts[tid]) * 1000)
    for tid, x in post_last.items():
        if tid in res_ts and x >= res_ts[tid] - 1:
            post[use_name.get(tid, "?")].append(max(0.0, (x - res_ts[tid]) * 1000))
    stop.extend(stop_max.values())
    ups.extend(ups_max.values())


def q(xs):
    if not xs:
        return "n=0"
    xs = sorted(xs)

    def p(v):
        return int(xs[min(len(xs) - 1, int(round(v / 100.0 * (len(xs) - 1))))])

    return f"n={len(xs)} p50={p(50)} p75={p(75)} p90={p(90)} p95={p(95)} p99={p(99)} max={int(xs[-1])} sum_s={int(sum(xs) / 1000)}"


print("PreToolUse chain wall-time proxy (ms) by tool:")
for k, v in sorted(pre.items(), key=lambda x: -len(x[1]))[:8]:
    print(f"  {k}\t{q(v)}")
print(
    "PostToolUse chain proxy (ms) by tool (attachment written after tool_result record):"
)
for k, v in sorted(post.items(), key=lambda x: -len(x[1]))[:8]:
    print(f"  {k}\t{q(v)}")
print(f"Stop: max hook durationMs per Stop (lower bound of chain wall time)\t{q(stop)}")
print(
    f"UserPromptSubmit: max hook durationMs per prompt (printers/cancels only)\t{q(ups)}"
)
