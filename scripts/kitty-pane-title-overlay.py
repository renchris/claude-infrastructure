#!/usr/bin/env python3
"""Toggleable pane titles for kitty that move NOTHING.

WHY THIS SHAPE. A pane title needs one cell-height of pixels and there are exactly
three places they can come from: take a row from the grid (kitty's built-in
`toggle_window_title_bars` — content shifts and every child gets SIGWINCH), reserve
one permanently in the padding (docs/research/kitty-pane-title-overlay-2026-09-14.md
route G — costs a row 100% of the time to buy an occasional bar), or draw ABOVE the
grid. Only the third costs nothing when off, and it is what this implements: a
graphics-protocol placement at z=1, which the protocol doc defines as painting over
the glyphs. The grid never changes, so no PTY is resized and no child is signalled.

THE ONE COST, stated plainly: while titles are up, row 1 of each pane is COVERED,
not moved. Nothing shifts; the top line is hidden behind the strip.

WHY THE REFRESH LOOP. kitty frees a placement whenever its anchoring cells are
cleared or scrolled away — `ESC[2J` even frees the image DATA, so a bare re-place
returns ENOENT and the PNG must be re-sent. There is no invalidation signal to
subscribe to, so holding the titles up means re-asserting them on a timer. That was
judged fatal when this route was evaluated for a PERSISTENT header; for a toggle it
is merely a loop that runs only while the titles are on.

q=2 IS MANDATORY, NOT A PREFERENCE. With q=0 the terminal's acknowledgement is
delivered into the *program's* stdin — a reply lands in whatever is running in the
pane. Suppressing responses is the only safe mode, and the cost is that there is no
error channel: failures here are silent by construction.
"""
import base64, io, json, os, stat, subprocess, sys, time, fcntl, struct, termios

LOG = os.path.expanduser("~/.claude/autonomy/kitty-title-overlay.log")


def _log(msg):
    """Failures here are otherwise INVISIBLE. The chord is a background launch with no
    tty: a traceback goes nowhere and a wrong answer reads as 'nothing happened'. This
    round was lost twice to exactly that — `painted 0 pane(s)` printed to a closed pipe."""
    try:
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        with open(LOG, "a") as fh:
            fh.write("%s %s\n" % (time.strftime("%Y-%m-%dT%H:%M:%S"), msg))
    except OSError:
        pass


def _ensure_pil():
    """Re-exec into an interpreter that HAS Pillow, if this one does not.

    The chord runs under `launch --type=background`, whose PATH is
    /Applications/kitty.app/Contents/MacOS:/usr/bin:/bin:/usr/sbin:/sbin — so `python3`
    is SYSTEM python, which ships no Pillow. Measured 2026-09-14: the script resolved
    its socket, found all four panes, and then died on `ModuleNotFoundError: PIL`.
    """
    try:
        import PIL  # noqa: F401
        return
    except ImportError:
        pass
    cache = os.path.expanduser("~/.claude/autonomy/kitty-title-overlay.interp")
    try:
        cand = open(cache).read().strip()
        if cand and os.path.exists(cand) and not os.environ.get("_KTO_REEXEC"):
            os.environ["_KTO_REEXEC"] = "1"
            os.execv(cand, [cand, os.path.abspath(__file__)] + sys.argv[1:])
    except OSError:
        pass
    if os.environ.get("_KTO_REEXEC"):
        _log("FATAL: no interpreter with Pillow found; titles cannot render")
        print("kitty-pane-title-overlay: no python with Pillow found", file=sys.stderr)
        sys.exit(3)
    for cand in ("/usr/local/bin/python3", "/opt/homebrew/bin/python3",
                 "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
                 "/usr/bin/python3"):
        if not os.path.exists(cand):
            continue
        probe = subprocess.run([cand, "-c", "import PIL"], capture_output=True)
        if probe.returncode == 0:
            # Remember the winner: each probe is a FULL interpreter start (~20ms), and
            # paying that on every keypress is most of the chord's felt latency.
            try:
                os.makedirs(os.path.dirname(cache), exist_ok=True)
                with open(cache, "w") as fh:
                    fh.write(cand)
            except OSError:
                pass
            os.environ["_KTO_REEXEC"] = "1"
            os.execv(cand, [cand, os.path.abspath(__file__)] + sys.argv[1:])
    _log("FATAL: scanned candidates, none had Pillow")
    print("kitty-pane-title-overlay: no python with Pillow found", file=sys.stderr)
    sys.exit(3)

