"""A9 per-turn hook census over a fixed transcript list (read-only).

Usage: python3 -I a9-turn-hook-census.py <file-list> <since-iso> [--json out.json]

For every hook attachment record at or after <since-iso> it aggregates, per (hookEvent, command):
  success count, durationMs distribution (hook_success only: KNOWN BIAS, CC records hook_success
  only when the hook printed something), cancels / timedOut, additionalContext chars parsed from
  the hook's stdout JSON, top-level systemMessage chars, blocking-error chars (exit-2 / decision
  block: these reach the model as a user-turn message), non-blocking errors.
It also counts normalisers per file: user prompts (string-content user records that are not tool
results), tool_use blocks by tool name, so per-turn rates can be derived.
Event-level hook_additional_context records (the harness's model-facing echo) are summed per
hookName as a cross-check on the stdout-parsed numbers.
No hook is executed; this only reads jsonl.
"""

import json
import sys
from collections import Counter, defaultdict

args = sys.argv[1:]
out_json = None
if "--json" in args:
    i = args.index("--json")
    out_json = args[i + 1]
    del args[i : i + 2]
flist, since = args[0], args[1]

agg = defaultdict(
    lambda: {
        "succ": 0,
        "dur": [],
        "cancel": 0,
        "timedout": 0,
        "cancel_dur": [],
        "timeout_ms": Counter(),
        "ac_n": 0,
        "ac_chars": 0,
        "sm_n": 0,
        "sm_chars": 0,
        "block_n": 0,
        "block_chars": 0,
        "nbe": 0,
        "exit": Counter(),
        "files": set(),
        "async_resp": 0,
    }
)
ev_ac = defaultdict(lambda: [0, 0])  # hookName -> [records, chars]
ev_sm = defaultdict(lambda: [0, 0])
tools = Counter()
prompts = 0
machine_prompts = 0
files_seen = 0
ts_min, ts_max = None, None


def ac_from_stdout(s):
    if not s:
        return None, None
    s = s.strip()
    try:
        j = json.loads(s)
    except ValueError:
        return None, None
    if not isinstance(j, dict):
        return None, None
    hso = j.get("hookSpecificOutput") or {}
    ac = hso.get("additionalContext") if isinstance(hso, dict) else None
    sm = j.get("systemMessage")
    return ac, sm


for path in open(flist):
    path = path.strip()
    if not path:
        continue
    try:
        fh = open(path, errors="replace")
    except OSError:
        continue
    files_seen += 1
    with fh:
        for ln in fh:
            hook = '"hook_' in ln or '"async_hook_response"' in ln
            isuser = '"type":"user"' in ln
            isasst = '"type":"assistant"' in ln and '"tool_use"' in ln
            if not (hook or isuser or isasst):
                continue
            try:
                r = json.loads(ln)
            except ValueError:
                continue
            ts = r.get("timestamp") or ""
            if ts < since:
                continue
            if ts_min is None or ts < ts_min:
                ts_min = ts
            if ts_max is None or ts > ts_max:
                ts_max = ts
            if r.get("type") == "user" and not r.get("isMeta"):
                c = (r.get("message") or {}).get("content")
                if isinstance(c, str):
                    prompts += 1
                    if c.lstrip().startswith(
                        "<task-notification"
                    ) or c.lstrip().startswith("<"):
                        machine_prompts += 1
                continue
            if r.get("type") == "assistant":
                for b in (r.get("message") or {}).get("content") or []:
                    if isinstance(b, dict) and b.get("type") == "tool_use":
                        tools[b.get("name") or "?"] += 1
                continue
            a = r.get("attachment")
            if not isinstance(a, dict):
                continue
            t = a.get("type") or ""
            ev = a.get("hookEvent") or "?"
            hn = a.get("hookName") or ev
            if t == "hook_additional_context":
                c = a.get("content")
                n = sum(len(x) for x in c) if isinstance(c, list) else len(c or "")
                ev_ac[hn][0] += 1
                ev_ac[hn][1] += n
                continue
            if t == "hook_system_message":
                ev_sm[hn][0] += 1
                ev_sm[hn][1] += len(a.get("content") or "")
                continue
            if t == "hook_blocking_error":
                be = a.get("blockingError") or {}
                cmd = be.get("command") or "?"
                k = agg[(ev, cmd)]
                k["block_n"] += 1
                k["block_chars"] += len(be.get("blockingError") or "")
                k["files"].add(path)
                continue
            if t == "async_hook_response":
                agg[(ev, "async:" + hn)]["async_resp"] += 1
                continue
            cmd = a.get("command") or "?"
            k = agg[(ev, cmd)]
            k["files"].add(path)
            if t == "hook_success":
                k["succ"] += 1
                if isinstance(a.get("durationMs"), (int, float)):
                    k["dur"].append(a["durationMs"])
                k["exit"][a.get("exitCode")] += 1
                ac, sm = ac_from_stdout(a.get("stdout"))
                if isinstance(ac, str) and ac:
                    k["ac_n"] += 1
                    k["ac_chars"] += len(ac)
                if isinstance(sm, str) and sm:
                    k["sm_n"] += 1
                    k["sm_chars"] += len(sm)
            elif t == "hook_cancelled":
                k["cancel"] += 1
                if a.get("timedOut"):
                    k["timedout"] += 1
                if isinstance(a.get("durationMs"), (int, float)):
                    k["cancel_dur"].append(a["durationMs"])
                k["timeout_ms"][a.get("timeoutMs")] += 1
            elif t == "hook_non_blocking_error":
                k["nbe"] += 1


