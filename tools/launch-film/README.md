# README hero: the 2026 launch film

The first element of this repo's README. The film was approved on 2026-10-13 and replaced the
terminal-fleet film built in `tools/hero-film/` (git history keeps that one).

| Artifact | What it is | File |
|---|---|---|
| **Hero** | the README's first element: GitHub's inline video player showing the master (1920 × 1080, 60 fps, with sound), uploaded as an attachment to closed issue #1, "README media: launch film" | the attachment URL at the top of `README.md` |
| **Loop** | an animated WebP, 1048 × 590, every one of the film's 1,755 frames at 60 fps, no sound; no longer on the README (there it looked crushed and silent) | `assets/hero/hero.webp` |
| **Poster** | one still from the film, 1920 × 1080 | `assets/hero/poster.jpg` |
| **Film** | the full film with sound: 29.25 s, 1920 × 1080, 60 fps, H.264 + AAC | `assets/hero/launch-film.mp4` |

The film's source (the Blender scene, the storyboard, the score) is not in this repo. What is here
is the film itself and the one script that turns it into the README loop.

## How it was made

An agent made it end to end: no studio, no stock footage, no generated video, no people.

1. **Story before look.** The product's value points were written down first (how many sessions run
   at once, how long work runs, when a person is needed), one angle was picked from them, and the
   story was judged before any frame was designed. The story: one Clawd with a `/goal` opens more
   sessions, they hand work to each other, and they come to you only for what only you can decide.
2. **Storyboard in film format.** One row per shot: time, camera move, angle, lens and depth,
   staging, on-screen words, sound, cut. Each feature the film shows was mapped to the mechanism in
   this repo that does it, and the board was approved before any long render.
3. **Blender Cycles.** One path-traced set: a stone terrace above a moving sea, olive trees, plush
   Clawds with real fur. The final render is 1,755 frames at 128 samples and took about 81 hours on
   one Mac.
4. **Preview-gated rounds.** Before the final render, each round was a cheap full-length preview
   with sound and one question. Four preview rounds fixed speed, staging, the hand-offs and the
   sound; the two that were timed took 2.7 and 3.2 hours.
5. **Sound.** A score composed in code, plus sound effects generated with ElevenLabs (sea, poofs,
   brush, chalk). No voice.

## What is real, and what is illustration

Real:

- **"40 sessions at once. 1,366 agents in a day."** Both are measured from this machine's Claude
  Code transcripts under one stated rule: count interactive sessions and every agent they spawned,
  each once; leave out headless runs; a session or agent counts in a window if it wrote a record in
  it. 40 sessions were active in one ten-minute window (2026-10-01); 1,366 agents ran in one day
  (2026-09-29).
- **The mechanics.** Each beat is something this repo does: a session opens a briefed session with
  its own `/goal`; a session whose context fills (the lid ring stops at 73 %) hands the same goal to
  a fresh one; a session leaves only after `SAFE TO CLOSE`; `sudo` reaches you as one command; a
  question reaches you with the session's conviction and its research.

Illustration:

- **Everything you see.** The terrace, the Clawds, the pennants and the props stand in for
  terminal sessions. No frame is a screen capture.
- **The lettering.** The signs are drawn in the scene, not captured from a terminal; the lettering
  on the hand-held props began as plates from an image model.
- **The two asks.** `sudo pmset` and "Spend about $250 of quota?" are examples of the two kinds of
  question that reach a person, not a record of one event.

## The README hero and the loop

The README's hero is GitHub's inline video player:
- the master is an attachment on closed issue #1;
- its bare `https://github.com/user-attachments/assets/<uuid>` URL sits on its own line;
- GitHub strips a raw `<video>` tag, but not an attachment URL.

The animated WebP below is kept for places that need a silent loop. As the README hero it looked crushed and had no sound (2026-10-13).

```sh
bash tools/launch-film/encode-loop.sh MASTER.mp4 assets/hero/hero.webp   # 1048 px wide, q20
```

The loop keeps every frame of the film at 60 fps: nothing is dropped, merged or shortened to save
bytes. Size was bought with pixel width and quality instead (the measured levers are in the
script's header). The film is one bright look, so one file serves both color schemes.

`assets/hero/launch-film.mp4` is the approved master, byte for byte.
