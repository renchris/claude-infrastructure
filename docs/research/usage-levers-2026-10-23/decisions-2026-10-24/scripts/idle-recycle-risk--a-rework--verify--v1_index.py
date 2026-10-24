#!/usr/bin/env python3
# Independent index (verifier). usage: python3 -I v1_index.py <out.jsonl> <start_iso> <acct=dir> ...
# One line per main-session transcript (not under subagents/) with mtime >= start: path, acct, size,
# sessionId, cwd, ts_first, ts_last, the first 3 non-meta, non-tool-result user prompts (8000 chars each),
# and the last 5 Bash commands containing "handoff-fire" or "--recycle".
import json, os, sys, time
from datetime import datetime

out_path, start_iso = sys.argv[1], sys.argv[2]
accts = [a.split("=", 1) for a in sys.argv[3:]]
t_start = datetime.fromisoformat(start_iso.replace("Z", "+00:00")).timestamp()


def text_of(c):
    if isinstance(c, list):
        return "\n".join(
            b.get("text", "")
            for b in c
            if isinstance(b, dict) and b.get("type") == "text"
        )
    return c if isinstance(c, str) else ""


t0 = time.time()
nfiles = nbytes = 0
with open(out_path, "w") as out:
    for acct, root in accts:
        root = os.path.expanduser(root)
        for dp, dn, fn in os.walk(root, followlinks=True):
            if "subagents" in dp.split(os.sep):
                continue
            for f in fn:
                if not f.endswith(".jsonl"):
                    continue
                p = os.path.join(dp, f)
                try:
                    st = os.stat(p)
                except OSError:
                    continue
                if st.st_mtime < t_start:
                    continue
                nfiles += 1
                rec = dict(
                    acct=acct,
                    path=p,
                    size=st.st_size,
                    fname=f[:-6],
                    sid=None,
                    cwd=None,
                    ts_first=None,
                    ts_last=None,
                    prompts=[],
                    hf_cmds=[],
                )
                with open(p, "rb") as fh:
                    for line in fh:
                        nbytes += len(line)
                        i = line.find(b'"timestamp":"')
                        if i >= 0:
                            ts = (
                                line[i + 13 : i + 41]
                                .split(b'"')[0]
                                .decode(errors="ignore")
                            )
                            if rec["ts_first"] is None:
                                rec["ts_first"] = ts
                            rec["ts_last"] = ts
                        want = (
                            rec["sid"] is None
                            or rec["cwd"] is None
                            or (
                                len(rec["prompts"]) < 3
                                and b'"type":"user"' in line
                                and b"tool_result" not in line
                            )
                            or (
                                (b"handoff-fire" in line or b"--recycle" in line)
                                and b'"tool_use"' in line
                            )
                        )
                        if not want:
                            continue
                        try:
                            r = json.loads(line)
                        except Exception:
                            continue
                        if r.get("isSidechain"):
                            continue
                        if rec["sid"] is None and r.get("sessionId"):
                            rec["sid"] = r["sessionId"]
                        if rec["cwd"] is None and r.get("cwd"):
                            rec["cwd"] = r["cwd"]
                        if (
                            r.get("type") == "user"
                            and not r.get("isMeta")
                            and len(rec["prompts"]) < 3
                        ):
                            c = (r.get("message") or {}).get("content")
                            if isinstance(c, list) and any(
                                isinstance(b, dict) and b.get("type") == "tool_result"
                                for b in c
                            ):
                                continue
                            t = text_of(c)
                            if t:
                                # keep head + the full-text marker/ledger facts (markers can sit past 8000 chars)
                                mk = "HANDOFF-RECYCLE-" in t
                                li = t.find("LEDGER AT RETIREMENT")
                                rec["prompts"].append(
                                    [
                                        r.get("timestamp"),
                                        t[:8000],
                                        mk,
                                        t[li : li + 200] if li >= 0 else "",
                                        len(t),
                                    ]
                                )
                        if r.get("type") == "assistant":
                            for b in (r.get("message") or {}).get("content") or []:
                                if (
                                    isinstance(b, dict)
                                    and b.get("type") == "tool_use"
                                    and b.get("name") == "Bash"
                                ):
                                    cmd = str((b.get("input") or {}).get("command", ""))
                                    if "handoff-fire" in cmd or "--recycle" in cmd:
                                        rec["hf_cmds"] = (
                                            rec["hf_cmds"]
                                            + [[r.get("timestamp"), cmd[:400]]]
                                        )[-5:]
                out.write(json.dumps(rec) + "\n")
sys.stderr.write(
    "V1DONE files=%d GB=%.2f secs=%.0f\n" % (nfiles, nbytes / 1e9, time.time() - t0)
)
