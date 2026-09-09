#!/usr/bin/env python3
"""
measure-close-vs-idl.py — the CLOSES-vs-EVALUATIONS instrument (W2 B21, CRITIC C5).

WHY. Three explanations were offered for a ~14 % gap between session closes and
Stop-hook IDL rows, and none reproduced: A01's "rotation-boundary exact identity"
(469 = 469), LEAD's "104 of 127 hook-less closes ran on 2.1.220" (2.1.220 has 17
closes / 16 rows), A09's "agent-* sidechain files" (measure-closes.py already
excludes them). Each was computed with a DIFFERENT definition of "close" and none
had a denominator for "did the hook actually run". This file fixes both.

THE THREE POPULATIONS, kept separate on purpose:

  END_TURN   every main-chain assistant record with message.stop_reason ==
             "end_turn". The critic's C5 definition. A superset: an end_turn can
             be followed by a tool_result (a queued-message continuation) or by
             another assistant record, in which case the turn did not end and no
             Stop fired.
  CLOSE      END_TURN restricted to TURN-FINAL, byte-for-byte the definition in
             scripts/measure-closes.py (message.id collapse; no tool_use block;
             the next assistant/user event is neither an assistant record nor a
             tool_result). --crosscheck asserts equality against that module.
  STOP       a `type:"system", subtype:"stop_hook_summary"` record. This is the
             harness's own receipt that the Stop chain RAN, and it names every
             hook in `hookInfos`. It is the honest denominator for "should this
             hook have written a row", and nothing before this measurement used it.

  WRITE-FAILED  a `hook_cancelled` attachment with hookEvent == "Stop" for that
             hook: the hook ran and was killed at its timeout, so its row never
             landed.

  unexplained(hook) = STOPS_naming_hook − IDL_rows(hook) − cancelled(hook)

CORPUS. The four per-account transcript roots, project dirs one level deep, i.e.
<root>/<project>/*.jsonl. Subagent transcripts live at
<root>/<project>/<sid>/subagents/agent-*.jsonl (depth 4) and are therefore
structurally outside the glob — --count-excluded proves it by counting them and
their end_turns, which is the fail direction this measurement had to avoid.

IDL. Read line by line with json.loads, NEVER `jq -s`: one 4 KB autonomy-sweep
record aborts a jq slurp mid-archive and the census then reads short and clean
(B17). Parse failures are counted and reported as their own stratum.

USAGE
  python3 scripts/measure-close-vs-idl.py --from 2026-09-08T08:22:00Z --to 2026-09-08T22:22:00Z
  python3 scripts/measure-close-vs-idl.py --days 3 --count-excluded --json /tmp/b21.json
  python3 scripts/measure-close-vs-idl.py --selftest
"""

import argparse
import calendar
import glob
import gzip
import json
import os
import re
import sys
import time
from collections import Counter, defaultdict

ROOTS = [
    "~/.claude/projects",
    "~/.claude-secondary/projects",
    "~/.claude-tertiary/projects",
    "~/.claude-quaternary/projects",
]
ROOTS_EXCLUDED_AS_ALIAS = ["~/.claude-next/projects"]

# The six Stop hooks B21 names. Keyed by the basename that appears both in the
# IDL `.hook` field and in a stop_hook_summary hookInfos command.
HOOKS = [
    "anti-deference-nudge",
    "completion-assert",
    "session-continue",
    "operator-readout",
    "goal-inert-watch",
    "dispatch-assert",
]
HOOK_SCRIPT = {h: h + ".sh" for h in HOOKS}

IDL_DIR = os.path.expanduser("~/.claude/autonomy")
IDL_LIVE = os.path.join(IDL_DIR, "idl.jsonl")

STATS = Counter()


# ── time ────────────────────────────────────────────────────────────────────
RE_TS = re.compile(r"^(\d{4})-(\d\d)-(\d\d)[T ](\d\d):(\d\d):(\d\d)")


