#!/usr/bin/env python3
"""mkfleet.py <dir> <now_epoch> [--effect F] [--day D] [--seed N] [--sessions N] [--d4 N]

A synthetic D3 fleet for tests/lever-verdicts.bats, with a PLANTED effect: under <dir> it writes
home/<four account roots>/projects transcripts, logs/idle-keepalive.jsonl gap rows,
logs/subagent-long-bash.jsonl (N D4 would-deny rows, few enough to fail the population gate),
logs/lever-rounds.jsonl (one kind=offline row, positive), state/flags.json (D3 at S2, pct 50, live,
stage started D days before now) and a fresh guard heartbeat; it prints the truth as JSON.

Each session holds 4 gaps of 1-2 h. A gap's return request rebuilds the cache at a cost
proportional to the context at the gap (the CUPED covariate) times lognormal noise; in a TREATED
gap (arm by lever_flags' own hash of the flags' salt) that cost is multiplied by (1 - F). Truth:
planted_pp_wk = mean control return cost x F x gaps per week.
"""

import argparse
import json
import math
import os
import random
import sys
import time

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "hooks", "lib"))
import lever_flags as lf  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("dir")
ap.add_argument("now", type=float)
ap.add_argument("--effect", type=float, default=0.5)
ap.add_argument("--day", type=float, default=15.0)
ap.add_argument("--seed", type=int, default=12)
ap.add_argument("--sessions", type=int, default=160)
ap.add_argument("--d4", type=int, default=3)
ap.add_argument("--no-aa", action="store_true", help="omit the qualifying S0 A/A row")
a = ap.parse_args()


def iso(t):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t))


def w(path, rows):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "a") as f:
        for r in rows:
            f.write(json.dumps(r, sort_keys=True, separators=(",", ":")) + "\n")


rnd = random.Random(a.seed)
home, logs, state = (os.path.join(a.dir, x) for x in ("home", "logs", "state"))
roots = [".claude", ".claude-secondary", ".claude-tertiary", ".claude-quaternary"]
accts = [".claude-next", ".claude-secondary", ".claude-tertiary", ".claude-quaternary"]
for r in roots:
    os.makedirs(os.path.join(home, r, "projects"), exist_ok=True)
os.makedirs(os.path.join(home, ".claude-next"), exist_ok=True)
if not os.path.lexists(os.path.join(home, ".claude-next", "projects")):
    os.symlink(
        os.path.join(home, ".claude", "projects"),
        os.path.join(home, ".claude-next", "projects"),
    )
start = a.now - a.day * 86400
doc = {
    "v": 1,
    "rev": 5,
    "updated_at": iso(start),
    "updated_by": "fixture",
    "levers": {},
}
for L in lf.LEVERS:
    live = L == "D3"
    doc["levers"][L] = {
        "decision": lf.DECISIONS[L],
        "stage": "S2" if live else "S0",
        "pct": 50 if live else 0,
        "holdback": 0,
        "mode": "live" if live else "shadow",
        "salt": "mk-" + L,
        "split_salt": "mks-" + L,
        "params_id": "p0",
        "candidate": None,
        "thresholds_sha": None,
        "trip": None,
        "stage_started_at": iso(start),
    }
os.makedirs(state, exist_ok=True)
os.environ["CC_LEVER_STATE_DIR"] = state  # lever_flags reads the heartbeat from here
for k in ("CC_LEVER_ALL", "CC_LEVER_D3", "CC_LEVER_EXCLUDE", "CC_IDLE_KEEPALIVE"):
    os.environ.pop(k, None)
with open(os.path.join(state, "flags.json"), "w") as f:
    json.dump(doc, f)
open(os.path.join(state, "guard.heartbeat"), "w").close()

