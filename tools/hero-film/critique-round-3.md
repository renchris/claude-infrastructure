# Critique, round 3: README loop (45.9 s) and launch film (63.1 s)

Reviewed build: round 2's first build (`d8f395208`), 2026-09-25. The critic was a fresh-context subagent
that saw only the brief, the operator's three verdicts, the rubric and the shipped files, never the
maker's reasoning. What was adopted and declined: [`README.md` § Round 2](README.md#critique-round-3-fresh-context).

Fresh-context review. L = loop time (s), F = film time (s). All inputs were present and readable.
How I measured:
- Frame timing: decoded `hero-dark.webp` with Pillow (1417 stored frames, 45.900 s) and checked frame layout with `webpmux -info`.
- Motion: consecutive-frame mean abs diff at 838 px, and cv2 Farneback optical flow (median over textured pixels, excluding the title, scaled to px/s at 1920).
- Film: ffmpeg decode of `launch-film.mp4` (3786 frames, 60 fps) to 480 px grey, then consecutive-frame diffs.
- Reading and legibility: read the 838 px frames myself at the times shown. Word counts are my own.
- Honesty: `ls` and `git grep` in the worktree.
Numbers are dark grade unless marked. Light was checked for the seam, contrast and frame layout only.

## 1. Scores

1. **Motion smoothness 6/10.** The flights ease cleanly (flow, px/s at 1920):
   - F1: 0 to about 225 (L6.0–7.0) to 0 at L8.42.
   - F2: 0 to about 700 (L30.2) to 0 at L33.1.
   - F3: 0 to about 600 (L42.2) to 0 at L44.6.
   Every flight frame lasts 16/17 ms, and the MP4 flights have no duplicated or skipped frame. Against that, the card vanishes in 2 frames at L5.82, the chips cut in 1 frame at L40.00, the pane reflows in 1 frame at L12.47, and there are encode ticks at L5.00, L28.65 and L44.60 (see findings).
2. **Orientation 8/10.** F1 and F3 keep the target in view from a wide 3/4 shot. F2 goes window to racks past an unexplained gate (L30.2–31.7) but lands on a labelled `~/.claude`.
3. **Read in time 7/10.**
   - Every caption, the card and every chip has more than enough time: the thought gets 12 words in 5.0 s, the card 20 words with 7.2 s still, the chips 2.4 s or more.
   - One legible paragraph fails: the peer's 24-word prompt is complete for only 0.90 s (L13.85–14.75).
4. **Concreteness 8/10.** Real Claude Code windows with a banner, statusline and `/handoff`, real file racks, and a Blocked card. The glowing lanes, amber pills and "land-lock" gate are still metaphor.
5. **Continuity 7/10.** One camera and no hard cuts. But state resets happen in view: the card and the split vanish mid-F1 (L5.82), and the racks flip green to amber in one frame (L32.43).
6. **Frame 0 is the answer 8/10.** All three lines are there, large and on the left, and the diorama behind previews the beats. The product line "~/.claude, deployed from git." is set at roughly half the size of the other two (estimated from pixel heights at 838).
7. **Legibility at 838 px 7/10.**
   - Captions, card and chips are crisp in both grades. Measured contrast of the terminal body is 12.6:1 (dark) and 7.7:1 (light).
   - Terminal and rack text is about 8 CSS px (estimated from the 10 px line pitch).
   - The light-grade amber rack rows reach only 4.3:1 (peak pixel against the row background).
8. **Honesty 6/10.**
   - Unsourced peer output is drawn as grey bars.
   - All 22 hook, command and skill names, `deploy-live.sh`, and the `handoff-fire.sh` flags exist in the repo.
   - "72 % sure, says the session." is not traceable (see Major 4).
   - The statusline ids `4f2ef1b9` and `dec7f8dc` are not commits in this repo (`git rev-parse` fails).
9. **Seam 9/10.** The last frame to frame 0 differs by a mean of 1.02/255, against 0.08 for a normal frame pair. The worst 16 px block is 13.9 (a normal pair gives 14.9). The poster is held continuously from L44.6 through L5.0 (6.3 s). Light: mean 0.75, and 780 px differ by more than 15 %.

## 2. The one image you remember

The ⛔ card, "Blocked — need your call: May a session switch to the bigger model on its own? **72 %**", in front of the split terminal under "Only decisions reach you." It is held completely still for 7.2 s (L21.45–28.65), so it outlasts everything else. The "72 %" is the biggest numeral in the loop, and it is the string I trust least (Major 4).

## 3. The loop's first 5 seconds, as a stranger

- A big claim on the left. My eye lands on "The sessions run each other." first; the smaller "~/.claude, deployed from git." reads as a kicker.
- On the right is a dark 3D diorama: cyan and violet lanes converge on a white frame labelled "land-lock", three green panels read `~/.claude`, there are a few tiny terminals, and a Blocked card sits in the foreground.
- I read the claim in about 3 s, then the card. I cannot tell what "land-lock" or the lanes are.
- Almost nothing moves: two amber pills creep (frame change 0.01–0.05/255 from L2.0 to 4.95). For 5 s it reads as a still banner.
- At 5.0 the words dissolve and the camera glides down toward the terminal, and now it is a film. At 5.8 the card I just read blinks out, together with the window's text. It looks like a glitch.

## 4. Findings

### Blocker

**B1. The card and window content vanish mid-flight (L5.80–5.83, F≈5.82).**
- What happens: in Pillow frames 348→350 (2 frames) the Blocked card, the split and all pane text disappear while the camera glides toward them at about 150 px/s. The window resets from "story finished" to "story not begun" in plain view. The same happens in the MP4 (ffmpeg tile at F5.75).
- Why it blocks: it is the first transition every viewer sees, it removes the object frame 0 just offered as the answer, and it is exactly the "jars" the operator rejected.
- Smallest fix: do the reset while it is invisible or slow. Either cross-fade card and content out over at least 0.5 s during L5.0–5.4, while the title fades and the window is small, or keep the end state until the window is off screen.

