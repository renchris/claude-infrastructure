#!/usr/bin/env python3
"""r15: cache misses after 5-60 min gaps in subagent / workflow-agent transcripts.

Read-only over ~/.claude*/projects/**/subagents/**/*.jsonl (deduped by realpath).
Window: responses with timestamp in [2026-09-10, 2026-09-25).

Per agent file:
  - assistant records grouped by message.id; first_ts = first record ts, last_ts = last
    record ts, usage = last record's usage; tool_use blocks collected across all records
    (each with the ts of the record that carried it).
  - responses ordered by first_ts. gap = first_ts(n) - first_ts(n-1) (request-to-request,
    closest to cache age). idle = first_ts(n) - last_ts(n-1).
  - miss: prev_total = input+cache_read+cache_creation of response n-1;
    cache_read(n) < 0.5*prev_total AND cache_creation(n) >= 0.5*prev_total.
  - For each miss with 300 <= gap <= 3600: tool_use(s) in response n-1, matched to
    tool_result records by tool_use_id; dur = tool_result ts - tool_use record ts.
    The gap is split into gen (response n-1 streaming: last_ts - first_ts), tool (longest
    measured tool dur) and post (next first_ts - tool_result ts); the largest component
    decides: gen -> long generation, post -> delay after result, tool -> classified by the
    dominant tool (Bash: bg flag, sleep/until/wait/while loop, prior bg launch, work class).
    No tool_use in response n-1 -> turn ended and was resumed by a later message.
Output: JSON rows on stdout-file for the report builder; no transcript text other than
command heads (first meaningful token after cd/export/VAR= prefixes).
"""

import json, os, subprocess, sys, collections, re
from datetime import datetime

LO, HI = "2026-09-10", "2026-09-25"
OUT = "/tmp/tokeff-w2/r15-rows.json"


def ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


def files():
    out = subprocess.run(
        "find -H ~/.claude* -path '*/projects/*' -path '*subagents*' -name '*.jsonl' "
        "-newermt 2026-09-10 2>/dev/null",
        shell=True,
        capture_output=True,
        text=True,
    ).stdout.split("\n")
    seen = {}
    for f in out:
        if not f:
            continue
        rp = os.path.realpath(f)
        seen.setdefault(rp, f)
    return sorted(seen)


SKIP = re.compile(r"^(cd|export|set|source|\.|mkdir|[A-Za-z_][A-Za-z0-9_]*=\S*)$")


def cmd_head(cmd):
    """First meaningful token: skip cd/export/set/source/mkdir/VAR= prefix segments."""
    segs = re.split(r"&&|\|\||;|\n", cmd or "")
    for seg in segs:
        toks = seg.strip().split()
        while toks and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", toks[0]):
            toks = toks[1:]
        if not toks or SKIP.match(toks[0]):
            continue
        return os.path.basename(toks[0])[:30]
    return "(prefix-only)"


def bg_before(tools, t):
    return any(
        x["name"] == "Bash"
        and (x["input"] or {}).get("run_in_background")
        and x["ts"] < t
        for x in tools
    )


KINDS = [
    ("nested LLM CLI run", r"\b(claude|copilot|codex|gemini)\b\s+(-p|--print|exec|-m|--model|run)\b"),
    ("build/test", r"\b(xcodebuild|swift (build|test)|bats|pytest|make|pnpm|npm|cargo|go test)\b"),
    ("network (curl/gh/rsync)", r"\b(curl|wget|gh|rsync)\b"),
    ("python/node script", r"\b(python3?|node|uv run)\b"),
    ("sleep/poll only", r"\b(sleep|until|wait)\b"),
]


def work_class(cmd):
    return next((n for n, pat in KINDS if re.search(pat, cmd or "")), "other")


WAITY = re.compile(r"\b(sleep|until|wait|while)\b")