W_WRITE, W_READ, W_OUT = 0.245, 0.0067, 0.404
gaps, d4, arm_rows = [], [], []
cost = {"treat": [], "ctrl": []}
n_gaps = 0
wpp = 0.0
span = (a.now - 3600 * 3) - (start + 600)
KEYS = ("arm", "u", "flag_src", "split", "pct_eff", "stage")
for i in range(a.sessions):
    sid = "%08x-1111-4000-8000-%012x" % (i, i)
    k = i % 4
    t = start + 600 + span * i / float(a.sessions) * 0.75
    sa = {L: lf.arm(L, sid, doc, "file") for L in ("D1", "D2")}
    arm_rows.append(
        {
            "v": 1,
            "kind": "session",
            "ts": iso(t),
            "sid": sid,
            "lineage": sid,
            "lineage_src": "self",
            "acct": accts[k],
            "excluded": False,
            "flag_src": "file",
            "flag_rev": 5,
            "arms": {L: {x: sa[L][x] for x in KEYS} for L in sa},
        }
    )
    if i < a.d4:
        d4.append(
            {
                "kind": "subagent_bash",
                "v": 3,
                "ts": iso(t + 30),
                "acct": accts[k],
                "sid": sid,
                "agent_id": "mk-ag%d" % i,
                "would_deny_class": "poll-loop",
                "exempt": None,
            }
        )
    lines = [
        {
            "type": "user",
            "timestamp": iso(t),
            "version": "2.1.293",
            "sessionId": sid,
            "message": {"role": "user", "content": "go"},
        }
    ]
    j = 0

    def req(ts, cw, cr, out):
        global j, wpp
        j += 1
        wpp += (cw * W_WRITE + cr * W_READ + out * W_OUT) / 1e6
        lines.append(
            {
                "type": "assistant",
                "timestamp": iso(ts),
                "sessionId": sid,
                "message": {
                    "id": "mk_%d_%d" % (i, j),
                    "model": "claude-opus-5-5",
                    "stop_reason": "end_turn",
                    "usage": {
                        "input_tokens": 0,
                        "cache_creation_input_tokens": cw,
                        "cache_read_input_tokens": cr,
                        "output_tokens": out,
                        "cache_creation": {
                            "ephemeral_5m_input_tokens": cw,
                            "ephemeral_1h_input_tokens": 0,
                        },
                    },
                    "content": [{"type": "text", "text": "ok"}],
                },
            }
        )

    req(t + 5, 2000, 40000, 300)
    t += 60
    for g in range(4):
        ctx = rnd.randrange(40000, 300000)
        dur = rnd.uniform(3600, 7200)
        t0 = t
        req(t0, 1000, ctx, 200)  # the last request before the gap
        unit = "%s:%s" % (sid, iso(t0))
        ar = lf.arm("D3", unit, doc, "file")
        arm = ar["arm"]
        arm_rows.append(
            dict(
                {x: ar[x] for x in KEYS},
                v=1,
                kind="event",
                lever="D3",
                unit=unit,
                ts=iso(t0),
                sid=sid,
                acct=accts[k],
            )
        )
        base = ctx * math.exp(rnd.gauss(0, 0.25) - 0.03125)
        cw = int(base * ((1 - a.effect) if arm == "treat" else 1.0))
        cost[arm].append(cw * W_WRITE / 1e6)
        req(t0 + dur, cw, 0, 0)  # the return: the cache rebuild
        gaps.append(
            {
                "kind": "gap",
                "v": 1,
                "ts": iso(t0 + dur),
                "sid": sid,
                "acct": accts[k],
                "start": iso(t0),
                "dur": dur,
                "wake_s": 3300,
                "ctx": ctx,
                "outcome": "no_wake",
            }
        )
        n_gaps += 1
        t = t0 + dur + 600
    w(
        os.path.join(
            home, roots[k], "projects", "-Users-x-mk%d" % (i % 3), sid + ".jsonl"
        ),
        lines,
    )
w(os.path.join(logs, "idle-keepalive.jsonl"), gaps)
w(os.path.join(logs, "lever-arms.jsonl"), sorted(arm_rows, key=lambda r: r["ts"]))
if not a.no_aa:  # the S0 A/A that qualified the online verdict, before the stage began
    w(
        os.path.join(logs, "lever-score.jsonl"),
        [
            {
                "v": 1,
                "kind": "aa",
                "ts": iso(start - 86400),
                "lever": "D3",
                "stage": "S0",
                "status": "ok",
                "online_ok": True,
            }
        ],
    )
w(os.path.join(logs, "subagent-long-bash.jsonl"), d4)
w(
    os.path.join(logs, "lever-rounds.jsonl"),
    [{"kind": "offline", "flow": "d3_keepalive", "pp_wk": 2.8, "ts": iso(start)}],
)
# ship-land rows (all known exits) and one account's weekly-meter readings at meter/wpp = 1.3
w(
    os.path.join(a.dir, "land.jsonl"),
    [
        {
            "ts": iso(start + 3600 * (h + 1)),
            "tool": "ship-land",
            "sid": "%08x-1111-4000-8000-%012x" % (h, h),
            "exit": (0, 0, 6, 42)[h % 4],
        }
        for h in range(12)
    ],
)
# claude-crashes.jsonl: a few deaths spread over the fleet (T4 reads CRASH rows, not RECYCLE)
w(
    os.path.join(logs, "claude-crashes.jsonl"),
    [
        {
            "ts": iso(a.now - 3600 * (h + 2)),
            "sid": "%08x-1111-4000-8000-%012x"
            % (a.sessions - 1 - 7 * h, a.sessions - 1 - 7 * h),
            "class": "CRASH" if h % 3 else "RECYCLE",
        }
        for h in range(6)
    ],
)
reset = iso(a.now + 3 * 86400)
w(
    os.path.join(logs, "account-utilization.jsonl"),
    [
        {
            "ts": iso(start + 60),
            "acct": "next",
            "auth": "ok",
            "weekly_pct": 0,
            "weekly_reset_at": reset,
        },
        {
            "ts": iso(a.now - 60),
            "acct": "next",
            "auth": "ok",
            "weekly_pct": int(round(1.3 * wpp)),
            "weekly_reset_at": reset,
        },
    ],
)
mc = sum(cost["ctrl"]) / len(cost["ctrl"])
per_week = n_gaps / (a.day / 7.0)
print(
    json.dumps(
        {
            "gaps": n_gaps,
            "treat": len(cost["treat"]),
            "ctrl": len(cost["ctrl"]),
            "ctrl_mean_pp": mc,
            "per_week": per_week,
            "planted_pp_wk": mc * a.effect * per_week,
            "wpp": wpp,
            "stage_started_at": iso(start),
        },
        sort_keys=True,
    )
)
