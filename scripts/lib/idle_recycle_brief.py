#!/usr/bin/env python3
"""idle_recycle_brief.py — the brief a D1 idle recycle hands its successor (docs/plans/USAGE_LEVERS.md
§ W7+ §2 D1, guards G3 and G5; wave S9). The d1_successor eval (tools/lever-evals/d1_successor/)
regenerates exactly this text for every case, so the brief production sends is the brief the eval
scored; wave S12 wires it into handoff-fire.sh. Nothing here registers a hook, wakes, recycles or
reads a flag.

WHAT THE BRIEF CARRIES (decisions-2026-10-24/REPORT.md decision 1):
  G3  the predecessor's final message, verbatim; the questions it left open and the steps it handed
      over; what was in flight (busy jobs) and the watchers and Monitors to re-arm; its transcript
      path. If a short reply could match more than one item, the successor asks before acting.
  G5  lazy orientation: the successor answers the brief in one line and reads nothing until the
      next message arrives.
  chain the D1-CHAIN marker (lineage root, predecessor sid, idle start, context at idle), which
      lever_chain.py and the guard's recycle-row check read back.

THE POINT. build() takes a dict with IRS v2 field names (hooks/boundary-handoff.sh: sid, idle_start,
ctx_at_idle, gap_s, lineage, pending_question, pq_why, busy_tool, busy_kinds, prompt_sha,
prompt_head). In the eval the point is the IRS row of the gap the case ends; in production (S12) the
due-time state carries the same names. prompt_sha / prompt_head describe the prompt that ENDED the
gap, so they go into the returned meta only, for joining a successor to its case: the brief text
never carries them (the future must not enter the successor's context).

build() is pure: records come in (session_jobs.records() order), text and meta come out.

CLI:
  idle_recycle_brief.py --transcript PATH (--point JSON | --irs-log FILE --sid SID [--idle-start T])
                        [--params JSON] [--json]
Prints the brief, or with --json {"text", "meta"}. Exit 0 ok · 2 usage or no matching IRS row.
Stdlib only, Python 3.9-safe.
"""

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, os.path.normpath(os.path.join(HERE, "..", "..", "hooks", "lib")))
import session_jobs as sj  # noqa: E402

V = 1
# the tunables a d1_successor round may change (one per round); anything else is refused
DEFAULTS = {
    "final_msg_chars": 6000,  # the final message is verbatim up to this, then cut from the FRONT
    "ask_rule": "multi",  # multi: ask when a short reply matches >1 item · always: ask on any short reply
    "lazy": True,  # G5: answer the brief in one line, read nothing until the next message
    "max_items": 8,  # per list (questions, steps, watchers)
}
ASK_RULES = ("multi", "always")

RUN_THIS = re.compile(r"▶\s*Run this:\s*\n+\s*`([^`\n]+)`")
FILED_ID = re.compile(r"`([0-9a-f]{12})`(?:\s*\(([^)\n]{1,160})\))?")
STEP_LINE = re.compile(
    r"^\s*(?:👤|◆|S6|Your side|Yours|WAITING)\b[:\s-]*(.+)$", re.I | re.M
)
SENT = re.compile(r"[^.!?\n]*\?")