def parse_ts(s):
    """ISO-8601 Z (with or without fractional seconds) → epoch seconds, or None."""
    if not s:
        return None
    m = RE_TS.match(s)
    if not m:
        return None
    return calendar.timegm(tuple(int(x) for x in m.groups()) + (0, 0, 0))


def fmt(ep):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(ep))


# ── corpus ──────────────────────────────────────────────────────────────────
def iter_transcripts(t0, verbose=True):
    """<root>/<project>/*.jsonl with mtime >= t0. Per-root counts always printed."""
    seen, per_root, files = set(), [], []
    for r in ROOTS:
        rp = os.path.realpath(os.path.expanduser(r))
        if rp in seen:
            per_root.append((r, 0, 0, "ALIAS of an earlier root — skipped"))
            continue
        seen.add(rp)
        if not os.path.isdir(rp):
            per_root.append((r, 0, 0, "MISSING"))
            continue
        found = []
        for d in os.listdir(rp):
            p = os.path.join(rp, d)
            if os.path.isdir(p):
                found += glob.glob(os.path.join(p, "*.jsonl"))
        inwin = [f for f in found if os.path.getmtime(f) >= t0]
        per_root.append((r, len(found), len(inwin), ""))
        files += inwin
    for r in ROOTS_EXCLUDED_AS_ALIAS:
        rp = os.path.realpath(os.path.expanduser(r))
        per_root.append((r, 0, 0, "symlink -> %s (excluded)" % rp))
    if verbose:
        print("CORPUS — main-chain transcripts, per root")
        for r, tot, inw, note in per_root:
            print("  %-32s total %5d   in-window %5d  %s" % (r, tot, inw, note))
        print("  %-32s total %5d   in-window %5d" % (
            "ALL FOUR ROOTS", sum(x[1] for x in per_root), sum(x[2] for x in per_root)))
    return files, per_root


def count_excluded_subagents(t0):
    """The fail direction, measured: agent-* files and their end_turns."""
    nfiles = nend = 0
    for r in ROOTS:
        rp = os.path.realpath(os.path.expanduser(r))
        if not os.path.isdir(rp):
            continue
        for path in glob.glob(os.path.join(rp, "*", "*", "subagents", "agent-*.jsonl")):
            if os.path.getmtime(path) < t0:
                continue
            nfiles += 1
            for line in open(path, errors="replace"):
                if '"end_turn"' not in line:
                    continue
                try:
                    r2 = json.loads(line)
                except Exception:
                    continue
                if r2.get("type") == "assistant" and \
                        (r2.get("message") or {}).get("stop_reason") == "end_turn":
                    nend += 1
    return nfiles, nend


# ── transcript walk ─────────────────────────────────────────────────────────
def assistant_text(rec):
    m = rec.get("message") or {}
    c = m.get("content")
    if isinstance(c, str):
        return c, False
    if not isinstance(c, list):
        return "", False
    txt, has_tool = [], False
    for b in c:
        if not isinstance(b, dict):
            continue
        if b.get("type") == "text":
            txt.append(b.get("text") or "")
        elif b.get("type") == "tool_use":
            has_tool = True
    return "\n".join(txt), has_tool


def is_tool_result(rec):
    c = (rec.get("message") or {}).get("content")
    if not isinstance(c, list):
        return False
    return any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c)


