#!/usr/bin/env python3
"""RED-proof every build-time gate in tools/banner/gen.py.

A guard that has never been observed to fire is a guess. Worse, on this branch it is a guess with a
track record: TWO assertions here were written, reviewed, committed and never ran — one because a
formatter had already turned the patch anchor's quotes around so the wiring edit no-opped, and a
green build caught neither time. So this script proves BOTH halves for every gate:

  * FIRES  — sabotage the input, require the specific gate to reject it, by MESSAGE and not merely by
             a non-zero exit. Keying on the exit status alone lets an unrelated earlier failure
             counterfeit the proof, which is how a skip comes to read as a pass.
  * WIRED  — `assert_all_gates_wired` reads build()'s own source, and case 1 below proves that guard
             itself detects an unwired assertion.

    scripts/banner-gate-redproof.py            # all cases
    scripts/banner-gate-redproof.py --list     # just the case names

Exit 0 = every gate fired for the right reason. Non-zero names the ones that did not.
"""

from __future__ import annotations

import argparse
import copy
import importlib.util
import re
import subprocess
import sys
from contextlib import contextmanager
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GEN = ROOT / "tools" / "banner" / "gen.py"


def load():
    spec = importlib.util.spec_from_file_location("banner_gen", GEN)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    # Registered BEFORE exec: @dataclass resolves its own class's module out of sys.modules, so a
    # gen.py loaded by path alone dies inside the decorator rather than anywhere near the cause.
    sys.modules["banner_gen"] = mod
    spec.loader.exec_module(mod)
    return mod


g = load()


@contextmanager
def sandbox():
    """Restore every global this suite mutates, so one case cannot contaminate the next.

    Deep-copied: RARE_EVENTS and WORLD_MOD are nested containers, and a shallow save would hand the
    next case a table a previous one had already edited in place — the whole suite would then be
    testing an accumulation of sabotage rather than one variable at a time.
    """
    names = [
        "RARE_EVENTS",
        "WORLD_MOD",
        "BAR_LEN",
        "HOP_PERIOD",
        "HOP_FROM_PCT",
        "HOP_TO_PCT",
        "HOP_RISE",
        "HOP_FALL",
        "print_ink",
        "assert_world_rates_integral",
        "BUDGET_WAIVED",
        "css",
    ]
    saved = {n: copy.deepcopy(getattr(g, n)) for n in names}
    try:
        yield
    finally:
        for n, v in saved.items():
            setattr(g, n, v)
        g._SCROLLING.clear()
        g._WARPED.clear()
        g._ENCODED_STRIP.clear()


def v(key: str = "v6a"):
    return next(a for a in g.VARIANTS if a.key.startswith(key))


# ── the cases ──────────────────────────────────────────────────────────────────────────────────
# Each returns None and must raise SystemExit carrying `want`.
CASES: list[tuple[str, str, object]] = []


def case(name: str, want: str):
    def deco(fn):
        CASES.append((name, want, fn))
        return fn

    return deco


@case("wiring: an assertion defined but never called", "DEFINED BUT NEVER CALLED")
def _wiring():
    # The exact shape of the S12 defect: the function exists, review sees it, nothing calls it.
    g.assert_nothing_calls_me = lambda: None
    try:
        g.build(v())
    finally:
        del g.assert_nothing_calls_me


@case("world: a fractional rate", "fractional world rate")
def _frac_rate():
    g.WORLD_MOD["rAsk"] = ((0, 12, 0), (12, 6, 2.5))
    g.build(v())


@case("world: a modulation outside its declared window", "modulates the world over")
def _outside():
    g.WORLD_MOD["rAsk"] = ((0, 12, 0), (12, 6, 3), (30, 2, 0))
    g.build(v())


@case("world: a stop that is never repaid", "behind nominal")
def _unbalanced():
    g.WORLD_MOD["rAsk"] = ((0, 12, 0),)
    g.build(v())


