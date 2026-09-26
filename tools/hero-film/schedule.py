#!/usr/bin/env python3
"""tools/hero-film/schedule.py: the hero film's edit lists, story keys and type schedule, from beat durations.

    python3 tools/hero-film/schedule.py           # print LOOP / FILM and their _STORY and _TYPE arrays
    python3 tools/hero-film/schedule.py --apply   # write them into tools/hero-film/film.js in place

Round three (README § Round 3) re-timed every beat again, against the operator's fourth verdict: round
two was "just universally slow". Each flight's length moves everything after it, so the numbers are
derived here rather than typed: a flight's duration comes from its image travel (1.875 x travel / 1,800
px/s, never under 1.6 s; round two used ~860 px/s), a line's hold from its reading time.
Change a duration here, --apply, then `npm run hero:pacing`; the gate, not this file, is the judge.

The rules it encodes: story moves inside a flight only after the first 12 % and before the last 12 %
(the camera is under way; calm frames need a standing line); type leaves in a flight's first 13 % and
arrives in its last 13 % (the picture is slow there); a line stands QUIET s (1.2) before the story moves
under it, and stays until every piece of type in its scene has had its reading time.
"""
import pathlib
import sys

R = lambda x: round(x, 2)
S = dict(start='S.start', clear='S.clear')
def flight_edges(t0, T):  # story may move only once under way; type moves only while slow
    return R(t0 + 0.12 * T), R(t0 + T - 0.12 * T), R(t0 + 0.13 * T), R(t0 + T - 0.13 * T)

QUIET = 1.2  # s a line stands before the story moves under it (round two: its whole reading time)
ARRIVE = 0.5  # s into a hold that a line finishes arriving (it starts in the flight's last 13 %)
LEAVE = 0.3  # s before a flight that a line starts leaving (it is gone by the flight's first 13 %)


def fly_time(travel):  # a flight's duration from its image travel (window.__moveL), at ~1,800 px/s peak
    return max(1.6, R(1.875 * travel / 1800))


def line(key, a, T_in, b, T_out):  # a line over the hold [a, b], arriving from the flight before
    return (key, R(a - 0.13 * T_in) if T_in else None, R(a + ARRIVE) if T_in else None,
            R(b - LEAVE) if T_out else None, R(b + 0.13 * T_out) if T_out else None)


def build(cut):
    E, story, typ = [], [(0, 'S.start')], []
    T1 = fly_time(1237)
    P = 5.1  # the poster: frame 0 holds the thought for its reading time (4.5 s) before it leaves
    E.append(dict(frm=0, to=P, cam='poster', drift='posterIn' if cut == 'film' else None, poster=True))
    typ.append(line("thought", 0, None, P, T1))
    s0, s1, _, _ = flight_edges(P, T1)
    story += [(s0, 'S.start'), (R(s0 + 0.6 * (T1 - 0.24 * T1)), 'S.clear')]  # the card and scrollback fade, not cut
    E.append(dict(frm=P, to=R(P + T1), fly="{ hop: 0.3 }"))
    a = R(P + T1)
    L0 = a + ARRIVE
    # The split: read the line for QUIET s, then the story plays 1:1 (the split, the boot, the brief);
    # the peer's chip (~2.7 s to read) is fully in ~3.25 s after the line lands.
    story += [(R(L0 + QUIET), 'S.clear'), (R(L0 + QUIET + 0.15), '0'), (R(L0 + QUIET + 3.45), '3.3')]
    split_off = R(L0 + 6.4)
    typ.append(line("split", a, T1, split_off, 0) [:3] + (split_off, R(split_off + 0.6)))
    d0 = R(split_off + 0.6)  # the decision's line arrives as the split's leaves
    typ.append(("decide", d0, R(d0 + 0.7)))
    # The card: QUIET s after its line lands it rises (1.5 s), then stands for its 7.0 s of reading.
    story += [(R(d0 + 0.7 + QUIET), '3.3'), (R(d0 + 0.7 + QUIET + 1.5), 'S.card[1]')]
    b = R(d0 + 0.7 + QUIET + 1.5 + 7.5)
    E.append(dict(frm=a, to=b, cam='window', drift='windowB' if cut == 'film' else None, chip="['peer']"))
    if cut == 'loop':
        T2 = fly_time(2480)
        m0, m1, _, _ = flight_edges(b, T2)
        # The racks turn amber by 60 % of the flight, while still distant, not as the camera settles.
        story += [(m0, 'S.card[1]'), (R(b + 0.6 * T2), 'S.stale[1]')]
        typ[-1] = typ[-1] + (R(b - LEAVE), R(b + 0.13 * T2))
        E.append(dict(frm=b, to=R(b + T2), fly="{ hop: 0.9, viaAt: [0, 4, 0] }", note="After the peer's commit: up off the window, over its line and the gate, down origin/main."))
        c = R(b + T2)
        Tin = T2
    else:
        T2 = max(2.0, fly_time(1464))  # it swings ~64 degrees round the fleet: at 1.6 s it turned 40 deg/s
        m0, m1, _, _ = flight_edges(b, T2)
        story += [(m0, 'S.card[1]'), (m1, '4.9')]
        typ[-1] = typ[-1] + (R(b - LEAVE), R(b + 0.13 * T2))
        # Pulled out and lifted, so the near fleet panes pass below the lens (critique round 3, m9).
        E.append(dict(frm=b, to=R(b + T2), fly="{ hop: 0.5, rise: 0.25 }"))
        g = R(b + T2)
        # The gate: read QUIET s, then three lands, the refused force push, the peer's commit (4.4 s).
        story += [(R(g + ARRIVE + QUIET), '4.9'), (R(g + ARRIVE + QUIET + 4.4), 'S.stale[0]')]
        h = R(g + ARRIVE + QUIET + 4.4 + 0.5)
        T3 = fly_time(1851)
        typ.append(line("gate", g, T2, h, T3))
        E.append(dict(frm=g, to=h, cam='gate', drift='gateB', chip="['force', 'denied', 'accounts']"))
        m0, m1, _, _ = flight_edges(h, T3)
        story += [(m0, 'S.stale[0]'), (m1, 'S.stale[1]')]
        E.append(dict(frm=h, to=R(h + T3), fly="{ hop: 0.3 }"))
        c = R(h + T3)
        Tin = T3
    # ~/.claude: read QUIET s, then verified, deploy-live.sh, the files turn green (2.05 story s in 2.2);
    # the verified chip (2.5 s to read) is in ~0.4 s after the story starts.
    story += [(R(c + ARRIVE + QUIET), 'S.stale[1]'), (R(c + ARRIVE + QUIET + 2.2), 'S.lit[1]')]
    d = R(c + ARRIVE + QUIET + 0.4 + 2.5 + 0.4)
    T4 = fly_time(2387 if cut == 'loop' else 2462)
    typ.append(line("racks", c, Tin, d, T4))
    E.append(dict(frm=c, to=d, cam='racks', drift='racksB' if cut == 'film' else None, chip="['verified', 'deploy']"))
    m0, m1, _, _ = flight_edges(d, T4)
    story += [(m0, 'S.lit[1]'), (m1, 'S.END')]
    E.append(dict(frm=d, to=R(d + T4), fly="{ hop: 0.6 }", rekey=cut == 'loop', note=None))
    e = R(d + T4)
    end = R(e + ARRIVE + 0.3) if cut == 'loop' else R(e + 5.2)
    typ.append(("thought", R(e - 0.13 * T4), R(e + ARRIVE), None, None))
    E.append(dict(frm=e, to=end, cam='posterOut' if cut == 'film' else 'poster', drift='poster' if cut == 'film' else None, poster=True))
    story.append((end, 'S.END'))
    return E, story, typ