def walk(path, t0, t1):
    """
    → dict per session id found in this file:
        closes, end_turns, stops, hook_ran[h], cancelled[h], versions
    All record-level filters (main chain, window) applied here.
    """
    recs, stops, cancels, versions = [], [], [], Counter()
    sids = Counter()
    for line in open(path, errors="replace"):
        line = line.strip()
        if not line:
            continue
        try:
            r = json.loads(line)
        except Exception:
            STATS["transcript_malformed_lines"] += 1
            continue
        if r.get("isSidechain") is True:
            STATS["sidechain_records_skipped"] += 1
            continue
        t = r.get("type")
        if t in ("assistant", "user"):
            recs.append(r)
        elif t == "system" and r.get("subtype") == "stop_hook_summary":
            ts = parse_ts(r.get("timestamp"))
            if ts is None or not (t0 <= ts < t1):
                continue
            stops.append(r)
            sids[r.get("sessionId") or r.get("session_id") or "?"] += 1
            if r.get("version"):
                versions[r["version"]] += 1
        elif t == "attachment":
            a = r.get("attachment") or {}
            if a.get("type") != "hook_cancelled" or a.get("hookEvent") != "Stop":
                continue
            ts = parse_ts(r.get("timestamp"))
            if ts is None or not (t0 <= ts < t1):
                continue
            cancels.append(r)

    # message.id collapse — one API response is written per content block.
    seq, i = [], 0
    while i < len(recs):
        r = recs[i]
        if r.get("type") != "assistant":
            seq.append(("user", None, is_tool_result(r), r))
            i += 1
            continue
        mid = (r.get("message") or {}).get("id")
        j = i + 1
        if mid is not None:
            while (j < len(recs) and recs[j].get("type") == "assistant"
                   and (recs[j].get("message") or {}).get("id") == mid):
                j += 1
        texts, tool = [], False
        for k in range(i, j):
            tx, hs = assistant_text(recs[k])
            if tx:
                texts.append(tx)
            tool = tool or hs
        seq.append(("assistant", "\n".join(texts), tool, recs[j - 1]))
        i = j

    per_sid = defaultdict(lambda: {
        "closes": 0, "end_turns": 0, "stops": 0,
        "hook_ran": Counter(), "cancelled": Counter(), "versions": Counter(),
        "not_turn_final": 0,
    })

    def sid_of(raw):
        return raw.get("sessionId") or raw.get("session_id") or "?"

    for k, (kind, text, tool, raw) in enumerate(seq):
        if kind != "assistant":
            continue
        if (raw.get("message") or {}).get("stop_reason") != "end_turn":
            continue
        ts = parse_ts(raw.get("timestamp"))
        if ts is None or not (t0 <= ts < t1):
            continue
        s = per_sid[sid_of(raw)]
        s["end_turns"] += 1
        if raw.get("version"):
            s["versions"][raw["version"]] += 1
        # the measure-closes.py turn-final test
        if tool or not text or not text.strip():
            s["not_turn_final"] += 1
            continue
        nxt = seq[k + 1] if k + 1 < len(seq) else None
        if nxt is not None and (nxt[0] == "assistant" or nxt[2] is True):
            s["not_turn_final"] += 1
            continue
        s["closes"] += 1

    for r in stops:
        s = per_sid[r.get("sessionId") or r.get("session_id") or "?"]
        s["stops"] += 1
        if r.get("version"):
            s["versions"][r["version"]] += 1
        for hi in r.get("hookInfos") or []:
            cmd = (hi.get("command") or "").split()
            base = os.path.basename(cmd[0]) if cmd else ""
            for h in HOOKS:
                if base == HOOK_SCRIPT[h]:
                    s["hook_ran"][h] += 1

    for r in cancels:
        a = r.get("attachment") or {}
        cmd = (a.get("command") or "").split()
        base = os.path.basename(cmd[0]) if cmd else ""
        s = per_sid[r.get("sessionId") or r.get("session_id") or "?"]
        if r.get("version"):
            s["versions"][r["version"]] += 1
        for h in HOOKS:
            if base == HOOK_SCRIPT[h]:
                s["cancelled"][h] += 1
    return per_sid


# ── IDL ─────────────────────────────────────────────────────────────────────
def idl_paths_for(t0, t1, verbose=True):
    """
    Live file plus every rotated archive whose window can overlap [t0,t1).
    An archive named ...<ROT>.gz holds records written BEFORE ROT and after the
    previous rotation, so it is needed iff ROT > t0.
    """
    out = []
    arcs = sorted(glob.glob(IDL_LIVE + ".2*.gz"))
    for a in arcs:
        m = re.search(r"\.(\d{8}T\d{6}Z)\.gz$", a)
        if not m:
            continue
        rot = calendar.timegm(time.strptime(m.group(1), "%Y%m%dT%H%M%SZ"))
        if rot > t0:
            out.append((a, rot))
    out.sort(key=lambda x: x[1])
    paths = [a for a, _ in out] + [IDL_LIVE]
    if verbose:
        print("IDL SOURCES (jq-tolerant, line by line)")
        for p in paths:
            print("  %s  (%.1f MB)" % (p, os.path.getsize(p) / 1e6))
    return paths


