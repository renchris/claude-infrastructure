#!/usr/bin/env python3
"""Probe A (startup-hooks Wave 6.2, gap-G2 §5): does a FileChanged hook push a toast and a
BEL into an IDLE pane, with no prompt ever typed?

Everything runs in a scratch tree: HOME, CLAUDE_CONFIG_DIR, the project dir and the hook
scripts all live under one mkdtemp dir. No live account dir, transcript dir or settings.json
is read or written. No API call is made (no prompt is typed; the scratch config has no auth).

Usage: probeA-filechanged.py <claude-binary> <evidence-out-dir> [--keep]
Needs pyte on PYTHONPATH for the screen replay (pip install --target /tmp/x pyte).

Deviation from gap-G2 §5, on purpose: §5 writes sidA at t+4 s, inside s1's 5 s toast, so by
§1 F8 (same-key de-dup) sidA would be dropped and (b) could never pass. Writes here are spaced
so each criterion is separately testable, and are anchored on the composer appearing (load on
this box is ~290, so wall-clock offsets from exec would race the footer mount, F6):
  T+1    alertdir/s1   (a) static absolute-dir watch, (d) toast lifetime, (f) BEL
  T+20   alerts/sidA   (b) SessionStart watchPaths
  T+20.5 alertdir/s2   (c) second toast inside sidA's window is dropped
  T+28   alerts/sidB   (e) cancelled hook's watchPaths lost
  T+34   alertdir/s3   positive control: the channel is still live after (e)'s silence
Run 1 (8 s spacing) showed why 20 s: the s1 toast queued ~8 s behind the startup "/effort"
notice, and F8 drops a key that is QUEUED as well as current, so sidA vanished behind it.
Group A's hook logs instead of being bare `true`, so whether it ever runs is measured.
--seed-prompt passes one argv prompt so a transcript exists for (h); the scratch config has no
credentials, so it cannot reach the API ("Not logged in").
"""

import base64, fcntl, json, os, pty, re, select, shutil, signal, struct, sys, tempfile, termios, threading, time

COLS, ROWS = 120, 40
BIN, OUT = sys.argv[1], sys.argv[2]
KEEP = "--keep" in sys.argv
SEED = "--seed-prompt" in sys.argv
os.makedirs(OUT, exist_ok=True)

S = os.path.realpath(tempfile.mkdtemp(prefix="w6probeA."))
HOME, CFG, PROJ, P, HK = (
    os.path.join(S, d) for d in ("home", "cfg", "proj", "p", "hooks")
)
for d in (HOME, CFG, PROJ + "/.claude", P + "/alerts", P + "/alertdir", HK):
    os.makedirs(d, exist_ok=True)
EV = P + "/ev.log"

json.dump(
    {
        "hasCompletedOnboarding": True,
        "theme": "dark",
        "projects": {
            PROJ: {
                "hasTrustDialogAccepted": True,
                "hasCompletedProjectOnboarding": True,
            }
        },
    },
    open(CFG + "/.claude.json", "w"),
)

NOW = "/usr/bin/perl -MTime::HiRes=time -e 'printf \"%.3f\", time'"
hooks = {
    "ss1.sh": f"""echo "SS1 $({NOW})" >> {EV}
printf '{{"hookSpecificOutput":{{"hookEventName":"SessionStart","watchPaths":["{P}/alerts/sidA"]}}}}\\n'
""",
    "ss2.sh": f"""trap 'echo "SS2TERM $({NOW})" >> {EV}; touch {P}/ss2.term; exit 143' TERM
for s in INT HUP PIPE USR1 USR2 QUIT; do trap "echo SS2SIG$s \\$({NOW}) >> {EV}" $s; done
echo "SS2START $({NOW}) pid=$$ ppid=$PPID parent=$(/bin/ps -o comm= -p $PPID)" >> {EV}
/bin/sleep 6 & sp=$!; wait $sp; rc=$?
echo "SS2END $({NOW}) sleep_rc=$rc" >> {EV}
printf '{{"hookSpecificOutput":{{"hookEventName":"SessionStart","watchPaths":["{P}/alerts/sidB"]}}}}\\n'
""",
    "fcA.sh": f"""in=$(cat); echo "A $({NOW}) $in" >> {EV}
""",
    "fcB.sh": f"""in=$(cat); echo "B $({NOW}) $in" >> {EV}
f=$(printf '%s' "$in" | /usr/bin/sed -n 's/.*"file_path":"\\([^"]*\\)".*/\\1/p'); b=${{f##*/}}
printf '{{"systemMessage":"ZZFCZZ %s","terminalSequence":"\\\\u0007"}}\\n' "$b"
""",
}
for name, body in hooks.items():
    open(os.path.join(HK, name), "w").write("#!/bin/bash\n" + body)


