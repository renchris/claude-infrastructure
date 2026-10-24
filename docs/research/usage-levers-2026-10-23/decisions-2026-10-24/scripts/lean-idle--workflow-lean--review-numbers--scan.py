#!/usr/bin/env python3
"""Reviewer's independent scan (numbers lens). Read-only over ~/.claude-*; writes only to
/tmp/lean-idle/workflow-lean/review-numbers/.
Differences from the researcher's replay.py, on purpose:
  - union of agent files over every copy of a run dir (largest file per agentId), not one best dir
  - usage per message id = max of each field over its records
  - records brief chars, cwd, visible output chars, thinking-signature chars, final-record count
  - own (simpler) need classifier
Outputs: runs.jsonl, slots.jsonl."""

import collections
import glob
import hashlib
import importlib.util
import json
import os
import re
import sys
import time
from concurrent.futures import ProcessPoolExecutor

sys.dont_write_bytecode = True
O = "/tmp/lean-idle/workflow-lean/review-numbers"
spec = importlib.util.spec_from_file_location("hookmod", os.path.join(O, "hookmod.py"))
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)

# 2026-09-24 00:00 CDT = 05:00Z
CUT_MS = 1790226000000
GIT = re.compile(
    r"(?:^|[\s;&|(])git\s+(?:-C\s+(\S+)\s+)?(?:-c\s+\S+\s+)*(commit|push|reset|rebase|merge|cherry-pick|stash|checkout|switch|add)\b"
)
TMP = re.compile(r"/tmp\b|/private/tmp|/var/folders|mktemp|\$TMPDIR|\$\{?TMPDIR")
SHIP = re.compile(r"(?:^|[\s;&|(/])(ship-land|deploy-live)(?:\.sh)?\b")


def acct(p):
    for a in ("next", "secondary", "tertiary", "quaternary"):
        if f"/.claude-{a}/" in p:
            return a
    return "?"


def scan(path):
    r = dict(aid=os.path.basename(path)[6:-6], path=path)
    try:
        meta = json.load(open(path[:-6] + ".meta.json"))
    except Exception:
        meta = {}
    r["agentType"] = meta.get("agentType")
    r["desc"] = meta.get("description")
    usage = collections.OrderedDict()
    brief_chars, nuser, first_ts, version, model, cwd = 0, 0, None, None, None, None
    tools = collections.Counter()
    need = collections.Counter()
    vis, sig, finals = 0, 0, set()
    try:
        fh = open(path, "rb")
    except OSError:
        return None
    with fh:
        for line in fh:
            try:
                d = json.loads(line)
            except Exception:
                continue
            t = d.get("type")
            if cwd is None and d.get("cwd"):
                cwd = d.get("cwd")
            if t == "user" and nuser < 2 and not usage:
                c = (d.get("message") or {}).get("content")
                if isinstance(c, str):
                    brief_chars += len(c)
                    nuser += 1
                elif isinstance(c, list):
                    if any(
                        isinstance(x, dict) and x.get("type") == "tool_result"
                        for x in c
                    ):
                        nuser = 2
                    else:
                        brief_chars += sum(
                            len(x.get("text") or "") for x in c if isinstance(x, dict)
                        )
                        nuser += 1
                continue
            if t != "assistant":
                continue
            m = d.get("message") or {}
            if m.get("model") == "<synthetic>":
                continue
            mid = m.get("id") or d.get("requestId") or d.get("uuid")
            u = m.get("usage") or {}
            e = usage.get(mid)
            if e is None:
                e = usage[mid] = [0, 0, 0, 0]
                if first_ts is None:
                    first_ts, version, model = (
                        d.get("timestamp"),
                        d.get("version"),
                        m.get("model"),
                    )
            e[0] = max(e[0], u.get("cache_creation_input_tokens") or 0)
            e[1] = max(e[1], u.get("cache_read_input_tokens") or 0)
            e[2] = max(e[2], u.get("input_tokens") or 0)
            e[3] = max(e[3], u.get("output_tokens") or 0)
            if m.get("stop_reason"):
                finals.add(mid)
            for c in m.get("content") or []:
                if not isinstance(c, dict):
                    continue
                ct = c.get("type")
                if ct == "thinking":
                    sig += len(c.get("signature") or "")
                    vis += len(c.get("thinking") or "")
                elif ct == "redacted_thinking":
                    sig += len(c.get("data") or "")
                elif ct == "text":
                    vis += len(c.get("text") or "")
                elif ct == "tool_use":
                    n = c.get("name") or ""
                    inp = c.get("input") or {}
                    vis += len(json.dumps(inp))
                    tools[n] += 1
                    if n == "Skill":
                        need["skill"] += 1
                    elif n.startswith("mcp__"):
                        need["mcp"] += 1
                    elif n in ("Agent", "Task"):
                        need["agent"] += 1
                    elif n in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
                        p = str(inp.get("file_path") or inp.get("notebook_path") or "")
                        if re.match(r"^(/Users/[^/]+|~)/\.claude", p):
                            need["home_claude_write"] += 1
                    elif n == "Bash":
                        cmd = str(inp.get("command") or "")
                        # crude: drop heredoc bodies and quoted strings before matching
                        c2 = re.sub(
                            r"<<-?\s*['\"]?(\w+)['\"]?.*?\n\1\b", " ", cmd, flags=re.S
                        )
                        c2 = re.sub(r"'[^']*'|\"(?:\\.|[^\"\\])*\"", " Q ", c2)
                        g = GIT.search(c2)
                        if g:
                            need["git_tmp" if (TMP.search(cmd)) else "git_real"] += 1
                        if SHIP.search(c2):
                            need["ship"] += 1
    reqs = list(usage.values())
    r.update(
        nreq=len(reqs),
        first_cw=reqs[0][0] if reqs else 0,
        first_cr=reqs[0][1] if reqs else 0,
        first_in=reqs[0][2] if reqs else 0,
        cw=sum(x[0] for x in reqs),
        cr=sum(x[1] for x in reqs),
        inp=sum(x[2] for x in reqs),
        out=sum(x[3] for x in reqs),
        nfinal=len(finals),
        brief_chars=brief_chars,
        first_ts=first_ts,
        version=version,
        model=model,
        cwd=cwd,
        tools=dict(tools),
        need=dict(need),
        vis=vis,
        sig=sig,
        size=os.path.getsize(path),
    )
    return r


