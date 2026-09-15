#!/usr/bin/env python3
"""Toggleable pane titles for kitty that move NOTHING and paint in ~25ms.

WHY THIS SHAPE. A pane title needs pixels and there are exactly three places they can
come from: take rows from the grid (kitty's built-in `toggle_window_title_bars` —
content shifts and every child gets SIGWINCH), reserve rows permanently in the padding
(docs/research/kitty-pane-title-overlay-2026-09-14.md route G — costs a row 100% of the
time to buy an occasional bar), or draw ABOVE the grid. Only the third costs nothing
when off, and it is what this implements: a graphics-protocol placement at z=1, which
the protocol doc defines as painting over the glyphs. The grid never changes, so no PTY
is resized and no child is signalled.

THE STRIP IS NOT CAPPED AT ONE CELL — but one cell is what it should be. A placement is
sized in PIXELS and simply occupies ceil(h/cell) rows, so it may be drawn as tall as we
like; measured against the real terminal, a 90px strip on a 45px cell rendered its full
90px. Two cells was therefore tried, and it put the label at 1.46x the body's cap height.
The verdict on that was "way too big", and rendering the middle grounds at 1:1 showed the
band, not the type, was what dominated: a two-cell band with smaller type reads worse than
either extreme. So the height stays at one cell and the type sits at that cell's ceiling —
the header is carried by REGISTER and COLOUR, which is what a one-cell band leaves you.

THE ONE COST, stated plainly: while titles are up, the top row of each pane is COVERED,
not moved. Nothing shifts; that line is hidden behind the strip.

WHY THE REFRESH LOOP. kitty frees a placement whenever its anchoring cells are cleared or
scrolled away — `ESC[2J` even frees the image DATA, so a bare re-place returns ENOENT and
the PNG must be re-sent. There is no invalidation signal to subscribe to, so holding the
titles up means re-asserting them on a timer.

WHY A DAEMON. The chord's ~0.5s was never WORK, it was process startup: interpreter ~20ms,
re-exec into a Pillow-capable python ~20ms, PIL import ~40ms, `kitty @ ls` ~30ms, the first
`ps` ~95ms, then a render per pane. The tty write itself measures 0.0ms. Shaving any of
that is shaving the wrong thing. So a daemon holds the pane list and the rendered strips
warm, and the keypress becomes a unix-socket message plus a tty write. The client path
imports no Pillow and re-execs nothing, so it is a bare interpreter start.

q=2 IS MANDATORY, NOT A PREFERENCE. With q=0 the terminal's acknowledgement is delivered
into the *program's* stdin — a reply lands in whatever is running in the pane. Suppressing
responses is the only safe mode, and the cost is that there is no error channel: failures
here are silent by construction.
"""
import os, sys                      # the client path imports NOTHING else — see _client()

AUTONOMY = os.path.expanduser("~/.claude/autonomy")
LOG      = os.path.join(AUTONOMY, "kitty-title-overlay.log")
STATE    = os.path.join(AUTONOMY, "kitty-title-overlay.state")
SOCK     = os.path.join(AUTONOMY, "kitty-title-overlay.sock")
LOCK     = os.path.join(AUTONOMY, "kitty-title-overlay.lock")
INTERP   = os.path.join(AUTONOMY, "kitty-title-overlay.interp")


def _log(msg):
    """Failures here are otherwise INVISIBLE. The chord is a background launch with no
    tty: a traceback goes nowhere and a wrong answer reads as 'nothing happened'. This
    round was lost twice to exactly that — `painted 0 pane(s)` printed to a closed pipe."""
    try:
        os.makedirs(AUTONOMY, exist_ok=True)
        import time
        with open(LOG, "a") as fh:
            fh.write("%s %s\n" % (time.strftime("%Y-%m-%dT%H:%M:%S"), msg))
    except OSError:
        pass


# ───────────────────────────── the fast path ─────────────────────────────────
# Everything above this line is import-cheap on purpose. A keypress must not pay for
# Pillow, json, or subprocess, none of which the client needs.

def _client(cmd, timeout=0.4):
    """Hand the command to a warm daemon. False means 'no daemon' — never 'it failed'.

    A dead daemon leaves its socket FILE behind, and connecting to that fails instantly
    with ECONNREFUSED, so staleness is self-detecting and needs no pidfile. That matters
    more than it sounds: a pidfile would have to be validated before use, and the only
    honest validation (`ps` for the start time) costs 95ms — more than the whole budget.
    """
    import socket
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        s.settimeout(timeout)
        s.connect(SOCK)
        s.sendall(cmd.encode() + b"\n")
        return s.recv(16).startswith(b"ok")
    except OSError:
        return False
    finally:
        try:
            s.close()
        except OSError:
            pass


def _spawn_daemon(initial):
    """Start the daemon detached, and let IT serve this first press.

    The interpreter must be a Pillow-capable one; the cached winner from a previous run
    is used when it is still there, and otherwise the daemon itself re-execs (it calls
    _ensure_pil on the way in), so this never has to probe interpreters on the keypress.
    """
    import subprocess
    interp = sys.executable
    try:
        cand = open(INTERP).read().strip()
        if cand and os.path.exists(cand):
            interp = cand
    except OSError:
        pass
    try:
        devnull = open(os.devnull, "r+b")
        subprocess.Popen([interp, os.path.abspath(__file__), "daemon",
                          "--initial=" + initial],
                         stdin=devnull, stdout=devnull, stderr=devnull,
                         start_new_session=True, close_fds=True)
        return True
    except OSError as e:
        _log("daemon spawn failed: %s" % e)
        return False


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
    import subprocess
    try:
        cand = open(INTERP).read().strip()
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
        if subprocess.run([cand, "-c", "import PIL"], capture_output=True).returncode == 0:
            try:
                os.makedirs(AUTONOMY, exist_ok=True)
                with open(INTERP, "w") as fh:
                    fh.write(cand)
            except OSError:
                pass
            os.environ["_KTO_REEXEC"] = "1"
            os.execv(cand, [cand, os.path.abspath(__file__)] + sys.argv[1:])
    _log("FATAL: scanned candidates, none had Pillow")
    print("kitty-pane-title-overlay: no python with Pillow found", file=sys.stderr)
    sys.exit(3)