def h(name, timeout=None):
    d = {"type": "command", "command": f"/bin/bash {HK}/{name}"}
    if timeout:
        d["timeout"] = timeout
    return d


settings = {
    "hooks": {
        "SessionStart": [{"hooks": [h("ss1.sh", 10)]}, {"hooks": [h("ss2.sh", 2)]}],
        "FileChanged": [
            {"matcher": P + "/alertdir", "hooks": [h("fcA.sh", 5)]},
            {"hooks": [h("fcB.sh", 5)]},
        ],
    }
}
json.dump(settings, open(PROJ + "/.claude/settings.json", "w"), indent=1)

env = {
    k: os.environ[k]
    for k in ("PATH", "LANG", "USER", "LOGNAME", "TMPDIR")
    if k in os.environ
}
env.update(
    HOME=HOME,
    CLAUDE_CONFIG_DIR=CFG,
    TERM="xterm-256color",
    DISABLE_AUTOUPDATER="1",
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="1",
    SHELL="/bin/bash",
)

chunks, lock = [], threading.Lock()
writes, anchor = [], {}
t0 = time.time()
pid, fd = pty.fork()
if pid == 0:
    os.chdir(PROJ)
    seed = ["probe: reply with one word"] if SEED else []
    os.execve(BIN, [BIN, "--setting-sources", "project"] + seed, env)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))

import pyte  # noqa: E402  (after fork: the child never needs it)

screen = pyte.Screen(COLS, ROWS)
stream = pyte.ByteStream(screen)


def composer_up():
    txt = re.sub(r"\s+", "", "".join(screen.display))
    return (
        "forshortcuts" in txt
        or "Trysomething" in txt.replace('"', "")
        or "─" * 20 in "".join(screen.display)
    )


def writer(T):
    plan = [
        (1.0, P + "/alertdir/s1", "x"),
        (20.0, P + "/alerts/sidA", "x"),
        (20.5, P + "/alertdir/s2", "y"),
        (28.0, P + "/alerts/sidB", "z"),
        (34.0, P + "/alertdir/s3", "w"),
    ]
    for off, path, val in plan:
        dt = T + off - time.time()
        if dt > 0:
            time.sleep(dt)
        open(path, "w").write(val + "\n")
        writes.append(
            {
                "t": round(time.time() - t0, 3),
                "path": path.replace(S, "$S"),
                "planned_off": off,
            }
        )


wt = None
deadline = None
while True:
    now = time.time()
    if deadline and now > deadline:
        break
    if not deadline and now - t0 > 60:  # never anchored: give up after 60 s
        break
    r, _, _ = select.select([fd], [], [], 0.1)
    if r:
        try:
            d = os.read(fd, 65536)
        except OSError:
            break
        if not d:
            break
        t = time.time() - t0
        chunks.append((t, d))
        stream.feed(d)
    if not anchor and (composer_up() or (now - t0 > 25)):
        anchor = {
            "t": round(time.time() - t0, 3),
            "how": "composer" if composer_up() else "fallback-25s",
        }
        T = time.time()
        wt = threading.Thread(target=writer, args=(T,), daemon=True)
        wt.start()
        deadline = T + 42
os.write(fd, b"\x03")
time.sleep(0.4)
os.write(fd, b"\x03")
time.sleep(0.6)
try:
    while True:
        r, _, _ = select.select([fd], [], [], 0.3)
        if not r:
            break
        d = os.read(fd, 65536)
        if not d:
            break
        chunks.append((time.time() - t0, d))
except OSError:
    pass
try:
    os.kill(pid, signal.SIGKILL)
except ProcessLookupError:
    pass
os.waitpid(pid, 0)

# ---- analysis: replay into a fresh screen, chunk by chunk ----
scr = pyte.Screen(COLS, ROWS)
st = pyte.ByteStream(scr)
markers = ["s1", "sidA", "s2", "sidB", "s3"]
vis = {m: [] for m in markers}  # list of [start, end] intervals
osc = re.compile(rb"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)")
bells = []
for t, d in chunks:
    st.feed(d)
    for m in re.finditer(rb"\x07", osc.sub(b"", d)):
        bells.append(round(t, 3))
    screen_txt = "\n".join(scr.display)
    for m in markers:
        on = re.search(r"ZZFCZZ %s\b" % re.escape(m), screen_txt) is not None
        iv = vis[m]
        if on and (not iv or iv[-1][1] is not None):
            iv.append([round(t, 3), None])
        elif not on and iv and iv[-1][1] is None:
            iv[-1][1] = round(t, 3)
raw = b"".join(d for _, d in chunks)
ev = open(EV).read().splitlines() if os.path.exists(EV) else []