# A row whose reason names a COMMAND-LINE invocation is not a Stop evaluation:
# `session-continue.sh set/clear` is run by the agent from a Bash tool call, so its
# row has no Stop to pair with and would otherwise mask a real shortfall.
RE_CLI_REASON = re.compile(r"^cli-")


def read_idl(paths, t0, t1, verbose=True):
    """→ per_sid_hook Counter[(sid,hook)], CLI-path subset, plus parse-failure strata."""
    rows = Counter()
    cli = Counter()
    hook_total = Counter()
    for p in paths:
        op = gzip.open if p.endswith(".gz") else open
        nbad = nline = 0
        with op(p, "rt", errors="replace") as fh:
            for line in fh:
                nline += 1
                line = line.strip()
                if not line:
                    continue
                try:
                    r = json.loads(line)
                except Exception:
                    nbad += 1
                    STATS["idl_parse_failures"] += 1
                    STATS["idl_parse_failure_bytes"] += len(line)
                    continue
                if not isinstance(r, dict):
                    nbad += 1
                    STATS["idl_parse_failures"] += 1
                    continue
                h = r.get("hook")
                if h not in HOOKS:
                    continue
                ts = parse_ts(r.get("ts"))
                if ts is None or not (t0 <= ts < t1):
                    continue
                key = (r.get("sid") or "?", h)
                rows[key] += 1
                hook_total[h] += 1
                if RE_CLI_REASON.match(str(r.get("reason") or "")):
                    cli[key] += 1
                    STATS["idl_cli_rows"] += 1
        STATS["idl_lines_read"] += nline
        if verbose:
            print("  read %-70s lines=%-9d parse-fail=%d" % (os.path.basename(p), nline, nbad))
    return rows, cli, hook_total


