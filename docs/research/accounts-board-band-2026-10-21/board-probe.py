#!/usr/bin/env python3
"""Resize probe for the SessionStart accounts board: start a session at 50 columns, resize to 160,
then to 40, then submit one prompt, and measure the board on screen after each step. Red on trunk
(the static SessionStart systemMessage), green with mods/accounts-readout drawing it as a band.

usage: board-probe.py <arm: trunk|band> <out dir>
  trunk  `git show origin/main:hooks/accounts-board.sh`, no mod      (TRUNK_REF overrides the ref)
  band   this checkout's hook + mods/accounts-readout (PROBE_MOD_DIR overrides the mod folder)

Method, as docs/research/accounts-responsive-mod-2026-10-19/resize-probe.py: a real pty.fork() on
Claude Code 2.1.293, TIOCSWINSZ for the geometry (the kernel sends SIGWINCH), pyte as the terminal.
Settings come from --settings only (`--setting-sources project`), so no fleet hook runs and no
shared settings file is touched; no slash command is typed. The board is produced fresh for each
run by THIS checkout's producer (`--keepwarm`) over the width-sweep bats fixture rows, into a
scratch board (CC_ACCOUNTS_BOARD, HOME scratch for the producer), so every run draws the same facts.

The measure. The board's ladder (every layout 35-195 cells) is the set of WHOLE lines. After each
step, only what Claude Code drew after it is read (a fresh terminal fed the bytes from that step
on, at the new size). A screen row whose text is a whole ladder line that carries a grid figure
(`N%`) is an intact grid row; a row that is a strict piece of one is a wrapped grid row. The
layout's width is the widest intact grid row. Needs: pyte, and /tmp/acct-probe/arms/{state/acct.json,
fixture.txt} from the 2026-10-19 study's setup-probe.sh.
"""

import fcntl, json, os, pty, re, select, struct, subprocess, sys, termios, time, unicodedata

import pyte

ARM, OUT = sys.argv[1], sys.argv[2]
CLAUDE = os.path.expanduser("~/.claude-293/node_modules/.bin/claude")
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
MOD_DIR = os.environ.get("PROBE_MOD_DIR") or os.path.join(
    REPO, "mods", "accounts-readout"
)
P = "/tmp/abb-probe"
WORK, BOARD, PANE, SHD = (
    f"{P}/work",
    f"{P}/board/board.txt",
    f"{P}/pane",
    f"{P}/sh-empty",
)
ROWS, START, WIDE, NARROW = 60, 50, 160, 40
SGR = re.compile(r"\x1b\[[0-9;]*m")
for d in (OUT, WORK, os.path.dirname(BOARD), PANE, SHD, f"{P}/home", f"{P}/trunk"):
    os.makedirs(d, exist_ok=True)

if ARM == "trunk":
    hook = f"{P}/trunk/accounts-board.sh"
    src = subprocess.run(
        [
            "git",
            "-C",
            REPO,
            "show",
            os.environ.get("TRUNK_REF", "origin/main") + ":hooks/accounts-board.sh",
        ],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    assert "band_handoff" not in src, (
        "the trunk ref already carries the band: pass a pre-band TRUNK_REF"
    )
    open(hook, "w").write(src)
    os.chmod(hook, 0o755)
else:
    hook = os.path.join(REPO, "hooks", "accounts-board.sh")

# A fresh board from THIS checkout's producer (the trunk hook simply ignores the ladder), over the
# fixture rows. `--keepwarm` sweeps its own rows (logged-out here), so the probe calls the same
# functions keepwarm calls — write_board(_render_board, _board_variants, _board_ladder) — on the
# fixture rows, the program loaded as a module (its `__main__` guard keeps main() from running).
DRIVER = r"""
import json, os, sys
ns = {"__name__": "board_probe"}
exec(compile(open(sys.argv[1]).read(), sys.argv[1], "exec"), ns)
fx = open(sys.argv[2]).read().replace("\n    rows = [", "\nrows = [").replace("\n    wj, cached", "\nwj, cached")
exec(fx, ns)
cfg = ns["load_cfg"](need_claude_bin=False)
rows, wj, cached = ns["rows"], ns["wj"], ns["cached"]
print(ns["write_board"](cfg, ns["_render_board"](cfg, rows, wj, cached), sig=ns["_board_sig"](rows),
      producer="board-probe", variants=ns["_board_variants"](cfg, rows, wj, cached),
      ladder=ns["_board_ladder"](cfg, rows, wj, cached)))
"""
penv = {
    **os.environ,
    "CLAUDE_ACCOUNTS_JSON": "/tmp/acct-probe/arms/state/acct.json",
    "CC_ACCOUNTS_BOARD": BOARD,
    "HOME": f"{P}/home",
    "CC_STARTUP_HEALTH_DIR": SHD,
    "CLAUDE_CODE_SESSION_ID": "",
}
kw = subprocess.run(
    [
        "python3",
        "-c",
        DRIVER,
        os.path.join(REPO, "bin", "claude-accounts"),
        "/tmp/acct-probe/arms/fixture.txt",
    ],
    env=penv,
    capture_output=True,
    text=True,
)
assert kw.stdout.strip() == BOARD, kw.stdout + kw.stderr
ladder = json.load(open(BOARD + ".ladder.json"))

settings = {
    "hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": hook}]}]}
}
args = [
    CLAUDE,
    "--setting-sources",
    "project",
    "--settings",
    json.dumps(settings),
    "--model",
    "claude-haiku-5-5",
]
if ARM == "band":
    args += ["--plugin-dir", MOD_DIR]