@case("world: two rates claiming one instant", "world modulations overlap")
def _overlapping_mods():
    g.WORLD_MOD["rAsk"] = ((0, 12, 0), (6, 6, 3))
    g.build(v())


@case("world: a stop deeper than the pad copy", "past the")
def _past_pad():
    # Proves assert_warp_within_tile: 41 strides of dead world is 1968px, past the 1920px pad.
    # THE ASK keeps its real 26.0s start, so its modulation begins after THE REFUSAL's ends at 21.0s
    # — `world_segments` refuses two rates for one instant, and moving the beat back to 13.0s made
    # it swallow THE REFUSAL and convict on that gate instead of this one.
    # Called directly: the duty budget would reject a window this wide first, and this gate is about
    # the pad, not the budget.
    g.RARE_EVENTS["rAsk"] = (26.0, 67.0)
    g.WORLD_MOD["rAsk"] = ((0, 41, 0), (41, 41, 2))
    g.assert_warp_within_tile()


@case("world: the print lock, under a rate that unlocks it", "FOOTPRINT LOCK BROKEN")
def _print_lock():
    # Proves assert_print_lock. THE ASK keeps its real 26.0-35.0s window — re-timing it to 13.0s put
    # it hard against THE SUMMONING's 13.0s end and the disjointness gate convicted first. The mods
    # stay inside the declared window (26.0-32.0s) and repay their own debt, so the ONE thing wrong
    # with this build is the fractional 1.5x rate.
    # The integral-rate gate normally catches this first, so it is neutered to let the input reach
    # the lock. That is the point: the lock must be able to convict on its own evidence, not inherit
    # a verdict from the guard upstream of it.
    g.assert_world_rates_integral = lambda: None
    g.WORLD_MOD["rAsk"] = ((0, 4, 0), (4, 8, 1.5))
    g.build(v())


@case("world: a hop inside a dead-stopped world", "inside a stopped/reversed")
def _hop_in_stop():
    # Proves assert_hop_clear_of_stopped_world. ONLY the hop clock moves: THE ASK keeps its real
    # 26.0-35.0s window (so disjointness and the duty budget have nothing to say first, which is how
    # the old 13.0-22.0s sabotage was convicting), and on an 8s clock the fourth hop is airborne
    # 29.76-31.36s — inside THE ASK's 26.0-32.0s dead world. The real 12s clock clears that same
    # stop by 0.64s, so this case is the margin's guard.
    g.HOP_PERIOD = 8.0
    g.HOP_RISE = g.HOP_PERIOD * g.HOP_FROM_PCT / 100  # 5.76
    g.HOP_FALL = g.HOP_PERIOD * g.HOP_TO_PCT / 100  # 7.36
    g.build(v())


