# Launch film: critique, round two (fresh context)

Reviewed build: round one's fixes, rendered 2026-09-25, every 0.5 s at 838 px. The critic was a fresh-context
subagent that saw only the frames and the brief (message, criteria, colour meaning), never the maker's
reasoning. What was adopted and declined is in [`README.md` § Decisions](README.md#decisions), under round two.


## 1. Scores

- **Concreteness 7:** the panes, paths and hook names are real (L4.0, L13.5, L16.5). The central shot is unlabeled ribbons, amber lozenges and blank slabs (L7.0).
- **Continuous camera 8:** no hard cuts; every change is a blurred flight (L3.0, L6.5, L10.5, L14.0, L17.5). F26.0 grazes the gate post, which smears into four stepped copies.
- **Frame 0 is the answer 7:** the sentence is large and complete (L0.0, F0.0). No object there shows "You only decide". The gate is about 50 px tall; the foreground terminal is an unreadable text block.
- **Legibility at 838 px 6:** captions and mid-shot terminals read (L4.0–L6.0). Lane labels (L0.0), "/ship · one at a time" (L7.0) and the ①/③ glyphs (L5.5) are unreadable or unexplained. "Model ladder" (L13.0) and "running bytes" (L15.0) are jargon.
- **Honesty 5:** the peer's "landed on origin/main" PING prints before the /handoff that fires it (L3.5–L4.5, F4.0). The YOUR CALL card, with yes/no buttons and "72 % sure" (L13.0, F17.0), reads as a mock-up.
- **Seam 6:** the wrap is clean: L19.0 vs L0.0 differs by more than 16 in 0 px (dark) and 237 px (light), measured with a PIL per-pixel diff. But mid-hold the terminal snaps from two panes to one and the green lane vanishes (L18.5 → L19.0: 7,810/6,041 px changed, measured). The film pops the same way (F29.0 → F29.5).

## 2. The one image

The fan: about ten lanes pinching into one boom gate under a red "git push --force / denied" flag (L8.5, F11.0). Right family, wrong emphasis: it sells "one land at a time", not the thesis. Put the decision card in this frame and it becomes the thesis.

## 3. The LOOP's first 3 seconds

A frozen title card (t00.00–t02.50 pixel-identical in both grades, measured). A stranger gets the sentence; the right half reads as a network diagram; nothing signals film. The headline blurs away at L3.0, but 13 words need about 3.3 s (estimated at 4 words/s).

## 4. Findings

### Blocker

1. **Result before cause (L3.5–L6.0, L11.0–L13.5, F4.0).** "PING RECEIVED FROM PEER … landed on origin/main" sits above the "/handoff" that spawns that peer, and at L3.5 the cycle prints twice. It reads as a doctored transcript and spoils the ending. *Fix:* start the pane empty at "❯ /handoff". Show the PING once, on the end-state terminal in frame 0.
2. **The decision card reads as fake UI (L12.5–L13.5, F17.0–F18.5).** Floating buttons, a "72 % sure" that belongs to nobody, "model ladder" jargon, and at F17.0 it is translucent. *Fix:* show the decision on the surface it really arrives on (an in-pane numbered question or the real notification), fully opaque. Use a question a stranger can parse; label whose confidence "72 %" is, or drop it.

### Major

3. **State resets happen on screen.** The ~/.claude rows are lit at L0.0, L7.0 and L14.5, go dark at L15.0 and relight at L16.5; the film does the same at F20.5 → F21.0 → F24.0. The pane pop is at L18.5 → L19.0. *Fix:* make frame 0 the end state (two-pane terminal, green lane, lit ~/.claude). Do every reset inside the L3.0 / F2.5 flight blur.
4. **The callout covers the evidence (L11.5–L13.0).** The "sent back by hooks/completion-assert.sh" chip sits on the red hook message, which becomes readable only at L13.5 as the card lands. *Fix:* anchor the chip above "Done." and inside the pane. Give the hook text at least 1 s alone before the card.
5. **No account story, and one hue is warm (L5.5, L7.0–L10.0).** No word says "account", and ①/③ go unexplained. Magenta (319°/324°) sits 35–45° from refused-red (4°/356°), measured by pixel sampling at L8.5. *Fix:* put a 14 px "account ①…④" chip at each bundle's origin, and use four cool hues, for example 185°/212°/240°/270°.
6. **The gate arm clips through the land-lock sign (L7.5, L9.5, F11.0, F12.0, F19.5, F20.0).** *Fix:* raise the sign at least one arm-length above the pivot, or cap the arm's lift below it.
7. **Captions collide with the scene (L15.0, F20.0–F25.0).** "~/.claude" sits half under "match." (F24.0), and the land-lock sign ghosts through the caption (F20.5). *Fix:* lower the ~/.claude layer about 40 px so its label clears the caption by at least 24 px.
8. **Frame 0 has no decision object and a tiny fan (L0.0).** *Fix:* scale the diorama so the gate is about 110 px tall, centred near x 620, and float the opaque YOUR CALL card at the near end of the fan.

### Minor

9. **The first 2.75 s are frozen (L0.0–L2.5).** *Fix:* start the WebP at the return landing (about L18.0), which gives roughly 3.9 s of first-play hold (estimated). Keep amber pills moving during the hold.
10. **Blank slabs (L7.0 left, Llight7.0, F27.0).** Backs of cards read as placeholders. *Fix:* turn them to face the camera, or cull them.
11. **Orphan words (F9.5 "its own lane.", F13.0 "a time.", L14.5 "until the").** *Fix:* fade whole lines in 0.3 s or less. Replace "running bytes" with the on-screen object: "until ~/.claude matches main".
12. **The light grade blurs the colour meaning (Llight7.0, Llight16.5).** Teal (31,126,133) and main-green (23,127,52) read as one family on white (measured by pixel sampling), and lit rows are 2 px ticks. *Fix:* use light-grade teal around (0,150,190), and give lit rows a full-row #dafbe1 tint.
