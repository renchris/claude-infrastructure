#!/usr/bin/env python3
"""measure-selfclose-rung.py — what rung was a session on when it retired itself?

WHY (exhaustive-drive W2-B1 / CRITIC C-R1 / SYNTHESIS §2B row B1): the proposal is to make
`handoff-fire.sh self-close` REFUSE on 📦 (unlanded) / ⛔ (open class-C packet) / REMAINDER≠0
instead of merely stamping the ledger. The cost of that rule is the legitimate retires it would
have refused, and the only honest way to price it is to read the rung each retiring session was
actually on AT THE MOMENT IT RETIRED.

THE INSTRUMENT, and why it is not `wrap-ledger.sh` run today. Running the ledger now in the
retired session's cwd answers a different question: `UNLANDED` is `origin/main..HEAD`, and over a
worktree whose HEAD has been frozen since the retire that count can only SHRINK as origin/main
advances — so a session that retired on 📦 reads ✅/🚀 today. The drift is one-directional toward
"would pass", and 41 of 54 cwds in the measured window no longer exist at all (worktree-gc). The
transcript is the frozen record: every Stop-hook close emits `RUNG=<glyph>\nREADOUT=…` (and often
the machine block) INTO the transcript, so the last such block before the self-close is the
session's own at-retire reading. Median staleness in the measured window: 56 s (p90 146 s).

THE PREDICATE IS READ FROM FIELDS, NEVER FROM THE RUNG. 🔧 is a compound — dirty ∨ gate-stale ∨
REMAINDER>0 ∨ FILED_MINE>0 ∨ DRAIN_SCOPE ∨ custody — so refusing on RUNG=🔧 refuses on terms the
rule never named. Measured, that distinction alone moves the answer across the 10 % decision
threshold (6.8 % on fields vs 11.4 % on the rung). `--rung-mode` reproduces the naive reading.

READ-ONLY over the four transcript roots. Writes nothing.
"""
from __future__ import annotations
import argparse, json, os, re, sys, tempfile

ROOTS = ["~/.claude", "~/.claude-secondary", "~/.claude-tertiary", "~/.claude-quaternary"]
# An INVOCATION, not a mention: a brief that merely quotes `handoff-fire.sh self-close` (every
# fired peer's brief does) must not be counted (memory: pgrep-f-matches-agent-briefs).
INVOKE = re.compile(r"(?:^|[;&|\n]\s*|\$\(\s*)[^\s;&|]*handoff-fire\.sh\s+self-close\b")
RUNG_BLOCK = re.compile(r"RUNG=(.)\s*\n\s*READOUT=", re.S)
REFUSE_RUNGS = {"📦", "⛔"}


def _texts(rec):
    out, msg = [], rec.get("message") or {}
    c = msg.get("content")
    if isinstance(c, str):
        out.append(c)
    elif isinstance(c, list):
        for x in c:
            if not isinstance(x, dict):
                continue
            if x.get("type") == "text":
                out.append(x.get("text", ""))
            elif x.get("type") == "tool_result":
                cc = x.get("content")
                if isinstance(cc, str):
                    out.append(cc)
                elif isinstance(cc, list):
                    out += [y.get("text", "") for y in cc if isinstance(y, dict)]
    v = rec.get("toolUseResult")
    if isinstance(v, str):
        out.append(v)
    elif isinstance(v, dict):
        # a nested JSON value re-escapes newlines; the RUNG block is a MULTI-LINE shape, so a
        # dumped dict must be un-escaped or the block can never match (it silently reads as
        # "no ledger", i.e. UNRESOLVABLE — a fail-quiet the selftest pins).
        out.append(json.dumps(v, ensure_ascii=False).replace("\\n", "\n"))
    return out