# ── report ──────────────────────────────────────────────────────────────────
def run(t0, t1, count_excluded=False, jsonout=None, crosscheck=False, verbose=True):
    print("WINDOW  %s .. %s   (%.1f h)" % (fmt(t0), fmt(t1), (t1 - t0) / 3600.0))
    print()
    files, per_root = iter_transcripts(t0, verbose)
    sessions = defaultdict(lambda: {
        "closes": 0, "end_turns": 0, "stops": 0, "not_turn_final": 0,
        "hook_ran": Counter(), "cancelled": Counter(), "versions": Counter(),
    })
    for f in files:
        for sid, d in walk(f, t0, t1).items():
            s = sessions[sid]
            for k in ("closes", "end_turns", "stops", "not_turn_final"):
                s[k] += d[k]
            s["hook_ran"] += d["hook_ran"]
            s["cancelled"] += d["cancelled"]
            s["versions"] += d["versions"]
    # drop sessions with no in-window activity at all
    sessions = {k: v for k, v in sessions.items()
                if v["end_turns"] or v["stops"] or v["cancelled"]}
    print()
    idl_paths = idl_paths_for(t0, t1, verbose)
    idl_rows, idl_cli, idl_hook_total = read_idl(idl_paths, t0, t1, verbose)
    print()

    def ver(s):
        return s["versions"].most_common(1)[0][0] if s["versions"] else "unknown"

    mixed = sum(1 for s in sessions.values() if len(s["versions"]) > 1)
    by_ver = defaultdict(lambda: {
        "sessions": 0, "closes": 0, "end_turns": 0, "stops": 0, "not_turn_final": 0,
        "h": defaultdict(Counter),
    })
    for sid, s_ in sessions.items():
        v = by_ver[ver(s_)]
        v["sessions"] += 1
        for k in ("closes", "end_turns", "stops", "not_turn_final"):
            v[k] += s_[k]
        # A close with no stop_hook_summary receipt is a Stop occasion we cannot
        # observe from the transcript side. It is NOT evidence the chain did not
        # run (some sessions emit no receipts at all yet still write IDL rows), so
        # it is carried as its own stratum, never silently as "explained".
        no_receipt = max(0, s_["closes"] - s_["stops"])
        for h in HOOKS:
            rows = idl_rows.get((sid, h), 0)
            cli = idl_cli.get((sid, h), 0)
            stop_rows = rows - cli
            canc = s_["cancelled"][h]
            short = max(0, s_["closes"] - stop_rows)
            d = v["h"][h]
            d["rows"] += rows
            d["cli"] += cli
            d["stop_rows"] += stop_rows
            d["cancelled"] += canc
            d["excess"] += max(0, stop_rows - s_["closes"])
            d["short"] += short
            d["short_writefail"] += min(short, canc)
            rem = short - min(short, canc)
            d["short_noreceipt"] += min(rem, no_receipt)
            d["unexplained"] += rem - min(rem, no_receipt)

    orphan_rows = sum(n for (sid, _), n in idl_rows.items() if sid not in sessions)

    print("=" * 104)
    print("PER BINARY VERSION, PER HOOK — session-wise (a session's shortfall never nets against")
    print("another's excess). shortfall = max(0, closes - Stop-path rows) summed over sessions.")
    print("=" * 104)
    results = {}
    for vname in sorted(by_ver, key=lambda x: -by_ver[x]["closes"]):
        d = by_ver[vname]
        print("\n%s   sessions=%d  END_TURN=%d  CLOSE(turn-final)=%d  STOP-receipts=%d"
              % (vname, d["sessions"], d["end_turns"], d["closes"], d["stops"]))
        print("  %-22s %7s %7s %6s %8s %9s %9s %9s %8s %8s" % (
            "hook", "closes", "rows", "cli", "shortfall", "write-fail",
            "no-receipt", "UNEXPL", "unexpl%", "excess"))
        results[vname] = {"sessions": d["sessions"], "closes": d["closes"],
                          "end_turns": d["end_turns"], "stop_receipts": d["stops"],
                          "not_turn_final": d["not_turn_final"], "hooks": {}}
        for h in HOOKS:
            x = d["h"][h]
            C = d["closes"]
            pct = (100.0 * x["unexplained"] / C) if C else 0.0
            print("  %-22s %7d %7d %6d %8d %9d %9d %9d %7.1f%% %8d" % (
                h, C, x["rows"], x["cli"], x["short"], x["short_writefail"],
                x["short_noreceipt"], x["unexplained"], pct, x["excess"]))
            results[vname]["hooks"][h] = {
                "closes": C, "rows": x["rows"], "cli_rows": x["cli"],
                "stop_path_rows": x["stop_rows"], "shortfall": x["short"],
                "write_failed": x["short_writefail"],
                "no_stop_receipt": x["short_noreceipt"],
                "unexplained": x["unexplained"],
                "unexplained_pct": round(pct, 2), "excess_rows": x["excess"],
                "hook_cancelled_total": x["cancelled"]}
    print()
    print("STRATA / DENOMINATOR")
    print("  sessions in window ................ %d   (mixed-version: %d)" % (len(sessions), mixed))
    print("  END_TURN not turn-final ........... %d   (not a Stop occasion by construction)"
          % sum(s["not_turn_final"] for s in sessions.values()))
    print("  IDL rows whose sid has no in-window transcript ... %d" % orphan_rows)
    print("  IDL parse failures ................ %d line(s), %d bytes"
          % (STATS["idl_parse_failures"], STATS["idl_parse_failure_bytes"]))
    print("  IDL lines read .................... %d" % STATS["idl_lines_read"])
    print("  IDL rows from a CLI (non-Stop) path  %d   (session-continue set/clear)"
          % STATS["idl_cli_rows"])
    print("  transcript malformed lines ........ %d" % STATS["transcript_malformed_lines"])
    print("  sidechain records skipped ......... %d" % STATS["sidechain_records_skipped"])
    if count_excluded:
        nf, ne = count_excluded_subagents(t0)
        print("  EXCLUDED subagent transcripts ..... %d file(s), %d end_turn record(s)" % (nf, ne))
        results["_excluded_subagents"] = {"files": nf, "end_turns": ne}
    if crosscheck:
        n = crosscheck_measure_closes(t0, t1)
        print("  CROSSCHECK vs measure-closes.py ... %s" % n)
        results["_crosscheck"] = n
    if jsonout:
        results["_window"] = [fmt(t0), fmt(t1)]
        results["_stats"] = dict(STATS)
        with open(jsonout, "w") as fh:
            json.dump(results, fh, indent=1)
        print("  json -> %s" % jsonout)
    return results


