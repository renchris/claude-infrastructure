#!/usr/bin/env python3
# Measure what a Stop-hook {"systemMessage": ...} ACTUALLY renders as in the Claude Code TUI.
# Companion to docs/research/tui-systemmessage-render-2026-08-22.md — read that for the findings;
# this file exists so the next person re-RUNS the measurement instead of trusting the write-up.
#
#   python3 docs/research/tui-systemmessage-render-2026-08-22.py [CONFIG_DIR]
#
# Method: fork a pty, run the live binary inside a throwaway project whose PROJECT settings register
# the same hook on SessionStart and Stop (--setting-sources project keeps the operator's own global
# hooks out of the capture — that contamination invalidated the first run of the 2026-08-08 channel
# probe). The hook emits ONE systemMessage carrying three sentinels; the RAW pty bytes are then
# inspected for the escapes around each.
#
# systemMessage is TUI-ONLY (final-response-shaping-2026-08-08 2a: silently dropped under `claude -p`,
# positive-controlled), which is why this cannot be a headless probe.
#
# READ THE CONTEXT LINES, NOT THE COUNTS. Run 1 of this probe sent its prompt into the folder-trust
# dialog, so no turn ran, Stop never fired, and only the SessionStart line rendered — a count of 1
# that looks exactly like a pass. The prefix (`SessionStart:startup says:` vs `Stop says:`) is what
# tells them apart.
import os, pty, sys, time, select

P = "/tmp/ansi-render-probe"
BIN = os.path.expanduser("~/.claude-220/node_modules/.bin/claude")
CFG = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/.claude-quaternary")

os.makedirs(P + "/.claude", exist_ok=True)
with open(P + "/hook.sh", "w") as f:
    f.write("#!/usr/bin/env bash\n"
            "# ESC via the JSON-legal \\u001b escape - the only legal way to put a control byte in a\n"
            "# JSON string, and exactly what `jq -n --arg` emits for a real ESC, i.e. the channel\n"
            "# hooks/operator-readout.sh actually uses.\n"
            'printf \'%s\\n\' \'{"systemMessage":"PROBE \\u001b[33mZZANSIZZ\\u001b[0m and `ZZCODEZZ` and ZZPLAINZZ END"}\'' + "\nexit 0\n")
os.chmod(P + "/hook.sh", 0o755)
with open(P + "/.claude/settings.json", "w") as f:
    f.write('{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"%s/hook.sh"}]}],'
            '"Stop":[{"hooks":[{"type":"command","command":"%s/hook.sh"}]}]}}\n' % (P, P))

pid, fd = pty.fork()
if pid == 0:
    os.chdir(P)
    os.environ["CLAUDE_CONFIG_DIR"] = CFG
    os.environ["TERM"] = "xterm-256color"
    os.environ["FORCE_COLOR"] = "1"
    os.execv(BIN, [BIN, "--setting-sources", "project", "--model", "claude-haiku-4-5-20251001"])

buf = b""


def pump(seconds):
    global buf
    t0 = time.time()
    while time.time() - t0 < seconds:
        r, _, _ = select.select([fd], [], [], 0.3)
        if r:
            try:
                d = os.read(fd, 65536)
            except OSError:
                return
            if not d:
                return
            buf += d


pump(10)                      # boot + the SessionStart hook
os.write(fd, b"\r")           # dismiss the folder-trust dialog (run 1 lost its prompt to it)
pump(8)
os.write(fd, b"say ok")       # one cheap turn, so Stop fires
time.sleep(1.5)
os.write(fd, b"\r")
pump(55)
os.write(fd, b"\x03"); time.sleep(0.4)
os.write(fd, b"\x03"); time.sleep(0.8)
pump(3)
try:
    os.kill(pid, 9); os.waitpid(pid, 0)
except OSError:
    pass

open(P + "/pty.out", "wb").write(buf)
print("captured bytes:", len(buf), "-> " + P + "/pty.out")
for name, sent in (("PLAIN", b"ZZPLAINZZ"), ("ANSI", b"ZZANSIZZ"), ("CODE", b"ZZCODEZZ")):
    n = buf.count(sent)
    print("%-6s sentinel: %-8s count=%d" % (name, "RENDERED" if n else "ABSENT", n))
i = 0
while True:
    i = buf.find(b"ZZANSIZZ", i)
    if i < 0:
        break
    print("  context:", repr(buf[max(0, i - 90):i + 90]))
    i += 1
print("raw ESC[33m present :", buf.count(b"\x1b[33m"), " (survived verbatim if >0)")
print("literal escape text :", buf.count(b"\\u001b"), " (stripped/escaped if >0)")
