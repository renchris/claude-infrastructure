#!/usr/bin/env python3
# Stage 3: quality-window text for pairs and controls. Same request grouping as stage2.py.
# usage: python3 -I stage3.py <workdir> [N=10]  -> quality.jsonl (one row per window)
# Windows: successor first N requests, predecessor last N requests before the brief, control first N.
# Per window: tool errors (tool name + first 240 chars of the result), assistant text phrase hits
# (broad context-loss / uncertainty list), and the operator prompts that arrive inside the window.
import json, os, re, sys
from datetime import datetime

W = sys.argv[1]
N = int(sys.argv[2]) if len(sys.argv) > 2 else 10
PH = {
    "no_context": r"(?:don't|do not) have (?:the |any |enough |full )?context|(?:lack|lacking|missing) (?:the )?context|without (?:the )?context",
    "unclear": r"\b(?:unclear|not clear|ambiguous)\b",
    "not_sure": r"\b(?:i'm not sure|i am not sure|not certain|i don't know|i do not know)\b",
    "cant_tell": r"\b(?:can't|cannot|couldn't|could not) (?:tell|determine|find|locate|see) (?:what|which|where|whether|the|any)\b",
    "brief_gap": r"\b(?:the brief|the handoff|the predecessor|my predecessor|previous session|prior session)\b.{0,60}\b(?:doesn't|does not|didn't|did not|never|no longer)\b",
    "ask_user": r"\b(?:could you (?:clarify|confirm|remind)|can you (?:clarify|confirm|remind)|which (?:one|file|task|item|branch|plan|pane) do you (?:mean|want))\b",
}
PHC = {k: re.compile(v, re.I) for k, v in PH.items()}


def ep(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def text_of(c):
    if isinstance(c, list):
        return "\n".join(
            b.get("text", "")
            for b in c
            if isinstance(b, dict) and b.get("type") == "text"
        )
    return c if isinstance(c, str) else ""


def load(p):
    reqs, idx, names = [], {}, {}
    errs = []  # (req index of the call, tool name, text)
    prompts = []
    with open(p, "rb") as fh:
        for line in fh:
            if b'"isSidechain":true' in line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            t = r.get("type")
            if t == "user":
                c = (r.get("message") or {}).get("content")
                if isinstance(c, list) and any(
                    isinstance(b, dict) and b.get("type") == "tool_result" for b in c
                ):
                    for b in c:
                        if (
                            isinstance(b, dict)
                            and b.get("type") == "tool_result"
                            and b.get("is_error")
                        ):
                            tid = b.get("tool_use_id")
                            ri, nm = names.get(tid, (None, None))
                            errs.append((ri, nm, text_of(b.get("content"))[:240]))
                    continue
                if not r.get("isMeta") and not r.get("isCompactSummary"):
                    tx = text_of(c)
                    if tx:
                        prompts.append((len(reqs), r.get("timestamp"), tx[:400]))
                continue
            if t != "assistant":
                continue
            m = r.get("message") or {}
            if m.get("model") == "<synthetic>" or r.get("isApiErrorMessage"):
                continue
            key = r.get("requestId") or m.get("id") or r.get("uuid")
            if key not in idx:
                idx[key] = len(reqs)
                reqs.append(dict(ts=r.get("timestamp"), text=""))
            q = reqs[idx[key]]
            for b in m.get("content") or []:
                if isinstance(b, dict):
                    if b.get("type") == "text":
                        q["text"] += b.get("text", "") + "\n"
                    elif b.get("type") == "tool_use":
                        names[b.get("id")] = (idx[key], b.get("name"))
    return reqs, errs, prompts


def window(reqs, errs, prompts, lo, hi, role, sid):
    hits = {k: 0 for k in PH}
    ex = {k: [] for k in PH}
    for i in range(lo, hi):
        tx = reqs[i]["text"]
        for k, rx in PHC.items():
            for mm in rx.finditer(tx):
                hits[k] += 1
                if len(ex[k]) < 2:
                    ex[k].append(
                        tx[max(0, mm.start() - 100) : mm.end() + 100].replace("\n", " ")
                    )
    E = [e for e in errs if e[0] is not None and lo <= e[0] < hi]
    P = [p for p in prompts if lo < p[0] <= hi]
    return dict(
        role=role,
        sid=sid,
        n_req=hi - lo,
        hits=hits,
        examples=ex,
        errors=E,
        prompts_in_window=P,
    )


pairs = [json.loads(l) for l in open(os.path.join(W, "pairs.jsonl"))]
ctls = [json.loads(l) for l in open(os.path.join(W, "controls.jsonl"))]
out = open(os.path.join(W, "quality.N%d.jsonl" % N), "w")
for pr in pairs:
    if not pr["pred_path"] or not os.path.exists(pr["pred_path"]):
        continue
    sr, se, sp = load(pr["succ_path"])
    pr_, pe, pp = load(pr["pred_path"])
    if len(sr) < 2:
        continue
    cut = ep(pr["brief_ts"] or "") or 1e18
    pend = len([q for q in pr_ if (ep(q["ts"] or "") or 0) < cut])
    if pend == 0:
        continue
    out.write(
        json.dumps(window(sr, se, sp, 0, min(N, len(sr)), "succ", pr["succ"])) + "\n"
    )
    out.write(
        json.dumps(window(pr_, pe, pp, max(0, pend - N), pend, "pred", pr["pred"]))
        + "\n"
    )
for c in ctls:
    sr, se, sp = load(c["ctl_path"])
    if len(sr) < N:
        continue
    w = window(sr, se, sp, 0, N, "ctl", c["ctl"])
    w["teammate"] = c["ctl_first_prompt"].startswith("<teammate-message")
    out.write(json.dumps(w) + "\n")
sys.stderr.write("DONE stage3\n")