def scan_file(path):
    """-> dict for a session that RETIRED via self-close, else None."""
    inv, results, after, frozen = [], {}, [], None
    try:
        fh = open(path, "r", errors="replace")
    except OSError:
        return None
    with fh:
        for line in fh:
            if "self-close" not in line and "READOUT=" not in line:
                continue
            try:
                rec = json.loads(line)
            except Exception:
                continue  # a truncated/oversized record is skipped, never fatal
            ts, typ = rec.get("timestamp") or "", rec.get("type")
            msg = rec.get("message") or {}
            for c in msg.get("content") or []:
                if not isinstance(c, dict):
                    continue
                if typ == "assistant" and c.get("type") == "tool_use" and c.get("name") == "Bash":
                    if INVOKE.search((c.get("input") or {}).get("command", "")):
                        inv.append({"ts": ts, "cwd": rec.get("cwd"), "sid": rec.get("sessionId"),
                                    "id": c.get("id")})
                elif typ == "user" and c.get("type") == "tool_result":
                    results[c.get("tool_use_id")] = True
    if not inv:
        return None
    inv.sort(key=lambda i: i["ts"])
    last = inv[-1]
    # A SUCCESSFUL self-close kills the pane INSIDE the tool call, so no tool_result is ever
    # written and only teardown `queue-operation` records follow. A tool_result, or any
    # substantive record after it, means the pane was still alive: an attempt, not a retire.
    with open(path, "r", errors="replace") as fh:
        for line in fh:
            if '"timestamp"' not in line:
                continue
            try:
                rec = json.loads(line)
            except Exception:
                continue
            ts = rec.get("timestamp") or ""
            if ts > last["ts"]:
                after.append(rec.get("type"))
            elif ts and "READOUT=" in line:
                for t in _texts(rec):
                    for m in RUNG_BLOCK.finditer(t):
                        seg = t[m.start():m.start() + 4000]
                        f = {k: v for k, v in re.findall(r"(?m)^([A-Z_]+)=(.*)$", seg)}
                        frozen = {"ts": ts, "rung": m.group(1), "fields": f}
    if results.get(last["id"]) or [a for a in after if a != "queue-operation"]:
        return None
    return {"file": path, "sid": last["sid"], "cwd": last["cwd"], "ts": last["ts"], "frozen": frozen}


def verdict(row, rung_mode=False):
    """-> 'REFUSE' | 'PASS' | 'UNRESOLVABLE'."""
    fr = row.get("frozen")
    if not fr:
        return "UNRESOLVABLE"
    if rung_mode:
        return "REFUSE" if fr["rung"] in (REFUSE_RUNGS | {"🔧"}) else "PASS"
    f = fr["fields"]

    def n(k):
        try:
            return int(f.get(k, "0") or 0)
        except ValueError:
            return 0
    # 📦 ∨ ⛔ ∨ REMAINDER≠0 — the rule AS SPECIFIED. The rung supplies 📦/⛔ when the emitted
    # block carried only the readout line; REMAINDER has no rung of its own (it folds into 🔧),
    # so an absent field is read as 0 and this arm can only UNDER-count, never invent a refusal.
    if fr["rung"] in REFUSE_RUNGS:
        return "REFUSE"
    return "REFUSE" if (n("UNLANDED") or n("AHEAD") or n("CHERRY") or n("BLOCKED")
                        or n("REMAINDER")) else "PASS"


def collect(roots, limit):
    import subprocess
    dirs = [os.path.join(os.path.expanduser(r), "projects") for r in roots]
    dirs = [d for d in dirs if os.path.isdir(d)]
    cand = subprocess.run(["rg", "-l", "--no-messages", "-F", "self-close", "-g", "*.jsonl", *dirs],
                          capture_output=True, text=True).stdout.split()
    cand.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    rows = []
    for p in cand:
        r = scan_file(p)
        if r:
            rows.append(r)
        if limit and len(rows) >= limit * 3:  # mtime order ≈ retire order, with slack
            break
    rows.sort(key=lambda r: r["ts"], reverse=True)
    return rows[:limit] if limit else rows


