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
import base64, io, json, os, subprocess, sys, time, fcntl, struct, termios

STATE = os.path.expanduser("~/.claude/autonomy/kitty-title-overlay.state")
IMG_BASE = 7100                      # image ids we own; never collides with a user's
FONT_CANDIDATES = [
    "/System/Library/Fonts/Menlo.ttc",
    "/System/Library/Fonts/SFNSMono.ttf",
    "/System/Library/Fonts/Monaco.dfont",
    "/Library/Fonts/Arial.ttf",
]
FG, BG = (236, 236, 236), (58, 58, 64)


def ksock():
    s = os.environ.get("KITTY_LISTEN_ON")
    if s:
        return s
    pid = os.environ.get("KITTY_PID")
    if pid:
        return "unix:/tmp/kitty-%s" % pid
    # last resort: a background `launch` may carry neither var
    import glob
    socks = sorted(glob.glob("/tmp/kitty-*"))
    return "unix:%s" % socks[0] if len(socks) == 1 else None


def kitty_ls(sock):
    cmd = ["kitty", "@"] + (["--to", sock] if sock else []) + ["ls"]
    out = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
    if out.returncode != 0:
        return []
    return json.loads(out.stdout)


def pane_tty(pid):
    """Slave tty of the pane's foreground process group leader."""
    r = subprocess.run(["ps", "-o", "tty=", "-p", str(pid)],
                       capture_output=True, text=True)
    t = r.stdout.strip()
    return "/dev/%s" % t if t and t != "??" else None


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


def strip_png(width, height, text):
    from PIL import Image, ImageDraw, ImageFont
    im = Image.new("RGB", (max(width, 1), max(height, 1)), BG)
    d = ImageDraw.Draw(im)
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
    pad = max(int(height * 0.28), 4)
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
    b = io.BytesIO()
    im.save(b, format="PNG", optimize=True)
    return b.getvalue()


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
    """(pane_id, title, tty) for panes we should label."""
    out = []
    for w in kitty_ls(sock):
        for t in w.get("tabs", []):
            if not all_windows and not t.get("is_focused"):
                continue
            panes = t.get("windows", [])
            if len(panes) < 2:          # a lone pane needs no label
                continue
            for p in panes:
                tty = pane_tty(p.get("pid"))
                if tty:
                    out.append((p["id"], (p.get("title") or "").strip(), tty))
    return out


def paint(sock, all_windows):
    n = 0
    for pid_, title, tty in targets(sock, all_windows):
        g = tiocgwinsz(tty)
        if not g:
            continue
        png = strip_png(int(g["xpx"]), int(round(g["ch"])), title or "(untitled)")
        if place(tty, png, IMG_BASE + (pid_ % 800)):
            n += 1
    return n


def wipe(sock, all_windows):
    for pid_, _t, tty in targets(sock, all_windows):
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
        # Re-assert until the state file is removed: kitty discards placements on
        # any clear or scroll and never says so, so this is the only way to hold.
        deadline = time.time() + 3600
        while os.path.exists(STATE) and time.time() < deadline:
            paint(sock, all_windows)
            time.sleep(2.0)
        wipe(sock, all_windows)
        return 0

    if arg == "once":
        print("painted %d pane(s)" % paint(sock, all_windows))
        return 0

    print("usage: kitty-pane-title-overlay.py [toggle|on|off|once] [--all]",
          file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
