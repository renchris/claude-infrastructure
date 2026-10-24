#!/usr/bin/env python3
# Keepalive replay scanner (read-only over transcripts). Extends w4/scan.py with: turn-opener kinds,
# every timestamped non-request record (to replay the keepalive's transcript-size check), entrypoint,
# /goal markers, hook blocks, and background jobs incl. watchers.
# usage: python3 -I scan.py <acct> <projects_dir> <start_epoch> <end_epoch> <outprefix>
import json
import os
import re
import sys
import time
from datetime import datetime

acct, root, t_start, t_end, outp = sys.argv[1:6]
t_start, t_end = float(t_start), float(t_end)
EV_LO = t_start - 2 * 86400

TSRX = re.compile(rb'"timestamp":"([^"]+)"')
TYRX = re.compile(rb'"type":"([a-z_-]+)"')
SUBRX = re.compile(rb'"subtype":"([a-z_]+)"')
ATTRX = re.compile(rb'"attachment":\{"type":"([a-z_]+)"')
TUIDB = re.compile(rb"<tool-use-id>([^<]+)</tool-use-id>")
NOTICE = b"<task-notification>\\n<task-id>"
CLOSE_MARKS = (b"self-close", b"--recycle", b'"/exit', b"<command-name>/exit")


def ts_epoch(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def text_of(r):
    c = (r.get("message") or {}).get("content")
    if isinstance(c, list):
        parts = []
        for b in c:
            if isinstance(b, dict):
                if b.get("type") == "tool_result":
                    return None
                parts.append(b.get("text", "") or "")
        c = " ".join(parts)
    return c if isinstance(c, str) else ""


def opener_kind(t):
    if t.startswith("<task-notification>\n<summary>"):
        if "peer mail" in t[:80]:
            return "mail"
        if "Goal check-in" in t[:80]:
            return "goal"
        return "rewake"
    if t.startswith("<task-notification>"):
        return "job"
    if t.startswith("<command-name>") or t.startswith("<command-message>"):
        return "cmd"
    if t.startswith("<local-command"):
        return "local"
    if (
        t.startswith("<scheduled")
        or "ScheduleWakeup" in t[:200]
        or t.startswith("<cron")
    ):
        return "sched"
    return "prompt"


files = []
for dp, dn, fn in os.walk(root, followlinks=True):
    if "/subagents" in dp:
        continue
    for f in fn:
        if not f.endswith(".jsonl"):
            continue
        p = os.path.join(dp, f)
        try:
            st = os.stat(p)
        except OSError:
            continue
        if st.st_mtime >= t_start:
            files.append((p, st.st_size, st.st_mtime))

t0 = time.time()
nbytes = 0
fo_req = open(outp + ".req", "w")
fo_ev = open(outp + ".ev", "w")
fo_op = open(outp + ".op", "w")
fo_job = open(outp + ".jobs", "w")
fo_files = open(outp + ".files", "w")
for fi, (p, sz, mt) in enumerate(files):
    rows, order = {}, []
    sid = os.path.basename(p)[:-6]
    eps = {}
    jobs = {}
    goal_n = 0
    try:
        fh = open(p, "rb")
    except OSError:
        continue
    with fh:
        for line in fh:
            nbytes += len(line)
            m = TSRX.search(line, 0, 4000) or TSRX.search(line)
            te = ts_epoch(m.group(1).decode(errors="ignore")) if m else None
            head = line[:400]
            if NOTICE in line:
                for tu in TUIDB.findall(line):
                    tu = tu.decode()
                    if tu in jobs and te and (jobs[tu][1] is None or te < jobs[tu][1]):
                        jobs[tu][1] = te
            if b'"type":"user"' in head:
                if b'"type":"tool_result"' in line[:700]:
                    continue
                rtype = "user"
            elif b'"role":"assistant"' in head:
                if b'"usage"' not in line:
                    continue
                rtype = "assistant"
            else:
                rtype = None
            if rtype is None:
                if te is not None and EV_LO <= te <= t_end:
                    am = ATTRX.search(head)
                    if am:
                        lab = "att:" + am.group(1).decode()
                    elif b'"type":"system"' in head:
                        sm = SUBRX.search(line, 0, 600)
                        lab = "sys:" + (sm.group(1).decode() if sm else "?")
                    elif line.startswith(b'{"type":"'):
                        tm = TYRX.search(line, 0, 60)
                        lab = "top:" + (tm.group(1).decode() if tm else "?")
                    else:
                        lab = "other"
                    if lab == "att:goal_status":
                        goal_n += 1
                    blk = ""
                    if lab == "att:hook_blocking_error":
                        mm = re.search(rb'"hookEvent":"([A-Za-z]+)"', line)
                        blk = mm.group(1).decode() if mm else ""
                    fo_ev.write("%d\t%.3f\t%s\t%s\n" % (fi, te, lab, blk))
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            if r.get("isSidechain"):
                continue
            te = ts_epoch(r.get("timestamp") or "") if isinstance(r.get("timestamp"), str) else te
            ep = r.get("entrypoint")
            if ep:
                eps[ep] = eps.get(ep, 0) + 1
            if r.get("type") == "user":
                t = text_of(r)
                if t is None:
                    continue  # tool_result
                if te is not None and EV_LO <= te <= t_end:
                    k = opener_kind(t)
                    extra = ""
                    if k == "job":
                        tus = TUIDB.findall(line)
                        extra = tus[0].decode() if tus else ""
                        st_m = re.search(r"<status>([a-z_]+)</status>", t)
                        extra += "|" + (st_m.group(1) if st_m else "")
                    fo_op.write(
                        "%d\t%.3f\t%s\t%d\t%s\t%s\n"
                        % (
                            fi,
                            te,
                            k,
                            int(bool(r.get("isMeta"))),
                            extra,
                            t[:90].replace("\t", " ").replace("\n", " "),
                        )
                    )
                continue
            if r.get("type") != "assistant":
                continue
            msg = r.get("message") or {}
            u = msg.get("usage")
            if not isinstance(u, dict) or msg.get("model") == "<synthetic>":
                continue
            if r.get("sessionId"):
                sid = r["sessionId"]
            for b in msg.get("content") or []:
                if not isinstance(b, dict) or b.get("type") != "tool_use":
                    continue
                nm, bi = b.get("name"), b.get("input") or {}
                if nm == "Bash" and bi.get("run_in_background"):
                    watcher = int("cc-await-ping" in str(bi.get("command", "")))
                elif nm == "Monitor":
                    watcher = 1
                elif nm in ("Agent", "Workflow", "Task"):
                    watcher = 0
                else:
                    continue
                if b.get("id") and b["id"] not in jobs:
                    jobs[b["id"]] = [te, None, nm, watcher]
            if te is None or te < EV_LO or te > t_end:
                continue
            key = r.get("requestId") or msg.get("id") or r.get("uuid")
            o = u.get("output_tokens") or 0
            if key in rows:
                if o > rows[key][9]:
                    rows[key][9] = o
                continue
            ccb = u.get("cache_creation") or {}
            rows[key] = [
                te,
                key,
                msg.get("model", ""),
                u.get("input_tokens") or 0,
                u.get("cache_creation_input_tokens") or 0,
                ccb.get("ephemeral_5m_input_tokens") or 0,
                ccb.get("ephemeral_1h_input_tokens") or 0,
                u.get("cache_read_input_tokens") or 0,
                0,
                o,
            ]
            order.append(key)
    closed = 0
    try:
        with open(p, "rb") as fh:
            fh.seek(max(0, sz - 262144))
            tail = fh.read()
        closed = int(any(mk in tail for mk in CLOSE_MARKS))
    except OSError:
        pass
    for tu, (js, je, nm, w) in jobs.items():
        if je is None and nm in ("Agent", "Task"):
            continue
        fo_job.write(
            "%d\t%s\t%s\t%s\t%d\t%s\t%s\n"
            % (fi, sid, tu, nm, w, "%.3f" % js if js else "", "%.3f" % je if je else "")
        )
    ep_main = max(eps, key=eps.get) if eps else ""
    fo_files.write(
        "%d\t%.0f\t%d\t%s\t%d\t%s\t%d\t%s\n"
        % (fi, mt, sz, sid, closed, ep_main, goal_n, p)
    )
    for k in order:
        x = rows[k]
        fo_req.write(
            "%s\t%d\t%s\t%.3f\t%s\t%s\t%d\t%d\t%d\t%d\t%d\t%d\n"
            % (acct, fi, sid, x[0], x[1], x[2], x[3], x[4], x[5], x[6], x[7], x[9])
        )
for f in (fo_req, fo_ev, fo_op, fo_job, fo_files):
    f.close()
sys.stderr.write(
    "DONE acct=%s files=%d bytes=%.2fGB secs=%.1f\n"
    % (acct, len(files), nbytes / 1e9, time.time() - t0)
)