# ───────────────────────────── the design ────────────────────────────────────
IMG_BASE = 7100                  # image ids we own; never collides with a user's

# THE STRIP IS ONE CELL TALL, AND THE TYPE IS PINNED AT THAT CELL'S CEILING.
#
# Band height and type size are INDEPENDENT dials, and it took overshooting to see which
# one was carrying the complaint. A placement is sized in pixels and is not clipped to the
# cell it anchors to (measured — see the module docstring), so two cells was available and
# was tried: caps at 1.46x the body's. The verdict was "way too big", and rendering the
# alternatives at 1:1 showed why it was not a type-size problem — a two-cell band with
# SMALLER type is worse, not better, because the slab is what dominates. The band is the
# dial that was wrong.
#
# So one cell, one covered row, and TYPE_RATIO at the largest em that fits it. That leaves
# the label at ~0.9x the body's cap height, which is FINE and is the point: at one cell the
# type cannot be the thing that makes a header, so the header is carried by REGISTER (a
# proportional semibold against a monospace body) and by the band's colour. Size was never
# the free dial it looked like.
#
# ── REVERSED 2026-09-15, BY THE OPERATOR, AND THE PARAGRAPH ABOVE IS KEPT AS THE RECORD ──
# "one unit larger, the band and the text together, so the text doesn't look oversized to
# its boundary container." The paragraph above is not wrong about what it measured; it is
# wrong about what it CONCLUDED, and the flaw is named in its own last line. Pinning the em
# to the cell's ink ceiling made ink/band 0.93 — the type stands 1px off both edges — which
# is the crowding he is describing. The comparison that sent the band back to one cell was
# "a two-cell band with SMALLER type", rendered and rejected on MY taste; a two-cell band
# with MODESTLY LARGER type was never rendered for him at all. It is now (scratchpad
# hdr/grid.py, seven candidates at 1:1 over real Monaco body):
#
#     cand    band      em   ink(worst)  worst/band   cap/body
#     1:38    1c/45px   38     42          0.93         0.96     ← was: crowded
#     2:42    2c/90px   42     46          0.51         1.04
#     2:46    2c/90px   46     51          0.57         1.14     ← is
#     2:50    2c/90px   50     57          0.63         1.29
#     2:58    2c/90px   58     66          0.73         1.46     ← "way too big"
#
# ── AND TWO CELLS WAS TOO LARGE (operator, 2026-09-15): "now the titles are too large.
#    is there no in between?" There is, and the reason I said there was not is a conflation
#    worth keeping: COVERAGE and BAND HEIGHT are two different numbers. ─────────────────
#
# The constraint is real but it binds COVERAGE. A placement shorter than the rows it spans
# leaves the last row PART painted, and the part it paints is the top of that row's glyphs,
# so live content under it reads as clipped. Nothing, however, forces the painted band to
# fill the placement. Cover two WHOLE cells — no partial row, no clipping — and paint the
# band for only the first BAND_FILL_CELLS of it, filling the remainder with the terminal's
# own background. Row 2 then reads as a blank line under the header, which is what a header
# wants anyway, and the band height becomes CONTINUOUS from one cell to two.
#
# Rendered at 1:1 over real body text, with the two rejected ends as the controls:
#
#     band   em   ink(worst)  ink/band   air/side   cap/body
#     45px   38     42px        0.93        1px       0.96    ← "oversized to its container"
#     54px   40     44px        0.81        5px       1.00
#     58px   41     46px        0.79        6px       1.04    ← was
#     62px   42     46px        0.74        8px       1.04    ← is
#     68px   44     48px        0.71       10px       1.11
#     90px   46     51px        0.57       19px       1.14    ← "too large"
#
# 58 was one unit up from 45 in the band and one in the type, and it turned 1px of air
# into 6. The operator then asked for the same move AGAIN — "one unit larger in BOTH band
# and text, with the text no longer crowding its container" (2026-09-15) — so the dial is
# now at 62/42: 8px of air each side, ink-to-band 0.74, label still 1.04x the body cap.
# That was the promise this ladder was built to keep: the next move in either direction is
# two constants, not another architecture. COVERAGE IS UNCHANGED at two whole cells (90px),
# so this buys the air without touching the placement and cannot reintroduce layout shift.
BAND_FILL_CELLS = 1.378          # the PAINTED band, in cells: 62px at a 45px cell
GROUND        = (0x1e, 0x1e, 0x24)   # config/kitty.conf `background` — the unpainted remainder


def band_geometry(cell):
    """(painted band height, placement height) for a cell of `cell` device px.

    The placement is always a whole number of cells so no row is ever part-painted; the
    band is whatever BAND_FILL_CELLS asks for inside it.
    """
    import math
    cell = max(int(round(cell)), 1)
    fill = max(int(round(cell * BAND_FILL_CELLS)), 1)
    cover = int(math.ceil(fill / float(cell))) * cell
    return fill, cover


def band_cells(cell=45):
    """How many whole rows a strip covers — derived, so it cannot drift from the band."""
    return band_geometry(cell)[1] // max(int(round(cell)), 1)

