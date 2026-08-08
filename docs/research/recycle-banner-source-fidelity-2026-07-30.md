# The self-recycle banner must RECREATE the BMO clip, not reference it

**Status:** v1 landed (`0dc1c05b`..`34e725d6`) and is the WRONG THING. v2 is a rebuild against the
actual source, which is now on disk. This document is the spec; it exists because v1 was built from a
prose shot list rather than from frames, and every error below follows from that.

**Reference (durable, outside any repo — the clip is Cartoon Network's, do not commit it):**
`/Users/chrisren/Development/.banner-ref/` — `bmo.webm` (1280×720, 7.421 s, 23.976 fps) plus 44
frames at 6 fps, `f001.png`..`f044.png`. Source: `youtube.com/watch?v=0QRpJv1nYG4`, an Adventure Time
**Halloween special** broadcast capture (the overlay says so — which is why BMO already wears a
costume star, and why the operator's "as if it was a halloween costume" was pointing at the source).

Re-fetch, if ever needed: `yt-dlp -f 'bv*+ba/b'`. This FAILS on yt-dlp older than ~2026.07 with
"nsig extraction failed" / "Requested format is not available" and offers only a 48×27 storyboard —
which is what sent v1 down the prose-only path. `brew upgrade yt-dlp` fixed it in one step.

## What v1 got wrong, and the one cause

v1 is a 1920×480 side-on pixel-art banner: our Dusk Line landscape, a caption block
(`SELF-RECYCLE` / `handoff-fire.sh --recycle` / a state line), and a front-facing clawd in a flat
teal shell that reaches behind itself. Operator verdict: *"completely different video that is front
facing and has our main session banner background… I thought we were going to re-create the video as
closely as we can except redraw bmo as a clawd-bmo."*

| v1 | the source |
|---|---|
| flat side-on / front elevation | **3/4 axonometric, camera looking DOWN** on a receding ground plane |
| our dusk ridge, moon, mounds, tufts, vignette | a flat dark night ground, a **brown leather basket** at left, scattered batteries, tiny grass tufts |
| caption block with a command + state line | **no type at all** |
| never turns; hatch is on the unseen "back" by implication | **turns a full 180°** so the audience SEES the back, the vents, and the open compartment |
| screen dies, creature stays standing | **it TOPPLES FACE-DOWN and lies dead on the ground** — the whole comic beat |
| one battery, orange, our brand | **three or four** navy/tan AA cells, stacked inside and scattered outside |

The single cause: "same style as the v6c hero" was read as *same scenery*, when the operator meant
*same craft level*. Fidelity to the clip outranks house style here. The mood happens to land near
Dusk Line anyway (see palette) — that instinct was not wrong, only its scope.

## Beat sheet, read off the frames (6 fps, so f-numbers are ~167 ms apart)

| t (s) | frames | pose / event |
|---|---|---|
| 0.00–0.85 | f001–f005 | standing, **FRONT** view: screen alive with face, yellow star at upper right, arms at its front |
| 0.85–1.30 | f006–f008 | leans and **turns** — a transitional 3/4 |
| 1.30–1.60 | f009 | upright, front-ish, first battery already on the ground at its lower right |
| 1.60–3.90 | f011–f023 | **BACK** view held: vent slots, `BMO` on the left side face, **compartment open**, batteries visible stacked inside, one arm curled INTO the opening; cells accumulate on the ground |
| 3.90–4.20 | f025 | still back-on, hatch open, batteries out |
| 4.20–5.50 | f027–f033 | **FALLEN, FACE-DOWN.** The front face now points up-camera: screen **black**, buttons and star visible on it, arms splayed left with visible hands, one leg up, cells scattered around |
| 5.50–5.80 | f035 | **rising** — back view, one leg lifting |
| 5.80–6.50 | f037–f041 | standing, back to camera, arms settling, compartment closed |
| 6.50–7.42 | f043–f044 | **turns back to FRONT**, screen alive again → loops to f001 |

Loop closes naturally: alive-and-facing at both ends.

## Palette, sampled (not guessed) — `magick -colors N -format %c histogram:`

Everything is night-graded, so BMO is **dark teal, not mint**. Do not brighten it back up; the
darkness is why the black screen reads as *off* at all.

| role | hex | notes |
|---|---|---|
| ground / sky field | `#023A50` | dominant, 81k px of the fallen frame |
| horizon band | `#034D6E` | slightly bluer, top of frame |
| body, lit face | `#1C6162` | the brightest large area on the character |
| body, side face | `#1B575A` | second face, ~5% darker — the only shading there is |
| back face | `#05394D` | darker still; nearly the ground value |
| screen, dead | `#031014` | near-black. This is the beat. |
| vents / open recess | `#062225` | |
| limbs (noodle arms, legs) | `#A3C3D3` | pale blue-grey, thin, with drawn fingers |
| highlight / fingers | `#F4FBFC` | |
| battery body | `#473A33` / `#54463B` | dark navy-brown in this grade |
| battery end cap | `#44402A` | dark olive-tan, with a `+` |
| star (costume) | `#ADC52A` | darkened yellow-green — the brightest accent in frame |
| buttons | `#5AA0C8` blue · `#50845D` green · magenta + yellow X on the front face | |

## Character construction (clawd-BMO)

A **rounded box in axonometric 3/4**, three faces visible at once (top edge, one long face, one end
face), each a flat fill with a dark outline — cel style, so SVG paths, NOT the pixel-rect vocabulary
of `gen.py`. Poses needed as discrete drawings: `front`, `turn3q`, `back`, `topple`, `fallen`,
`rising`. Limbs are thin tapered noodles with hands, drawn as strokes/paths, free to overlap the body.

**What makes it clawd rather than BMO** — the costume read the operator asked for, kept from v1
because that part worked: clawd's own `#D77757` body shows at the edges of the shell, its four legs
and arm stubs stay bare, and clawd's real eyes are the dots on the screen. On the fallen frame the
screen is black, so the eyes go with it — which is exactly the point.

## What survives from v1 (do not rebuild)

`tools/banner/recycle.py`'s machinery is sound and should be reused wholesale:

* `Track` — waypoint authoring, and it **refuses to emit unless t=0 and t=P are identical**.
* Rejection of duplicate keyframe percentages, and `assert_return_travel_is_invisible`. See memory
  `css-duplicate-keyframe-is-a-glide`: same-percentage keys MERGE, turning an authored teleport into
  a multi-second glide — it silently broke three animations and every gate stayed green.
* `assert_power_is_one_fact` — the screen/eyes/mouth/spill all derive from ONE window. Still right:
  here the window is "no cell seated", spanning the fall.
* `scripts/banner-verify.sh <asset> --period <P>` (6 checks) and `scripts/banner-video.sh` (frame
  ordering by `k`, never by glob).

Replaced entirely: the scene, the camera, the caption, and every pose.

---

## VERDICT: the recreation route is a dead end. v1 stands.

Both recreation attempts were built and both were rejected, and the reasons are worth keeping
because they are about the SUBJECT, not the execution.

**Attempt A — trace the frames into flat vector, six poses.** Faithful pose by pose; `banner-verify`
ALIVE measured **3 distinct frames across a 3-second window**. 177 frames of continuous cel animation
is not six poses, and 177 vector poses is megabytes.

**Attempt B — recolour every frame's teal to clawd's orange by hue band.** Technically clean: smooth,
speckle-free, the source's own 177 frames and timing, 189 KB of mp4. Operator verdict:

> *"You just re-colored BMO. You didn't re-create the scene with Clawd as BMO. This may be a dead
> end here."*

That is the correct read, and it generalises: **a recolour is not a redraw.** clawd is a specific
form — the 11x8 pixel creature, square body, two square eyes, stub arms, four legs — and shifting the
hue of a DIFFERENT character's silhouette produces an orange BMO, not clawd. Fidelity to the source's
shot and fidelity to our own character were in direct conflict here, and the resolution is that the
character wins: a banner in this README exists to show clawd.

So the shipped asset stays **v1** — the front-facing dusk banner where clawd is drawn as clawd and
BMO is a costume laid over him. Its weakness was never the framing; it was that the batteries "just
look like blocks", fixed by giving each cell three charge segments (lit vs hollow) so it reads as
charged or flat rather than merely orange or grey.

**What NOT to retry:** re-attempting the shot-faithful recreation. The blocker is not tooling — the
clip, the frames, the palette and a working tracer all exist under `~/Development/.banner-ref` and in
this file's history. The blocker is that the goal itself trades our character away.