def evt(prefix):
    return [ln for ln in ev if ln.startswith(prefix + " ")]


def btimes(name):
    out = []
    for ln in evt("B"):
        if "/" + name + '"' in ln:
            out.append(round(float(ln.split()[1]) - t0, 3))
    return out


transcripts = []
for root, _, files in os.walk(CFG):
    for f in files:
        if f.endswith(".jsonl"):
            p = os.path.join(root, f)
            body = open(p, "rb").read()
            transcripts.append(
                {
                    "path": p.replace(S, "$S"),
                    "bytes": len(body),
                    "ZZFCZZ": body.count(b"ZZFCZZ"),
                    "hook_records": body.count(b'"hookEvent"'),
                }
            )
any_zz_on_disk = []
for root, _, files in os.walk(CFG):
    for f in files:
        p = os.path.join(root, f)
        try:
            if b"ZZFCZZ" in open(p, "rb").read():
                any_zz_on_disk.append(p.replace(S, "$S"))
        except OSError:
            pass


def bell_after(t, within=3.0):
    return [b for b in bells if t <= b <= t + within]


s1 = vis["s1"][0] if vis["s1"] else None
s1_life = round(s1[1] - s1[0], 3) if s1 and s1[1] else None
sidA = vis["sidA"][0] if vis["sidA"] else None
s2_write = next((w["t"] for w in writes if w["path"].endswith("/s2")), None)
s2_inside = bool(
    sidA
    and s2_write
    and sidA[0] <= s2_write + 0.7
    and (sidA[1] is None or s2_write < sidA[1])
)
verdict = {
    "a_static_dir_toast_idle": {
        "pass": bool(vis["s1"]),
        "s1_visible": vis["s1"],
        "B_ran_s1": btimes("s1"),
    },
    "b_sessionstart_watchpaths": {
        "pass": bool(vis["sidA"] and btimes("sidA")),
        "sidA_visible": vis["sidA"],
        "B_ran_sidA": btimes("sidA"),
    },
    "c_second_toast_dropped": {
        "pass": bool(not vis["s2"] and btimes("s2") and s2_inside),
        "s2_visible": vis["s2"],
        "B_ran_s2": btimes("s2"),
        "s2_write_inside_sidA_window": s2_inside,
    },
    "d_toast_lifetime_s": {
        "pass": bool(s1_life and 4.0 <= s1_life <= 6.5),
        "s1_lifetime": s1_life,
    },
    "e_cancelled_hook_paths_lost": {
        "pass": bool(not vis["sidB"] and not btimes("sidB") and vis["s3"]),
        "sidB_visible": vis["sidB"],
        "B_ran_sidB": btimes("sidB"),
        "control_s3_visible": vis["s3"],
    },
    "f_bel_per_event": {
        # one standalone BEL within 1 s of EVERY group-B run, deduped toast or not
        "pass": bool(evt("B"))
        and all(bell_after(b, 1.0) for n in markers for b in btimes(n)),
        "B_runs": {n: btimes(n) for n in markers},
        "standalone_bel_times": bells,
    },
    "g_term_marker": {
        "answer": "TERM delivered (trap ran)"
        if os.path.exists(P + "/ss2.term")
        else "no TERM marker",
        "ss2_lines": [ln.replace(S, "$S") for ln in ev if ln.startswith("SS2")],
    },
    "h_zero_tokens": {
        "pass": bool(transcripts) and all(x["ZZFCZZ"] == 0 for x in transcripts),
        "transcripts": transcripts,
        "files_with_ZZFCZZ": any_zz_on_disk,
    },
    "groupA_hook_ran": evt("A"),
    "seed_prompt": SEED,
}
summary = {
    "binary": BIN,
    "t0_epoch": round(t0, 3),
    "anchor": anchor,
    "writes": writes,
    "verdict": verdict,
    "load_at_end": os.getloadavg(),
    "ev_log": [ln.replace(S, "$S") for ln in ev],
    "settings": json.loads(json.dumps(settings).replace(S, "$S")),
}
json.dump(summary, open(os.path.join(OUT, "result.json"), "w"), indent=1)
open(os.path.join(OUT, "screen-final.txt"), "w").write("\n".join(scr.display))
with open(os.path.join(OUT, "chunks.jsonl"), "w") as fh:
    for t, d in chunks:
        fh.write(
            json.dumps({"t": round(t, 4), "b64": base64.b64encode(d).decode()}) + "\n"
        )
for k, v in verdict.items():
    print(k, json.dumps(v)[:300])
print("anchor", anchor, "load", os.getloadavg())
if not KEEP:
    shutil.rmtree(S, ignore_errors=True)
else:
    print("scratch kept:", S)