def crosscheck_measure_closes(t0, t1):
    """Independent close count from scripts/measure-closes.py's own extract_closes."""
    import importlib.util
    p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "measure-closes.py")
    spec = importlib.util.spec_from_file_location("mc", p)
    mc = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mc)
    files, _ = mc.iter_transcripts((time.time() - t0) / 86400.0, verbose=False)
    n = 0
    for f, root in files:
        for c in mc.extract_closes(f, root):
            ts = parse_ts(c.get("ts"))
            if ts is not None and t0 <= ts < t1:
                n += 1
    return n


# ── selftest ────────────────────────────────────────────────────────────────
def selftest():
    import tempfile
    ok = True

    def chk(name, got, want):
        nonlocal ok
        good = got == want
        ok = ok and good
        print("  %-52s %s  got=%r want=%r" % (name, "PASS" if good else "FAIL", got, want))

    chk("parse_ts plain", parse_ts("2026-09-08T08:22:00Z"),
        calendar.timegm((2026, 9, 8, 8, 22, 0, 0, 0, 0)))
    chk("parse_ts fractional", parse_ts("2026-09-08T08:22:00.913Z"),
        calendar.timegm((2026, 9, 8, 8, 22, 0, 0, 0, 0)))
    chk("parse_ts junk", parse_ts("not-a-time"), None)

    t0 = parse_ts("2026-09-08T00:00:00Z")
    t1 = parse_ts("2026-09-09T00:00:00Z")
    d = tempfile.mkdtemp()
    p = os.path.join(d, "s.jsonl")
    def a(uuid, sid, ts, stop, blocks, mid=None, sidechain=False):
        return json.dumps({"type": "assistant", "uuid": uuid, "sessionId": sid,
                           "timestamp": ts, "version": "2.1.260", "isSidechain": sidechain,
                           "message": {"id": mid or uuid, "stop_reason": stop,
                                       "content": blocks}})
    TXT = [{"type": "text", "text": "done."}]
    TOOL = [{"type": "text", "text": "x"}, {"type": "tool_use", "id": "t", "name": "Bash", "input": {}}]
    def u(ts, tr=False):
        c = ([{"type": "tool_result", "tool_use_id": "t"}] if tr
             else [{"type": "text", "text": "next please"}])
        return json.dumps({"type": "user", "sessionId": "S", "timestamp": ts,
                           "isSidechain": False, "message": {"content": c}})
    lines = [
        a("u1", "S", "2026-09-08T01:00:00Z", "end_turn", TXT),          # close #1
        u("2026-09-08T01:30:00Z"),
        a("u2", "S", "2026-09-08T02:00:00Z", "end_turn", TXT),          # end_turn then tool_result
        u("2026-09-08T02:00:05Z", tr=True),                             # → NOT turn-final
        a("u3", "S", "2026-09-08T03:00:00Z", "tool_use", TOOL),         # not an end_turn at all
        u("2026-09-08T03:00:05Z", tr=True),
        a("u4", "S", "2026-09-08T04:00:00Z", "end_turn", TXT),          # close #2 (EOF-terminated)
        a("u5", "S", "2026-09-08T05:00:00Z", "end_turn", TXT, sidechain=True),   # sidechain → gone
        json.dumps({"type": "system", "subtype": "stop_hook_summary", "sessionId": "S",
                    "timestamp": "2026-09-08T04:00:01Z", "version": "2.1.260",
                    "isSidechain": False,
                    "hookInfos": [{"command": "~/.claude/hooks/anti-deference-nudge.sh",
                                   "durationMs": 5},
                                  {"command": "~/.claude/hooks/session-continue.sh"}]}),
        json.dumps({"type": "attachment", "sessionId": "S", "isSidechain": False,
                    "timestamp": "2026-09-08T04:00:02Z", "version": "2.1.260",
                    "attachment": {"type": "hook_cancelled", "hookEvent": "Stop",
                                   "command": "~/.claude/hooks/anti-deference-nudge.sh",
                                   "timedOut": True}}),
        "{ this is not json",
    ]
    open(p, "w").write("\n".join(lines) + "\n")
    STATS.clear()
    r = walk(p, t0, t1)["S"]
    chk("end_turns in window (sidechain excluded)", r["end_turns"], 3)
    chk("closes = turn-final only", r["closes"], 2)
    chk("not-turn-final stratum", r["not_turn_final"], 1)
    chk("stop_hook_summary counted", r["stops"], 1)
    chk("hook_ran anti-deference", r["hook_ran"]["anti-deference-nudge"], 1)
    chk("hook_ran session-continue (no durationMs still ran)",
        r["hook_ran"]["session-continue"], 1)
    chk("write-failed via hook_cancelled", r["cancelled"]["anti-deference-nudge"], 1)
    chk("malformed transcript line counted, not fatal", STATS["transcript_malformed_lines"], 1)
    chk("sidechain skipped", STATS["sidechain_records_skipped"], 1)

    # IDL reader: a giant record must not abort the walk (the B17 failure mode)
    ip = os.path.join(d, "idl.jsonl")
    with open(ip, "w") as fh:
        fh.write(json.dumps({"ts": "2026-09-08T04:00:00Z", "hook": "anti-deference-nudge",
                             "sid": "S", "disposition": "abstained", "reason": "no-tell"}) + "\n")
        fh.write("{" + "x" * 4096 + "\n")                        # the 4 KB aborting record
        fh.write(json.dumps({"ts": "2026-09-08T04:00:01Z", "hook": "completion-assert",
                             "sid": "S", "disposition": "fired"}) + "\n")
        fh.write(json.dumps({"ts": "2026-09-07T04:00:01Z", "hook": "completion-assert",
                             "sid": "S", "disposition": "fired"}) + "\n")   # out of window
        fh.write(json.dumps({"ts": "2026-09-08T04:00:02Z", "hook": "waiting-recycle",
                             "sid": "S"}) + "\n")                            # not one of the six
    STATS.clear()
    rows, cli, tot = read_idl([ip], t0, t1, verbose=False)
    chk("IDL rows after the 4 KB record (reader did not abort)",
        rows[("S", "completion-assert")], 1)
    chk("IDL row before it", rows[("S", "anti-deference-nudge")], 1)
    chk("IDL out-of-window excluded", tot["completion-assert"], 1)
    chk("IDL non-target hook ignored", tot.get("waiting-recycle", 0), 0)
    chk("IDL parse failure counted as its own stratum", STATS["idl_parse_failures"], 1)
    print("SELFTEST %s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 2


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--from", dest="t_from", help="window start, ISO Z")
    ap.add_argument("--to", dest="t_to", help="window end, ISO Z (default: now)")
    ap.add_argument("--days", type=float, help="window = last N days ending --to/now")
    ap.add_argument("--count-excluded", action="store_true",
                    help="count the subagent transcripts this walk excludes (the fail direction)")
    ap.add_argument("--crosscheck", action="store_true",
                    help="re-count closes with scripts/measure-closes.py's own extract_closes")
    ap.add_argument("--json", dest="jsonout")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    t1 = parse_ts(a.t_to) if a.t_to else int(time.time())
    if a.t_from:
        t0 = parse_ts(a.t_from)
    elif a.days:
        t0 = int(t1 - a.days * 86400)
    else:
        ap.error("need --from or --days")
    run(t0, t1, a.count_excluded, a.jsonout, a.crosscheck)
    return 0


if __name__ == "__main__":
    sys.exit(main())