# A HEADER MUST BE A DIFFERENT REGISTER, not just a different size. Matching the body's
# Monaco exactly made it read as more body text — "the font size/style/placement is still
# too similar to the body text". Four registers were rendered at 1:1 against real body
# text (Menlo Bold sentence · Monaco uppercase tracked · SF Semibold sentence · SF
# Semibold uppercase tracked) and the proportional semibold wins outright: it is visibly
# NOT terminal output, which is the whole job, and unlike the uppercase variants it stays
# readable when a session name runs long.
#
# SF Pro is the macOS system UI face, so a label set in it reads as chrome by convention,
# not by decoration. It is a variable font; the Semibold instance is selected by name and
# falls back silently to Regular if that ever fails.
UI_FONT      = "/System/Library/Fonts/SFNS.ttf"
UI_VARIATION = "Semibold"
TYPE_RATIO   = 0.678             # of the PAINTED band (not the placement): em 42 at 62px.
                                 #
                                 # THE OLD BOUND WAS THE FONT'S, NOT THE INK'S. Sizing by
                                 # `ascent + descent <= band` capped this at em 37 and was
                                 # reported as a hard ceiling — twice. It is not: those
                                 # metrics reserve room for accents and descenders the
                                 # glyphs may never use, so the box is ~9px taller than
                                 # anything a title actually draws. Measured ink, worst
                                 # realistic case (accented capitals ÅÉÎÕÜ plus gjpqy):
                                 # em 37 -> 42px, em 38 -> 43px, em 40 -> 44px, and the
                                 # band is 45 with 2px reserved so nothing sits flush
                                 # against an edge. So em 38 is the real accent-safe
                                 # ceiling — ONE unit above the old bound, and the last
                                 # one that holds for EVERY string rather than only the
                                 # ones that happen to carry no accent.
                                 #
                                 # THAT CEILING IS STILL THE RIGHT NUMBER AND IS NO LONGER
                                 # THE RIGHT TARGET (2026-09-15). A ceiling is where type
                                 # stops being safe, not where a header should sit: at the
                                 # ceiling the label touches its own band, which is the
                                 # crowding the operator named. This ratio now buys AIR on
                                 # purpose — em 46 in a 90px band, accented worst case 51px,
                                 # so ~19px of band above and below the ink. The em is still
                                 # bounded by the same ink rule below, which is what keeps
                                 # a pathological title from clipping; it simply is not
                                 # pressed against it any more.
                                 #
                                 # Going past the metrics box is only safe because the
                                 # baseline is now solved from the ACTUAL string's ink
                                 # (see strip_png) rather than from asc/desc, and because
                                 # a title whose ink still overflows steps the em down
                                 # until it fits. Without both, this would clip silently.
TRACKING     = 0.6               # a hair of tracking; proportional type at label size

# SF PRO HAS NO ✳ ◐ ◑ ✻ ✶ — and every Claude Code pane title STARTS with one. Read out of
# the real cmaps, not guessed: those five are absent from SFNS and present in Menlo. A
# missing glyph in PIL does not raise, it draws .notdef — a striped box — so this was
# invisible until a strip was rendered at 1:1 and looked at. Any character the UI face
# lacks is therefore drawn from SYMBOL_FONT instead, cap-height-matched to the primary,
# and the two are set on a shared BASELINE (anchor "ls") so the run does not stagger.
SYMBOL_FONT   = "/System/Library/Fonts/Menlo.ttc"
NOTDEF_PROBE  = "\uE000"       # private use: no font carries it, so its bitmap IS .notdef
FONT_CANDIDATES = [
    UI_FONT,
    "/System/Library/Fonts/Monaco.ttf",
    SYMBOL_FONT,
]

# Palette read off config/kitty.conf: background #1e1e24 · foreground #e6e6e6.
#
# VIBRANCY CARRIES FOCUS, and only focus. The operator asked for more of it after two
# rounds of slate; the answer is not to saturate every pane — seven loud bands say nothing
# — but to spend the whole colour budget on the ONE that is live. #2f62d8 is kitty's own
# active_border_color hue at full chroma, so the focused strip and the focused border are
# the same blue, and the idle bands lift just far enough off the ground to read as bands.
BAND_IDLE = (0x3f, 0x55, 0x90)   # 2.30:1 over the ground, and BLUE rather than grey:
                                 # four idle candidates were rendered beside the live band and
                                 # this one carries the most chroma while still losing to it
BAND_LIVE = (0x2f, 0x62, 0xd8)   # 3.05:1 over the ground — the vivid one, the focused one
INK_IDLE  = (0xf4, 0xf6, 0xfd)   # 6.67:1 on its band
INK_LIVE  = (0xff, 0xff, 0xff)   # 5.4:1 on the blue


_FACES = {}


def _faces(em):
    """(primary, symbol, notdef_signature) for one em, resolved once.

    notdef is detected by RENDERING a codepoint no font carries (U+E000, private use) and
    keeping its bitmap: PIL exposes no cmap, and every other test lies — `getmask` returns
    ink for .notdef and `getlength` returns a perfectly ordinary advance.
    """
    hit = _FACES.get(em)
    if hit:
        return hit
    from PIL import ImageFont
    primary = None
    for p in FONT_CANDIDATES:
        if not os.path.exists(p):
            continue
        try:
            primary = ImageFont.truetype(p, max(em, 8))
            if p == UI_FONT:
                try:
                    primary.set_variation_by_name(UI_VARIATION)
                except Exception:
                    pass          # Regular is an acceptable degrade, a crash is not
            break
        except Exception:
            continue
    if primary is None:
        primary = ImageFont.load_default()
        out = (primary, primary, None)
        _FACES[em] = out
        return out

    def cap_h(font):
        bb = font.getbbox("HEXBD")
        return max(bb[3] - bb[1], 1)

    symbol = primary
    if os.path.exists(SYMBOL_FONT):
        try:
            probe = ImageFont.truetype(SYMBOL_FONT, max(em, 8))
            scaled = max(int(round(em * cap_h(primary) / float(cap_h(probe)))), 8)
            symbol = ImageFont.truetype(SYMBOL_FONT, scaled)
        except Exception:
            symbol = primary
    try:
        m = primary.getmask(NOTDEF_PROBE, mode="L")
        notdef = (m.size, bytes(m))
    except Exception:
        notdef = None
    out = (primary, symbol, notdef)
    _FACES[em] = out
    return out


