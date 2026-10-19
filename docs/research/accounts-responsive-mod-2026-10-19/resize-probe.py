#!/usr/bin/env python3
"""Resize probe for the /accounts readout: draw it at 160 columns, resize the pane to 40, and
count the readout rows that come out wrapped. Red on trunk (static hook systemMessage), green
with mods/accounts-readout loaded.

usage: resize-probe.py <arm: trunk|mod> <repo> <out dir> [--scroll]
  <repo>    whose bin/claude-accounts and hooks/relay-verbatim.sh run (trunk: a `git show
            origin/main:` copy of both; mod: the worktree)
  --scroll  after the readout, have the model reply with 90 lines (a shell command's output
            would be folded into one row) so the readout has left the live screen before the
            resize (the scrollback case)

Method (as docs/research/board-render-2026-09-22.md): a real pty.fork() on Claude Code 2.1.293,
TIOCSWINSZ to set the geometry (the kernel sends SIGWINCH), and pyte as the terminal. Settings
come from --settings only (`--setting-sources project`, empty project dir), so no fleet hook and
no shared settings file is touched; no slash command is typed. The readout runs over the
width-sweep bats fixture rows (FIXTURE in tests/accounts-width-sweep.bats), so every run draws
the same facts and the reference ladder below matches what was drawn.

The measure. The ladder (`--ladder`, every layout the renderer makes from 35 to 195 cells) is the
set of WHOLE lines. A readout row on the screen after the resize, less its 5-cell indent, is
either one of those lines or a piece of one: a piece is a wrapped row, and a piece of an account
grid line is a wrapped grid row. Only what Claude Code drew AFTER the resize is measured (a fresh
terminal fed the bytes from the resize on): a row it did not redraw is not counted as fixed.
Needs: pyte (`uv venv` + `uv pip install pyte`), jq, the fixture wrapper named in FIXTURE_BIN.
"""

import fcntl, json, os, pty, re, select, struct, subprocess, sys, termios, time

import pyte

ARM, REPO, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
SCROLL = "--scroll" in sys.argv
CLAUDE = os.path.expanduser("~/.claude-293/node_modules/.bin/claude")
FIXTURE_BIN = "/tmp/acct-probe/arms/claude-accounts-fixture"
HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT_REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))   # this checkout
MOD_DIR = os.path.join(SCRIPT_REPO, "mods", "accounts-readout")
WORK = "/tmp/acct-probe/work"
ROWS, WIDE, NARROW = 60, 160, 40
SGR = re.compile(r"\x1b\[[0-9;]*m")
os.makedirs(OUT, exist_ok=True)
os.makedirs(WORK, exist_ok=True)
with open("/tmp/acct-probe/arms/repo", "w") as f:
    f.write(REPO)

settings = {
    "hooks": {
        "PostToolUse": [
            {
                "matcher": "Bash",
                "hooks": [
                    {"type": "command", "command": f"{REPO}/hooks/relay-verbatim.sh"}
                ],
            }
        ]
    },
    "permissions": {"allow": [f"Bash({FIXTURE_BIN}:*)", "Bash(seq:*)"]},
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
if ARM == "mod":
    args += ["--plugin-dir", MOD_DIR]


def setsize(fd, cols):
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, cols, 0, 0))


pid, fd = pty.fork()
if pid == 0:
    os.chdir(WORK)
    os.environ["TERM"] = "xterm-256color"
    for k in ("CLAUDECODE", "CLAUDE_CODE_SESSION_ID", "CLAUDE_PID", "CC_PANE_DIR"):
        os.environ.pop(k, None)
    os.execv(CLAUDE, args)
setsize(fd, WIDE)
scr = pyte.HistoryScreen(WIDE, ROWS, history=20000)
stream = pyte.ByteStream(scr)
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
            stream.feed(d)


def text(s):
    hist = [
        "".join(line[x].data for x in range(s.columns)).rstrip()
        for line in s.history.top
    ]
    return hist + [ln.rstrip() for ln in s.display]


def wait_for(pat, sec):
    t = time.time()
    while time.time() - t < sec:
        pump(0.5)
        if re.search(pat, "\n".join(text(scr))):
            return True
    return False


def ask(prompt, done_pat, sec=120):
    os.write(fd, prompt.encode())
    pump(1)
    os.write(fd, b"\r")
    return wait_for(done_pat, sec)


pump(6)
if "trust" in "\n".join(text(scr)).lower():
    os.write(fd, b"\r")
    pump(5)