### Major

**M1. The loop is a still picture 42 % of the time, with dead air under captions that promise action.**
- Stored frames held for 1 s or more (Pillow durations; each is a single stored frame, zero motion):
  - L8.45–11.48 (3.03 s)
  - L14.75–16.17 (1.42 s)
  - L17.40–20.03 (2.63 s)
  - L21.45–28.65 (7.20 s)
  - L33.12–37.02 (3.90 s)
  - L38.80–40.00 (1.20 s)
  That is 19.4 s of 45.9 s.
- The worst moment: "A session fires a peer." sits over an empty, frozen terminal for 3.0 s before anything is typed. "Only decisions reach you." waits 3.3 s for the card.
- On GitHub a 7.2 s freeze reads as a stalled image, which cuts against verdict 1.
- Smallest fix:
  - Start `/handoff` about 0.5 s after the arrival at L8.4, and bring the card in about 0.8 s after its caption.
  - Keep ambient life in every hold: the amber pills moving on the background lanes, a cursor blink, a 2–4 px/s drift like the film has.
  - Cut the racks pre-flip hold from 3.9 s to about 1.5 s.

**M2. The gate beat and red are missing from the loop (L28.65–33.05).**
- The brief requires commits landing on origin/main one at a time through a gate, and red for refused.
- The loop only glimpses the land-lock during F2 and F3 and never names it. The only red on screen is the ⛔ glyph.
- The film has the whole beat (F32.85–41.45: "One land at a time. A dangerous call never runs." and `git push --force` → "denied: it never runs").
- Smallest fix: spend the roughly 6 s freed by M1 on a trimmed version of the film's gate beat. The loop stays at about 46 s.

**M3. The peer's prompt is legible but gone in 0.90 s (L13.85–14.75).**
- The text: "You are building the README hero LAUNCH FILM for claude-infrastructure (public repo github.com/renchris/claude-infrastructure). Your cwd is a fresh worktree on branch feat/readme-hero-film off origin/main." That is 24 words, and it is still for only 0.62 s before it scrolls.
- It is the proof that the peer is a real session, and it is the operator's "can't read anything in time" complaint in miniature. The pacing gate does not count it.
- Smallest fix: hold it at least 5 s (let "I'll start by…" and the grey bars grow below instead of scrolling it off), or grey-bar the paragraph.

**M4. "72 % sure, says the session." does not look sourced (L20.3–29.5 and frame 0).**
- The real format, `⛔ Blocked — need your call: <decision>.` (commands/wrap.md:139), has no confidence field.
- `git grep` finds "sure, says" only in tools/hero-film/panes.js:332, the film's own source.
- The figure is the largest type on the card.
- Smallest fix: cite the session it came from in tools/hero-film/README.md, or drop the confidence line and keep the real `Blocked — need your call:` string.

### Minor

**m1. Encode ticks at the flight edges (L5.00, L28.65, L44.60).**
- One-frame whole-picture changes, where neighbouring frames change by 0.71, 0.65 and 1.09:
  - L5.00: mean 3.51/255. The static title changes by 2.68 with zero displacement, and the lane glow visibly thickens.
  - L28.65: 2.11.
  - L44.60: 3.98.
- webpmux shows frames 1 and 1340 are the only lossless ones, so quality switches as motion starts and stops.
- Fix: encode the 10 frames either side of each flight edge at the flight's quality, or the poster at the same lossy quality.

**m2. Chips cut in one frame.**
- L40.00: "on origin/main · verified by content" and `deploy-live.sh` go from luminance 36 to 20 in a single frame, while the caption fades over 0.45 s.
- The film does the same with the account chips at F41.45 (diff 0.87 against 0.04) and the verified chips at F52.60 (0.72 against 0.06).
- Fix: fade the chips out with the caption.

**m3. The split is a one-frame reflow (L12.47).** The left pane re-wraps to half width in one frame (mean diff 1.42 against 0.01; worst 16 px block 56), and the 1 px divider then draws down. At 838 px the key beat reads as "text jumped". Fix: slide the pane boundary over about 0.4 s, or let the right pane grow in from the edge.

**m4. The racks go backwards (L32.43).** The rows flip from green to amber in one frame (diff 2.64 against 1.7) while the camera is still settling, before the caption explains it. Fix: arrive with them already amber, and set that state during F2 while the racks are distant.

**m5. Frame 0 hierarchy.** "~/.claude, deployed from git." is about 55 % the size of the other two lines (estimated), yet it is the only line that names the product. Fix: set all three lines at one size, or give line 1 at least 75 % of it.

**m6. Small text.** Terminal and rack text is about 8 CSS px at 838 (estimated). It is fine on 2x screens and marginal on 1x. Fix: raise the pane font about 20 % in the window scene, where the pane fills the frame.

**m7. Light-grade amber.** The amber rack rows measure 4.3:1, and the amber-to-green flip (L37.15–38.8) is pale peach to pale green, weak in light. Fix: darken the light-grade amber text to at least 5.5:1 and saturate the green fill.

**m8. Statusline ids.** `4f2ef1b9` and `dec7f8dc` are not commits here. If they are session ids, fine. If they are meant as SHAs, use real ones.

**m9. Film flight window→gate (F30.0–31.0).** Near panes sweep across the lens: median frame change is 7.29, against 4.3–4.6 in every other flight. This is the film's most jarring second. Fix: raise the camera path so the near panes pass below frame, or slow that segment by about 30 %.