STATE = os.path.expanduser("~/.claude/autonomy/kitty-title-overlay.state")
IMG_BASE = 7100                      # image ids we own; never collides with a user's
FONT_CANDIDATES = [
    "/System/Library/Fonts/Menlo.ttc",
    "/System/Library/Fonts/SFNSMono.ttf",
    "/System/Library/Fonts/Monaco.dfont",
    "/Library/Fonts/Arial.ttf",
]
# Every value below is READ OFF config/kitty.conf, not chosen. The strip must belong to
# this terminal, and an invented grey is exactly how it stops belonging.
#   background #1e1e24 · foreground #e6e6e6 · color8 #727272 · color7 #c8c8c8
BG        = (0x1e, 0x1e, 0x24)   # the terminal's OWN background: no card, no bar
INK_IDLE  = (0x8a, 0x8a, 0x94)   #  4.85:1 — a label sits BELOW the body it labels
INK_LIVE  = (0xa8, 0xa8, 0xb2)   #  7.03:1 — the focused pane, promoted ONE ramp step
RULE      = (0x3a, 0x3a, 0x42)   # one hairline, ~rgba(255,255,255,.10) over BG
# Why not brighter: body is 13.29:1. The first version painted the title at 14.04:1 —
# brighter than the content it describes, which inverts the hierarchy. Measured, not felt.


def ksock():
    """Resolve a socket `kitty @` can reach FROM A SUBPROCESS.

    KITTY_LISTEN_ON is NOT always a path. Inside `launch --type=background` kitty
    hands the child an inherited file descriptor — `fd:47` — and Python's subprocess
    closes non-standard fds, so `kitty @ --to fd:47` reaches nothing and every query
    returns empty. That is SILENT: the script finds no panes and paints none.

    Two further traps, both measured 2026-09-14, both from matching a NAME instead of
    testing the thing: `/tmp/kitty-*` also matches leftover logs and screenshots (13
    entries here, exactly ONE of them a socket), and `ps -o comm=` TRUNCATES at 16
    chars, so kitty reads as "/Applications/ki" and any endswith("kitty") test fails.
    So: test for an actual socket, and identify the owner by ancestry, never by name.
    """
    def sock_for(pid):
        path = "/tmp/kitty-%s" % pid
        try:
            return "unix:%s" % path if stat.S_ISSOCK(os.stat(path).st_mode) else None
        except OSError:
            return None

    s = os.environ.get("KITTY_LISTEN_ON") or ""
    if s.startswith("unix:"):
        return s
    got = sock_for(os.environ.get("KITTY_PID") or "")
    if got:
        return got
    # Walk our own ancestry; the kitty that owns this pane names the socket
    # (listen_on is `unix:/tmp/kitty-{kitty_pid}`). No name comparison anywhere.
    cur = os.getppid()
    for _ in range(12):
        if cur <= 1:
            break
        got = sock_for(cur)
        if got:
            return got
        try:
            r = subprocess.run(["ps", "-o", "ppid=", "-p", str(cur)],
                               capture_output=True, text=True)
            cur = int((r.stdout or "0").strip() or 0)
        except Exception:
            break
    # Last resort: the one real socket, if there is exactly one
    import glob
    socks = [p for p in glob.glob("/tmp/kitty-*")
             if sock_for(p.rsplit("-", 1)[-1])]
    return "unix:%s" % socks[0] if len(socks) == 1 else None


def kitty_ls(sock):
    cmd = ["kitty", "@"] + (["--to", sock] if sock else []) + ["ls"]
    out = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
    if out.returncode != 0:
        return []
    return json.loads(out.stdout)


_TTY_CACHE = {}