def pct(xs, p):
    if not xs:
        return "-"
    xs = sorted(xs)
    return str(int(xs[min(len(xs) - 1, int(round(p / 100.0 * (len(xs) - 1))))]))


print(f"files={files_seen} since={since} records ts range {ts_min} .. {ts_max}")
print(
    f"user prompts={prompts} (of which '<'-prefixed machine prompts={machine_prompts})"
)
print(
    "tool_use by name (top 15):",
    ", ".join(f"{n}={c}" for n, c in tools.most_common(15)),
)
print("tool_use total:", sum(tools.values()))
print()
hdr = "event\tcommand\tsucc\tp50\tp90\tp99\tmax\tcancel\ttimedout\tAC_n\tAC_chars\tSM_n\tSM_chars\tBLOCK_n\tBLOCK_chars\tNBE\tasync\tfiles"
print(hdr)
rows = []
for (ev, cmd), k in agg.items():
    if ev == "SessionStart":
        continue
    rows.append((ev, cmd, k))
rows.sort(
    key=lambda r: (r[0], -(r[2]["ac_chars"] + r[2]["block_chars"]), -r[2]["cancel"])
)
for ev, cmd, k in rows:
    d = k["dur"]
    print(
        "\t".join(
            str(x)
            for x in [
                ev,
                cmd.replace("~/.claude/hooks/", "").replace(
                    "/Users/chrisren/.claude/hooks/", ""
                ),
                k["succ"],
                pct(d, 50),
                pct(d, 90),
                pct(d, 99),
                (int(max(d)) if d else "-"),
                k["cancel"],
                k["timedout"],
                k["ac_n"],
                k["ac_chars"],
                k["sm_n"],
                k["sm_chars"],
                k["block_n"],
                k["block_chars"],
                k["nbe"],
                k["async_resp"],
                len(k["files"]),
            ]
        )
    )
print()
print("event-level hook_additional_context (model-facing) by hookName: records chars")
for hn, (n, c) in sorted(ev_ac.items(), key=lambda x: -x[1][1]):
    print(f"  {hn}\t{n}\t{c}")
print("event-level hook_system_message by hookName: records chars")
for hn, (n, c) in sorted(ev_sm.items(), key=lambda x: -x[1][1]):
    print(f"  {hn}\t{n}\t{c}")
if out_json:
    with open(out_json, "w") as f:
        json.dump(
            {
                f"{ev}|{cmd}": {
                    kk: (
                        sorted(v)
                        if isinstance(v, list)
                        else (
                            len(v)
                            if isinstance(v, set)
                            else (dict(v) if isinstance(v, Counter) else v)
                        )
                    )
                    for kk, v in k.items()
                }
                for (ev, cmd), k in agg.items()
            },
            f,
            default=str,
        )
