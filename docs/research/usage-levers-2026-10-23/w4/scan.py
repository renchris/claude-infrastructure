#!/usr/bin/env python3
# W4 scanner: main-session requests over a window, one TSV per account. Read-only over transcripts.
# usage: python3 -I scan.py <acct> <projects_dir> <start_epoch> <end_epoch> <out_tsv>
# Rows: one per unique requestId per file (output = max over its streamed records).
# Sidecar <out_tsv>.files: file index, mtime, size, sessionId, closed flag, first prompt (300 chars).
import json
import os
import re
import sys
import time
from datetime import datetime

acct, root, t_start, t_end, out_path = sys.argv[1:6]
t_start, t_end = float(t_start), float(t_end)


def ts_epoch(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def prompt_text(r):
    c = (r.get("message") or {}).get("content")
    if isinstance(c, list):
        c = " ".join(b.get("text", "") for b in c if isinstance(b, dict))
    return c if isinstance(c, str) else ""


# A pane that retired itself (self-close / recycle / exit) cannot sit idle afterwards.
TUIDB = re.compile(rb"<tool-use-id>([^<]+)</tool-use-id>")
NOTICE = b"<task-notification>\\n<task-id>"
CLOSE_MARKS = (b"self-close", b"--recycle", b'"/exit', b"<command-name>/exit")

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
nbytes = bad = 0
meta = []
jout = open(out_path + ".jobs", "w")
with open(out_path, "w") as out:
    out.write("acct\tfile\tsid\tts\treq\tmodel\tinp\tcc\tcc5\tcc1h\tcr\tout\tturn\n")
    for fi, (p, sz, mt) in enumerate(files):
        rows, order = {}, []
        pending_turn = 1
        sid = os.path.basename(p)[:-6]
        first_prompt = ""
        jobs = {}  # tool_use_id -> [start, end (its notice) or None, tool name, watcher flag]
        try:
            fh = open(p, "rb")
        except OSError:
            continue
        with fh:
            for line in fh:
                nbytes += len(line)
                head = line[:1500]
                # A job's notice is first written as a queue-operation record, then delivered inside a
                # user record; the earliest timestamp carrying its tool-use-id is when the job ended.
                if NOTICE in line:
                    for tu in TUIDB.findall(line):
                        tu = tu.decode()
                        if tu in jobs:
                            i = line.find(b'"timestamp":"')
                            te_n = ts_epoch(line[i + 13:i + 40].split(b'"')[0].decode()) if i >= 0 else None
                            if te_n and (jobs[tu][1] is None or te_n < jobs[tu][1]):
                                jobs[tu][1] = te_n
                if b'"type":"user"' in head or b'"type": "user"' in head:
                    if b'"tool_result"' not in line:
                        # opener kind: 1 = prompt (typed, peer, hook), 2 = a background job's notice
                        pending_turn = 1
                        if NOTICE in line:
                            pending_turn = 2
                        if not first_prompt:
                            try:
                                r = json.loads(line)
                                if not r.get("isMeta"):
                                    t = prompt_text(r)
                                    if t and not t.startswith("<local-command"):
                                        first_prompt = t[:300]
                            except Exception:
                                pass
                    continue
                if b'"usage"' not in line or b'"assistant"' not in line:
                    continue
                try:
                    r = json.loads(line)
                except Exception:
                    bad += 1
                    continue
                if r.get("type") != "assistant" or r.get("isSidechain"):
                    continue
                m = r.get("message") or {}
                u = m.get("usage")
                if not isinstance(u, dict) or m.get("model") == "<synthetic>":
                    continue
                if r.get("sessionId"):
                    sid = r["sessionId"]
                te = ts_epoch(r.get("timestamp", ""))
                for b in m.get("content") or []:
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
                if te is None or te < t_start or te > t_end:
                    pending_turn = 0
                    continue
                key = r.get("requestId") or m.get("id") or r.get("uuid")
                o = u.get("output_tokens") or 0
                if key in rows:
                    if o > rows[key][9]:
                        rows[key][9] = o
                    continue
                ccb = u.get("cache_creation") or {}
                rows[key] = [
                    te,
                    key,
                    m.get("model", ""),
                    u.get("input_tokens") or 0,
                    u.get("cache_creation_input_tokens") or 0,
                    ccb.get("ephemeral_5m_input_tokens") or 0,
                    ccb.get("ephemeral_1h_input_tokens") or 0,
                    u.get("cache_read_input_tokens") or 0,
                    0,
                    o,
                    pending_turn,
                ]
                pending_turn = 0
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
            # a foreground Agent/Task returns its result inline and never gets a notice: not a job
            if je is None and nm in ("Agent", "Task"):
                continue
            jout.write("%d\t%s\t%s\t%s\t%d\t%s\t%s\n" % (fi, sid, tu, nm, w,
                       "%.3f" % js if js else "", "%.3f" % je if je else ""))
        meta.append(
            (
                fi,
                mt,
                sz,
                sid,
                closed,
                first_prompt.replace("\t", " ").replace("\n", " "),
            )
        )
        for k in order:
            x = rows[k]
            out.write(
                "%s\t%d\t%s\t%.3f\t%s\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%d\n"
                % (
                    acct,
                    fi,
                    sid,
                    x[0],
                    x[1],
                    x[2],
                    x[3],
                    x[4],
                    x[5],
                    x[6],
                    x[7],
                    x[9],
                    x[10],
                )
            )
with open(out_path + ".files", "w") as ff:
    for fi, mt, sz, sid, closed, fp in meta:
        ff.write(
            "%d\t%.0f\t%d\t%s\t%d\t%s\t%s\n"
            % (fi, mt, sz, sid, closed, files[fi][0], fp)
        )
sys.stderr.write(
    "DONE acct=%s files=%d bytes=%.2fGB bad=%d secs=%.1f\n"
    % (acct, len(files), nbytes / 1e9, bad, time.time() - t0)
)
