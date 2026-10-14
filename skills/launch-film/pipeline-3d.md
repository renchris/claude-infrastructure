# Path-traced launch film pipeline (state page → Blender Cycles)

For a film whose look is a rendered 3D set. Written from the claude-infrastructure film (2026-10; Blender 4.2.0, Cycles
on Metal, an M1 Max shared with about 20 other sessions). The scripts named here live in the private work folder
`~/Development/personal/launch-film-2026/first-principles/work/looks/a2/` until they are promoted to `kit/3d/`.

## 1. Shape

- **One clock, one state engine.**
  - A web page (three.js is enough) holds the clock, the shots, every rig and the cues.
  - It dumps per-frame state as JSON (`dump.sh` → `state/state.json` through `render.mjs eval`).
  - Blender builds the set from that JSON and is only the camera and the renderer.
  - The score and the effects read the same cue export (`state/cues.json`).
- **Assert the dump:** frame count = story duration × fps, indices contiguous. Close-ups spliced in post are counted separately, from the edit list.
- **One directory per round,** with scripts taking the round directory as an argument. Copying scripts per round (`*_r2`, `*_r3d`, `*_r3i`, `finish_r4.sh`) let the gate drift from the film: `gate_a2.py` kept a clock and beat list that the edit and the restage had changed.

## 2. Measure from state before any pixels (`measure_r3.py`)

- **Speed.** Measure each subject's own screen speed by projecting its centre at frames n and n+1 through frame n+1's camera, so camera motion does not count. Skip pairs across a cut. Report the maximum per shot against the cap: about 0.73 frame widths per second, i.e. 1,400 px/s at 1920 wide.
- **Move starts** per beat and per eighth-beat ("the same instant").
- **Intersections.** Plan-view intersections, character against prop and character against character, plus the clear gap in front of each seated character. All must be 0.
- **Line of sight** for every close-up lens. Reject a frame when another subject sits within about 80 px of the lens-to-subject segment. In 2026-10, `scene.py` picked each close-up's side this way, after frames 0–7 of one close-up were found blocked only after 1,500 final frames.
- **Sound and light:** loudness per second from the mix (no second below the bed) and mean light per shot.
- **Gates:** every gate reads duration, beats and splices from the cue export, and prints which checks ran.

## 3. Stills

- The first, middle and last frame of every shot and every close-up, at low samples.
- 100 % crops of contacts, faces and lettering.
- A board generated from the edit list, with film timecodes.

## 4. Cheap motion preview (`preview_render.py` → `preview_post.py`)

- **Settings:** 50 % size, 8 samples, light tree off, persistent data on.
- **Frames:** render every other frame, counted from each shot's first frame so no cut moves, and hold each for two. Close-ups also render every other frame.
- **Output:** muxed with the current mix, at full length.
- **Reuse:** keep ids and seeds stable so unchanged frames come out identical. Diff the new state against the last round's and re-render only the frames that changed. A change that touches every frame (moving water, wind) re-renders all of them.
- **2026-10 numbers:**
  - Round 3 planned about 830 frames at about 7 s each (about 1.7 h) and took 2.7 h under a load average of about 430.
  - Round 4 rendered 878 frames at a median of 11.4 s in 3.2 h (`preview_driver_r4.log`: 23:24:36 → 02:34:31).
  - Round 3b reused 432 frames.

## 5. Final render

- **One renderer on the machine.**
  - Use an mkdir lock (`rlock.sh`) plus `pgrep -f "Blender -b"` before starting. A lock released by a dead driver's EXIT trap let an orphaned Blender keep rendering beside the next one (83 → 132 s/frame).
  - Watch the renderer's pid or its log, never a `pgrep` pattern that the watcher's own command line also matches (`pipeline.md` §6).
- **Run the driver in `screen -dmS <name>`.** Never nohup it from a tool shell: a nohup'd driver died with the shell while Blender lived on.
- **Resumable:**
  - set `use_overwrite=False` and `use_placeholder=False`;
  - before each pass, decode every PNG and rename failures to `.bad` (delete nothing);
  - retry passes (40 main, 12 close-up), because something outside may SIGKILL Blender under memory pressure (2026-10-04).
- **Budget (`SKILL.md` §7).**
  - Time a probe at final settings on the heaviest shots, then take its median × frames × 2 on a shared machine. Re-check after 50 frames.
  - Scaling the preview by samples × pixels does not work: 11.4 s × 16 × 4 = 729 s/frame predicted, 88.5 s measured.
  - 2026-10 measured, from the Blender `Time:` lines:
    - probe about 72 s/frame;
    - main frames a median of 88.5 s (p90 294 s);
    - close-ups a median of 123.7 s;
    - 81.4 h of wall clock against a 37.5 h estimate.
- **Diagnose a slow frame before acting.** Split its time into scene sync (to `Sample 0/`) and sampling, using the Blender log.
  - In 2026-10, sync had a median of 10.1 s per frame up to frame 1,274 and 192.4 s past frame 1,300, under swap.
  - Frame 1,275 took 235.7 min on its own.
  - Process priority was not the lever. If you renice for a call, restore it afterwards.
- **Leave a swapped-out render running.** It resumed on its own when the load fell, and a restart would hit the same memory wall.
- **A watcher reports only on change:** a stall, a rate shift over 2×, or done, each with the ETA.

## 6. Post and finish (`post.py`, `finish_r4.sh`)

- **The chain:**
  - 16-bit PNG frames → FFV1 `rgb48le` lossless master, with close-ups spliced in by an edit list;
  - one RGB→BT.709 conversion;
  - H.264 at CRF 18 with AAC at 256 kb/s;
  - a poster and a 3-frame board;
  - a send copy if the master exceeds 31,000,000 B.
- **Make ffprobe assert:** size, fps, frame count, duration, an audio stream. `finish_r4.sh` only prints its ffprobe line.

## 7. Paid sound effects (`sound_el.py`)

- Cache every generation by prompt, so nothing is paid for twice.
- Pass the key on stdin from the secrets store.
- Take placements from the cue export.
- Level-match the A/B passes on the same picture (2026-10: −20.1 dBFS RMS).
- 2026-10 spend: 1,175 of 40,000 credits.