def scan(path):
    kind = "workflow" if "/subagents/workflows/" in path else "subagent"
    msgs = collections.OrderedDict()
    results = {}  # tool_use_id -> ts
    tur_bg = {}  # tool_use_id -> backgroundTaskId present
    others = []  # (ts, type, subtype) of non-assistant records
    for line in open(path, errors="replace"):
        try:
            r = json.loads(line)
        except Exception:
            continue
        t = r.get("timestamp")
        if not t:
            continue
        typ = r.get("type")
        m = r.get("message") or {}
        if typ == "assistant" and m.get("id"):
            e = msgs.get(m["id"])
            if e is None:
                e = msgs[m["id"]] = {
                    "first": ts(t),
                    "last": ts(t),
                    "usage": None,
                    "tools": [],
                    "iso": t,
                    "stop": None,
                }
            e["last"] = ts(t)
            e["last_iso"] = t
            if m.get("usage"):
                e["usage"] = m["usage"]
            if m.get("stop_reason"):
                e["stop"] = m["stop_reason"]
            for b in m.get("content") or []:
                if isinstance(b, dict) and b.get("type") == "tool_use":
                    e["tools"].append(
                        {
                            "id": b.get("id"),
                            "name": b.get("name"),
                            "input": b.get("input") or {},
                            "ts": ts(t),
                        }
                    )
        elif typ == "user":
            c = m.get("content")
            if isinstance(c, list):
                for b in c:
                    if isinstance(b, dict) and b.get("type") == "tool_result":
                        results[b.get("tool_use_id")] = ts(t)
                        tu = r.get("toolUseResult")
                        if isinstance(tu, dict) and tu.get("backgroundTaskId"):
                            tur_bg[b.get("tool_use_id")] = True
            else:
                others.append((ts(t), "user_text"))
        else:
            others.append((ts(t), f"{typ}:{r.get('subtype') or ''}"))
    a_tools_all = [t for v in msgs.values() for t in v["tools"]]
    resp = sorted(
        (v for v in msgs.values() if v["usage"] and LO <= v["iso"][:10] < HI),
        key=lambda v: v["first"],
    )
    rows = []
    pairs = 0
    gap_pairs = 0
    gap_hits = 0
    for a, b in zip(resp, resp[1:]):
        pairs += 1
        gap = b["first"] - a["first"]
        if not (300 <= gap <= 3600):
            continue
        gap_pairs += 1
        ua, ub = a["usage"], b["usage"]
        prev_total = (
            ua.get("input_tokens", 0)
            + ua.get("cache_read_input_tokens", 0)
            + ua.get("cache_creation_input_tokens", 0)
        )
        cr, cc = (
            ub.get("cache_read_input_tokens", 0),
            ub.get("cache_creation_input_tokens", 0),
        )
        if not (prev_total and cr < 0.5 * prev_total and cc >= 0.5 * prev_total):
            gap_hits += 1
            continue
        idle = b["first"] - a["last"]
        tools = []
        for tl in a["tools"]:
            rt = results.get(tl["id"])
            dur = (rt - tl["ts"]) if rt else None
            tools.append((tl, dur, rt))
        gen = (
            a["last"] - a["first"]
        )  # response-a streaming time (incl. long tool input)
        wclass = None
        cause, detail, dur_dom, head, bg = (
            "no tool (turn ended; resumed by message)",
            "",
            None,
            "",
            None,
        )
        tl = None
        if tools:
            meas = [x for x in tools if x[1] is not None]
            if meas:
                tl, dur_dom, rt = max(meas, key=lambda x: x[1])
            else:
                tl, dur_dom, rt = tools[0]
        post = (b["first"] - rt) if (tl is not None and dur_dom is not None) else idle
        comps = {"gen": gen, "tool": dur_dom or 0, "post": post}
        dom = max(comps, key=comps.get)
        if tl is not None and dur_dom is None:
            cause = f"unknown (no tool_result for {tl['name']})"
        elif dom == "gen":
            cause = "long generation of response n-1 (not a tool wait)"
        elif tl is None:
            pass
        elif dom == "post":
            cause = "delay after tool result (not the tool)"
            detail = tl["name"]
        else:
            name, inp = tl["name"], tl["input"]
            if name == "Bash":
                bg = bool(inp.get("run_in_background"))
                head = cmd_head(inp.get("command"))
                detail = head
                wclass = work_class(inp.get("command"))
                if bg:
                    cause = "Bash run_in_background (launch itself slow)"
                elif WAITY.search(inp.get("command") or ""):
                    cause = (
                        "foreground Bash wait/poll loop after a bg launch"
                        if bg_before(a_tools_all, tl["ts"])
                        else "foreground Bash wait/poll loop (no prior bg launch)"
                    )
                else:
                    cause = "foreground Bash (work)"
            elif name == "Monitor":
                cause = "Monitor"
            elif name in ("Agent", "Task"):
                cause = "Agent/Task child"
            elif "orkflow" in name:
                cause = "Workflow"
            elif name == "WebFetch":
                cause = "WebFetch"
            else:
                cause = "other tool"
                detail = name
        timeout = tl["input"].get("timeout") if tl is not None else None
        between = sorted({k for (t0, k) in others if a["last"] < t0 < b["first"]})
        rows.append(
            {
                "file": path,
                "kind": kind,
                "t1": a["iso"],
                "t2": b["iso"],
                "gap_s": round(gap),
                "idle_s": round(idle),
                "prev_total": prev_total,
                "cache_read": cr,
                "cache_creation": cc,
                "cause": cause,
                "detail": detail,
                "tool_dur_s": None if dur_dom is None else round(dur_dom),
                "cmd_head": head,
                "work_class": wclass,
                "bg": bg,
                "n_tools": len(tools),
                "stop": a["stop"],
                "between": between,
                "timeout": (
                    a["tools"]
                    and max(a["tools"], key=lambda x: 0)["input"].get("timeout")
                )
                or None,
            }
        )
    return rows, pairs, gap_pairs, gap_hits, kind


def main():
    fs = files()
    allrows = []
    stats = collections.Counter()
    for f in fs:
        rows, pairs, gp, gh, kind = scan(f)
        stats[f"files_{kind}"] += 1
        stats[f"pairs_{kind}"] += pairs
        stats[f"gap_pairs_{kind}"] += gp
        stats[f"gap_hits_{kind}"] += gh
        allrows += rows
    json.dump({"stats": stats, "rows": allrows}, open(OUT, "w"), indent=1)
    print(dict(stats), len(allrows), file=sys.stderr)


if __name__ == "__main__":
    main()
