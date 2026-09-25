#!/usr/bin/env python3
"""sched.py — drive the F1 offline gate: every task x 10 reps (5 per arm), ABBA order.

  sched.py plan   [--accounts next,next4,next3]   write $GATE_ROOT/schedule.json (idempotent)
  sched.py run    [--workers 3]                   execute pending cells; resumable
  sched.py status                                 one line per state

Design (eval/GATE.md § Method):
- Order per task: ABBA ABBA AB, A = full on even task numbers and slim on odd ones, so neither
  arm always goes first.
- Blocks: reps 1-4, 5-8, 9-10. A block runs entirely on ONE account (accounts carry slightly
  different hook sets until migration 0037 lands, so account is blocked out of the arm contrast).
  Blocks rotate across accounts.
- Two reps of one task never run at once (T3's /tmp script leak), and a block's reps run in order.
- Before each dispatch the account's weekly and 5-hour use are read (claude-accounts --json);
  an account at >= STOP_PCT is skipped, and if every account is over, the run pauses and says so.
- A cell whose failure class is quota/auth/timeout is re-queued (max 3 attempts) and never counted
  as an arm failure. The class comes from error text only (collect.py).
"""

import json, os, subprocess, sys, threading, time

H = os.path.dirname(os.path.abspath(__file__))
G = os.environ.get("GATE_ROOT", "/tmp/tokeff-gate")
SCHED = f"{G}/schedule.json"
LOG = f"{G}/sched.log"
STOP_PCT = int(os.environ.get("GATE_STOP_PCT", "85"))
CCD = {
    "next": "~/.claude-next",
    "next2": "~/.claude-secondary",
    "next3": "~/.claude-tertiary",
    "next4": "~/.claude-quaternary",
}
lock = threading.RLock()  # re-entrant: log() is called while next_cell() holds the lock


def log(msg):
    line = time.strftime("%H:%M:%S ") + msg
    with lock:
        open(LOG, "a").write(line + "\n")
    print(line, flush=True)


TASKS = os.environ.get("GATE_TASKS", f"{H}/tasks")
RUNNER = os.environ.get("GATE_RUNNER", f"{H}/run.sh")


def tasks():
    return sorted(
        d for d in os.listdir(TASKS) if os.path.isfile(f"{TASKS}/{d}/prompt.txt")
    )


def plan(accounts, arms=("full", "slim"), nreps=10, only=None, reps_map=None, offset=0):
    """Defaults reproduce the F1 plan exactly. F3/F4 pass --arms, --reps, --tasks, --reps-map:
    order is ABBA repeated and cut at the rep count; blocks are runs of 4 reps on one account.
    --rep-offset N (round 4 extension) only relabels rep r as r+N, so an extension's runs can be
    pooled with an earlier round's without colliding; order and blocking are unchanged."""
    if os.path.exists(SCHED):
        print(f"schedule exists: {SCHED}")
        return
    cells, k = [], 0
    for ti, t in enumerate(t for t in tasks() if not only or t in only):
        a, b = arms if int(t[1:3]) % 2 == 0 else arms[::-1]
        n = (reps_map or {}).get(t, nreps)
        order = [(a, b, b, a)[i % 4] for i in range(n)]
        allr = list(range(1, n + 1))
        for bi, reps in enumerate(allr[i : i + 4] for i in range(0, n, 4)):
            acct = accounts[k % len(accounts)]
            k += 1
            for r in reps:
                cells.append(
                    dict(
                        task=t,
                        rep=r + offset,
                        arm=order[r - 1],
                        block=f"{t}/b{bi + 1}",
                        account=acct,
                        state="pending",
                        attempts=0,
                        history=[],
                    )
                )
    json.dump(cells, open(SCHED, "w"), indent=1)
    print(f"planned {len(cells)} cells over {len(tasks())} tasks on {accounts}")


