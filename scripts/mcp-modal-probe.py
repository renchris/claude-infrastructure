#!/usr/bin/env python3
"""Does the project .mcp.json approval MODAL render in a real TUI, and does --settings suppress it?

`claude mcp list` reports the STATUS the gate computes; it does not prove what the interactive UI
draws. This launches a real TUI on a pty, reads the screen for a few seconds, kills it, and greps
for the dialog text. Arm 1 is the positive control: without it a silent arm 2 proves nothing.
"""

import os, pty, re, select, signal, sys, time

# 🚨 THE DETECTOR MUST STRIP ESCAPES FIRST. The Ink TUI renders this dialog word by word with a
# cursor-column escape between EVERY word — `2\x1b[5Gnew\x1b[9GMCP\x1b[13Gservers…` — so a grep for
# the literal sentence matches NOTHING even while the dialog is plainly on screen. The first run of
# this probe reported modal=no on all three arms, INCLUDING the control, which is the only reason
# the blindness was caught: a control that cannot fire turns every negative into a false all-clear.
_ANSI = re.compile(
    rb"\x1b\[[0-9;<>?]*[a-zA-Z]|\x1b[\]\[][^\x07\x1b]*(?:\x07|\x1b\\)?|\x1b[78]"
)


def flatten(b):
    return re.sub(rb"\s+", b" ", _ANSI.sub(b" ", b))


CLI = os.environ.get(
    "PROBE_CLI",
    os.path.expanduser(
        "~/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe"
    ),
)
DIR = os.environ.get("PROBE_DIR", "/private/tmp/mcp-modal-probe")
CFG = os.environ.get("PROBE_CFG", os.path.expanduser("~/.claude-tertiary"))
NEEDLE = b"new MCP servers found in this project"
SECONDS = float(os.environ.get("PROBE_SECONDS", "25"))


def fixture():
    """Build the probe's own project dir, so the run is repeatable after a binary upgrade.

    The two servers point at a script that speaks no MCP — deliberately. This probe asks only what
    the UI DRAWS; a server that connects would add startup latency and prove nothing extra.
    """
    os.makedirs(DIR, exist_ok=True)
    fake = os.path.join(DIR, "fake.sh")
    with open(fake, "w") as fh:
        fh.write("#!/bin/bash\nsleep 30\n")
    os.chmod(fake, 0o755)
    with open(os.path.join(DIR, ".mcp.json"), "w") as fh:
        fh.write(
            '{"mcpServers":{"probeA":{"command":"%s"},"probeB":{"command":"%s"}}}\n'
            % (fake, fake)
        )
    with open(os.path.join(DIR, "decision-off.json"), "w") as fh:
        fh.write('{"disabledMcpjsonServers":["probeA","probeB"]}\n')


def run(label, extra):
    env = dict(os.environ, CLAUDE_CONFIG_DIR=CFG, TERM="xterm-256color")
    pid, fd = pty.fork()
    if pid == 0:  # child: the TUI
        os.chdir(DIR)
        os.execve(CLI, [CLI] + extra, env)
    buf, deadline = b"", time.time() + SECONDS
    while time.time() < deadline:
        r, _, _ = select.select([fd], [], [], 0.5)
        if fd in r:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                break
            if not chunk:
                break
            buf += chunk
    try:
        os.kill(pid, signal.SIGKILL)
        os.waitpid(pid, 0)
    except OSError:
        pass
    os.close(fd)
    flat = flatten(buf)
    hit = NEEDLE in flat
    # …and it must read the FLATTENED screen for the same reason `hit` does.
    up = (
        b"for shortcuts" in flat
        or b"Bypassing Permissions" in flat
        or b"auto-accept" in flat
    )
    print(
        f"{label:<34} modal={'YES' if hit else 'no ':<4} ui_up={'YES' if up else 'no '}  bytes={len(buf)}"
    )
    return hit, up, buf


if __name__ == "__main__":
    fixture()
    arms = [
        ("1 CONTROL: no flag", []),
        ("2 --settings disabled (the fix)", [f"--settings={DIR}/decision-off.json"]),
        ("3 --strict-mcp-config alone", ["--strict-mcp-config"]),
    ]
    results = {}
    for label, extra in arms:
        results[label] = run(label, extra)
    # THE ACCEPTANCE, asserted rather than eyeballed: the control and the strict-only arm must BOTH
    # show the dialog (that is what makes arm 2's silence mean something), and arm 2 must not.
    ok = (
        results["1 CONTROL: no flag"][0]
        and results["3 --strict-mcp-config alone"][0]
        and not results["2 --settings disabled (the fix)"][0]
    )
    print(
        "\nVERDICT: "
        + (
            "PASS — the decision flag suppresses the dialog; --strict-mcp-config does not"
            if ok
            else "FAIL — re-read the arms; a control that does not fire makes every negative meaningless"
        )
    )
    # Dump the control's dialog region so the match is inspectable, not just a boolean.
    ctrl = results["1 CONTROL: no flag"][2]
    ctrl = flatten(ctrl)
    i = ctrl.find(NEEDLE)
    if i >= 0:
        print("\n--- control screen around the dialog ---")
        print(ctrl[max(0, i - 200) : i + 400].decode("utf-8", "replace"))