def _face_for(ch, primary, symbol, notdef):
    if notdef is None or symbol is primary:
        return primary
    try:
        m = primary.getmask(ch, mode="L")
        return symbol if (m.size, bytes(m)) == notdef else primary
    except Exception:
        return primary


_PNG_CACHE = {}


def strip_png(width, band_h, text, live=False, cover_h=None):
    """One title strip: a band `band_h` tall inside a placement `cover_h` tall.

    Three decisions, each with a reference behind it:
      · a real BAND, not a tint — a pane header's whole job is to be pickable out of the
        page, and the first version borrowed a no-card rule written for transcript speech.
      · hierarchy carried by SIZE and by SATURATION, in that order: the label outranks the
        body by 1.46x in cap height, and the live pane outranks the idle ones by hue.
      · no rule, no shadow, no box. The band's own edge against the terminal ground is the
        structural signal, and at this height it does not need help.
    """
    key = (width, band_h, text, live, cover_h)
    hit = _PNG_CACHE.get(key)
    if hit is not None:
        return hit
    from PIL import Image, ImageDraw
    W, H = max(width, 1), max(band_h, 1)
    # THE PLACEMENT IS AS TALL AS ITS WHOLE ROWS; THE BAND NEED NOT BE. Everything below
    # the band is painted the terminal's own background, so the row the placement covers
    # but the band does not reads as an empty line rather than as clipped glyph tops —
    # which is what makes a band height between one cell and two possible at all.
    C = max(cover_h or H, H)
    im = Image.new("RGB", (W, C), GROUND)
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, W, H - 1], fill=BAND_LIVE if live else BAND_IDLE)
    FG = INK_LIVE if live else INK_IDLE
    em = max(int(H * TYPE_RATIO), 8)
    primary, symbol, notdef = _faces(em)
    # THE INSET IS A PROPERTY OF THE CELL, NOT OF THE BAND. It was `H * 0.21`, which is
    # the same 9px while the band was one cell and silently became 18px the moment the band
    # became two — doubling a horizontal margin because a VERTICAL dimension changed, and
    # walking the label out of alignment with the body text under it. Divide the band back
    # down to its cell first.
    pad = max(int((H / max(BAND_FILL_CELLS, 0.1)) * 0.21), 8)  # inset, off the pane edge
    faces = [(ch, _face_for(ch, primary, symbol, notdef)) for ch in text]

    def measure(seq):
        return sum(f.getlength(c) + TRACKING for c, f in seq)

    if measure(faces) > W - 2 * pad:
        while faces and measure(faces) > W - 2 * pad - primary.getlength("…"):
            faces.pop()
        faces.append(("…", primary))
    # BASELINE FROM INK, NOT FROM METRICS — and the em steps down if the ink still
    # overflows. `getbbox(anchor="ls")` returns each glyph's ink relative to the baseline
    # (y0 negative above it), so the union over the glyphs actually being drawn is the
    # exact box on screen. Centring THAT is what makes a label sit right whether or not it
    # happens to carry an accent or a descender, and it is what makes an em above the
    # font's own ascent+descent safe rather than a silent clip.
    def ink_span(seq):
        top, bot = None, None
        for c, f in seq:
            try:
                b = f.getbbox(c, anchor="ls")
            except Exception:
                continue
            if b[1] == b[3]:
                continue                      # a space has no ink
            top = b[1] if top is None else min(top, b[1])
            bot = b[3] if bot is None else max(bot, b[3])
        return (top, bot) if top is not None else None
    span = ink_span(faces)
    BREATHE = 2                               # 1px of band above and below the ink; a
                                              # glyph flush against the edge reads clipped
                                              # even when it is not
    while span and (span[1] - span[0]) > H - BREATHE and em > 8:
        em -= 1                               # an exotic title degrades, never clips
        primary, symbol, notdef = _faces(em)
        faces = [(c, _face_for(c, primary, symbol, notdef)) for c, _f in faces]
        span = ink_span(faces)
    if span:
        base = (H - (span[1] - span[0])) // 2 - span[0]
    else:
        try:
            asc, desc = primary.getmetrics()
            base = max((H - (asc + desc)) // 2, 0) + asc
        except Exception:
            base = H // 2
    x = pad
    for ch, f in faces:      # per glyph, so tracking and the symbol fallback are possible
        try:
            d.text((x, base), ch, font=f, fill=FG, anchor="ls")
        except Exception:
            d.text((x, base - int(H * 0.7)), ch, font=f, fill=FG)
        x += f.getlength(ch) + TRACKING
    import io
    b = io.BytesIO()
    # compress_level=1, not the default 6. The payload's only journey is a write into a
    # tty on this machine — eight strips measure 1.5ms — so trading ~3KB per strip for a
    # markedly cheaper encode is free, and the encode is the one thing that can hold the
    # GIL while a keypress is waiting to be answered.
    im.save(b, format="PNG", optimize=False, compress_level=1)
    out = b.getvalue()
    if len(_PNG_CACHE) > 128:
        _PNG_CACHE.clear()
    _PNG_CACHE[key] = out
    return out


# ───────────────────────────── the proof ─────────────────────────────────────

BODY_FONT = "/System/Library/Fonts/Monaco.ttf"   # kitty.conf font_family
BODY_EM   = 36                                   # font_size 18.0 on a 2x display


def measure(cell_h=45):
    """Print what the size argument actually turns on, at kitty's own device scale.

    1:1 and not an analogy — kitty runs Monaco at font_size 18.0, which on a 2x display is
    a 36px em, and PIL's truetype(36) is that same em, so the ink boxes here are the ink
    boxes on the glass.

    THE CEILING IS MEASURED FROM INK, AND THAT CORRECTS A BOUND STATED TWICE. The earlier
    rule was `ascent + descent <= band`, which capped the type at em 37 and was reported as
    a hard limit. Those metrics reserve room for accents and descenders a given string may
    never draw, so the box runs ~9px taller than anything a title actually puts on screen.
    The real limit is the worst string we might be handed — accented capitals plus
    descenders — and it sits three ems higher. Sizing to it is only safe because strip_png
    now solves the baseline from the ACTUAL string's ink and steps the em down when that
    ink would not fit, so the bound below is a design target rather than a promise.
    """
    from PIL import Image, ImageDraw, ImageFont

    def ink_h(font, text):
        im = Image.new("L", (2400, 500), 0)
        ImageDraw.Draw(im).text((20, 200), text, font=font, fill=255)
        bb = im.getbbox()
        return (bb[3] - bb[1]) if bb else 0

    CAPS, TYPICAL, WORST = "HEXBD", "Kitty pane-title overlay", "ÅÉÎÕÜ Kitty gjpqy"
    BREATHE = 2
    body = ImageFont.truetype(BODY_FONT, BODY_EM)
    b_cap = ink_h(body, CAPS)
    band, cover = band_geometry(cell_h)
    em = max(int(band * TYPE_RATIO), 8)
    primary, _symbol, _nd = _faces(em)
    t_cap, typ, worst = ink_h(primary, CAPS), ink_h(primary, TYPICAL), ink_h(primary, WORST)
    ceiling = 8
    for e in range(8, 160):             # the largest em whose WORST-CASE ink still fits
        if ink_h(_faces(e)[0], WORST) <= band - BREATHE:
            ceiling = e
    ratio = worst / float(band)
    print("cell            %d device px   band %d px in a %d px placement (%d whole cell(s))"
          % (cell_h, band, cover, cover // cell_h))
    print("BODY   Monaco   em %-3d  cap %d px" % (BODY_EM, b_cap))
    print("TITLE  SF %-9s em %-3d  cap %d px   = %.2fx BODY" % (UI_VARIATION, em, t_cap,
                                                                t_cap / float(b_cap)))
    print("  ink: typical %d px · accented worst case %d px · band %d px (need %d spare)"
          % (typ, worst, band, BREATHE))
    print("  INK-TO-BAND: %.2f  (air %d px above and below the worst case)"
          % (ratio, (band - worst) // 2))
    print("  CEILING for this band: em %d — headroom %d em(s)" % (ceiling, ceiling - em))
    # THE TARGET IS AIR, NOT THE CEILING (2026-09-15). This used to demand `headroom <= 1`,
    # i.e. it asserted the exact crowding the operator then asked us to remove — a test
    # pinning the defect as the contract. The ceiling is still computed and printed, because
    # it is the bound that keeps a pathological title from clipping; it is no longer the
    # target. A header's label wants somewhere around half its band: below BREATHES_LO it is
    # a lost line in a slab, above BREATHES_HI it is pressed against its own container.
    # AIR IN PIXELS, NOT A RATIO OF THE BAND. A ratio was the second attempt and it rules
    # out the band heights the operator can actually choose between: the same 0.79 is
    # 6px of air at 58px and 19px at 90px, and 90px was rejected on sight. What he named
    # is the gap — "the text doesn't look oversized to its boundary container" — and the
    # gap is what the eye reads, so the gap is what is asserted. AIR_MIN 4 is comfortably
    # above the 1px this shipped with and comfortably below every candidate rendered.
    AIR_MIN = 4                         # device px of band above and below the worst ink
    OUTRANKS = 1.00                     # the label may not be SMALLER than the body's cap
    face_ok = os.path.basename(FONT_CANDIDATES[0]) != os.path.basename(BODY_FONT)
    fits = worst <= band - BREATHE
    air = (band - worst) // 2
    breathes = air >= AIR_MIN
    outranks = (t_cap / float(b_cap)) >= OUTRANKS
    whole = (cover % cell_h) == 0 and band <= cover
    print("VERDICT %s" % (
        "BREATHING (%dpx of air each side, >= %d) and OUTRANKING the body (%.2fx), in a "
        "register the body does not use, on a whole-cell placement"
        % (air, AIR_MIN, t_cap / float(b_cap))
        if (fits and breathes and outranks and face_ok and whole) else
        "FAILS: %s%s%s%s%s" % (
            "" if fits else "the accented worst case overflows; ",
            "" if breathes else "only %dpx of air each side, under %d; " % (air, AIR_MIN),
            "" if outranks else "the label is %.2fx the body cap, under %.2fx; " % (
                t_cap / float(b_cap), OUTRANKS),
            "" if face_ok else "same face as the body; ",
            "" if whole else "the placement is not a whole number of cells — the last row "
                             "would be part-painted and its glyph tops would read clipped")))
    return 0 if (fits and breathes and outranks and face_ok and whole) else 1


# ───────────────────────────── talking to kitty ──────────────────────────────

def ksock():
    """Resolve a socket `kitty @` can reach FROM A SUBPROCESS.

    KITTY_LISTEN_ON is NOT always a path. Inside `launch --type=background` kitty hands
    the child an inherited file descriptor — `fd:54` — and Python's subprocess closes
    non-standard fds, so `kitty @ --to fd:54` reaches nothing and every query returns
    empty. That is SILENT: the script finds no panes and paints none. KITTY_PID is not
    set on that launch either (measured), so ancestry is the route.

    Two further traps, both from matching a NAME instead of testing the thing:
    `/tmp/kitty-*` also matches leftover logs and screenshots (13 entries here, exactly
    ONE of them a socket), and `ps -o comm=` TRUNCATES at 16 chars, so kitty reads as
    "/Applications/ki" and any endswith("kitty") test fails. So: test for an actual
    socket, and identify the owner by ancestry, never by name.
    """
    import stat, subprocess

    def sock_for(pid):
        path = "/tmp/kitty-%s" % pid
        try:
            return path if stat.S_ISSOCK(os.stat(path).st_mode) else None
        except OSError:
            return None

    s = os.environ.get("KITTY_LISTEN_ON") or ""
    if s.startswith("unix:"):
        p = s[5:]
        try:
            if stat.S_ISSOCK(os.stat(p).st_mode):
                return p
        except OSError:
            pass
    got = sock_for(os.environ.get("KITTY_PID") or "")
    if got:
        return got
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
    import glob
    socks = [p for p in glob.glob("/tmp/kitty-*") if sock_for(p.rsplit("-", 1)[-1])]
    return socks[0] if len(socks) == 1 else None


def kitty_pid(sock):
    """The pid in the socket's own name. The daemon's whole lifetime hangs off this."""
    try:
        return int(os.path.basename(sock or "").rsplit("-", 1)[-1])
    except (ValueError, AttributeError):
        return 0


def kitty_ls(sock):
    import json, subprocess
    cmd = ["kitty", "@"] + (["--to", "unix:" + sock] if sock else []) + ["ls"]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
    except Exception:
        return []
    if out.returncode != 0:
        return []
    try:
        return json.loads(out.stdout)
    except ValueError:
        return []


_TTY_CACHE = {}


def pane_ttys(panes):
    """Every pane's tty, resolved ONCE per pane and then never again.

    Two measurements shaped this. Four separate `ps` calls cost 32ms — so batch. But ONE
    `ps` still costs 94.7ms on this machine, because the expense is spawning a process
    that walks the whole table, not the number of pids asked about. Batching alone
    therefore bought almost nothing, and the right number of lookups per pane is one.

    THE KEY IS (pane_id, pid), NOT pid — and the cache is PRUNED to the panes kitty just
    listed. A pid is reused within minutes on a busy machine, and this code's output is
    raw escape sequences written into a device file: a stale pid->tty mapping does not
    degrade, it paints an image into a stranger's terminal. A pane id plus the pid that
    was seen inside it cannot be re-minted by a reused pid alone, and pruning means a
    returning pid is re-resolved from scratch rather than answered from memory.
    """
    import subprocess
    live = set()
    missing = []
    for p in panes:
        k = (p.get("id"), p.get("pid"))
        if not k[0] or not k[1]:
            continue
        live.add(k)
        if k not in _TTY_CACHE:
            missing.append(k)
    for k in [k for k in _TTY_CACHE if k not in live]:
        del _TTY_CACHE[k]
    if missing:
        r = subprocess.run(["ps", "-o", "pid=,tty=",
                            "-p", ",".join(str(k[1]) for k in missing)],
                           capture_output=True, text=True)
        by_pid = {}
        for line in (r.stdout or "").splitlines():
            parts = line.split()
            if len(parts) >= 2 and parts[1] != "??":
                try:
                    by_pid[int(parts[0])] = "/dev/%s" % parts[1]
                except ValueError:
                    pass
        for k in missing:                   # remember the misses too, so a pane with no
            _TTY_CACHE[k] = by_pid.get(k[1])  # tty is not re-probed every single cycle
    return _TTY_CACHE


def tiocgwinsz(path):
    """Exact pane pixel size and therefore exact cell size — no assumed constants."""
    import fcntl, struct, termios
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


def _tty_write(tty, data, budget=0.03):
    """Write to a pane's tty without letting that pane stall the keypress.

    A blocking write here is not hypothetical. Bytes written to a pane's tty go into the
    output queue kitty drains, and a pane whose terminal is busy fills that queue: measured
    once in sixty presses, the daemon's socket round trip jumped from 1.9ms to 197ms, and
    the ~12KB strip write was where it sat. One busy pane must not be able to hold the
    chord, so the fd is opened NON-BLOCKING with a small budget — a pane that cannot take
    its strip simply does not get one this cycle, and the 0.35s hold loop offers it again.
    """
    import select, time as _t
    try:
        fd = os.open(tty, os.O_WRONLY | os.O_NONBLOCK)
    except OSError:
        return False
    try:
        end = _t.time() + budget
        i = 0
        while i < len(data):
            try:
                i += os.write(fd, data[i:])
            except BlockingIOError:
                left = end - _t.time()
                if left <= 0:
                    return False
                # WAIT, do not POLL. A 12KB strip does not fit one tty buffer, so a
                # sleep-retry loop spends the whole budget on every pane — measured, the
                # round trip went from 1.9ms to 161ms when this slept instead of selecting.
                if not select.select([], [fd], [], left)[1]:
                    return False
            except OSError:
                return False
        return True
    finally:
        os.close(fd)


def place(tty, png, img_id, budget=0.05):
    """Transmit+display at row 1 col 1, above the text, without moving the cursor.

    DELETE FIRST. kitty keys image DATA by id: transmitting new bytes under an id it
    already holds keeps the OLD image and ignores yours, with NO error. Two consecutive
    restyles once appeared to change nothing because every pane was still displaying the
    very first strip it had been given.
    """
    import base64
    b64 = base64.standard_b64encode(png)
    CH = 4096
    parts = [b"\0337\033[1;1H",                       # save cursor, home
             b"\033_Ga=d,d=I,i=%d,q=2\033\\" % img_id]
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
    parts.append(b"\0338")                            # restore cursor
    return _tty_write(tty, b"".join(parts), budget=budget)


def clear(tty, img_id, budget=0.04):
    _tty_write(tty, b"\033_Ga=d,d=I,i=%d,q=2\033\\" % img_id, budget=budget)


def targets(sock, all_windows):
    """(pane_id, title, tty, is_focused) for panes we should label."""
    found = []
    for w in kitty_ls(sock):
        for t in w.get("tabs", []):
            if not all_windows and not t.get("is_focused"):
                continue
            # A LONE PANE GETS A LABEL TOO. This used to `continue` on len < 2, on the
            # reasoning that a single pane needs no disambiguation — which answers a question
            # nobody asked. The label's job is not only "which of these is which"; it is also
            # "what is this session", and that is exactly as useful in one pane as in four.
            # Operator, 2026-09-14: the chord "doesn't work when there is only one split pane
            # in the window", and it was this line, silently, with no log and no error.
            found.extend(t.get("windows", []))
    ttys = pane_ttys(found)
    out = []
    for p in found:
        tty = ttys.get((p.get("id"), p.get("pid")))
        if tty:
            out.append((p["id"], (p.get("title") or "").strip() or "(untitled)", tty,
                        bool(p.get("is_focused"))))
    return out


def render(tg):
    """(tty, png, img_id) for every target — the whole cost of a paint, done ahead.

    YIELDS BETWEEN STRIPS. This runs on the daemon's refresh thread while the accept loop
    is waiting to answer a keypress, and PIL holds the GIL through a rasterise-and-encode.
    Without the yield a press that lands mid-cycle waits for the WHOLE cycle — measured at
    234ms against a 38ms median. With it, the worst case is one strip.
    """
    import time as _t
    frames = []
    for pid_, title, tty, live in tg:
        _t.sleep(0)
        g = tiocgwinsz(tty)
        if not g:
            continue
        band, cover = band_geometry(g["ch"])
        frames.append((tty, strip_png(int(g["xpx"]), band, title, live, cover),
                       IMG_BASE + (pid_ % 800)))
    return frames


def paint_frames(frames, budget=0.04):
    """Paint every pane, under ONE shared deadline.

    The budget is per PAINT, not per pane, because the thing being protected is the
    keypress and a keypress does not care which pane was slow. A pane that cannot take its
    strip inside the remaining time is simply skipped and offered it again 0.35s later by
    the hold loop — which is invisible — whereas eight panes each allowed to stall would
    not be. Measured: kitty occasionally stops draining its ttys for ~150ms, and without a
    shared deadline that lands on the press.
    """
    import time as _t
    end = _t.time() + budget
    n = 0
    for tty, png, iid in frames:
        left = end - _t.time()
        if left <= 0:
            break
        if place(tty, png, iid, budget=min(left, 0.05)):
            n += 1
    return n


def wipe(tg, budget=0.12):
    """Erase every strip, under one deadline — `off` is a keypress too."""
    import time as _t
    end = _t.time() + budget
    for pid_, _title, tty, _live in tg:
        left = end - _t.time()
        if left <= 0:
            break
        clear(tty, IMG_BASE + (pid_ % 800), budget=min(left, 0.04))


# ───────────────────────────── the daemon ────────────────────────────────────

def daemon(initial, all_windows):
    """Hold the pane list and the rendered strips warm so a keypress is only a tty write.

    THE REFRESH RUNS ON ITS OWN THREAD, and that is the whole point rather than a detail.
    A refresh is `kitty @ ls` plus, for a pane it has not seen, one `ps` — ~30ms and ~95ms,
    the two costs this daemon exists to keep off the keypress. Doing them on the accept
    loop simply MOVES them: measured, one press in five landed mid-refresh and took 293ms
    against 40ms for the others. So the loop that answers the socket never blocks on
    anything but `accept`, and the thread that does the talking never touches a tty.

    Lifetime is tied to ONE kitty process. It exits when that kitty dies — checked by
    `os.kill(pid, 0)`, which is free, rather than by a `kitty @` round trip, which is not
    — and it unlinks its socket on the way out. A daemon left behind by a dead kitty
    cannot paint anywhere, because every tty it knew died with that kitty, and the next
    chord's connect() to its stale socket file fails instantly with ECONNREFUSED.
    """
    import fcntl, socket, threading, time
    os.makedirs(AUTONOMY, exist_ok=True)
    lockfh = open(LOCK, "w")
    try:
        fcntl.flock(lockfh, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return 0                                # another daemon owns this; not an error
    sock = ksock()
    kpid = kitty_pid(sock)
    if not kpid:
        _log("daemon: no kitty socket; refusing to start")
        return 4
    try:
        os.unlink(SOCK)
    except OSError:
        pass
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(SOCK)
    srv.listen(8)

    # HOT while the titles are up or a press is recent; COLD after that. A refresh is a
    # `kitty @ ls` subprocess, so the cost of staying warm is fork/exec churn rather than
    # CPU (measured 0.2%), and forty spawns a minute forever on a busy machine is not a
    # thing to leave running for a key that may go unpressed for a day. The pane list can
    # be COLD_POLL stale at a press with no visible consequence: the hold loop re-warms
    # within HOT_POLL and the very next repaint covers anything that changed.
    HOLD, HOT_POLL, COLD_POLL, HOT_FOR = 0.35, 1.5, 15.0, 120.0
    IDLE_EXIT = 6 * 3600           # nobody has pressed it in six hours; the next press
                                   # respawns in ~400ms and this stops holding 31MB
    st = {"on": False, "all": all_windows, "tg": [], "frames": [],
          "touched": time.time()}
    stop = threading.Event()

    def warm(force=False):
        tg = targets(sock, st["all"])
        st["tg"], st["frames"] = tg, render(tg)
        if not tg and (st["on"] or force):
            _log("warm: no targets (sock=%r) — a pane query that returns nothing is the "
                 "SILENT failure mode, not a quiet success" % (sock,))

    def warm_loop():
        while not stop.is_set():
            try:
                warm()
            except Exception as e:              # a refresh must never kill the daemon
                _log("warm failed: %s" % e)
            hot = st["on"] or (time.time() - st["touched"]) < HOT_FOR
            stop.wait(HOT_POLL if hot else COLD_POLL)

    warm(force=True)
    t = threading.Thread(target=warm_loop, daemon=True)
    t.start()

    def turn_on():
        st["on"] = True
        paint_frames(st["frames"], budget=0.025)   # the keypress's whole share
        try:
            with open(STATE, "w") as fh:
                fh.write(str(os.getpid()))
        except OSError:
            pass

    def turn_off():
        st["on"] = False
        wipe(st["tg"])
        try:
            os.unlink(STATE)
        except OSError:
            pass

    if initial in ("toggle", "on"):
        turn_on()
    try:
        while True:
            try:
                os.kill(kpid, 0)                # our kitty; free liveness check
            except OSError:
                break
            if not st["on"] and time.time() - st["touched"] > IDLE_EXIT:
                break
            srv.settimeout(HOLD if st["on"] else 1.0)
            try:
                conn, _ = srv.accept()
            except (socket.timeout, OSError):
                conn = None
            if conn is not None:
                try:
                    conn.settimeout(0.5)
                    msg = conn.recv(64).decode("utf-8", "replace").strip()
                except OSError:
                    msg = ""
                cmd = msg.split()[0] if msg else ""
                st["touched"] = time.time()
                if "--all" in msg and not st["all"]:
                    st["all"] = True
                    try:
                        warm()
                    except Exception:
                        pass
                if cmd == "toggle":
                    cmd = "off" if st["on"] else "on"
                if cmd == "on":
                    turn_on()
                elif cmd == "off":
                    turn_off()
                try:
                    conn.sendall(b"ok\n")
                    conn.close()
                except OSError:
                    pass
                if cmd == "quit":
                    break
            elif st["on"]:
                paint_frames(st["frames"])      # hold: kitty frees a placement on any
                                                # clear or scroll and never says so
    finally:
        stop.set()
        if st["on"]:
            wipe(st["tg"])
        for path in (STATE, SOCK):
            try:
                os.unlink(path)
            except OSError:
                pass
        try:
            srv.close()
        except OSError:
            pass
    return 0


# ───────────────────────────── entry points ──────────────────────────────────

def cold(arg, all_windows):
    """No daemon, no socket: do the work here. Used by `once` and by --no-daemon."""
    sock = ksock()
    os.makedirs(AUTONOMY, exist_ok=True)
    if arg == "toggle":
        arg = "off" if os.path.exists(STATE) else "on"
    tg = targets(sock, all_windows)
    if not tg:
        _log("no targets: sock=%r — a pane query that returns nothing is the SILENT "
             "failure mode, not a quiet success" % (sock,))
    if arg == "off":
        try:
            os.unlink(STATE)
        except OSError:
            pass
        wipe(tg)
        return 0
    n = paint_frames(render(tg))
    if arg == "on":
        with open(STATE, "w") as fh:
            fh.write(str(os.getpid()))
    if arg == "once":
        print("painted %d pane(s)" % n)
    return 0


def main():
    argv = sys.argv[1:]
    arg = argv[0] if argv and not argv[0].startswith("-") else "toggle"
    all_windows = "--all" in argv

    if arg == "daemon":
        _ensure_pil()
        initial = ""
        for a in argv:
            if a.startswith("--initial="):
                initial = a.split("=", 1)[1]
        return daemon(initial, all_windows)

    if arg == "stop":
        print("ok" if _client("quit") else "no daemon")
        return 0

    if arg in ("toggle", "on", "off"):
        if "--no-daemon" not in argv:
            if _client(arg + (" --all" if all_windows else "")):
                return 0
            if _spawn_daemon(arg if arg != "off" else "off"):
                # `off` with no daemon has nothing to erase but a cold-path leftover, so
                # it still runs here; `on`/`toggle` are served by the daemon we just made.
                if arg == "off":
                    _ensure_pil()
                    return cold("off", all_windows)
                return 0
        _ensure_pil()
        return cold(arg, all_windows)

    if arg == "once":
        _ensure_pil()
        return cold("once", all_windows)

    if arg == "measure":
        _ensure_pil()
        cell = 45
        for a in argv:
            if a.startswith("--cell="):
                cell = int(a.split("=", 1)[1])
        return measure(cell)

    print("usage: kitty-pane-title-overlay.py "
          "[toggle|on|off|once|daemon|stop|measure] [--all] [--no-daemon]", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
