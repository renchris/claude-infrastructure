#!/usr/bin/env python3
# Stage 1: index every main-session transcript (not under subagents/) modified since START on one account.
# usage: python3 -I stage1.py <acct> <projects_dir> <start_iso> <out_jsonl>
# One JSON line per file: sid, cwd, first/last ts, first non-meta user prompt (6000 chars), recycle markers,
# and every Bash tool_use whose command mentions --recycle (the predecessor side of a recycle).
import json, os, re, sys, time
from datetime import datetime

acct, root, start_iso, out_path = sys.argv[1:5]
t_start = datetime.fromisoformat(start_iso.replace("Z", "+00:00")).timestamp()
MARK = re.compile(r"HANDOFF-(?:RECYCLE|ENGAGE)-[A-Za-z0-9._-]+")


def text_of(c):
    if isinstance(c, list):
        return "\n".join(
            b.get("text", "")
            for b in c
            if isinstance(b, dict) and b.get("type") == "text"
        )
    return c if isinstance(c, str) else ""


files = []
for dp, dn, fn in os.walk(root, followlinks=True):
    if "/subagents" in dp:
        continue
    for f in fn:
        if f.endswith(".jsonl"):
            p = os.path.join(dp, f)
            try:
                st = os.stat(p)
            except OSError:
                continue
            if st.st_mtime >= t_start:
                files.append((p, st.st_size, st.st_mtime))
t0 = time.time()
nb = 0
with open(out_path, "w") as out:
    for p, sz, mt in files:
        rec = dict(
            acct=acct,
            path=p,
            size=sz,
            mtime=mt,
            sid=os.path.basename(p)[:-6],
            sessionId=None,
            cwd=None,
            ts_first=None,
            ts_last=None,
            first_prompt=None,
            fp_ts=None,
            fp_uuid=None,
            markers=[],
            recycle_cmds=[],
            n_lines=0,
            n_user_prompts=0,
        )
        try:
            fh = open(p, "rb")
        except OSError:
            continue
        with fh:
            for line in fh:
                nb += len(line)
                rec["n_lines"] += 1
                i = line.find(b'"timestamp":"')
                ts = (
                    line[i + 13 : i + 37].split(b'"')[0].decode(errors="ignore")
                    if i >= 0
                    else None
                )
                if ts:
                    if rec["ts_first"] is None:
                        rec["ts_first"] = ts
                    rec["ts_last"] = ts
                need = False
                if rec["cwd"] is None and b'"cwd":"' in line:
                    need = True
                if (
                    rec["first_prompt"] is None
                    and b'"type":"user"' in line[:3000]
                    and b'"tool_result"' not in line
                ):
                    need = True
                if b"--recycle" in line and b'"tool_use"' in line:
                    need = True
                if (
                    b'"type":"user"' in line[:3000]
                    and b'"tool_result"' not in line
                    and b'"isMeta":true' not in line
                ):
                    rec["n_user_prompts"] += 1
                if not need:
                    continue
                try:
                    r = json.loads(line)
                except Exception:
                    continue
                if r.get("isSidechain"):
                    continue
                if rec["cwd"] is None and r.get("cwd"):
                    rec["cwd"] = r["cwd"]
                if r.get("sessionId") and rec["sessionId"] is None:
                    rec["sessionId"] = r["sessionId"]
                if (
                    rec["first_prompt"] is None
                    and r.get("type") == "user"
                    and not r.get("isMeta")
                ):
                    t = text_of((r.get("message") or {}).get("content"))
                    if (
                        t
                        and not t.startswith("<local-command")
                        and not t.startswith("<command-name>/")
                        and not t.startswith("Caveat:")
                    ):
                        rec["first_prompt"] = t[:6000]
                        rec["fp_ts"] = r.get("timestamp")
                        rec["fp_uuid"] = r.get("uuid")
                        rec["markers"] = sorted(set(MARK.findall(t)))
                if r.get("type") == "assistant":
                    for b in (r.get("message") or {}).get("content") or []:
                        if (
                            isinstance(b, dict)
                            and b.get("type") == "tool_use"
                            and b.get("name") == "Bash"
                        ):
                            cmd = str((b.get("input") or {}).get("command", ""))
                            if "--recycle" in cmd:
                                rec["recycle_cmds"].append(
                                    [r.get("timestamp"), cmd[:600], b.get("id")]
                                )
        out.write(json.dumps(rec) + "\n")
sys.stderr.write(
    "DONE acct=%s files=%d GB=%.2f secs=%.0f\n"
    % (acct, len(files), nb / 1e9, time.time() - t0)
)
