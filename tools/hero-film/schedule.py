#!/usr/bin/env python3
"""tools/hero-film/schedule.py: the hero film's edit lists, story keys and type schedule, from beat durations.

    python3 tools/hero-film/schedule.py           # print LOOP / FILM and their _STORY and _TYPE arrays
    python3 tools/hero-film/schedule.py --apply   # write them into tools/hero-film/film.js in place

Round two (README § Round 2) re-timed every beat against scripts/hero-film-pacing.py, and each flight's
length moves everything after it, so the numbers are derived here rather than typed: a flight's
duration comes from its image travel (1.875 x travel / ~860 px/s), a line's hold from its reading time.
Change a duration here, --apply, then `npm run hero:pacing`; the gate, not this file, is the judge.

The rules it encodes: story moves inside a flight only after the first 12 % and before the last 12 %
(the camera is under way; calm frames need a standing line); type leaves in a flight's first 13 % and
arrives in its last 13 % (the picture is under 250 px/s there); each line is read (reading time + 0.3 s)
before the story moves under it.
"""
import pathlib
import sys

R = lambda x: round(x, 2)
S = dict(start='S.start', clear='S.clear')
def flight_edges(t0, T):  # story may move only once under way; type moves only while slow
    return R(t0 + 0.12 * T), R(t0 + T - 0.12 * T), R(t0 + 0.13 * T), R(t0 + T - 0.13 * T)

def window_scene(a, story, typ):
    story += [(R(a + 2.9), 'S.clear'), (R(a + 3.05), '0'), (R(a + 6.35), '3.3'), (R(a + 11.55), '3.3'), (R(a + 13.05), 'S.card[1]')]
    typ += [("split", R(a - 0.6), R(a + 0.1), R(a + 7.75), R(a + 8.35)), ("decide", R(a + 8.35), R(a + 9.05))]
    return R(a + 20.25)

def build(cut):
    E, story, typ = [], [(0, 'S.start')], []
    T1 = 3.4
    E.append(dict(frm=0, to=5.0, cam='poster', drift='posterIn' if cut == 'film' else None, poster=True))
    typ.append(("thought", None, None, 5.0, R(5.0 + 0.13 * T1)))
    s0, s1, _, _ = flight_edges(5.0, T1)
    story += [(s0, 'S.start'), (R(s0 + 0.4), 'S.clear')]
    E.append(dict(frm=5.0, to=R(5.0 + T1), fly="{ hop: 0.3 }"))
    a = R(5.0 + T1)
    b = window_scene(a, story, typ)
    E.append(dict(frm=a, to=b, cam='window', drift='windowB' if cut == 'film' else None, chip="['peer']"))
    typ[-1] = typ[-1] + (b, R(b + 0.6))
    if cut == 'loop':
        T2 = 4.4
        m0, m1, _, _ = flight_edges(b, T2)
        story += [(m0, 'S.card[1]'), (m1, 'S.stale[1]')]
        E.append(dict(frm=b, to=R(b + T2), fly="{ hop: 0.9, viaAt: [0, 4, 0] }", note="After the peer's commit: up off the window, over its line and the gate, down origin/main."))
        c = R(b + T2)
    else:
        T2 = 4.2
        m0, m1, _, _ = flight_edges(b, T2)
        story += [(m0, 'S.card[1]'), (m1, '4.9')]
        E.append(dict(frm=b, to=R(b + T2), fly="{ hop: 0.3 }"))
        g = R(b + T2)
        story += [(R(g + 4.1), '4.9'), (R(g + 8.5), 'S.stale[0]')]
        typ.append(("gate", R(g - 0.13 * T2), R(g + 0.1), R(g + 8.6), R(g + 9.1)))
        h = R(g + 8.6)
        E.append(dict(frm=g, to=h, cam='gate', drift='gateB', chip="['force', 'denied', 'accounts']"))
        T3 = 4.2
        m0, m1, _, _ = flight_edges(h, T3)
        story += [(m0, 'S.stale[0]'), (m1, 'S.stale[1]')]
        E.append(dict(frm=h, to=R(h + T3), fly="{ hop: 0.3 }"))
        c = R(h + T3)
    Tin = T2 if cut == 'loop' else T3
    typ.append(("racks", R(c - 0.13 * Tin), R(c + 0.1)))
    story += [(R(c + 3.8), 'S.stale[1]'), (R(c + 5.85), 'S.lit[1]')]
    d = R(c + 6.95)
    E.append(dict(frm=c, to=d, cam='racks', drift='racksB' if cut == 'film' else None, chip="['verified', 'deploy']"))
    typ[-1] = typ[-1] + (d, R(d + 0.6))
    T4 = 4.6 if cut == 'loop' else 5.0
    m0, m1, _, _ = flight_edges(d, T4)
    story += [(m0, 'S.lit[1]'), (m1, 'S.END')]
    E.append(dict(frm=d, to=R(d + T4), fly="{ hop: 0.6 }", rekey=cut == 'loop', note=None))
    e = R(d + T4)
    end = R(e + 1.3) if cut == 'loop' else R(e + 5.5)
    typ.append(("thought", R(e - 0.7), R(e + 0.1), None, None))
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
