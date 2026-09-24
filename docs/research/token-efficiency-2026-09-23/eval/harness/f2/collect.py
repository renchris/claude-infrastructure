#!/usr/bin/env python3
"""f2/collect.py <workflow-transcript-dir> <out-dir> — per-slot metrics, verifier verdicts, blind dossiers.

For every agent in the workflow journal (label f2:<brief>:r<rep>) it reads agent-<id>.jsonl and
agent-<id>.meta.json and computes:
  - usage summed over DISTINCT assistant message ids (streamed chunks repeat the usage block),
    first-request prefix (input + cache_creation + cache_read of the first response),
    responses, tool errors, list $ at Opus 5.5 weights, and the meter proxy (input + cache_creation + output)
  - StructuredOutput first-try validity: the first StructuredOutput call did not come back as an error
  - out-of-OUTDIR writes: Write/Edit/NotebookEdit paths, and Bash commands that write (>, tee, cp, mv,
    mkdir, touch, sed -i) to an absolute path outside the slot's OUTDIR
  - verifier: the slot's numbers vs truth.json (exact briefs), else "judged"
Writes <out>/metrics.json, <out>/dossiers/<brief>/dossier-<k>.md (dossier order shuffled per brief,
seeded) and <out>/keys/<brief>.json mapping dossier -> agentType. Dossiers carry the brief, the tool
calls, the returned headline and answer.md — never the agent type, the model, or the token counts.
"""

import glob, json, os, random, re, sys

W, OUT = sys.argv[1], sys.argv[2]
G = os.environ.get("GATE_ROOT", "/tmp/tokeff-gate")
F = f"{G}/f2"
truth = json.load(open(f"{F}/truth.json"))
P = {
    "in": 4.0,
    "cw5": 5.0,
    "cw1h": 8.0,
    "cr": 0.20,
    "out": 20.0,
}  # $/MTok, Opus 5.5 list (BASELINE.md weights)

agents = {}
for line in open(f"{W}/journal.jsonl"):
    r = json.loads(line)
    if r.get("type") == "started" and str(r.get("label", "")).startswith("f2:"):
        agents[r["agentId"]] = r["label"]
    if r.get("type") == "result" and r.get("agentId") in agents:
        agents[r["agentId"]] = agents[
            r["agentId"]
        ]  # keep label; result read from the transcript

WRITE_BASH = re.compile(
    # literal absolute targets only: `> /x`, `>> /x`, `tee [-a] /x`, `mkdir [-p] /x`, `touch /x`
    r"(>>?|\btee(?:\s+-a)?|\bmkdir(?:\s+-p)?|\btouch)\s*(/[\w./~-]+)"
)


def slot_metrics(aid, label):
    _, brief, rep = label.split(":")
    rep = int(rep[1:])
    outdir = f"{F}/out/{brief}-r{rep}"
    meta = json.load(open(f"{W}/agent-{aid}.meta.json"))
    seen, first = {}, None
    tool_err = 0
    calls, results = [], {}
    so_calls = []
    final_text = ""
    for line in open(f"{W}/agent-{aid}.jsonl"):
        try:
            r = json.loads(line)
        except Exception:
            continue
        m = r.get("message") or {}
        if r.get("type") == "assistant":
            u = m.get("usage") or {}
            if m.get("id") and m["id"] not in seen:
                seen[m["id"]] = u
                if first is None:
                    first = u
            for c in m.get("content") or []:
                if c.get("type") == "tool_use":
                    calls.append((c.get("id"), c.get("name"), c.get("input") or {}))
                    if c.get("name") == "StructuredOutput":
                        so_calls.append(c.get("id"))
                if c.get("type") == "text":
                    final_text = c.get("text", "")
        if r.get("type") == "user" and isinstance(m.get("content"), list):
            for c in m["content"]:
                if isinstance(c, dict) and c.get("type") == "tool_result":
                    body = c.get("content")
                    if isinstance(body, list):
                        body = " ".join(
                            x.get("text", "") for x in body if isinstance(x, dict)
                        )
                    results[c.get("tool_use_id")] = (
                        bool(c.get("is_error")),
                        str(body or ""),
                    )
                    tool_err += bool(c.get("is_error"))
    tok = {
        "input": 0,
        "cache_creation": 0,
        "cache_read": 0,
        "output": 0,
        "cw1h": 0,
        "cw5m": 0,
    }
    for u in seen.values():
        tok["input"] += u.get("input_tokens") or 0
        tok["cache_creation"] += u.get("cache_creation_input_tokens") or 0
        tok["cache_read"] += u.get("cache_read_input_tokens") or 0
        tok["output"] += u.get("output_tokens") or 0
        cc = u.get("cache_creation") or {}
        tok["cw1h"] += cc.get("ephemeral_1h_input_tokens") or 0
        tok["cw5m"] += cc.get("ephemeral_5m_input_tokens") or 0
    other_cw = tok["cache_creation"] - tok["cw1h"] - tok["cw5m"]
    cost = (
        tok["input"] * P["in"]
        + tok["cw1h"] * P["cw1h"]
        + (tok["cw5m"] + max(other_cw, 0)) * P["cw5"]
        + tok["cache_read"] * P["cr"]
        + tok["output"] * P["out"]
    ) / 1e6
    prefix = sum(
        (first or {}).get(k) or 0
        for k in (
            "input_tokens",
            "cache_creation_input_tokens",
            "cache_read_input_tokens",
        )
    )
    so_first_ok = bool(so_calls) and not results.get(so_calls[0], (True, ""))[0]
    outside = []
    for cid, name, inp in calls:
        paths = []
        if name in ("Write", "Edit", "NotebookEdit", "MultiEdit"):
            paths.append(inp.get("file_path") or inp.get("notebook_path") or "")
        if name == "Bash":
            paths += [m.group(2) for m in WRITE_BASH.finditer(inp.get("command", ""))]
        for p in paths:
            if (
                p
                and p.startswith("/")
                and not p.startswith(outdir)
                and not p.startswith("/dev/")
            ):
                outside.append(f"{name}: {p}")
    # the returned object is the last StructuredOutput input that was accepted
    ret = None
    for cid in reversed(so_calls):
        if not results.get(cid, (True, ""))[0]:
            ret = next(inp for i, n, inp in calls if i == cid)
            break
    return dict(
        agent_id=aid,
        brief=brief,
        rep=rep,
        agent_type=meta.get("agentType"),
        responses=len(seen),
        first_prefix=prefix,
        **tok,
        cost_usd=round(cost, 6),
        meter_proxy=tok["input"] + tok["cache_creation"] + tok["output"],
        tool_calls=len(calls),
        tool_errors=tool_err,
        so_calls=len(so_calls),
        so_first_try_valid=so_first_ok,
        returned=ret is not None,
        numbers=(ret or {}).get("numbers"),
        headline=(ret or {}).get("headline"),
        outside_writes=outside,
        calls=[(n, json.dumps(i, ensure_ascii=False)[:300]) for _, n, i in calls],
        results=[results.get(c, (False, ""))[1][:300] for c, _, _ in calls],
        final_text=final_text,
    )


