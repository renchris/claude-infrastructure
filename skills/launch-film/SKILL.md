---
name: launch-film
description: "Make, re-work or audit a launch film or README hero video: story, look, board, stills, motion previews, sound, final render and README, each ending on one operator yes, with checks for past rejections. Owns taste; hyperframes owns mechanics."
---

# Launch film

Story → look → board → stills check → motion previews → sound → one final render → README. Each step ends on an
operator question, and nothing downstream is built before its yes. Carry this order to a new product, never a finished
film's look.

Read this file top to bottom. Open an appendix only when a step names it:
- `operator-feedback.md`: every verdict verbatim and dated; the evidence for each rule here.
- `studio-method.md`: craft rules and design gates for 2D and code-built films.
- `pipeline.md`, `design-gate.md`, `kit/`: the web (CDP) pipeline, for 2D films and for the §1 rough film.
- `pipeline-3d.md`: the path-traced pipeline (state page → Blender Cycles), previews, resumable renders, paid sound.
- `reference-film-method.md`: reading a reference film for method, after §1.

## 0. Working rules (every step)

1. Write every operator word verbatim and dated into the project's `BRIEF.md` before acting on it; keep timings in
   `STATUS.md`. A recycled context reads both first.
2. One decision per question, worded "(yes / what to change)". When the operator is curious about an alternative, show
   both side by side instead of arguing.
3. A "(Recommended)" option must pass every rule in this file: never a render longer than a preview before §5, a fixed
   length, a beat that halts the film, or a raw system sound. A recommended pick stays provisional until the motion
   yes: four 2026-10 picks were reversed at motion review, and "Render the full film (Recommended)" started a 34.8 h
   render before anyone had seen the motion.
4. Deliver, then ask. Send a copy under 30 MiB and `open` the master, and ask only after the send has succeeded: a
   question sent beside a failed upload may be answered unseen. Order: film, then board or stills, then the question.
5. Only the operator's yes counts. A critic's SHIP, a passing gate or your own "APPROVED" is a floor: a film refined
   through nine critic rounds to SHIP drew "I don't think we signed off on this general idea" (2026-10-01).
6. An answer that is not an answer (a side question, a typed comment, silence) is recorded verbatim and acted on as
   named, and the same gate question is asked again. A no that names no fault gets one multi-select of candidate faults,
   measured ones included: four bare "Change it" answers became "Props feel random"; "which dark thing?" became "The
   mood".
