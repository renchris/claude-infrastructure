#!/usr/bin/env python3
"""hero-film-pacing.py: gate the hero film's pacing, per frame, on numbers rather than an eye.

    python3 scripts/hero-film-pacing.py PACING.json [PACING.json ...] [--baseline]

PACING.json is the page's own report (node scripts/hero-film-capture.mjs --cut loop --probe FILE):
one row per 1/60 s with the camera's image flow over a 3 x 3 grid at the subject's depth, its
direction and position, the story clock, and each piece of type's visibility and motion.

The operator's verdict on round one (2026-09-25): "everything moves and jars so fast I don't feel
oriented nor I can read anything in time". So two families of rule, each a hard bound:

MOTION, every frame, both cuts. The picture may not slide faster than MAX_FLOW (px per second at 1920
wide, the fastest of nine grid points at the subject's depth), no named object on screen (a window,
a gate post, a rack, the card; weighted down over the frame's outer 150 px, where it is peripheral)
may sweep faster than MAX_SWEEP, the camera may not turn faster than MAX_TURN, and the
picture's speed (the RMS of the grid) may not change faster than MAX_ACCEL, which is what "eased in and out" means as a
number: a flight has to start from rest and build up speed over about a second, and stop the same way.
Type may not move (arrive or leave) while the picture moves faster than TYPE_FLOW.

READING, every piece of type (a line, the governing thought, a chip, the decision card). Its reading
time is READ_BASE + READ_WORD per word + READ_CODE per code token (a token of a monospace string); the
card counts as type only while it is at least CARD_W px wide on screen (smaller, it is an object). It
must stand fully visible and still, with the camera calm (image flow under CALM), for at least that
long. A line must also stand QUIET s before its scene's story clock starts to move (round two demanded
its whole reading time there, which is most of what made round two "universally slow"; the viewer
reads on while the scene plays under the line, and the line still stands its full reading time).
The thought on the loop's frame 0 keeps the full rule: a first visit reads it before anything moves. And no story action may play on a calm frame without a
line standing still to name it. In the loop, frame 0 must already hold the thought for its reading
time (a first visit starts there), and a piece of type that stands across the seam is timed across it.

--baseline prints the tables and the violations but exits 0 (the round-one ruler).
"""

import json
import math
import sys
from pathlib import Path

# Round 3 (operator, 2026-09-25: round two was "just universally slow"; round one "jars so fast"). The
# bounds sit between the two measured rounds: round one peaked at 7,044 px/s, round two at 865.
MAX_FLOW = 2000.0  # px/s at 1920 wide: about one frame width a second, 33 px a frame at 60 fps
MAX_SWEEP = 3000.0  # px/s: the fastest named object on screen (window, gate post, rack, card corner)
MAX_TURN = 40.0  # deg/s of view direction
MAX_ACCEL = 4500.0  # px/s^2 of image speed: still eased, ~0.8 s from rest to full speed, and back
CALM = 60.0  # px/s: slower than this the picture is holding (the film's creep is slower still)
TYPE_FLOW = 400.0  # px/s: type arrives and leaves only while the picture is slower than this
QUIET = 1.2  # s: a line stands this long before the story moves under it (round two: its whole reading time)
CARD_W = 400.0  # px at 1920: the card's body text is ~11 CSS px at the README's 838 px from here up
CHIP_V = 90.0  # px/s: a chip may ride its object this fast and still be read
STILL_MOVE = 0.5  # px: a word displaced further than this is still arriving or leaving
FULL = 0.99  # opacity
READ_BASE, READ_WORD, READ_CODE = 1.0, 0.3, 0.5  # s
STORY_EPS = 1e-6


def words(s):
    return [w for w in s.split() if any(ch.isalnum() for ch in w)]


def reading_time(text):
    return (
        READ_BASE
        + READ_WORD * len(words(text["prose"]))
        + READ_CODE * len(words(text["code"]))
    )