pid, fd = pty.fork()
if pid == 0:
    os.chdir(WORK)
    os.environ.update(
        {
            "TERM": "xterm-256color",
            "CC_ACCOUNTS_BOARD": BOARD,
            "CC_PANE_DIR": PANE,
            "CC_STARTUP_HEALTH_DIR": SHD,
        }
    )
    for k in ("CLAUDECODE", "CLAUDE_CODE_SESSION_ID", "CLAUDE_PID", "CC_PANE_COLS"):
        os.environ.pop(k, None)
    os.execv(CLAUDE, args)


def setsize(cols):
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, cols, 0, 0))


setsize(START)
raw = bytearray()


def pump(sec):
    t = time.time()
    while time.time() - t < sec:
        r, _, _ = select.select([fd], [], [], 0.2)
        if r:
            try:
                d = os.read(fd, 65536)
            except OSError:
                return
            if not d:
                return
            raw.extend(d)


def screen(cut, cols):
    s = pyte.Screen(cols, ROWS)
    pyte.ByteStream(s).feed(bytes(raw[cut:]))
    return [ln.rstrip() for ln in s.display]


def wait_for(cut, cols, pat, sec):
    t = time.time()
    while time.time() - t < sec:
        pump(0.5)
        if re.search(pat, "\n".join(screen(cut, cols))):
            return True
    return False


def cells(t):
    return sum(2 if unicodedata.east_asian_width(c) in ("W", "F") else 1 for c in t)


whole = {SGR.sub("", ln).strip() for v in ladder["variants"] for ln in v["lines"]}
grid = {w for w in whole if re.search(r"\d+%", w)}


def measure(rows):
    intact, pieces = [], []
    for r in rows:
        b = r.strip().replace("[-]", "").strip()
        if not b:
            continue
        if b in grid:
            intact.append(b)
        elif b not in whole and len(b) >= 3 and any(b in g for g in grid):
            pieces.append(b)
    return {
        "intact_grid_rows": len(intact),
        "wrapped_grid_rows": len(pieces),
        "layout_cells": max((cells(x) for x in intact), default=0),
        "pieces": pieces,
    }


steps = {}
pump(8)
if "trust this folder" in "\n".join(screen(0, START)):
    os.write(fd, b"\x1b[B")
    pump(0.5)
    os.write(fd, b"\r")
ok_start = wait_for(0, START, r"\d+%", 30)
pump(3)


def step(name, cut, cols):
    rows = screen(cut, cols)
    open(f"{OUT}/{name}.txt", "w").write("\n".join(rows))
    steps[name] = {"cols": cols, **measure(rows)}


step(f"1-start-{START}", 0, START)
cut = len(raw)
setsize(WIDE)
pump(6)
step(f"2-resized-{WIDE}", cut, WIDE)
cut = len(raw)
setsize(NARROW)
pump(6)
step(f"3-resized-{NARROW}", cut, NARROW)
# The rest of the 40-200 range, wider and narrower in turn, then back to 40 for the prompt.
sweep = {}
for cols in (200, 60, 180, 80, 140, 100, 120, 45, NARROW):
    cut = len(raw)
    setsize(cols)
    pump(4)
    rows = screen(cut, cols)
    sweep[cols] = {k: v for k, v in measure(rows).items() if k != "pieces"} | {
        "pieces": measure(rows)["pieces"][:4]
    }
    open(f"{OUT}/sweep-{cols}.txt", "w").write("\n".join(rows))
os.write(fd, b"Reply with only the word ALPHA.")
pump(1)
os.write(fd, b"\r")
cut = len(raw)
ok_prompt = wait_for(cut, NARROW, r"⏺ ALPHA", 120)
pump(3)
# after the prompt, the whole live screen (the fresh-terminal read would hold only the reply's diff)
s = pyte.Screen(NARROW, ROWS)
pyte.ByteStream(s).feed(bytes(raw))
rows = [ln.rstrip() for ln in s.display]
open(f"{OUT}/4-after-prompt.txt", "w").write("\n".join(rows))
steps["4-after-prompt"] = {"cols": NARROW, **measure(rows)}

os.write(fd, b"\x03")
pump(0.5)
os.write(fd, b"\x03")
pump(1)
try:
    os.kill(pid, 9)
except OSError:
    pass
os.waitpid(pid, 0)
open(f"{OUT}/raw.bin", "wb").write(bytes(raw))

s1, s2, s3, s4 = (
    steps[k]
    for k in (
        f"1-start-{START}",
        f"2-resized-{WIDE}",
        f"3-resized-{NARROW}",
        "4-after-prompt",
    )
)
checks = {
    "board_drawn_at_start": s1["intact_grid_rows"] > 0,
    "wider_layout_at_160": s2["layout_cells"] > s1["layout_cells"],
    "zero_wrapped_grid_rows_at_40": s3["intact_grid_rows"] > 0
    and s3["wrapped_grid_rows"] == 0,
    "band_gone_after_prompt": s4["intact_grid_rows"] == 0
    and s4["wrapped_grid_rows"] == 0,
    "zero_wrapped_grid_rows_40_to_200": all(
        v["intact_grid_rows"] > 0 and v["wrapped_grid_rows"] == 0
        for v in sweep.values()
    ),
}
verdict = {
    "arm": ARM,
    "cc": "2.1.293",
    "turns_ok": [ok_start, ok_prompt],
    "steps": steps,
    "sweep": sweep,
    "checks": checks,
    "green": all(checks.values()) and ok_start and ok_prompt,
}
json.dump(verdict, open(f"{OUT}/verdict.json", "w"), indent=1, ensure_ascii=False)
print(
    f"verdict arm={ARM} green={verdict['green']} "
    + " ".join(f"{k}={v}" for k, v in checks.items())
    + " | "
    + " ".join(
        f"{k}:cells={v['layout_cells']},intact={v['intact_grid_rows']},wrapped={v['wrapped_grid_rows']}"
        for k, v in steps.items()
    )
)