def main():
    t0 = time.time()
    runs = {}
    for p in (l.strip() for l in open(f"{O}/runjson.txt")):
        try:
            d = json.load(open(p))
        except Exception:
            continue
        rid = d.get("runId") or os.path.basename(p)[:-5]
        e = runs.setdefault(
            rid, dict(runId=rid, start=None, script=None, name=None, jsons=[])
        )
        e["jsons"].append(p)
        st = d.get("startTime")
        if st and (e["start"] is None or st < e["start"]):
            e["start"] = st
        s = d.get("script")
        if isinstance(s, str) and len(s) > len(e["script"] or ""):
            e["script"] = s
        e["name"] = e["name"] or d.get("workflowName")
    for p in (l.strip() for l in open(f"{O}/scripts.txt")):
        m = re.search(r"(wf_[0-9a-f]{8}-[0-9a-f]{3})\.m?js$", p)
        if not m:
            continue
        rid = m.group(1)
        e = runs.setdefault(
            rid, dict(runId=rid, start=None, script=None, name=None, jsons=[])
        )
        if not e["script"]:
            try:
                e["script"] = open(p, encoding="utf-8", errors="replace").read()
                e["script_from_file"] = True
            except OSError:
                pass
    dirs = collections.defaultdict(list)
    for p in (l.strip().replace("//", "/") for l in open(f"{O}/rundirs.txt")):
        dirs[os.path.basename(p)].append(p)
    for rid in dirs:
        runs.setdefault(
            rid, dict(runId=rid, start=None, script=None, name=None, jsons=[])
        )
    # agent files: union over all copies, keep largest per agentId
    jobs = {}
    owner = {}
    for rid, e in runs.items():
        best = {}
        for d in dirs.get(rid, []):
            for a in glob.glob(d + "/agent-*.jsonl"):
                aid = os.path.basename(a)[6:-6]
                sz = os.path.getsize(a)
                if aid not in best or sz > best[aid][1]:
                    best[aid] = (a, sz)
        e["aids"] = sorted(best)
        e["ncopies"] = len(dirs.get(rid, []))
        e["accts"] = sorted(
            {acct(d) for d in dirs.get(rid, [])} | {acct(p) for p in e["jsons"]}
        )
        for aid, (a, sz) in best.items():
            if aid in owner and owner[aid] != rid:
                e.setdefault("shared_aids", []).append(aid)
            owner[aid] = rid
            jobs[aid] = a
    print("runs", len(runs), "agent files", len(jobs), file=sys.stderr)
    # window: start from JSON, else earliest slot ts (computed after scan)
    with ProcessPoolExecutor(8) as ex:
        res = list(ex.map(scan, list(jobs.values()), chunksize=16))
    slots = {r["aid"]: r for r in res if r}
    print("scanned", len(slots), f"{time.time() - t0:.0f}s", file=sys.stderr)
    fr = open(f"{O}/runs.jsonl", "w")
    fs = open(f"{O}/slots.jsonl", "w")
    for rid, e in runs.items():
        ss = [slots[a] for a in e["aids"] if a in slots]
        ts_min = min((s["first_ts"] for s in ss if s["first_ts"]), default=None)
        e["ts_min"] = ts_min
        src = e.get("script")
        sites = []
        if src:
            try:
                for off, args in hook.agent_calls(src):
                    row = hook.slot_row(src, off, args)
                    row["frags"] = [
                        f for f in re.split(r"\$\{[^}]*\}", (args[0] if args else ""))
                    ]
                    sites.append(row)
            except Exception as ex_:  # noqa
                e["replay_error"] = str(ex_)[:200]
        e["sha"] = hashlib.sha1(src.encode()).hexdigest()[:12] if src else None
        e["sites"] = [{k: v for k, v in s.items() if k != "frags"} for s in sites]
        e["verdicts"] = dict(collections.Counter(s["verdict"] for s in sites))
        e["would_deny"] = e["verdicts"].get("would-deny", 0) > 0
        e["script_chars"] = len(src) if src else None
        # journal labels
        labels = {}
        for d in dirs.get(rid, []):
            jp = os.path.join(d, "journal.jsonl")
            if os.path.exists(jp):
                for l in open(jp):
                    try:
                        j = json.loads(l)
                    except Exception:
                        continue
                    if j.get("type") == "started" and j.get("agentId"):
                        labels[j["agentId"]] = j.get("label")
        for s in ss:
            s["runId"] = rid
            s["label"] = labels.get(s["aid"])
            fs.write(json.dumps(s) + "\n")
        out = {k: v for k, v in e.items() if k not in ("script",)}
        fr.write(json.dumps(out) + "\n")
    print("done", f"{time.time() - t0:.0f}s", file=sys.stderr)


if __name__ == "__main__":
    main()
