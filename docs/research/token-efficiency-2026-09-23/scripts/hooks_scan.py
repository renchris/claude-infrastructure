#!/usr/bin/env python3
"""Stream every in-window transcript file listed in extract.sqlite `ctx` and pull out the hook
layer's footprint, with enough attribution to name the script:

  helem  one row per hook attachment ELEMENT. hook_additional_context carries a content[] list
         (one entry per hook that emitted additionalContext, merged by Claude Code, no command);
         hook_blocking_error carries blockingError.command; hook_success/cancelled carry command.
  hmeta  'Stop hook feedback:' meta user messages (the second copy of a Stop block reason).
  hstop  system/stop_hook_summary records: one per Stop event (hookErrors, hookAdditionalContext,
         preventedContinuation) -- the ground truth for "a Stop event happened".

Join key to extract `item`: (file, uid) with uid = record uuid + '#0'.
Run: cd /tmp && nice -n 10 python3 hooks_scan.py   (~1-2 min, 4 workers)
Output: data/hooks.sqlite (overwritten).
"""

import json
import os
import re
import sqlite3
import sys
from multiprocessing import Pool

BASE = "/Users/chrisren/Development/.worktrees/wt-feat-token-efficiency-2026-09-23/docs/research/token-efficiency-2026-09-23"
EXTRACT = f"{BASE}/data/extract.sqlite"
OUT = f"{BASE}/data/hooks.sqlite"
SINCE = "2026-09-09T00:00:00Z"
PFX = 160
CMD_RE = re.compile(r'hook blocking error from command: "([^"]*)"')


def norm_cmd(c):
    if not c:
        return None
    c = c.replace("/Users/chrisren/", "~/").replace("$HOME/", "~/")
    return c


PERS_RE = re.compile(r"Output too large \(([^)]*)\)")


def persisted_prefix(e):
    """For a <persisted-output> element (Claude Code replaced an over-10k-char hook output
    with a 2,000-char preview), return 'PERSISTED|<original size>|<preview head>' so the
    element can be attributed to the hook whose output was persisted."""
    if not e.startswith("<persisted-output>"):
        return e[:PFX]
    m = PERS_RE.search(e)
    body = e.split("):\n", 2)[-1] if "Preview (first" in e else ""
    return "PERSISTED|%s|%s" % (m.group(1) if m else "?", body[:PFX])


