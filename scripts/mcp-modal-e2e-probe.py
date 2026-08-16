#!/usr/bin/env python3
"""END-TO-END: run the flags the LIVE handoff-fire composes, in a pty, and see what the TUI draws.

Arm A = the live composition (isolation flags + the new --settings decision).
Arm B = the SAME line with --settings stripped — the pre-fix shape, and the positive control.
Without B, a silent A proves only that the harness saw nothing.
"""

import os, pty, re, select, signal, time

CLI = os.path.expanduser(
    "~/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe"
)
CFG = os.path.expanduser("~/.claude-tertiary")
DIR = "/private/tmp/mcp-modal-probe"
TMP = os.environ.get("TMPDIR", "/tmp")
MCPCFG = f"{TMP}/cc-mcp-userscope-.claude-tertiary.json"
DECISION = f"{TMP}/cc-mcp-decision-off--private-tmp-mcp-modal-probe.json"
MODAL = b"new MCP servers found in this project"
_ANSI = re.compile(
    rb"\x1b\[[0-9;<>?]*[a-zA-Z]|\x1b[\]\[][^\x07\x1b]*(?:\x07|\x1b\\)?|\x1b[78]"
)


def flat(b):
    return re.sub(rb"\s+", b" ", _ANSI.sub(b" ", b))


def run(label, argv, seconds=30):
    env = dict(
        os.environ,
        CLAUDE_CONFIG_DIR=CFG,
        TERM="xterm-256color",
        CC_ACCOUNT_PINNED="1",
        CLAUDE_ISOLATION_SKIP="1",
    )
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(DIR)
        os.execve(CLI, [CLI] + argv, env)
    buf, end = b"", time.time() + seconds
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.5)
        if fd in r:
            try:
                c = os.read(fd, 65536)
            except OSError:
                break
            if not c:
                break
            buf += c
    try:
        os.kill(pid, signal.SIGKILL)
        os.waitpid(pid, 0)
    except OSError:
        pass
    os.close(fd)
    f = flat(buf)
    modal = MODAL in f
    # The composer/footer is the proof the session actually got somewhere, not just that it
    # avoided the dialog by dying.
    up = b"for shortcuts" in f or b"auto-accept" in f or b"Bypassing Permissions" in f
    print(
        f"{label:<40} modal={'YES' if modal else 'no ':<4} reached_ui={'YES' if up else 'no '}  bytes={len(buf)}"
    )
    return modal, up


BASE = ["--strict-mcp-config", f"--mcp-config={MCPCFG}"]
a_modal, a_up = run(
    "A  live fire (with --settings)", BASE + [f"--settings={DECISION}", "say OK"]
)
b_modal, b_up = run("B  CONTROL: same line, no --settings", BASE + ["say OK"])
print()
print(
    "VERDICT: "
    + (
        "PASS — the control stalls at the dialog, the live composition does not"
        if (b_modal and not a_modal)
        else "INCONCLUSIVE — read the arms; a control that does not stall proves nothing"
    )
)