def pane_ttys(pids):
    """Every pane's tty, resolved ONCE per pid and then never again.

    Two measurements shaped this. Four separate `ps` calls cost 32ms — so batch. But
    ONE `ps` still costs 94.7ms on this machine, because the expense is spawning a
    process that walks the whole table, not the number of pids asked about. Batching
    alone therefore bought almost nothing.

    A pane's tty cannot change while the pane lives, so the right number of lookups
    per pid is one. The cache is in-memory ONLY and deliberately not persisted: pids
    are reused after death, and a stale pid->tty mapping would write escape sequences
    into somebody else's terminal.
    """
    pids = [p for p in pids if p]
    if not pids:
        return {}
    missing = [p for p in pids if p not in _TTY_CACHE]
    if not missing:
        return {p: _TTY_CACHE[p] for p in pids if _TTY_CACHE.get(p)}
    r = subprocess.run(["ps", "-o", "pid=,tty=", "-p", ",".join(str(p) for p in missing)],
                       capture_output=True, text=True)
    for line in (r.stdout or "").splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[1] != "??":
            try:
                _TTY_CACHE[int(parts[0])] = "/dev/%s" % parts[1]
            except ValueError:
                pass
    for p in missing:                      # remember the misses too, so a pane with no
        _TTY_CACHE.setdefault(p, None)     # tty is not re-probed on every single cycle
    if len(_TTY_CACHE) > 512:
        _TTY_CACHE.clear()
    return {p: _TTY_CACHE[p] for p in pids if _TTY_CACHE.get(p)}


def tiocgwinsz(path):
    """Exact pane pixel size and therefore exact cell size — no assumed constants."""
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    except OSError:
        return None
    try:
        buf = fcntl.ioctl(fd, termios.TIOCGWINSZ, b"\0" * 8)
        rows, cols, xpx, ypx = struct.unpack("HHHH", buf)
        if not (rows and cols and xpx and ypx):
            return None
        return dict(rows=rows, cols=cols, xpx=xpx, ypx=ypx,
                    cw=xpx / cols, ch=ypx / rows)
    finally:
        os.close(fd)


_PNG_CACHE = {}