def quota():
    try:
        rows = json.loads(
            subprocess.run(
                ["claude-accounts", "--json"],
                capture_output=True,
                text=True,
                timeout=60,
            ).stdout
        )
        if isinstance(rows, dict):  # claude-accounts --json is {"rows": [...], ...}
            rows = rows["rows"]
        return {
            r["acct"]: (r.get("weekly_pct") or 0, r.get("session_pct") or 0)
            for r in rows
        }
    except Exception as e:
        log(f"quota read failed: {e}")
        return {}


def save(cells):
    with lock:
        json.dump(cells, open(SCHED + ".tmp", "w"), indent=1)
        os.replace(SCHED + ".tmp", SCHED)


def run(workers):
    cells = json.load(open(SCHED))
    busy_tasks, over = set(), set()
    q = {"t": 0, "v": {}}

    def fresh_quota():
        if time.time() - q["t"] > 120:
            q["v"], q["t"] = quota(), time.time()
            for a, (w, s) in q["v"].items():
                if (w >= STOP_PCT) and a not in over:
                    over.add(a)
                    log(
                        f"STOP-PCT: {a} weekly {w}% >= {STOP_PCT}% — no further dispatch to it"
                    )
        return q["v"]

    def next_cell():
        with lock:
            fq = fresh_quota()
            for c in cells:
                if c["state"] != "pending" or c["task"] in busy_tasks:
                    continue
                # a block's reps run in order: every earlier rep of the block must be done
                if any(
                    o["block"] == c["block"]
                    and o["rep"] < c["rep"]
                    and o["state"] != "done"
                    for o in cells
                ):
                    continue
                if c["account"] in over:
                    started = any(
                        o["block"] == c["block"] and o["state"] == "done" for o in cells
                    )
                    alts = [a for a in fq if a not in over and a != "next2"]
                    if not alts:
                        continue
                    log(
                        f"reassign {c['task']} r{c['rep']} {c['account']} -> {alts[0]} (block started={started})"
                    )
                    for o in cells:
                        if o["block"] == c["block"] and o["state"] == "pending":
                            o["account"] = alts[0]
                w, s = fq.get(c["account"], (0, 0))
                if (
                    s >= 95
                ):  # 5-hour window nearly spent: let other accounts' cells go first
                    continue
                c["state"] = "running"
                busy_tasks.add(c["task"])
                return c
            return None

    def work(wid):
        idle = 0
        while True:
            c = next_cell()
            if c is None:
                with lock:
                    left = [o for o in cells if o["state"] in ("pending", "running")]
                if not left:
                    return
                idle += 1
                if idle % 30 == 0:
                    log(
                        f"w{wid}: waiting ({len(left)} cells left; over={sorted(over)})"
                    )
                time.sleep(20)
                continue
            idle = 0
            c["attempts"] += 1
            ccd = os.path.expanduser(CCD[c["account"]])
            log(
                f"w{wid}: start {c['task']} r{c['rep']} {c['arm']} on {c['account']} (attempt {c['attempts']})"
            )
            save(cells)
            p = subprocess.run(
                [RUNNER, c["arm"], c["task"], str(c["rep"]), ccd],
                capture_output=True,
                text=True,
            )
            rundir = f"{G}/runs/{c['task']}/r{c['rep']}"
            cp = subprocess.run(
                [sys.executable, f"{H}/collect.py", rundir, c["task"]],
                capture_output=True,
                text=True,
            )
            try:
                m = json.loads(cp.stdout.strip().splitlines()[-1])
            except Exception:
                m = {
                    "fail_class": "collect-error",
                    "detail": (cp.stderr or p.stderr)[-400:],
                }
            c["history"].append({"attempt": c["attempts"], "rc": p.returncode, **m})
            with lock:
                busy_tasks.discard(c["task"])
                if (
                    m.get("fail_class") in ("quota", "auth", "timeout", "collect-error")
                    and c["attempts"] < 3
                ):
                    c["state"] = "pending"
                    if m.get("fail_class") == "quota":
                        q["t"] = 0
                    log(
                        f"w{wid}: RE-QUEUE {c['task']} r{c['rep']} ({m.get('fail_class')})"
                    )
                else:
                    c["state"] = "done"
                    log(
                        f"w{wid}: done {c['task']} r{c['rep']} {c['arm']} class={m.get('fail_class')} "
                        f"${m.get('cost_usd')} turns={m.get('turns')} push={m.get('push_attempted')}/"
                        f"{m.get('push_refused')}"
                    )
            save(cells)
            time.sleep(5)  # pacing between dispatches from one worker

    ts = []
    for i in range(workers):
        t = threading.Thread(target=work, args=(i,))
        t.start()
        ts.append(t)
        time.sleep(15)  # stagger the first wave
    for t in ts:
        t.join()
    log("ALL DONE")