def scan(path):
    helem, hmeta, hstop = [], [], []
    try:
        fh = open(path, "rb")
    except OSError:
        return path, helem, hmeta, hstop
    with fh:
        for raw in fh:
            if (
                b'"attachment"' not in raw
                and b"Stop hook feedback" not in raw
                and b"stop_hook_summary" not in raw
            ):
                continue
            try:
                r = json.loads(raw)
            except Exception:
                continue
            ts = r.get("timestamp") or ""
            if ts < SINCE:
                continue
            uid = (r.get("uuid") or "") + "#0"
            t = r.get("type")
            if t == "attachment":
                a = r.get("attachment") or {}
                at = a.get("type") or ""
                if not (at.startswith("hook_") or at == "session_context"):
                    continue
                rend = r.get("rendered")
                rchars = (
                    sum(len(x.get("content") or "") for x in rend)
                    if isinstance(rend, list)
                    else -1
                )
                hn, he = a.get("hookName"), a.get("hookEvent")
                cmd = a.get("command")
                if at == "hook_blocking_error":
                    be = a.get("blockingError") or {}
                    cmd = be.get("command") if isinstance(be, dict) else None
                    txt = (
                        be.get("blockingError", "") if isinstance(be, dict) else str(be)
                    )
                    elems = [txt]
                elif at == "hook_additional_context":
                    c = a.get("content")
                    elems = c if isinstance(c, list) else [c or ""]
                elif at in (
                    "hook_success",
                    "hook_non_blocking_error",
                    "hook_system_message",
                    "hook_stopped_continuation",
                    "hook_cancelled",
                ):
                    elems = [
                        a.get("content")
                        or a.get("stdout")
                        or a.get("stderr")
                        or a.get("message")
                        or ""
                    ]
                elif at == "session_context":
                    elems = [json.dumps({k: v for k, v in a.items() if k != "type"})]
                else:
                    elems = [
                        json.dumps({k: v for k, v in a.items() if k != "type"})[:2000]
                    ]
                for i, e in enumerate(elems):
                    e = e if isinstance(e, str) else json.dumps(e)
                    helem.append(
                        (
                            path,
                            uid,
                            ts,
                            at,
                            hn,
                            he,
                            norm_cmd(cmd),
                            i,
                            len(elems),
                            len(e),
                            persisted_prefix(e),
                            rchars,
                            1 if isinstance(rend, list) else 0,
                        )
                    )
            elif t == "user" and r.get("isMeta"):
                c = (r.get("message") or {}).get("content")
                s = (
                    c
                    if isinstance(c, str)
                    else (json.dumps(c) if c is not None else "")
                )
                if (
                    s.lstrip().startswith("Stop hook feedback")
                    or "Stop hook feedback:" in s[:60]
                ):
                    hmeta.append((path, uid, ts, len(s), s[:PFX]))
            elif t == "system" and r.get("subtype") == "stop_hook_summary":
                errs = r.get("hookErrors") or []
                adds = r.get("hookAdditionalContext") or []
                infos = r.get("hookInfos") or []
                hstop.append(
                    (
                        path,
                        r.get("uuid"),
                        ts,
                        len(errs),
                        sum(len(str(x)) for x in errs),
                        len(adds),
                        sum(len(str(x)) for x in adds),
                        1 if r.get("preventedContinuation") else 0,
                        r.get("hookCount") or len(infos),
                        json.dumps([str(x)[:PFX] for x in adds])[:2000],
                    )
                )
    return path, helem, hmeta, hstop


def main():
    src = sqlite3.connect(f"file:{EXTRACT}?mode=ro", uri=True)
    files = [r[0] for r in src.execute("SELECT file FROM ctx ORDER BY file_bytes DESC")]
    if len(sys.argv) > 1:
        files = files[: int(sys.argv[1])]
    tmp = OUT + ".tmp"
    if os.path.exists(tmp):
        os.remove(tmp)
    out = sqlite3.connect(tmp)
    out.executescript("""
    CREATE TABLE helem (file TEXT, uid TEXT, ts TEXT, att_type TEXT, hook_name TEXT, hook_event TEXT,
      command TEXT, elem_idx INT, n_elems INT, elem_chars INT, prefix TEXT, rendered_chars INT, has_rendered INT);
    CREATE TABLE hmeta (file TEXT, uid TEXT, ts TEXT, chars INT, prefix TEXT);
    CREATE TABLE hstop (file TEXT, uuid TEXT, ts TEXT, n_err INT, err_chars INT, n_add INT, add_chars INT,
      prevented INT, hook_count INT, add_prefixes TEXT);
    """)
    with Pool(4) as pool:
        for n, (path, he, hm, hs) in enumerate(
            pool.imap_unordered(scan, files, chunksize=8)
        ):
            out.executemany("INSERT INTO helem VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", he)
            out.executemany("INSERT INTO hmeta VALUES (?,?,?,?,?)", hm)
            out.executemany("INSERT INTO hstop VALUES (?,?,?,?,?,?,?,?,?,?)", hs)
    out.executescript("""
    CREATE INDEX helem_fu ON helem(file, uid);
    CREATE INDEX hmeta_fu ON hmeta(file, uid);
    CREATE INDEX hstop_f ON hstop(file, ts);
    """)
    out.commit()
    out.close()
    os.replace(tmp, OUT)
    print("files", len(files), "->", OUT)


if __name__ == "__main__":
    main()