def strip_png(width, height, text, live=False):
    """One cell-high title strip.

    The design is three decisions, each with a reference behind it:
      · background = the terminal's OWN background, so the strip reads as empty space
        rather than a card. Airbnb's no-card rule is the highest-value anti-template
        move available and it costs nothing.
      · ONE hairline along the bottom — the single structural signal, no shadow, no box.
      · hierarchy carried by LUMINANCE, never by size or hue. The focused pane is
        promoted one step; kitty's blue border already says which pane is focused, so
        this is a quiet echo, not a second encoding.
    """
    key = (width, height, text, live)
    hit = _PNG_CACHE.get(key)
    if hit is not None:
        return hit
    from PIL import Image, ImageDraw, ImageFont
    im = Image.new("RGB", (max(width, 1), max(height, 1)), BG)
    d = ImageDraw.Draw(im)
    FG = INK_LIVE if live else INK_IDLE
    font = None
    for p in FONT_CANDIDATES:
        if os.path.exists(p):
            try:
                font = ImageFont.truetype(p, max(int(height * 0.62), 8))
                break
            except Exception:
                continue
    if font is None:
        font = ImageFont.load_default()
    pad = 0  # column 1 — optically aligned with the pane's own text column
    # trim to fit rather than overflow the strip
    t = text
    while t and d.textlength(t, font=font) > width - 2 * pad:
        t = t[:-1]
    try:
        asc, desc = font.getmetrics()
        y = max((height - (asc + desc)) // 2, 0)
    except Exception:
        y = 0
    d.text((pad, y), t, font=font, fill=FG)
    # the one hairline: bottom edge only, full bleed, no corners, no shadow
    d.line([(0, height - 1), (width, height - 1)], fill=RULE, width=1)
    b = io.BytesIO()
    im.save(b, format="PNG", optimize=True)
    out = b.getvalue()
    if len(_PNG_CACHE) > 64:
        _PNG_CACHE.clear()
    _PNG_CACHE[key] = out
    return out


def place(tty, png, img_id):
    """Transmit+display at row 1 col 1, above the text, without moving the cursor."""
    b64 = base64.standard_b64encode(png)
    CH = 4096
    parts = [b"\0337\033[1;1H"]                      # save cursor, home
    i, first = 0, True
    while i < len(b64):
        chunk, i = b64[i:i + CH], i + CH
        more = b"1" if i < len(b64) else b"0"
        if first:
            parts.append(b"\033_Ga=T,f=100,z=1,C=1,q=2,i=%d,m=%s;%s\033\\"
                         % (img_id, more, chunk))
            first = False
        else:
            parts.append(b"\033_Gm=%s,q=2;%s\033\\" % (more, chunk))
    parts.append(b"\0338")                           # restore cursor
    try:
        with open(tty, "wb", buffering=0) as fh:
            fh.write(b"".join(parts))
        return True
    except OSError:
        return False


def clear(tty, img_id):
    try:
        with open(tty, "wb", buffering=0) as fh:
            fh.write(b"\033_Ga=d,d=I,i=%d,q=2\033\\" % img_id)
    except OSError:
        pass


def targets(sock, all_windows):
    """(pane_id, title, tty, is_focused) for panes we should label."""
    found = []
    for w in kitty_ls(sock):
        for t in w.get("tabs", []):
            if not all_windows and not t.get("is_focused"):
                continue
            panes = t.get("windows", [])
            if len(panes) < 2:          # a lone pane needs no label
                continue
            for p in panes:
                found.append(p)
    ttys = pane_ttys([p.get("pid") for p in found if p.get("pid")])
    out = []
    for p in found:
        tty = ttys.get(p.get("pid"))
        if tty:
            out.append((p["id"], (p.get("title") or "").strip(), tty,
                        bool(p.get("is_focused"))))
    return out


def paint(sock, all_windows):
    n = 0
    tg = targets(sock, all_windows)
    if not tg:
        _log("no targets: sock=%r — a pane query that returns nothing is the SILENT "
             "failure mode, not a quiet success" % (sock,))
    for pid_, title, tty, live in tg:
        g = tiocgwinsz(tty)
        if not g:
            continue
        png = strip_png(int(g["xpx"]), int(round(g["ch"])),
                        title or "(untitled)", live)
        if place(tty, png, IMG_BASE + (pid_ % 800)):
            n += 1
    return n


def wipe(sock, all_windows):
    for pid_, _t, tty, _live in targets(sock, all_windows):
        clear(tty, IMG_BASE + (pid_ % 800))


def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else "toggle"
    all_windows = "--all" in sys.argv
    sock = ksock()
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    on = os.path.exists(STATE)

    if arg == "toggle":
        arg = "off" if on else "on"

    if arg == "off":
        if os.path.exists(STATE):
            os.remove(STATE)
        wipe(sock, all_windows)
        return 0

    if arg == "on":
        with open(STATE, "w") as fh:
            fh.write(str(os.getpid()))
        # Re-assert until the state file is removed: kitty discards placements on any
        # clear or scroll and never says so, so this is the only way to hold.
        #
        # SPEED. A cycle is two very different costs: asking kitty what the panes are
        # (a `kitty @` spawn plus a `ps`, ~40ms) and actually drawing (a tty write,
        # measured 0.0ms). Re-querying every cycle capped the refresh at ~2s, which is
        # long enough that a repaint visibly eats a title and it stays eaten. So the
        # pane list is cached and refreshed about once a second, while the redraw runs
        # at REFRESH — the titles re-appear faster than the eye resolves, which is the
        # whole of "feels faster" here.
        REFRESH, REQUERY_EVERY = 0.35, 8
        deadline = time.time() + 3600
        tg, i = None, 0
        while os.path.exists(STATE) and time.time() < deadline:
            if tg is None or i % REQUERY_EVERY == 0:
                tg = targets(sock, all_windows)
                if not tg:
                    _log("hold: no targets (sock=%r)" % (sock,))
            for pid_, title, tty, live in tg:
                g = tiocgwinsz(tty)
                if not g:
                    continue
                png = strip_png(int(g["xpx"]), int(round(g["ch"])),
                                title or "(untitled)", live)
                place(tty, png, IMG_BASE + (pid_ % 800))
            i += 1
            time.sleep(REFRESH)
        wipe(sock, all_windows)
        return 0

    if arg == "once":
        print("painted %d pane(s)" % paint(sock, all_windows))
        return 0

    print("usage: kitty-pane-title-overlay.py [toggle|on|off|once] [--all]",
          file=sys.stderr)
    return 2


if __name__ == "__main__":
    _ensure_pil()
    sys.exit(main())