def _iso(t):
    return datetime.fromtimestamp(float(t), timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def validate_params(p):
    """→ DEFAULTS overlaid with p; ValueError naming the key and why on anything else."""
    out = dict(DEFAULTS)
    for k, v in (p or {}).items():
        if k not in DEFAULTS:
            raise ValueError(
                "brief param %r is not tunable (tunable: %s)"
                % (k, ", ".join(sorted(DEFAULTS)))
            )
        if k == "ask_rule" and v not in ASK_RULES:
            raise ValueError(
                "brief param ask_rule=%r: must be one of %s" % (v, ", ".join(ASK_RULES))
            )
        if k == "lazy" and not isinstance(v, bool):
            raise ValueError("brief param lazy=%r: must be true or false" % (v,))
        if k in ("final_msg_chars", "max_items") and (
            not isinstance(v, int) or isinstance(v, bool) or v < 1
        ):
            raise ValueError("brief param %s=%r: must be a positive integer" % (k, v))
        out[k] = v
    return out


def _text(c):
    if isinstance(c, str):
        return c
    return "\n".join(
        b.get("text", "")
        for b in c or []
        if isinstance(b, dict) and b.get("type") == "text"
    )


def final_message(recs, before):
    """The last assistant text at or before `before` (epoch s), and any AskUserQuestion questions in
    that same final turn."""
    text, asks = "", []
    for r in recs:
        t = sj._ts(r)
        if r.get("type") != "assistant" or t is None or t >= before + 1:
            continue
        c = sj._content(r)
        if not isinstance(c, list):
            continue
        tx = _text(c).strip()
        if tx:
            text, asks = tx, []
        for b in c:
            if (
                isinstance(b, dict)
                and b.get("type") == "tool_use"
                and b.get("name") == "AskUserQuestion"
            ):
                for q in (b.get("input") or {}).get("questions") or []:
                    if isinstance(q, dict) and q.get("question"):
                        asks.append(str(q["question"]))
    return text, asks


def open_questions(text, asks):
    qs = [q.strip() for q in asks]
    for m in SENT.finditer(text):
        s = m.group(0).strip(" *_`>-")
        if len(s) >= 8 and "://" not in s and s not in qs:
            qs.append(s)
    return qs


def handed_steps(text):
    steps = ["run: `%s`" % m.group(1).strip() for m in RUN_THIS.finditer(text)]
    for m in FILED_ID.finditer(text):
        s = "filed `%s`%s" % (
            m.group(1),
            (" (%s)" % m.group(2).strip()) if m.group(2) else "",
        )
        if s not in steps:
            steps.append(s)
    for m in STEP_LINE.finditer(text):
        s = m.group(1).strip()
        if s and s not in steps:
            steps.append(s)
    return steps


def watchers(recs, t):
    """Watchers (a background cc-await-ping Bash, a Monitor) launched at or before t whose completion
    notice has not arrived by t: what the successor must re-arm. A foreground call that only mentions
    cc-await-ping (`--stand-down`, a grep) is not a watcher. → [description]"""
    launched, ended = {}, set()
    for r in recs:
        rt = sj._ts(r)
        if rt is None or rt > t:
            continue
        c = sj._content(r)
        if r.get("type") in ("user", "queue-operation"):
            s = (
                c
                if isinstance(c, str)
                else json.dumps(c)
                if c is not None
                else str(r.get("content") or "")
            )
            if "<task-notification>" in s:
                ended.update(sj.TUID.findall(s))
        if r.get("type") != "assistant" or not isinstance(c, list):
            continue
        for b in c:
            if (
                not isinstance(b, dict)
                or b.get("type") != "tool_use"
                or not b.get("id")
            ):
                continue
            inp = b.get("input") if isinstance(b.get("input"), dict) else {}
            if b.get("name") == "Monitor":
                launched[b["id"]] = (
                    "Monitor: %s"
                    % str(inp.get("description") or inp.get("command") or "")[:160]
                )
            elif (
                b.get("name") == "Bash"
                and inp.get("run_in_background")
                and "cc-await-ping" in str(inp.get("command", ""))
                and "--stand-down" not in str(inp.get("command", ""))
            ):
                launched[b["id"]] = "watcher: `%s`" % str(inp.get("command"))[:160]
    return [d for k, d in launched.items() if k not in ended]


def _cap(items, n):
    return items[:n] + (
        ["(%d more in the transcript)" % (len(items) - n)] if len(items) > n else []
    )


def build(point, recs, params=None, transcript=None):
    """→ (text, meta). point: IRS v2 field names (see the module doc). recs: the predecessor's
    main-thread records; only those at or before point['idle_start'] are read."""
    p = validate_params(params)
    t_idle = float(point["idle_start"])
    recs = [r for r in recs if (sj._ts(r) or 0) <= t_idle + 1]
    final, asks = final_message(recs, t_idle)
    qs = open_questions(final, asks)
    steps = handed_steps(final)
    st = sj.running_at(sj.jobs(recs), t_idle)
    wat = watchers(recs, t_idle)
    pred = point.get("sid") or "?"
    root = point.get("lineage") or pred
    ctx_k = int(float(point.get("ctx_at_idle") or 0)) // 1000
    gap_m = int(float(point.get("gap_s") or 0)) // 60
    if len(final) > p["final_msg_chars"]:
        final = (
            "[…first %d chars cut]\n" % (len(final) - p["final_msg_chars"])
            + final[-p["final_msg_chars"] :]
        )
    L = [
        "D1 IDLE RECYCLE — you continue session %s (lineage %s), recycled after it sat idle%s at %dk tokens."
        % (pred, root, (" %d min" % gap_m) if gap_m else "", ctx_k),
        "D1-CHAIN v%d lineage=%s pred=%s idle_start=%s ctx_k=%d"
        % (V, root, pred, _iso(t_idle), ctx_k),
        "",
    ]
    if p["lazy"]:
        L.append(
            "How to start (G5): read nothing and run nothing now. Answer this message with one line "
            '("Ready.") and wait. When the next message arrives, act on it from this brief; open the '
            "transcript below only if that message needs something the brief does not hold."
        )
    if p["ask_rule"] == "multi":
        L.append(
            'Ambiguity (G3): if a short reply ("yes", "cancel", "open it", "that one") could match '
            "more than one item below, ask which one in one line before acting. Never make a state "
            "change on a guess."
        )
    else:
        L.append(
            'Ambiguity (G3): if the next message is a short reply ("yes", "cancel", "open it", "that '
            'one"), name the item you take it to mean and ask for a yes before acting. Never make a state '
            "change on a guess."
        )
    L += [
        "",
        "## The predecessor's final message (verbatim)",
        final or "(no assistant text before the idle point)",
        "",
    ]
    if qs:
        L += ["## Questions it left open"] + [
            "- " + q for q in _cap(qs, p["max_items"])
        ]
    elif point.get("pending_question"):
        L += [
            "## Questions it left open",
            "- the final message leaves the operator a call (%s); see it above"
            % (point.get("pq_why") or "?"),
        ]
    else:
        L += ["## Questions it left open", "- none"]
    L += ["", "## Steps it handed over"] + (
        ["- " + s for s in _cap(steps, p["max_items"])] or ["- none"]
    )
    L += ["", "## In flight at the idle point"]
    L.append(
        "- busy: %s (oldest %ss)" % (", ".join(st["busy_kinds"]), st["busy_oldest_s"])
        if st["busy"]
        else "- nothing busy"
    )
    L += ["", "## Watchers and Monitors to re-arm"] + (
        ["- " + w for w in _cap(wat, p["max_items"])] or ["- none"]
    )
    L += [
        "",
        "## Transcript",
        "- %s (read only if needed)"
        % (transcript or point.get("transcript") or "(unknown)"),
    ]
    meta = dict(
        v=V,
        lineage=root,
        pred=pred,
        idle_start=t_idle,
        ctx_k=ctx_k,
        params=p,
        n_questions=len(qs),
        n_steps=len(steps),
        n_watchers=len(wat),
        busy=st["busy"],
        prompt_sha=point.get("prompt_sha"),
        prompt_head=point.get("prompt_head"),
    )
    return "\n".join(L) + "\n", meta


def irs_point(log, sid, idle_start=None):
    """The IRS v2 row (schema 2, v ok) for sid — the one with idle_start, else the latest."""
    best = None
    with open(log) as fh:
        for ln in fh:
            try:
                r = json.loads(ln)
            except ValueError:
                continue
            if r.get("sid") != sid or r.get("v") != "ok" or r.get("schema") != 2:
                continue
            if (
                idle_start is not None
                and abs(float(r.get("idle_start") or 0) - idle_start) > 1
            ):
                continue
            best = r
    return best


def main(argv):
    ap = argparse.ArgumentParser(
        prog="idle_recycle_brief.py", description=__doc__.split("\n")[0]
    )
    ap.add_argument("--transcript", required=True)
    ap.add_argument("--point")
    ap.add_argument("--irs-log")
    ap.add_argument("--sid")
    ap.add_argument("--idle-start", type=float)
    ap.add_argument("--params")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv)
    try:
        if a.point:
            point = json.loads(a.point)
        elif a.irs_log and a.sid:
            point = irs_point(a.irs_log, a.sid, a.idle_start)
            if point is None:
                sys.stderr.write(
                    "idle_recycle_brief: no IRS v2 ok row for sid %s in %s\n"
                    % (a.sid, a.irs_log)
                )
                return 2
        else:
            sys.stderr.write(
                "idle_recycle_brief: give --point JSON or --irs-log FILE --sid SID\n"
            )
            return 2
        if "idle_start" not in point:
            sys.stderr.write("idle_recycle_brief: the point has no idle_start\n")
            return 2
        text, meta = build(
            point,
            sj.records(a.transcript, tail_bytes=8_000_000),
            json.loads(a.params) if a.params else None,
            a.transcript,
        )
    except ValueError as e:
        sys.stderr.write("idle_recycle_brief: %s\n" % e)
        return 2
    if a.json:
        print(json.dumps(dict(text=text, meta=meta), sort_keys=True))
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