def selftest():
    """Fixtures pin the two claims the number rests on: a RETIRE is a self-close with no
    tool_result, and the predicate reads FIELDS (so a 🔧 raised by FILED_MINE must PASS)."""
    def rec(**kw):
        return json.dumps(kw)
    cases = {
        # ⛔ at retire -> REFUSE
        "blocked": ([rec(type="user", timestamp="2026-01-01T00:00:00Z",
                         toolUseResult={"stdout": "RUNG=⛔\nREADOUT=⛔ need your call\nBLOCKED=1"}),
                     rec(type="assistant", timestamp="2026-01-01T00:01:00Z", cwd="/tmp/x",
                         sessionId="s1", message={"content": [{"type": "tool_use", "id": "t1",
                         "name": "Bash", "input": {"command": "$HOME/.claude/scripts/handoff-fire.sh self-close --terminal"}}]}),
                     rec(type="queue-operation", timestamp="2026-01-01T00:01:10Z")], "REFUSE"),
        # ✅ at retire -> PASS
        "clean": ([rec(type="user", timestamp="2026-01-01T00:00:00Z",
                       toolUseResult={"stdout": "RUNG=✅\nREADOUT=✅ done\nUNLANDED=0\nREMAINDER=0"}),
                   rec(type="assistant", timestamp="2026-01-01T00:01:00Z", cwd="/tmp/x",
                       sessionId="s2", message={"content": [{"type": "tool_use", "id": "t1",
                       "name": "Bash", "input": {"command": "handoff-fire.sh self-close --terminal"}}]})], "PASS"),
        # 🔧 raised by FILED_MINE, NOT by REMAINDER -> PASS on fields, REFUSE on the rung
        "wrench_filed": ([rec(type="user", timestamp="2026-01-01T00:00:00Z",
                              toolUseResult={"stdout": "RUNG=🔧\nREADOUT=🔧 loose\nDIRTY=0\nAHEAD=0\nREMAINDER=0\nFILED_MINE=1"}),
                          rec(type="assistant", timestamp="2026-01-01T00:01:00Z", cwd="/tmp/x",
                              sessionId="s3", message={"content": [{"type": "tool_use", "id": "t1",
                              "name": "Bash", "input": {"command": "handoff-fire.sh self-close --terminal"}}]})], "PASS"),
        # 📦 -> REFUSE
        "parked": ([rec(type="user", timestamp="2026-01-01T00:00:00Z",
                        toolUseResult={"stdout": "RUNG=📦\nREADOUT=📦 branch only\nUNLANDED=3"}),
                    rec(type="assistant", timestamp="2026-01-01T00:01:00Z", cwd="/tmp/x",
                        sessionId="s4", message={"content": [{"type": "tool_use", "id": "t1",
                        "name": "Bash", "input": {"command": "handoff-fire.sh self-close --terminal"}}]})], "REFUSE"),
        # no ledger block before the retire -> UNRESOLVABLE
        "noledger": ([rec(type="assistant", timestamp="2026-01-01T00:01:00Z", cwd="/tmp/x",
                          sessionId="s5", message={"content": [{"type": "tool_use", "id": "t1",
                          "name": "Bash", "input": {"command": "handoff-fire.sh self-close --terminal"}}]})], "UNRESOLVABLE"),
    }
    ok = True
    with tempfile.TemporaryDirectory() as d:
        for name, (lines, want) in cases.items():
            p = os.path.join(d, name + ".jsonl")
            open(p, "w").write("\n".join(lines) + "\n")
            row = scan_file(p)
            got = verdict(row) if row else "NOT-A-RETIRE"
            good = got == want
            ok &= good
            print(f"  {'ok  ' if good else 'FAIL'} {name}: want {want}, got {got}")
        # rung-mode control: the SAME fixture must flip, or the field/rung distinction is untested
        row = scan_file(os.path.join(d, "wrench_filed.jsonl"))
        got = verdict(row, rung_mode=True)
        good = got == "REFUSE"
        ok &= good
        print(f"  {'ok  ' if good else 'FAIL'} wrench_filed under --rung-mode: want REFUSE, got {got}")
        # a self-close that RETURNED (tool_result present) is an attempt, never a retire
        p = os.path.join(d, "refused.jsonl")
        open(p, "w").write("\n".join([
            json.dumps({"type": "assistant", "timestamp": "2026-01-01T00:01:00Z", "cwd": "/tmp/x",
                        "sessionId": "s6", "message": {"content": [{"type": "tool_use", "id": "t1",
                        "name": "Bash", "input": {"command": "handoff-fire.sh self-close --terminal"}}]}}),
            json.dumps({"type": "user", "timestamp": "2026-01-01T00:01:05Z",
                        "message": {"content": [{"type": "tool_result", "tool_use_id": "t1",
                        "content": "!! self-close needs $ITERM_SESSION_ID"}]}}),
        ]) + "\n")
        good = scan_file(p) is None
        ok &= good
        print(f"  {'ok  ' if good else 'FAIL'} a self-close that returned is not a retire")
    print("SELFTEST", "PASS" if ok else "FAIL")
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=54, help="newest N retirements (0 = all found)")
    ap.add_argument("--rung-mode", action="store_true", help="refuse on RUNG∈{📦,⛔,🔧} (the naive reading)")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    rows = collect(ROOTS, a.limit)
    for r in rows:
        r["verdict"] = verdict(r, a.rung_mode)
        r["rung"] = (r["frozen"] or {}).get("rung")
    if a.json:
        json.dump(rows, sys.stdout, ensure_ascii=False, indent=1)
        return 0
    ref = sum(1 for r in rows if r["verdict"] == "REFUSE")
    unr = sum(1 for r in rows if r["verdict"] == "UNRESOLVABLE")
    res = len(rows) - unr
    for r in rows:
        print(f"{r['verdict']:13} {r['rung'] or '?'} {r['ts']} {os.path.basename(r['cwd'] or '?')}")
    pct = (100.0 * ref / res) if res else float("nan")
    print(f"\nREFUSED={ref} RESOLVABLE={res} UNRESOLVABLE={unr} PCT={pct:.1f} "
          f"MODE={'rung' if a.rung_mode else 'fields'}")
    print("VERDICT=" + ("CROSSES-90 (< 10 %)" if pct < 10 else "STAYS-ANNOTATE (>= 10 %)"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
