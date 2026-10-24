#!/usr/bin/env python3
# Stage 2: per-session request/tool event extraction for a list of transcripts.
# usage: python3 -I stage2.py <paths.txt> <out.jsonl>
# A "request" = one assistant API call (records grouped by requestId / message.id; output = max).
# For each request: ts, ctx (input+cache_write+cache_read), cw, cr, out, tool calls (name + key),
# context-loss phrase hits in assistant text. Tool results: chars of the result text and is_error.
# Also: compaction points (request index), non-tool-result user prompts (ts, request index, 300 chars).
import hashlib, json, re, sys

paths = [l.strip() for l in open(sys.argv[1]) if l.strip()]
out = open(sys.argv[2], "w")
LOSS = re.compile(
    r"(?i)\b(?:i (?:don't|do not) have (?:the |any |enough |full )?context|(?:lack|lacking|missing) (?:the )?context|"
    r"no context (?:on|about|for)|(?:don't|do not) (?:know|recall|remember) (?:what|which|where|why) (?:you|the (?:previous|prior|earlier)|my predecessor|the predecessor)|"
    r"not sure what (?:you|the operator) (?:mean|meant|are referring|refer)|which (?:one|file|task|item|branch|plan) do you mean|"
    r"could you (?:clarify|remind me)|(?:can't|cannot|couldn't) (?:find|see) (?:the|any) (?:earlier|previous|prior)|"
    r"predecessor(?:'s)? (?:didn't|did not|never) (?:say|leave|record|mention|note)|the brief (?:doesn't|does not) (?:say|specify|mention)|"
    r"(?:no|without) (?:record|memory) of (?:what|that|the earlier|the previous))"
)


def h(s):
    return hashlib.md5((s or "").encode()).hexdigest()[:12]


def text_of(c):
    if isinstance(c, list):
        parts = []
        for b in c:
            if isinstance(b, dict):
                if b.get("type") == "text":
                    parts.append(b.get("text", ""))
                elif b.get("type") == "image":
                    parts.append(
                        "x" * 6000
                    )  # ~1.5k tokens per image, a rough placeholder
        return "\n".join(parts)
    return c if isinstance(c, str) else ""


def tool_key(name, i):
    if name == "Read":
        return i.get("file_path", "")
    if name == "Bash":
        return str(i.get("command", ""))[:3000]
    if name == "Grep":
        return json.dumps(
            {
                k: i.get(k)
                for k in (
                    "pattern",
                    "path",
                    "glob",
                    "type",
                    "output_mode",
                    "-i",
                    "-n",
                    "multiline",
                )
            },
            sort_keys=True,
        )
    if name == "Glob":
        return json.dumps({k: i.get(k) for k in ("pattern", "path")}, sort_keys=True)
    if name in ("Edit", "MultiEdit"):
        return json.dumps(
            [
                i.get("file_path", ""),
                h(i.get("old_string")),
                h(i.get("new_string")),
                bool(i.get("replace_all")),
            ]
        )
    if name == "Write":
        return json.dumps([i.get("file_path", ""), h(i.get("content"))])
    return ""


for p in paths:
    reqs, idx_of, results, prompts, compacts = [], {}, {}, [], []
    sid = None
    try:
        fh = open(p, "rb")
    except OSError:
        continue
    with fh:
        for line in fh:
            if b'"isSidechain":true' in line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            t = r.get("type")
            if r.get("sessionId") and not sid:
                sid = r["sessionId"]
            if t == "system" and r.get("subtype") == "compact_boundary":
                compacts.append(len(reqs))
                continue
            if t == "user":
                if r.get("isCompactSummary"):
                    compacts.append(len(reqs))
                    continue
                c = (r.get("message") or {}).get("content")
                if isinstance(c, list) and any(
                    isinstance(b, dict) and b.get("type") == "tool_result" for b in c
                ):
                    for b in c:
                        if isinstance(b, dict) and b.get("type") == "tool_result":
                            results[b.get("tool_use_id")] = [
                                len(text_of(b.get("content"))),
                                bool(b.get("is_error")),
                            ]
                    continue
                if r.get("isMeta"):
                    continue
                tx = text_of(c)
                if tx:
                    prompts.append([r.get("timestamp"), len(reqs), tx[:300]])
                continue
            if t != "assistant":
                continue
            m = r.get("message") or {}
            if m.get("model") == "<synthetic>" or r.get("isApiErrorMessage"):
                continue
            u = m.get("usage") or {}
            key = r.get("requestId") or m.get("id") or r.get("uuid")
            if key not in idx_of:
                idx_of[key] = len(reqs)
                reqs.append(
                    dict(
                        ts=r.get("timestamp"),
                        ctx=(u.get("input_tokens") or 0)
                        + (u.get("cache_creation_input_tokens") or 0)
                        + (u.get("cache_read_input_tokens") or 0),
                        cw=u.get("cache_creation_input_tokens") or 0,
                        cr=u.get("cache_read_input_tokens") or 0,
                        out=u.get("output_tokens") or 0,
                        tools=[],
                        loss=[],
                    )
                )
            q = reqs[idx_of[key]]
            q["out"] = max(q["out"], u.get("output_tokens") or 0)
            for b in m.get("content") or []:
                if not isinstance(b, dict):
                    continue
                if b.get("type") == "tool_use":
                    nm = b.get("name")
                    q["tools"].append(
                        [b.get("id"), nm, tool_key(nm, b.get("input") or {})]
                    )
                elif b.get("type") == "text":
                    for mm in LOSS.finditer(b.get("text", "")):
                        s = b["text"]
                        q["loss"].append(s[max(0, mm.start() - 80) : mm.end() + 80])
    out.write(
        json.dumps(
            dict(
                path=p,
                sid=sid,
                reqs=reqs,
                results=results,
                prompts=prompts,
                compacts=compacts,
            )
        )
        + "\n"
    )
sys.stderr.write("DONE stage2 %d\n" % len(paths))
