#!/usr/bin/env python3
# noise-floor scanner: every transcript (main + subagents) touched in the window, one account.
# usage: python3 -I scan.py <acct> <projects_dir> <start_epoch> <end_epoch> <out_prefix>
# Writes <out_prefix>.req.tsv  : one row per unique requestId per file (output = max over streamed records)
#        <out_prefix>.files.tsv: per file: idx, path, is_sub, sid, parent_sid, cwd, tool_results,
#                                tool_err_total, tool_err_hook, tool_err_user, ptl_n, ptl_last_ts,
#                                last_real_ts, ratelimit_n, apierr_n, workflow_calls, agent_calls, poll_loops,
#                                bash_calls
# Read-only over transcripts.
import json
import os
import re
import sys
import time
from datetime import datetime

acct, root, t_start, t_end, outp = sys.argv[1:6]
t_start, t_end = float(t_start), float(t_end)
SLACK = (
    86400.0  # keep one day before the window so gaps/ctx at the window start are known
)


def ts_epoch(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


CWD = re.compile(rb'"cwd":"([^"]+)"')
TSRE = re.compile(rb'"timestamp":"([^"]+)"')
# poll loop: an until/while loop that sleeps, or a bare long sleep (the W3 rule's class, widened)
POLL = re.compile(
    r"\b(until|while)\b[\s\S]{0,600}?\bsleep\b|select\(undef|time\.sleep\("
)

files = []
for dp, dn, fn in os.walk(root, followlinks=True):
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
bad = 0
fo = open(outp + ".files.tsv", "w")
fo.write(
    "fi\tpath\tis_sub\tsid\tparent_sid\tcwd\ttool_results\ttool_err\ttool_err_hook\ttool_err_user"
    "\tptl_n\tptl_last_ts\tlast_real_ts\tratelimit_n\tapierr_n\tworkflow_calls\tagent_calls\tpoll_loops\tbash_calls\n"
)
ro = open(outp + ".req.tsv", "w")
ro.write("acct\tfi\tis_sub\tsid\tts\treq\tmodel\tinp\tcc\tcc1h\tcr\tout\tturn\n")
for fi, (p, sz, mt) in enumerate(files):
    is_sub = 1 if "/subagents/" in p else 0
    if is_sub:
        parts = p.split("/subagents/")[0]
        parent_sid = os.path.basename(parts)
    else:
        parent_sid = os.path.basename(p)[:-6]
    sid = parent_sid if not is_sub else os.path.basename(p)[:-6]
    cwd = ""
    tr = te_all = te_hook = te_user = 0
    ptl_n = 0
    ptl_last = 0.0
    last_real = 0.0
    rl_n = ae_n = 0
    wf = ag = poll = bashn = 0
    rows, order = {}, []
    pending_turn = 1
    try:
        fh = open(p, "rb")
    except OSError:
        continue
    with fh:
        for line in fh:
            nbytes += len(line)
            if not cwd:
                m = CWD.search(line[:4000])
                if m:
                    cwd = m.group(1).decode("utf-8", "replace")
            head = line[:1500]
            if b'"type":"user"' in head:
                n_tr = line.count(b'"type":"tool_result"')
                if n_tr:
                    tr += n_tr
                    if b'"is_error":true' in line:
                        try:
                            r = json.loads(line)
                            for b in (r.get("message") or {}).get("content") or []:
                                if (
                                    not isinstance(b, dict)
                                    or b.get("type") != "tool_result"
                                    or not b.get("is_error")
                                ):
                                    continue
                                c = b.get("content")
                                if isinstance(c, list):
                                    c = " ".join(
                                        x.get("text", "")
                                        for x in c
                                        if isinstance(x, dict)
                                    )
                                c = (c or "")[:400].lower()
                                te_all += 1
                                if "hook" in c:
                                    te_hook += 1
                                elif (
                                    "doesn't want to proceed" in c
                                    or "user rejected" in c
                                    or "interrupted by user" in c
                                    or "rejected by user" in c
                                ):
                                    te_user += 1
                        except Exception:
                            bad += 1
                else:
                    pending_turn = 1
                continue
            if b'"isApiErrorMessage":true' in line:
                try:
                    r = json.loads(line)
                    m = r.get("message") or {}
                    t = " ".join(
                        b.get("text", "")
                        for b in m.get("content") or []
                        if isinstance(b, dict)
                    ).lower()
                    te = ts_epoch(r.get("timestamp", "")) or 0.0
                    if te >= t_start - SLACK:
                        if (
                            "prompt is too long" in t
                            or "too long" in t
                            and "prompt" in t
                        ):
                            ptl_n += 1
                            ptl_last = max(ptl_last, te)
                        elif "limit" in t and r.get("error") == "rate_limit":
                            rl_n += 1
                        else:
                            ae_n += 1
                except Exception:
                    bad += 1
                continue
            if b'"usage"' not in line or b'"assistant"' not in head:
                continue
            try:
                r = json.loads(line)
            except Exception:
                bad += 1
                continue
            if r.get("type") != "assistant":
                continue
            m = r.get("message") or {}
            u = m.get("usage")
            if not isinstance(u, dict) or m.get("model") == "<synthetic>":
                continue
            te = ts_epoch(r.get("timestamp", ""))
            if te is None:
                continue
            if te > last_real:
                last_real = te
            if te < t_start - SLACK or te > t_end:
                pending_turn = 0
                continue
            key = r.get("requestId") or m.get("id") or r.get("uuid")
            o = u.get("output_tokens") or 0
            if key in rows:
                if o > rows[key][8]:
                    rows[key][8] = o
                continue
            for b in m.get("content") or []:
                if not isinstance(b, dict) or b.get("type") != "tool_use":
                    continue
                nm = b.get("name")
                if nm == "Workflow":
                    wf += 1
                elif nm in ("Agent", "Task"):
                    ag += 1
                elif nm == "Bash":
                    bashn += 1
                    if is_sub:
                        cmd = str((b.get("input") or {}).get("command", ""))
                        if POLL.search(cmd):
                            poll += 1
            ccb = u.get("cache_creation") or {}
            rows[key] = [
                te,
                key,
                m.get("model", ""),
                u.get("input_tokens") or 0,
                u.get("cache_creation_input_tokens") or 0,
                ccb.get("ephemeral_1h_input_tokens") or 0,
                u.get("cache_read_input_tokens") or 0,
                0,
                o,
                pending_turn if not is_sub else 0,
            ]
            pending_turn = 0
            order.append(key)
    fo.write(
        "%d\t%s\t%d\t%s\t%s\t%s\t%d\t%d\t%d\t%d\t%d\t%.0f\t%.0f\t%d\t%d\t%d\t%d\t%d\t%d\n"
        % (
            fi,
            p,
            is_sub,
            sid,
            parent_sid,
            cwd.replace("\t", " "),
            tr,
            te_all,
            te_hook,
            te_user,
            ptl_n,
            ptl_last,
            last_real,
            rl_n,
            ae_n,
            wf,
            ag,
            poll,
            bashn,
        )
    )
    for k in order:
        x = rows[k]
        ro.write(
            "%s\t%d\t%d\t%s\t%.3f\t%s\t%s\t%d\t%d\t%d\t%d\t%d\t%d\n"
            % (
                acct,
                fi,
                is_sub,
                parent_sid,
                x[0],
                x[1],
                x[2],
                x[3],
                x[4],
                x[5],
                x[6],
                x[8],
                x[9],
            )
        )
fo.close()
ro.close()
sys.stderr.write(
    "DONE %s files=%d GB=%.2f bad=%d secs=%.0f\n"
    % (acct, len(files), nbytes / 1e9, bad, time.time() - t0)
)