def angle(a, b):
    d = sum(x * y for x, y in zip(a, b)) / (math.hypot(*a) * math.hypot(*b))
    return math.degrees(math.acos(max(-1.0, min(1.0, d))))


def runs(mask, cyclic):
    """Maximal runs of True as (start, length) over indices, joined across the end when cyclic."""
    n = len(mask)
    out = []
    i = 0
    while i < n:
        if mask[i]:
            j = i
            while j < n and mask[j]:
                j += 1
            out.append([i, j - i])
            i = j
        else:
            i += 1
    if cyclic and len(out) > 1 and out[0][0] == 0 and out[-1][0] + out[-1][1] == n:
        last = out.pop()
        out[0] = [last[0], last[1] + out[0][1]]
    elif cyclic and len(out) == 1 and out[0][1] == n:
        pass
    return out


def check(path, baseline):
    R = json.loads(Path(path).read_text())
    fr = R["frames"]
    fps = R["fps"]
    n = len(fr)
    cyclic = R["cut"] == "loop"
    dt = 1.0 / fps
    nxt = lambda i: (i + 1) % n if cyclic else min(i + 1, n - 1)
    # The picture's speed at the subject's depth (the grid), and separately the fastest named object
    # on screen (the sweep), so a post the camera skims past is caught even when the scene is slow.
    flow = [max(f["flow"]) * fps for f in fr]
    sweep = [f.get("sweep", 0) * fps for f in fr]
    turn = [angle(fr[i]["fwd"], fr[nxt(i)]["fwd"]) * fps for i in range(n)]
    travel = [math.dist(fr[i]["p"], fr[nxt(i)]["p"]) * fps for i in range(n)]
    # Acceleration of the whole picture's speed: the RMS of the nine grid points. A max kinks whenever the
    # fastest point changes (and the object sweep steps as objects enter and leave), which a finite
    # difference reads as a jolt the camera never made.
    rms = [math.sqrt(sum(v * v for v in f["flow"]) / len(f["flow"])) * fps for f in fr]
    accel = [abs(rms[nxt(i)] - rms[i]) * fps for i in range(n)]
    ds = [(fr[nxt(i)]["s"] - fr[i]["s"]) for i in range(n)]
    if cyclic:
        ds[-1] = (
            0.0  # the story wraps from END to start across the seam; the camera holds the poster
        )
    calm = [v <= CALM for v in flow]
    bad = []

    print(
        f"\n== {Path(path).name}: {R['cut']} / {R['theme']}, {R['duration']:.2f} s, {n} frames at {fps} fps =="
    )
    # -- motion, per edit that moves the camera (a loop flight, or every film edit)
    print(
        "\nMOTION  (image flow px/s at 1920 wide; turn deg/s; travel units/s; accel px/s^2)"
    )
    print(
        f"{'span':>13}  {'kind':<22} {'dur':>5}  {'flow max':>8} {'x frame/s':>9} {'turn max':>8} {'travel':>7} {'accel':>7} {'v in':>6} {'v out':>6}"
    )
    for k, ed in enumerate(R["edits"]):
        idx = [i for i, f in enumerate(fr) if f["edit"] == k]
        if not idx:
            continue
        a, b = idx[0], idx[-1]
        fmax = max(flow[i] for i in idx)
        smax = max(sweep[i] for i in idx)
        if not ed["fly"] and fmax <= CALM and R["cut"] == "loop":
            continue
        kind = (
            f"fly {ed['fly'][0]}->{ed['fly'][1]}"
            if ed["fly"]
            else (ed["cam"] or ed["line"] or ("poster" if ed["poster"] else "edit"))
        )
        near = min(fr[i].get("near", 99) for i in idx)
        print(
            f"{ed['from']:6.2f}-{ed['to']:5.2f}  {kind:<22} {ed['to'] - ed['from']:5.2f}  {fmax:8.0f} {fmax / 1920:9.2f} sweep {smax:5.0f} near {near:5.1f} "
            f"{max(turn[i] for i in idx):8.1f} {max(travel[i] for i in idx):7.2f} {max(accel[i] for i in idx):7.0f} "
            f"{flow[(a - 1) % n]:6.0f} {flow[b]:6.0f}"
        )
    for name, series, lim, unit in (
        ("image flow", flow, MAX_FLOW, "px/s"),
        ("sweep", sweep, MAX_SWEEP, "px/s"),
        ("turn", turn, MAX_TURN, "deg/s"),
        ("accel", accel, MAX_ACCEL, "px/s^2"),
    ):
        worst = max(range(n), key=lambda i: series[i])
        over = sum(1 for v in series if v > lim)
        verdict = "ok" if over == 0 else "FAIL"
        print(
            f"  {name:<10} max {series[worst]:8.1f} {unit:<6} at t={fr[worst]['t']:6.2f}   bound {lim:6.0f}   frames over: {over:4d}  {verdict}"
        )
        if over:
            bad.append(
                f"{name}: {over} frame(s) over {lim:.0f} {unit} (max {series[worst]:.0f} at t={fr[worst]['t']:.2f})"
            )

    # -- reading, per piece of type
    print(
        "\nREADING  (need = reading time; still = fully visible, not moving, camera calm; quiet = still before the story moves)"
    )
    print(
        f"{'unit':<18} {'on at':>6} {'off at':>6} {'need':>5} {'still':>6} {'quiet':>6} {'margin':>7}  verdict"
    )
    units = list(R["texts"].keys())
    min_margin = (math.inf, "")
    for u in units:
        text = R["texts"][u]
        need = reading_time(text)
        if u == "card":
            vis = [
                f["card"]["a"]
                if f["card"] and f["card"]["w"] >= CARD_W and f["card"]["at"] and 0 <= f["card"]["at"][0] <= 1920 and 0 <= f["card"]["at"][1] <= 1080
                else 0.0
                for f in fr
            ]
            pos = [
                (f["card"]["at"] if f["card"] and f["card"]["at"] else None) for f in fr
            ]
            move = [0.0] * n
        else:
            vis = [f["units"][u][0] for f in fr]
            move = [f["units"][u][1] for f in fr]
            pos = [f["units"][u][2:4] for f in fr]
        is_line = u == "thought" or u.startswith("line:")
        speed = [0.0] * n
        if not is_line:
            for i in range(n):
                j = nxt(i)
                if (
                    pos[i] is not None
                    and pos[j] is not None
                    and vis[i] >= FULL
                    and vis[j] >= FULL
                ):
                    speed[i] = math.dist(pos[i], pos[j]) * fps
        still = [
            vis[i] >= FULL
            and move[i] <= STILL_MOVE
            and calm[i]
            and (is_line or speed[i] <= CHIP_V)
            for i in range(n)
        ]
        for start, length in runs([v > 0.01 for v in vis], cyclic):
            occ = [(start + k) % n for k in range(length)]
            occ_set = set(occ)
            best = (0, None)
            for s0, ln in runs(still, cyclic):
                if (s0 % n) in occ_set and ln > best[0]:
                    best = (ln, s0)
            st_len = best[0] * dt
            quiet = st_len
            if best[1] is not None:
                for k in range(best[0]):
                    if ds[(best[1] + k) % n] > STORY_EPS:
                        quiet = k * dt
                        break
            ok_still = st_len + 1e-9 >= need
            q_need = min(need, QUIET)
            ok_quiet = (not is_line) or quiet + 1e-9 >= q_need
            margin = min(st_len - need, quiet - q_need) if is_line else st_len - need
            if margin < min_margin[0]:
                min_margin = (margin, f"{u} at {fr[occ[0]]['t']:.2f}")
            verdict = "ok" if ok_still and ok_quiet else "FAIL"
            print(
                f"{u:<18} {fr[occ[0]]['t']:6.2f} {fr[occ[-1]]['t'] + dt:6.2f} {need:5.1f} {st_len:6.2f} {quiet if is_line else float('nan'):6.2f} {margin:+7.2f}  {verdict}"
            )
            if not ok_still:
                bad.append(
                    f"{u} at {fr[occ[0]]['t']:.2f}: still {st_len:.2f} s < reading time {need:.2f} s"
                )
            elif not ok_quiet:
                bad.append(
                    f"{u} at {fr[occ[0]]['t']:.2f}: the story moves {quiet:.2f} s after it settles, before its reading time {need:.2f} s"
                )
        if u == "thought" and cyclic:
            head = 0
            while head < n and still[head]:
                head += 1
            quiet0 = next((k for k in range(head) if ds[k] > STORY_EPS), head) * dt
            ok = quiet0 + 1e-9 >= need
            print(
                f"{'thought @ frame 0':<18} {0.0:6.2f} {head * dt:6.2f} {need:5.1f} {head * dt:6.2f} {quiet0:6.2f} {quiet0 - need:+7.2f}  {'ok' if ok else 'FAIL'}"
            )
            if not ok:
                bad.append(
                    f"frame 0 holds the thought still for {quiet0:.2f} s < its reading time {need:.2f} s"
                )
            if quiet0 - need < min_margin[0]:
                min_margin = (quiet0 - need, "thought from frame 0")

    def spans(idx):
        out = []
        for i in idx:
            if out and i == out[-1][1] + 1:
                out[-1][1] = i
            else:
                out.append([i, i])
        return ", ".join(f"{fr[a]['t']:.2f}-{fr[b]['t'] + dt:.2f}" for a, b in out[:6])

    # -- type moves only while the camera is slow
    line_units = [u for u in units if u == "thought" or u.startswith("line:")]
    moving = [
        i
        for i in range(n)
        if flow[i] > TYPE_FLOW
        and any(
            fr[i]["units"][u][0] > 0.01 and (fr[i]["units"][u][0] < FULL or fr[i]["units"][u][1] > STILL_MOVE)
            for u in line_units
        )
    ]
    print(f"\n  frames where a line moves while the picture moves faster than {TYPE_FLOW:.0f} px/s: {len(moving)}  {'ok' if not moving else 'FAIL ' + spans(moving)}")
    if moving:
        bad.append(f"{len(moving)} frame(s) of type moving while the camera is fast ({spans(moving)})")

    # -- no action without a line naming it
    named = [
        any(
            fr[i]["units"][u][0] >= FULL and fr[i]["units"][u][1] <= STILL_MOVE
            for u in line_units
        )
        for i in range(n)
    ]
    unnamed = [i for i in range(n) if calm[i] and ds[i] > STORY_EPS and not named[i]]
    print(
        f"  calm frames where the story moves with no line standing: {len(unnamed)}  {'ok' if not unnamed else 'FAIL ' + spans(unnamed)}"
    )
    if unnamed:
        bad.append(
            f"{len(unnamed)} calm frame(s) of story action with no line standing (first at t={fr[unnamed[0]]['t']:.2f})"
        )
    print(
        f"  max image flow {max(flow):.0f} px/s ({max(flow) / 1920:.2f} frame/s), max turn {max(turn):.1f} deg/s, min reading margin {min_margin[0]:+.2f} s ({min_margin[1]})"
    )
    return bad


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    baseline = "--baseline" in sys.argv
    if not args:
        sys.exit(__doc__)
    bad = []
    for a in args:
        bad += [f"{Path(a).name}: {b}" for b in check(a, baseline)]
    print()
    if bad:
        print("PACING FAIL")
        for b in bad:
            print(f"  - {b}")
        sys.exit(0 if baseline else 1)
    print("PACING PASS")


if __name__ == "__main__":
    main()