def status():
    cells = json.load(open(SCHED))
    from collections import Counter

    print(Counter(c["state"] for c in cells))
    print(Counter((c["account"], c["state"]) for c in cells))
    done = [c for c in cells if c["state"] == "done"]
    print(
        "cost so far $%.2f" % sum((c["history"][-1].get("cost_usd") or 0) for c in done)
    )


def stop():
    """Stop the driver AND every run it started, then re-queue the interrupted cells.

    `timeout` puts each claude run in its OWN process group, so killing the driver's group alone
    orphans the runs, which then keep working in (or next to) a fixture the next driver rebuilds —
    measured 2026-09-24, it contaminated three r1 cells. Walk the descendants and kill every group.
    """
    pid = int(open(f"{G}/sched.pid").read().strip())
    ps = subprocess.run(
        ["ps", "-axo", "pid=,ppid=,pgid="], capture_output=True, text=True
    ).stdout.split("\n")
    rows = [tuple(map(int, ln.split())) for ln in ps if ln.strip()]
    kids, frontier = {pid}, {pid}
    while frontier:
        frontier = {p for p, pp, _ in rows if pp in frontier} - kids
        kids |= frontier
    groups = sorted({g for p, _, g in rows if p in kids})
    for g in groups:
        try:
            os.killpg(g, 15)
        except ProcessLookupError:
            pass
    cells = json.load(open(SCHED))
    n = 0
    for c in cells:
        if c["state"] == "running":
            c.update(state="pending", attempts=0, history=[])
            n += 1
    save(cells)
    print(
        f"stopped {len(kids)} processes in {len(groups)} groups; re-queued {n} running cells"
    )


def requeue(specs):
    """requeue T01-feature:1 ... — send done cells back to pending (e.g. a contaminated run)."""
    cells = json.load(open(SCHED))
    for s in specs:
        t, r = s.rsplit(":", 1)
        for c in cells:
            if c["task"] == t and c["rep"] == int(r):
                c["history"].append({"requeued": True})
                c.update(state="pending", attempts=0)
                print(f"requeued {t} r{r}")
    save(cells)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    args = sys.argv[2:]
    if cmd == "plan":
        accts = (
            args[args.index("--accounts") + 1].split(",")
            if "--accounts" in args
            else ["next", "next4", "next3"]
        )
        opt = lambda k: args[args.index(k) + 1] if k in args else None
        rm = opt("--reps-map")
        plan(
            accts,
            tuple(opt("--arms").split(",")) if opt("--arms") else ("full", "slim"),
            int(opt("--reps") or 10),
            set(opt("--tasks").split(",")) if opt("--tasks") else None,
            {kv.split("=")[0]: int(kv.split("=")[1]) for kv in rm.split(",")}
            if rm
            else None,
            int(opt("--rep-offset") or 0),
        )
    elif cmd == "run":
        run(int(args[args.index("--workers") + 1]) if "--workers" in args else 3)
    elif cmd == "stop":
        stop()
    elif cmd == "requeue":
        requeue(args)
    else:
        status()
