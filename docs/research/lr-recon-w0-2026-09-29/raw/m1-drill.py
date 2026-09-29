#!/usr/bin/env python3
"""W0 item 1, the throwaway drill: N concurrent `claude --resume` relaunches in kitty windows this
session created (OS window `lr-w0`), timing paint -> first ACCEPTED Enter at 2 s resolution.

Per pane, all panes at once: type the relaunch command; poll the screen every 0.25 s until the empty
composer renders (a `❯` row alone between two rule rows, so a replayed `❯ <old prompt>` cannot
match); type a draft carrying a unique marker; poll until the composer shows the draft
(lr-fire-resume's DRAFT-MINE = its `composer-painted`); send CR #1 at once; then every RESEND_S,
while the draft is still in the composer, send another CR. "Accepted" = the marker's user record
lands in the session transcript; it is credited to the last CR sent before it.

usage: m1-drill.py SIDS_FILE WINDOW_IDS_FILE CLAUDE_BIN CONFIG_DIR OUT_JSONL
"""

import json, os, re, subprocess, sys, threading, time

KITTEN = [
    "/Applications/kitty.app/Contents/MacOS/kitten",
    "@",
    "--to",
    os.environ.get("KITTY_TO", "unix:/tmp/kitty-73832"),
]
RESEND_S, DEADLINE_S = 2.0, 120.0
sids = open(sys.argv[1]).read().split()
wins = open(sys.argv[2]).read().split()
BIN, CFG, OUT = sys.argv[3], sys.argv[4], sys.argv[5]
PROJ = os.path.join(CFG, "projects", "-private-tmp-lrw0-scratch")
RULE = re.compile(r"^─{20,}")
lock = threading.Lock()


def k(*a):
    return subprocess.run(KITTEN + list(a), capture_output=True, text=True).stdout


def screen(w):
    return k("get-text", "--match", f"id:{w}").splitlines()


def composer(lines):
    """text inside the composer box (rule / ❯ ... / rule), or None if no composer is rendered."""
    rules = [i for i, l in enumerate(lines) if RULE.match(l)]
    for a, b in zip(rules, rules[1:]):
        body = lines[a + 1 : b]
        if body and body[0].startswith("❯"):
            return " ".join(x.strip() for x in body)[1:].strip()
    return None


def accepted(sid, marker):
    try:
        with open(os.path.join(PROJ, sid + ".jsonl")) as f:
            for line in f:
                if marker in line and '"type":"user"' in line:
                    return True
    except OSError:
        pass
    return False


def run(i, sid, w, t_start):
    rec = dict(pane=i, sid8=sid[:8], window=w)
    marker = f"W0DRILL{i:02d}x{int(t_start) % 100000}"
    k(
        "send-text",
        "--match",
        f"id:{w}",
        f"clear; CLAUDE_CONFIG_DIR={CFG} {BIN} --model claude-haiku-4-5-20251001 --resume {sid}\r",
    )
    t0 = time.time()
    while time.time() - t0 < DEADLINE_S:
        c = composer(screen(w))
        if c is not None and marker not in c:
            rec["relaunch_to_composer_s"] = round(time.time() - t0, 2)
            break
        time.sleep(0.25)
    else:
        rec["result"] = "NO-COMPOSER"
        return rec
    # DRILL_PROMPT (run 3): a slash-command-shaped draft like lr-fire-resume's real
    # `/limit-recover ingest <bundle> ... run:<token>`; `{marker}` is replaced per pane.
    tpl = os.environ.get("DRILL_PROMPT", "Reply with only OK {marker}")
    k("send-text", "--match", f"id:{w}", tpl.replace("{marker}", marker))
    while time.time() - t0 < DEADLINE_S:
        c = composer(screen(w))
        if c and marker in c:
            t_paint = time.time()
            rec["relaunch_to_paint_s"] = round(t_paint - t0, 2)
            break
        time.sleep(0.25)
    else:
        rec["result"] = "NO-PAINT"
        return rec
    crs = []
    k("send-key", "--match", f"id:{w}", "enter")
    crs.append(round(time.time() - t_paint, 2))
    next_cr = time.time() + RESEND_S
    while time.time() - t_paint < DEADLINE_S:
        if accepted(sid, marker):
            rec.update(
                result="ACCEPTED",
                accepted_cr=len(crs),
                cr_sent_at_s=crs,
                accepted_cr_sent_at_s=crs[-1],
                paint_to_record_s=round(time.time() - t_paint, 2),
            )
            return rec
        if time.time() >= next_cr:
            c = composer(screen(w))
            if c and marker in c:  # DRAFT-MINE: our draft still sits in the composer
                k("send-key", "--match", f"id:{w}", "enter")
                crs.append(round(time.time() - t_paint, 2))
            next_cr = time.time() + RESEND_S
        time.sleep(0.25)
    rec.update(result="NOT-ACCEPTED", cr_sent_at_s=crs)
    return rec


results = []
t_start = time.time()


def worker(i, sid, w):
    r = run(i, sid, w, t_start)
    with lock:
        results.append(r)


ts = [
    threading.Thread(target=worker, args=(i, s, w))
    for i, (s, w) in enumerate(zip(sids, wins))
]
for t in ts:
    t.start()
for t in ts:
    t.join()
with open(OUT, "w") as f:
    for r in sorted(results, key=lambda r: r["pane"]):
        f.write(json.dumps(r) + "\n")
acc = sorted(
    r["accepted_cr_sent_at_s"] for r in results if r.get("result") == "ACCEPTED"
)
first_ok = sum(1 for r in results if r.get("accepted_cr") == 1)
print(f"n={len(results)} accepted={len(acc)} first_cr_accepted={first_ok}")
if acc:
    q = lambda p: acc[min(len(acc) - 1, int(round(p * (len(acc) - 1))))]
    print(
        f"paint->accepted_CR_sent_at: p50={q(0.5)} p90={q(0.9)} max={acc[-1]}  all={acc}"
    )
