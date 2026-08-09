# pty-run.py — run a command attached to a REAL pty, capture combined output, exit with its code.
#
# WHY THIS EXISTS RATHER THAN script(1). `script -q /dev/null <cmd>` is the usual macOS pty
# allocator and it works from an interactive shell — but it calls tcgetattr on ITS OWN stdin, so
# from any context without a controlling terminal (an agent tool call, cron, launchd, a CI job) it
# dies with:
#     script: tcgetattr/ioctl: Operation not supported on socket
# Measured 2026-08-08: that is exactly what happened when scripts/cloud-ceiling-probe.sh first
# tried to give `claude --cloud` the interactive terminal it demands. Substituting one pty
# allocator for another moved the failure without fixing it; the failure had simply changed which
# component was holding it wrong. pty.openpty() needs nothing of the caller's stdin.
#
# Verified here on all four properties a measurement rig depends on: the child sees `[ -t 1 ]`
# true against a same-command control, stdout is captured, stderr is captured, and the child's
# exit code propagates. PTY_RUN_TIMEOUT_S (default 180) bounds a child that never exits.
import os, pty, sys, select, subprocess, time

# Run argv[1:] attached to a real pty on all three fds, capture combined output, exit with the
# child's code. Unlike script(1) this needs NO tty on OUR OWN stdin — script(1) calls tcgetattr on
# its stdin and dies "Operation not supported on socket" when invoked from an agent tool call,
# a cron job, or anything else without a controlling terminal.
TIMEOUT = float(os.environ.get("PTY_RUN_TIMEOUT_S", "180"))
STRIP = os.environ.get("PTY_RUN_STRIP_ANSI", "") not in ("", "0")


def strip_ansi(d):
    """Remove terminal control sequences a pty makes the child emit.

    A pty is not free: the child now believes it is talking to a terminal, so it emits cursor
    control, bracketed-paste toggles, OSC colour queries and charset selects around the payload.
    Measured 2026-08-08, a one-line 'Created cloud session: …' came back wrapped in eleven such
    sequences. Two consequences, and the second is the dangerous one: the ledger records unreadable
    JSON, and a classifier's regex can be SPLIT by an escape sitting inside the phrase it matches —
    so a real quota refusal could read as unrecognised purely because of how it was framed.
    Order matters: OSC strings are consumed whole BEFORE the generic control sweep, or their
    introducer is eaten first and their payload ('11;?') survives as literal text.
    """
    import re

    d = re.sub(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)", "", d)  # OSC … BEL | ST

    # ⚠️ CURSOR MOTION IS WHITESPACE. DELETING IT CORRUPTS THE TEXT BEING CLASSIFIED.
    # A TUI does not emit runs of spaces; it emits cursor motion. Strip that as decoration and the
    # words fuse. Measured live 2026-08-08, a real refusal arrived as:
    #     Error:Bundleuploadfailed:Socketisclosedafter3attempts.
    # Every classifier pattern downstream contains a space ("weekly limit reached", "rate limit",
    # "interactive terminal"), so a refusal rendered this way matches NOTHING and is reported as
    # `refused-other` — a non-verdict — when it may have been the ceiling itself. That is the
    # instrument lying about the subject in the one direction that looks like honest abstention.
    # Converted to the spaces they stand for, BEFORE the generic CSI sweep can eat them.
    #
    # 🚨 G WAS MISSING UNTIL 2026-08-09, AND THIS COMMENT IS WHY THAT WAS HARD TO SEE. The rule was
    # written for CSI n C (cursor FORWARD) alone, so CSI n G (cursor horizontal ABSOLUTE) fell
    # through to the generic delete one line below — directly under a paragraph describing exactly
    # the defect it was still committing. The symptom above is itself a G artifact: replaying the
    # real bytes `Error:\x1b[8GBundle\x1b[15Gupload…` through this function produced
    # `Error:Bundleuploadfailed:Socketis closed` — fused where the sequence was G, spaced where it
    # was C. That mixed shape is the signature all over ~/.claude/autonomy/cloud/ceiling-probe.jsonl
    # (`Error:Bundleuploadfailed:…Pleasesetup  GitHubon`), where 6 of 9 `refused-other` rows are
    # real bundle refusals this function made unreadable. cloud-bundle-probe.sh's own normalise()
    # had already learned this and handles [CG]; the allocator every probe shares had not.
    # Absolute positioning is not a run length, so it collapses to ONE space rather than n.
    d = re.sub(r"\x1b\[(\d*)C", lambda m: " " * max(1, int(m.group(1) or 1)), d)
    d = re.sub(r"\x1b\[\d*G", " ", d)

    d = re.sub(r"\x1b\[[0-9;?<>=]*[A-Za-z]", "", d)  # CSI
    d = re.sub(r"\x1b[()][A-Za-z0-9]", "", d)  # charset select
    d = re.sub(r"\x1b[78=><NOPcM]", "", d)  # single-char escapes
    d = re.sub(
        r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", "", d
    )  # stray controls (incl. any bare ESC)
    return d.replace("\r\n", "\n").replace("\r", "\n")


cmd = sys.argv[1:]
if not cmd:
    sys.stderr.write("pty-run: no command\n")
    sys.exit(2)

mfd, sfd = pty.openpty()
try:
    p = subprocess.Popen(cmd, stdin=sfd, stdout=sfd, stderr=sfd, close_fds=True)
except OSError as e:
    os.close(mfd)
    os.close(sfd)
    sys.stderr.write("pty-run: cannot exec %s: %s\n" % (cmd[0], e))
    sys.exit(127)
os.close(sfd)

chunks, deadline = [], time.time() + TIMEOUT
while True:
    if time.time() > deadline:
        p.kill()
        chunks.append(b"\npty-run: TIMEOUT after %ds\n" % int(TIMEOUT))
        break
    try:
        r, _, _ = select.select([mfd], [], [], 0.25)
    except (OSError, ValueError):
        break
    if r:
        try:
            d = os.read(mfd, 65536)
        except OSError:  # EIO = the slave side closed; normal EOF on a pty
            break
        if not d:
            break
        chunks.append(d)
    elif p.poll() is not None:
        # The child is gone; one non-blocking drain, then stop. Without the poll guard this loop
        # spins forever on a pty whose master never reports EOF while any fd holds the slave.
        try:
            while True:
                d = os.read(mfd, 65536)
                if not d:
                    break
                chunks.append(d)
        except OSError:
            pass
        break

try:
    os.close(mfd)
except OSError:
    pass
raw = b"".join(chunks)
if STRIP:
    sys.stdout.write(strip_ansi(raw.decode("utf-8", "replace")))
else:
    sys.stdout.buffer.write(raw)
sys.stdout.flush()
sys.exit(p.wait())