7. A "Yes, but…" freezes everything it did not name. Fix the named faults, nothing else.
8. The session that asked acts on the answer within the scope it was given; relay only what changes scope ("Yes — take
   it to motion" waited 11 h for a relay, 2026-10-02).
9. While a question is open, run the state measurements and the budget probe; never start the long render. When the
   operator must act (a permission, a key, a publish), give the exact action, then poll its observable state in a
   bounded background loop instead of waiting to be told.
10. Spend: free first; paid tools only for an approved use, with the cost stated before asking. When a paid route hits a
    limit, fall back to the free one at once.
11. Ruled out unless the operator reopens them: a human shoot or studio, stock footage with type over it, generated
    video as the film's basis, narration over dark frames.

## 1. Story gate

From the repo, with no look, reference or medium yet (`kit/brag-slim/SKILL.md` for the intake):
1. The product in use: its 2–3 beats (entry → action → result).
2. The intake: what it is, who it is for, what sets it apart, the most impressive true claim, the visual hook, what to
   show.
3. **Value points, MECE.** One row per point: the point · the mechanism in the repo that does it · how it appears on
   screen as an action. Split along the operator's axes; write down what is left out on purpose.
4. **One angle** that makes the value felt, not explained. Do not picture the problem the product removes: walls of
   real terminal text for a product that quiets them drew "It still reads very noisy and confusing" (2026-10-04).
5. **Carrier mini-gate.** In chat, send the value-points table with 2–3 carrier candidates and ask "Which carrier, or
   your idea?". In 2026-10 the operator's own carrier came straight after this table ("First tell me the value points
   we will go through in the story…", then "a "swarm" of efficiently self managing Clawds"). Characters from the host
   product's world acting out its real mechanics, one throughline followed through every shot, passed. UI objects
   acting out a metaphor read as "so weird and makes zero sense"; an invented object with no anchor read as "abstract
   and i dont understand it"; a UI walkthrough read as "very "tutorial"".
6. **Truth.** Every number on screen is measured under a written rule; every mechanic shown is real; stakes are true.
   Names on screen belong to this product. Real UI, icons and sounds, when shown, keep their real form but are
   translated into the film's material, never pasted in.
7. Beats, then a deliberately rough film (any medium, plain look) at whatever length its reads need (≥ 1.0 s + 0.3 s
   per word). Report the length; never offer one as a choice.

**Gate:** "Is this the right STORY, even if the look still needs work? (yes / what to change)". On yes the story is
frozen; a look note never changes it.

## 2. Look gate

1. Two looks of the frozen story side by side, each at full length with its own mix and its own words treatment, each
   labelled with its measured full-render time. (In 2026-10 this was two 23 s films; a stills-only A/B is untested.)
2. Fidelity means finish against the operator's named comparators, not a number of dimensions. In 2026-10 a
   path-traced, dressed, worn and inhabited set passed (its props were built in code); raster code-built 3D read as
   "school project 3d render" and an undressed set of scanned assets as "'blender demo' quality". A 2D film passed for
   Natural TTS.
3. Bright and inhabited: never dark, never an empty void ("purgatory rather than utopia").
4. **The words are part of the look.** List in-world ideas for them before generating anything ("can we ideate before
   you generate?"), show mock-ups of the chosen few, and let one idea carry every read: four unrelated lettering props
   drew "Props feel random". References and generated mock-ups set the minimum finish; preview one built element at
   100 % against its mock-up before building the rest ("We need to BEAT the quality from nano banana frames").

**Gate:** the operator picks a look. Then close it one element at a time (character, set, props, words), each with "Is
<element> at the bar? (yes / what to change)". Never offer a render longer than a preview here: in 2026-10, 14 of 15
"render the full film now?" offers drew look notes instead of answers, and the look stage ran 70.6 h.

## 3. Board gate

A storyboard in film format:
- script spine: words · feature · time;
- feature map: every feature against its repo mechanism, MECE, with what was left out. It is a coverage check: the shot
  list follows the carrier's action, and no shot exists only to show a feature;
- shot list, one row per shot: time (s, frames) · camera move as a verb, start → end framing · angle and size · lens
  and depth of field · staging and action · feature landed · on-screen words · the cut out;
- several set-ups, heights and transitions ("As a filmographer we need multiple shots at multiple
  angles/motions/transitions"); cut outside read windows, on a match (a held line, a whip, a shape, an object passed
  across the cut);
- every on-screen number re-measured, with its script beside the board;
- changes numbered C1…Cn, each separable, with a reason;
- the contact board generated from the edit list in film order with timecodes.

**Gate:** an answer per change. A board approves structure only. Light, sound, length and timing are judged on the §5
preview, so keep them out of the board question: two board-approved changes (a quiet window in the score, a sun moving
behind the stops) came back as "the music just cuts out and then its dark and gloomy for no reason".

## 4. Stills check (internal, before every render)

First, middle and last frame of every shot and every close-up, reviewed at three zooms (`studio-method.md` §5):
- staging measured from the scene state: nothing intersects anything (count = 0), and each subject has a clear gap in
  front of it;
- every close-up lens has a clear line of sight to its subject on every frame, ends included;
- the backdrop shows the same world in every shot, and nothing in the background is a still photo while the foreground
  moves;
- words live in the scene: one in-world medium that fits the set, made on screen by a visible maker, reading ≥ 28 px at
  1080p with contrast checked; hand-made lettering has no two identical glyphs ("The text still reads as font").

No operator question unless the look itself changed.

## 5. Motion gate (repeat until yes)

The final render is never the first full-length view of the motion. Each round:
1. **Measure from the scene state, before pixels:** each subject's own screen speed with camera motion removed (cap a
   named subject near 0.73 frame widths per second, 1,400 px/s at 1920 wide; the 0.47 widths/s whole-picture cap of
   the 2D loop gate is untested in 3D); move starts per beat (stagger them); intersections; loudness per second; mean
   light per shot.
2. **Render a cheap full-length preview with the sound** (`pipeline-3d.md` §4): half size, low samples, every other
   frame held. Reuse unchanged frames from the last round.
3. **Ask one question:** "Is the motion right now, and the staging, music and light with it? (yes / what to change)".

Every preview is held to:
- every change has a visible giver and receiver: nothing appears with nobody beside it, no lettering without a hand, no
  turn without a motive (2026-10: each mechanic a paw-to-paw pennant pass with both characters on screen, taught once
  close, then repeated wide);
- every appearance has anticipation (about 0.5 s) and a settle; a character beat holds about 1 s;
- the product's interruptions happen in stride, inside a camera move with the music running; a beat that halts the
  film to explain reads as "a "stop" from the movie immersiveness";
- many units at once read as order: events on the beat grid, staggered starts, no crossings ("Ensure it looks
  organized at scale");
- no dark or dead beat; "dark" can mean mood (energy dropping, a crowd going still, music thinning), which no luminance
  number catches ("The mood");
- 60 fps on everything that moves; every read ≥ 1.0 s + 0.3 s per word;
- length is an output: never squeeze beats to a clock, never pad ("Appropriate length for the best film, rather than
  trying to fit the best film within a set length").

**Gate:** "Yes, motion is right".

## 6. Sound (beside the final render)

- A product whose output is sound plays it as returned and gets the room (Natural TTS: music to digital silence under
  the voice). Otherwise the score never drops out; under a quieter beat, a few dB at most (a bed 10–25 dB down still
  read as "The halfway point cutoff without music is so jarring").
- Incidental system sounds (a notification chime) are translated into the score as an in-key accent, never dropped in
  raw.
- Paid generation only after the motion yes: A/B passes on the same picture, level-matched, cost stated first.

**Gate:** the operator picks a mix. Sound blocks only the finish, never the render.

## 7. Final render

Start the pixels on the motion yes. Budget from a timed probe at final settings on the heaviest shots, on the machine
as it is loaded: probe median × frames × 2 for a machine shared with other sessions. Write the budget down and re-check
it after 50 frames. (2026-10: scaling the preview by samples × pixels overestimated 8×; the two full renders ran 1.7×
and 2.2× their probe-based estimates.) One renderer, resumable, verified frames, and a watcher that speaks only on a
stall, a rate change over 2× or done (`pipeline-3d.md` §5).

## 8. Finish, verify, ask

- One colour conversion; a lossless master; an H.264 + AAC deliverable. Assert with ffprobe: size, fps, frame count =
  round(duration × fps), an audio stream, loudness and true peak in band.
- Every gate reads duration, beats and splices from the cue export, never a constant, and prints which checks ran and
  the frame count it read. A pass with a skipped section is a fail.
- Watch it end to end, then deliver per §0.4 with its board: "Is this the launch film? (yes / what to change)". In the
  same message, ask for whatever §9 needs from the operator (browser automation for the upload, the publish go).

## 9. README

A film with sound is the README hero as GitHub's inline video player at master quality, never an animated WebP (silent,
visibly compressed). An animated WebP is only for a silent loop that was never a film. A session brief that says
otherwise is wrong: fix the brief.
1. `gh issue create` a closed issue "README media: <film>", its body saying what it hosts and not to delete it.
2. Upload the master, not a send copy, as an attachment (100 MB on GitHub Pro). There is no public API for
   attachments; a logged-in browser uploads it.
3. Put the bare `https://github.com/user-attachments/assets/<uuid>` URL on its own line under the title and badges;
   caption with verified facts only.
4. `gh api markdown -f mode=gfm -f context=<owner/repo> -F text=@README.md` must render a `<video>` for that uuid; then
   check on github.com that it plays with sound at full size.

**Gate:** the hero equals the master in resolution, frame rate and audio.

## 10. Worked examples (sequence and verdicts; their looks are not templates)

**Natural TTS, 2026-09-26/27.** One prompt, "Create our launch video with https://github.com/latent-spaces/brag" →
brag-slim intake → one angle → v1: "This is good. It's very "2000s classroom friendly" vibes" (story kept) → two look
re-rolls → "Great. Add to our README.md". README via an issue attachment (`03fe526`), first hero asset (`0d3c429`).

**claude-infrastructure, 2026-09-25 → 10-13.** About 25 directions without a story yes that held (re-skins of one
script, then starts from a look, a reference or a medium) → "Why cant we see how we came to producing the NaturalTTS
from prompts/first principles and not overfit to the actual output?" → §1 re-run → story "Yes" about an hour later →
look A/B → board → a 34.8 h render before any motion preview → four previews → "Yes, motion is right" → 81.4 h final →
"Yes" (2026-10-13) → README WebP: "crushed … also no sound" → attachment video (`24cb58e9f`). Verdicts:
`operator-feedback.md`. Full record: `~/Development/personal/launch-film-2026/` (`BRIEF.md`, `STATUS.md`,
`RETROSPECTIVE.md`, `first-principles/`).

## Do NOT

- Carry an approved film's look to another product ("we overfit to the exact output style and not the methodology of
  design and composition").
- Restage a reference's shot or borrow its accent colour. If a stranger could name the reference from our frame, redo it.
- Use the AI-template tells (`studio-method.md` §3).
- Hand the model our own previous film as a reference: references leak content.
- Use music without a documented licence.
- Cite `file:line` in new notes; cite a grep.