def js(cut):
    E, story, typ = build(cut)
    N = cut.upper()
    out = [f"const {N} = ["]
    for x in E:
        if x.get('note'): out.append(f"  // {x['note']}")
        if x.get('rekey'):
            out.append("  // REKEY: this flight's background is two levels off (invisible), so every pixel of the poster that")
            out.append("  // follows differs from the frame before it and the encoder re-sends the poster whole (sister repo).")
        parts = [f"from: {x['frm']}", f"to: {x['to']}"]
        if x.get('cam'): parts.append(f"cam: '{x['cam']}'")
        if x.get('drift'): parts.append(f"drift: '{x['drift']}'")
        if x.get('fly'): parts.append(f"fly: {x['fly']}")
        if x.get('fly') and cut == 'loop': parts.append("blur: true")
        if x.get('rekey'): parts.append("rekey: true")
        if x.get('poster'): parts.append("poster: true")
        if x.get('chip'): parts.append(f"chip: {x['chip']}")
        out.append("  { " + ", ".join(parts) + " },")
    out.append("]")
    out.append(f"const {N}_STORY = [")
    row = []
    for t, s in story:
        row.append(f"[{t}, {s}]")
    for i in range(0, len(row), 5): out.append("  " + ", ".join(row[i:i + 5]) + ",")
    out.append("]")
    out.append(f"const {N}_TYPE = [")
    for k, i0, i1, o0, o1 in typ:
        parts = [f"key: '{k}'"]
        if i0 is not None: parts.append(f"in: [{i0}, {i1}]")
        if o0 is not None: parts.append(f"out: [{o0}, {o1}]")
        out.append("  { " + ", ".join(parts) + " },")
    out.append("]")
    return "\n".join(out)


def apply():
    film = pathlib.Path(__file__).with_name("film.js")
    s = film.read_text()
    for cut in ("loop", "film"):
        gen = js(cut)
        name = cut.upper()
        for part in (f"const {name} = [", f"const {name}_STORY = [", f"const {name}_TYPE = ["):
            a = s.index(part)
            b = s.index("\n]\n", a) + 3
            g = gen[gen.index(part):]
            g = g[: g.index("\n]") + 2] + "\n"  # the last array has no newline after it in js()
            s = s[:a] + g + s[b:]
    film.write_text(s)
    print(f"wrote {film}")


if __name__ == "__main__":
    if "--apply" in sys.argv:
        apply()
    else:
        print(js("loop"))
        print(js("film"))
