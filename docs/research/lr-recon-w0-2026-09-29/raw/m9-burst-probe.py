#!/usr/bin/env python3
"""W0 item 9: burst probe (C5 of docs/research/codex-vs-claude-200-2026-09-16/README.md).

For each account and each N in NS: start N headless cold sessions at the same instant (a barrier
releases all N Popen calls together), each asking for a one-word reply on the fleet's model, and
record per session: every `api_retry` system event CC emitted (CC retries 529 / "temporarily
limiting" silently, so the final result alone would hide the limiter), the final is_error, and the
wall time. Rounds are spaced by GAP_S so one round's limiter window does not leak into the next.

usage: m9-burst-probe.py OUT_JSONL ACCT=CFG_DIR [ACCT=CFG_DIR ...]
env:   NS (default 2,3,4,5,6) · GAP_S (default 60) · MODEL (default claude-opus-5-5)
"""

import json, os, subprocess, sys, threading, time

OUT = sys.argv[1]
ACCTS = [a.split("=", 1) for a in sys.argv[2:]]
NS = [int(x) for x in os.environ.get("NS", "2,3,4,5,6").split(",")]
GAP_S = float(os.environ.get("GAP_S", "60"))
MODEL = os.environ.get("MODEL", "claude-opus-5-5")
BIN = os.path.expanduser(
    os.environ.get("CLAUDE_BIN", "~/.claude-284/node_modules/.bin/claude")
)
CWD = os.environ.get("PROBE_CWD", "/tmp/lrw0/scratch")
LIMIT_TXT = "temporarily limiting"


def one(acct, cfg, n, i, barrier, rows):
    env = dict(os.environ, CLAUDE_CONFIG_DIR=os.path.expanduser(cfg))
    barrier.wait()
    t0 = time.time()
    p = subprocess.run(
        [
            BIN,
            "-p",
            "--verbose",
            "--output-format",
            "stream-json",
            "--model",
            MODEL,
            "This is a load probe. Reply with only the word OK.",
        ],
        cwd=CWD,
        env=env,
        capture_output=True,
        text=True,
        timeout=600,
    )
    retries, final = [], {}
    for line in p.stdout.splitlines():
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if e.get("type") == "system" and e.get("subtype") == "api_retry":
            retries.append(
                {
                    "status": e.get("error_status"),
                    "error": str(e.get("error"))[:120],
                    "attempt": e.get("attempt"),
                }
            )
        if e.get("type") == "result":
            final = e
    # Only the error-bearing surfaces: the whole stdout also carries ids and token counts, where a
    # bare "529" substring matched on the smoke run with no error at all.
    blob = (
        " ".join(r["error"] for r in retries)
        + " "
        + str(final.get("result"))
        + " "
        + p.stderr
    )
    blob529 = (
        any(r["status"] == 529 for r in retries)
        or "Overloaded" in blob
        or " 529" in blob
    )
    rows.append(
        dict(
            acct=acct,
            n=n,
            i=i,
            wall_s=round(time.time() - t0, 1),
            rc=p.returncode,
            is_error=final.get("is_error"),
            result=str(final.get("result"))[:80],
            retries=len(retries),
            retry_statuses=sorted({r["status"] for r in retries if r["status"]}),
            limiting_text=LIMIT_TXT in blob,
            s529=blob529,
            retry_detail=retries[:4],
        )
    )


with open(OUT, "a") as f:
    for acct, cfg in ACCTS:
        for n in NS:
            rows, barrier = [], threading.Barrier(n)
            ts = [
                threading.Thread(target=one, args=(acct, cfg, n, i, barrier, rows))
                for i in range(n)
            ]
            at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            for t in ts:
                t.start()
            for t in ts:
                t.join()
            fails = sum(1 for r in rows if r["is_error"] or r["rc"] != 0)
            retried = sum(1 for r in rows if r["retries"])
            limiting = sum(1 for r in rows if r["limiting_text"])
            s529 = sum(1 for r in rows if r["s529"])
            summ = dict(
                kind="round",
                acct=acct,
                n=n,
                at=at,
                first_turn_failed=fails,
                retried=retried,
                limiting_text=limiting,
                s529=s529,
                wall_s=sorted(r["wall_s"] for r in rows),
            )
            for r in sorted(rows, key=lambda r: r["i"]):
                f.write(json.dumps(dict(kind="session", **r)) + "\n")
            f.write(json.dumps(summ) + "\n")
            f.flush()
            print(json.dumps(summ), flush=True)
            time.sleep(GAP_S)
