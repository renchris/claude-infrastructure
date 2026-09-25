# Launch film: critique, round one (in-session)

Reviewed build: the first cut, rendered 2026-09-25, every 0.5 s at 838 px (the README column).

**Not fresh-context, and why.** The brief asks for a fresh-context critic that has not seen the
maker's reasoning. The spawn was refused three times by the machine's capacity gate (twice
`active`: 8 sessions mid-turn; then `reserve-active`: the operator was at the keyboard, and
autonomy yields), and the gate prescribes doing the step in-session rather than retrying. So this
round was run by the maker, from the rendered frames only, against the stated criteria; round two
(`critique-round-2.md`) is the fresh-context one. What was adopted is in
[`README.md` § Decisions](README.md#decisions).

## Findings

1. **Budget: blocker.** The dark loop encoded to 11.0 MB against a ~5 MB budget. Measured per scene:
   the closing poster hold (1.4 s) was 6.27 MB, because it is stored near-lossless while the ping,
   the fold and the whole kinetic headline animate in it. Every other scene was 0.1–0.7 MB/s.
2. **L13.8–14.7, the flight to `~/.claude`: major.** The camera leaves through the hanging card; a
   giant blurred "2%" smears across the frame.
3. **L10.8–13.8, the false "done": major.** At 838 px the hook's row is ~6 px text. Only the
   headline carries the beat; nothing on screen says what refused it.
4. **L3.4–6.0, the split: major.** The peer's `③ feat/readme-hero-film` chip shows for the last
   ~0.4 s of the hold (its line draws too late), anchored below the window's base: the peer's own
   lane is lost in the one scene that introduces it.
5. **Colour: major.** The split's divider is drawn in kitty's green, which the film reserves for
   verified or landed.
6. **L6.9–9.9, the deny wall: minor.** A faint translucent rectangle; it reads as a tint, not a
   barrier.
7. **`~/.claude` sign: minor.** ~9 CSS px over the racks on the poster.
8. **Pane text: minor, declined.** A window's rows are ~7 CSS px at 838. They are texture that
   says "Claude Code, working"; the scene's line of type and the chips carry the meaning, and
   larger pane type would halve what a pane can show.

Honesty: no finding. Every legible string is real (README § Honesty rule), with one correction made
in this round: the panes' header read `v2.1.266`, and the session that made the film runs 2.1.280.