ok1 = ask(
    f"Run exactly this one shell command and nothing else, then reply with only the word "
    f"ALPHA: {FIXTURE_BIN} --readout --no-agents --max-wait 0",
    r"⏺ ALPHA",
)
pump(4)
ok2 = True
if SCROLL:
    ok2 = ask(
        "Without running any tool, reply with the whole numbers from 1 to 90, one per line, "
        "then the word BRAVO on its own line, and nothing else.",
        r"(?m)^\s*BRAVO\s*$", 180,
    )
    pump(4)
open(f"{OUT}/1-drawn-{WIDE}.txt", "w").write("\n".join(text(scr)))
cut = len(raw)
setsize(fd, NARROW)
scr.resize(ROWS, NARROW)
pump(8)
open(f"{OUT}/2-resized-{NARROW}.txt", "w").write("\n".join(text(scr)))
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

# What Claude Code drew after the resize, alone.
after = pyte.HistoryScreen(NARROW, ROWS, history=20000)
pyte.ByteStream(after).feed(bytes(raw[cut:]))
redrawn = text(after)
open(f"{OUT}/3-redrawn-after-resize.txt", "w").write("\n".join(redrawn))

# The reference: every whole line the renderer makes, from the same fixture.
lad = json.loads(
    subprocess.run(
        [FIXTURE_BIN, "--readout", "--ladder", "--no-agents", "--max-wait", "0"],
        capture_output=True,
        text=True,
        env={
            **os.environ,
            "ARM_REPO": SCRIPT_REPO,
            "CLAUDE_CODE_SESSION_ID": "",
        },
    ).stdout
)
whole = {SGR.sub("", ln).rstrip() for v in lad["variants"] for ln in v["lines"]}
grid = {
    w
    for w in whole
    if re.search(r"\d+%", w)
    or re.search(r"\baccount\b.*\blive\b", w)
    or re.search(r"5-hour", w)
}


def measure(rows):
    """(rows in the readout block, wrapped rows, wrapped grid rows, the pieces), or None.

    The block ends at the model's reply row (`⏺ ALPHA`) and starts after the last row that
    heads the readout above it: the shell-command row or the hook message's header. A resize
    repaint reprints only what fits the screen, so the head may not be in `rows`; then the block
    starts at the first row that is not the echoed prompt."""
    end = next((i for i, r in enumerate(rows) if re.match(r"^⏺ ALPHA", r)), None)
    if end is None:
        return None
    heads = [i for i in range(end) if re.search(r"Ran \d+ shell command|PostToolUse:Bash says:", rows[i])]
    start = heads[-1] + 1 if heads else next(
        (i for i in range(end) if re.match(r"^\s+(⎿\s+)?\S", rows[i])
         and not re.match(r"^\s{2}\S", rows[i])), end)
    block = rows[start:end]
    if heads and re.search(r"⎿\s+➤ desk", rows[heads[-1]]):
        block = [rows[heads[-1]]] + block
    pieces, gpieces, intact = [], [], 0
    for r in block:
        body = (r[5:] if len(r) >= 5 else "").rstrip()
        if body.strip() and body in whole:
            intact += 1
        if not body.strip() or body in whole:
            continue
        pieces.append(body)
        if any(body.strip() in g for g in grid):
            gpieces.append(body)
    return (len(block), len(pieces), len(gpieces), pieces, intact) if intact + len(pieces) else None


res = measure(redrawn)
wide = measure(open(f"{OUT}/1-drawn-{WIDE}.txt").read().split("\n"))
verdict = {
    "arm": ARM,
    "scroll": SCROLL,
    "turns_ok": [ok1, ok2],
    "drawn_at_160": None if wide is None else {"rows": wide[0], "wrapped": wide[1]},
    "redrawn_after_resize": res is not None,
    "after_resize_40": None
    if res is None
    else {
        "rows": res[0],
        "intact_rows": res[4],
        "wrapped_rows": res[1],
        "wrapped_grid_rows": res[2],
        "pieces": res[3],
    },
}
json.dump(verdict, open(f"{OUT}/verdict.json", "w"), indent=1, ensure_ascii=False)
g = "n/a (readout not redrawn after the resize)" if res is None else res[2]
print(
    f"verdict arm={ARM} scroll={SCROLL} turns_ok={ok1 and ok2} "
    f"redrawn_after_resize={res is not None} wrapped_grid_rows={g} "
    f"wrapped_rows={'n/a' if res is None else res[1]} block_rows={'n/a' if res is None else res[0]}"
)