@case(
    "css: negative keyframe percentages (the REAL committed v6b)",
    "invalid keyframe selector",
)
def _negative_pcts():
    """Replayed from the real shipped artifact, at a DERIVED revision.

    Two traps, both of which this case has already fallen into once:

      · A hand-written approximation of the defect can pass the check vacuously, so the input has to
        be the stylesheet that actually shipped.
      · `HEAD:` was the first spelling and it broke the moment the fix was committed — HEAD's v6b no
        longer has the defect, so the case silently began asserting against a clean artifact. A
        pinned SHA is no better: this repo land-rebases, so the SHA moves and the proof turns into a
        skip. A skip reads as a pass.

    So the revision is DERIVED: walk the file's own history newest-first and take the first one that
    still carries a negative keyframe percentage. Self-maintaining across rebases, and if no
    revision has it any more the case says so loudly instead of quietly passing.
    """
    path = "assets/banner/v6b-two-sessions.svg"
    revs = subprocess.run(
        ["git", "-C", str(ROOT), "log", "--format=%H", "--", path],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.split()
    for rev in revs:
        blob = subprocess.run(
            ["git", "-C", str(ROOT), "show", f"{rev}:{path}"],
            capture_output=True,
            text=True,
        ).stdout
        sheet = re.search(r"<style>(.*?)</style>", blob, re.S)
        if sheet and "%,-" in sheet.group(1):
            g.assert_keyframe_pcts_sane(v("v6b"), sheet.group(1))
            return
    raise SystemExit(
        f"redproof: no revision of {path} in this history carries a negative keyframe percentage, so "
        f"this case has nothing real to replay and is proving nothing. It was written against a "
        f"defect that shipped; if the history no longer reaches it, retire the case explicitly "
        f"rather than leaving it green."
    )


@case("layout: two strip features on canvas at once", "are on canvas")
def _two_features():
    # Proves assert_one_strip_feature. THE OVERLAP is withdrawn from ALWAYS_EMITTED and from every
    # variant's `events`, and `strip_features` reserves canvas only for beats the variant EMITS — so
    # the gate sees ONE feature and cannot fire until the sabotage hands it the two-feature world it
    # guards. Re-adding the name is exactly the one-line revert ALWAYS_EMITTED documents.
    # Deliberately keeps the 4 s temporal gap satisfied — 5.0 s clear of THE ASK and 4.5 s clear of
    # the peek — because the whole reason this gate exists is that a strip-borne beat is on canvas
    # for ~20 s however brief its declared window is. 40.0s is a whole number of strides off the
    # real 36.0s (384px, exactly 8 pitches), so `overlap_run`'s half-pitch check — which runs
    # whether or not the beat is emitted — still reads the same 24px offset and stays silent.
    art = copy.copy(v())
    art.events = ("peek", "rOverlap")
    g.BAR_LEN = 400.0
    g.RARE_EVENTS["rOverlap"] = (40.0, 44.0)
    g.build(art)


@case("layout: the overlap run off the half-pitch", "off the ambient print grid")
def _half_pitch():
    g.RARE_EVENTS["rOverlap"] = (
        36.25,
        44.5,
    )  # a quarter-stride, so the run lands ON the grid
    g.build(v())


@case("layout: overlap ink that is not ambient ink", "differs from an ambient print")
def _ink():
    orig = g.print_ink
    g.print_ink = lambda x: (
        orig(x).replace('width="8"', 'width="12"') if x > 2000 else orig(x)
    )
    g.build(v())


@case("theme: a painted shape with no fill rule", "no fill in the stylesheet")
def _unthemed():
    # Exactly the defect that shipped THE REFUSAL's barrier in solid black on its first render:
    # strip the one rule and the shape falls back to SVG's initial fill, confidently, in a colour no
    # theme chose.
    orig = g.css
    g.css = lambda art: re.sub(r"\.rfp\{[^}]*\}", "", orig(art))
    g.build(v())


@case("gate: a window too close to P for its swap edge", "too close to P")
def _gate_overflow():
    # Proves the swap-edge guard inside `gate()`. A gate is only EMITTED for a beat the variant
    # emits, and the cheer is withdrawn everywhere — so its window has to be handed to a variant
    # that declares it or nothing reads the number at all. rCheer composites with the peek, so
    # disjointness exempts that pair, and 4.99s sits inside the duty band: the only illegal thing
    # here is a window ending 0.01s from P with a 0.1s swap edge still to run.
    art = copy.copy(v())
    art.events = ("peek", "rCheer")
    g.RARE_EVENTS["rCheer"] = (235.0, 239.99)
    g.build(art)


@case("gate: THE ASK with two rate-zero spans", "rate-zero spans")
def _two_stops():
    g.WORLD_MOD["rAsk"] = ((0, 4, 0), (4, 2, 1), (6, 4, 0), (10, 4, 3))
    g.build(v())


@case(
    "warp: a layer scrolled at a rate its warp was not sized for",
    "SCROLL/WARP MISMATCH",
)
def _warp_scroll_mismatch():
    """Replays the REAL shipped defect, not an invention of one.

    `tf0` scrolled at `STRIP_PERIOD` (20 s, 96 px/s) inside a wrapper registered from `ground_detail`'s
    `P/8` (30 s, 64 px/s), so through THE ASK's dead world it crept at 32 px/s while `tf1` and `fgb`
    froze byte-exact. The sabotage below is that exact disagreement, re-introduced through `css` so
    the layer's declared period is untouched — which is the shape the defect actually had: one number
    written twice, and only one of the two copies wrong.
    """
    orig = g.css
    g.css = lambda art: re.sub(
        r"\.tf0s\{animation:sc [0-9.]+s", ".tf0s{animation:sc 20s", orig(art)
    )
    g.build(v())


@case("warp: no layer at the strip rate", "no layer scrolls at the strip rate")
def _no_strip():
    g._WARPED.clear()
    g._WARPED.add(8.0)
    g._ENCODED_STRIP.clear()
    g.warp_css()


@case(
    "legacy: the stride/scroll lock (scale off the solution)",
    "stride/scroll NOT LOCKED",
)
def _stride():
    art = copy.copy(v())
    art.clawd_scale = 1.06
    g.build(art)


@case("legacy: the duty budget (an over-long beat)", "duty budget breached")
def _duty():
    # Proves assert_duty_budget. The cheer this used to stretch is emitted by no variant, so
    # `active_events` never measures it; the peek is a beat v6a actually declares. 18.0s breaches
    # BOTH the 10.0s per-instance ceiling and the 4% per-type one, and it stays 13.5s clear of THE
    # ASK, so the disjointness gate ahead of it has nothing to say first.
    g.RARE_EVENTS["peek"] = (48.5, 66.5)
    g.build(v())


@case("legacy: event disjointness (two beats stacked)", "overlap or sit within")
def _disjoint():
    # Proves assert_events_disjoint — the guard against the stacked-beat defect v5a shipped at four
    # concurrent events, and the ONE gate here that could not be shown to fire at all: it stacked
    # THE OVERLAP, which no variant emits, so `active_events` never saw the collision. It has to
    # stack beats the variant actually declares, so the peek — v6a's own — is dropped onto THE ASK's
    # 26.0-35.0s window. The peek composites only with the cheer, so nothing exempts this pair.
    g.RARE_EVENTS["peek"] = (33.0, 39.0)
    g.build(v())


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()
    if args.list:
        for n, _w, _f in CASES:
            print(n)
        return 0

    print(f"banner-gate-redproof: {len(CASES)} gates, sabotaging each\n")
    bad = []
    for name, want, fn in CASES:
        with sandbox():
            try:
                fn()
            except SystemExit as e:
                msg = str(e)
                if want in msg:
                    print(f"  ✓ {name}")
                    continue
                bad.append(
                    (
                        name,
                        f"fired on the WRONG check: wanted {want!r}, got {msg[:160]!r}",
                    )
                )
                print(f"  ✗ {name}  — wrong check")
                continue
            except Exception as e:  # noqa: BLE001 - a crash is not a verdict
                bad.append(
                    (name, f"crashed instead of rejecting: {type(e).__name__}: {e}")
                )
                print(f"  ✗ {name}  — crashed, not rejected")
                continue
            bad.append((name, "ACCEPTED the sabotage — this gate does not fire"))
            print(f"  ✗ {name}  — ACCEPTED the sabotage")

    print()
    if bad:
        print(f"banner-gate-redproof: FAIL — {len(bad)} of {len(CASES)} gates unproven")
        for name, why in bad:
            print(f"  · {name}\n      {why}")
        return 1

    # A suite that proves every gate rejects bad input, and never checks that the real thing still
    # builds, would pass with a gate wired to reject everything.
    for art in g.VARIANTS:
        g.build(art)
    print(
        f"banner-gate-redproof: PASS — {len(CASES)}/{len(CASES)} gates fire, and all "
        f"{len(g.VARIANTS)} variants still build clean"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