EXACT = {
    "B02": ["expansions", "empty_fallbacks", "files"],
    "B03": ["sessions", "sessions_with_feedback", "feedback_records"],
    "B04": ["bats_files", "test_cases"],
    "B05": ["allow_entries", "cc_entries"],
    "B07": ["sh_files", "total_lines"],
    "B09": ["count", "highest"],
}


def verify(s):
    b, n = s["brief"], s["numbers"] or {}
    if b in EXACT:
        want = truth[b]
        ok = all(
            str(n.get(k)).lstrip("0") == str(want[k]).lstrip("0")
            # B04: `bats --count` (15403) is an equally valid definition of "@test cases"
            or (k == "test_cases" and n.get(k) == want.get("test_cases_bats_count"))
            for k in EXACT[b]
        )
        return "pass" if ok else "fail"
    if b == "B08":
        return "pass" if n.get("rows") == len(truth["B08"]["rows"]) else "fail"
    return "judged"


rows = []
for aid, label in sorted(agents.items(), key=lambda kv: kv[1]):
    if not os.path.exists(f"{W}/agent-{aid}.jsonl"):
        continue
    s = slot_metrics(aid, label)
    s["verifier"] = verify(s)
    rows.append(s)
os.makedirs(f"{OUT}/keys", exist_ok=True)
json.dump(
    [
        {k: v for k, v in s.items() if k not in ("calls", "results", "final_text")}
        for s in rows
    ],
    open(f"{OUT}/metrics.json", "w"),
    indent=1,
)

BRIEF_TEXT = {}
wf = open(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "workflow.js")
).read()
for m in re.finditer(r"\{ id: '(B\d\d)', text: `(.*?)` \}", wf, re.S):
    BRIEF_TEXT[m.group(1)] = (
        m.group(2).replace("${T}", f"{F}/tree").replace("${F}", F).replace("\\$", "$")
    )
for b in sorted({s["brief"] for s in rows}):
    group = [s for s in rows if s["brief"] == b]
    random.Random(f"f2-{b}").shuffle(group)
    d = f"{OUT}/dossiers/{b}"
    os.makedirs(d, exist_ok=True)
    keys = {}
    for k, s in enumerate(group, 1):
        ans = f"{F}/out/{b}-r{s['rep']}/answer.md"
        body = (
            open(ans, errors="replace").read()
            if os.path.exists(ans)
            else "(no answer.md was written)"
        )
        calls = "\n".join(
            f"{i + 1}. `{n}: {inp}`\n   → {res}".replace("\r", "")
            for i, ((n, inp), res) in enumerate(zip(s["calls"], s["results"]))
        )
        stray = "\n".join(f"- {p}" for p in s["outside_writes"]) or "(none)"
        open(f"{d}/dossier-{k}.md", "w").write(
            f"# Dossier {k}\n\n## Brief\n```\n{BRIEF_TEXT.get(b, '')}\n```\n\n## Returned headline\n{s['headline']}\n\n"
            f"## Returned numbers\n`{json.dumps(s['numbers'])}`\n\n## answer.md\n{body[:12000]}\n\n"
            f"## Tool calls ({len(s['calls'])}) with the first 300 chars of each result\n{calls}\n\n"
            f"## Writes outside the slot's OUTDIR detected by the harness\n{stray}\n"
        )
        keys[f"dossier-{k}.md"] = {
            "agent_type": s["agent_type"],
            "rep": s["rep"],
            "agent_id": s["agent_id"],
        }
    json.dump(
        {"brief": b, "dossiers": keys}, open(f"{OUT}/keys/{b}.json", "w"), indent=1
    )
print(
    f"{len(rows)} slots; verifier:",
    {v: sum(1 for s in rows if s["verifier"] == v) for v in ("pass", "fail", "judged")},
)
