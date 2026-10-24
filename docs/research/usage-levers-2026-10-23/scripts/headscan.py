#!/usr/bin/env python3
# Read-only. For every transcript modified in the last 7 days on each account, read lines only
# until the first assistant record carrying usage (cap 600 lines / 8 MB) and record what was
# injected before it plus the first request's input-side token total.
import json, os, sys, time, glob

ACCTS = {
    "next": "~/.claude-next",
    "next2": "~/.claude-secondary",
    "next3": "~/.claude-tertiary",
    "next4": "~/.claude-quaternary",
}
CUTOFF = time.time() - 7 * 86400
out = open("/tmp/usage-audit/headscan.jsonl", "w")


def clen(v):
    if v is None:
        return 0
    if isinstance(v, str):
        return len(v)
    return len(json.dumps(v, ensure_ascii=False))


def msg_text_len(m):
    c = (m or {}).get("content")
    if isinstance(c, str):
        return len(c)
    if isinstance(c, list):
        n = 0
        for b in c:
            if isinstance(b, dict):
                n += (
                    len(b.get("text") or "") + clen(b.get("content"))
                    if b.get("type") != "image"
                    else 0
                )
        return n
    return 0


seen_real = set()
for acct, base in ACCTS.items():
    root = os.path.realpath(os.path.expanduser(base + "/projects"))
    if root in seen_real:
        continue
    seen_real.add(root)
    for dp, dn, fn in os.walk(root):
        for f in fn:
            if not f.endswith(".jsonl"):
                continue
            p = os.path.join(dp, f)
            try:
                st = os.stat(p)
            except OSError:
                continue
            if st.st_mtime < CUTOFF:
                continue
            sub = "/subagents/" in p
            rec = {"acct": acct, "sub": sub, "path": p, "bytes": st.st_size}
            if sub:
                try:
                    rec["agentType"] = json.load(open(p[:-6] + ".meta.json")).get(
                        "agentType"
                    )
                except Exception:
                    rec["agentType"] = None
            att = {}
            instr = []
            hooks = []
            prompt_chars = 0
            nuser = 0
            read = 0
            try:
                with open(p, "rb") as fh:
                    for i, raw in enumerate(fh):
                        read += len(raw)
                        if i > 600 or read > 8_000_000:
                            break
                        try:
                            r = json.loads(raw)
                        except Exception:
                            continue
                        t = r.get("type")
                        if t == "assistant":
                            u = (r.get("message") or {}).get("usage")
                            if u:
                                rec["u"] = [
                                    u.get("input_tokens", 0),
                                    u.get("cache_creation_input_tokens", 0),
                                    u.get("cache_read_input_tokens", 0),
                                    u.get("output_tokens", 0),
                                ]
                                rec["ts"] = r.get("timestamp")
                                rec["model"] = (r.get("message") or {}).get("model")
                                break
                        elif t == "user":
                            nuser += 1
                            if not r.get("isMeta"):
                                prompt_chars += msg_text_len(r.get("message"))
                        elif t == "attachment":
                            a = r.get("attachment") or {}
                            at = a.get("type")
                            if at == "instructions":
                                for e in a.get("files") or []:
                                    instr.append(
                                        [
                                            e.get("path"),
                                            e.get("type"),
                                            clen(e.get("content")),
                                        ]
                                    )
                                continue
                            if at and at.startswith("hook"):
                                n = (
                                    clen(a.get("content"))
                                    if at != "hook_success"
                                    else clen(a.get("stdout"))
                                )
                                hooks.append(
                                    [
                                        at,
                                        a.get("hookEvent"),
                                        a.get("hookName"),
                                        os.path.basename(
                                            (a.get("command") or "").split()[0]
                                        )
                                        if a.get("command")
                                        else None,
                                        n,
                                    ]
                                )
                                continue
                            n = 0
                            for k, v in a.items():
                                if k in ("type", "isInitial", "skillCount"):
                                    continue
                                n += clen(v)
                            if at == "prompt_snapshot":
                                n = clen(a.get("systemPrompt"))
                            att[at] = att.get(at, 0) + n
            except OSError:
                continue
            rec.update(
                att=att,
                instr=instr,
                hooks=hooks,
                prompt_chars=prompt_chars,
                nuser=nuser,
            )
            out.write(json.dumps(rec) + "\n")
out.close()
print("DONE")
