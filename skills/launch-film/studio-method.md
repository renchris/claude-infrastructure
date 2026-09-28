# Studio method: what separates a designed launch film from a slide deck

Read this before designing a film and again before the stills review. `SKILL.md` owns the bar, the truth rules and
the procedure; this file owns the craft rules and the design gates that make a film read as designed rather than as
slides.

**Source.** Distilled on 2026-09-28 from @0xMovez's X Article "How to build motion design studio with Opus 5.5
(Full-course)" (https://x.com/0xMovez/status/2104216919033192746). Also from the 21 posts it embeds, their threads,
29 videos measured frame by frame, 15 figures, and the repos it links: JohnHeibel/PDoomVideo,
JohnHeibel/ClaudeAnimationBase, buildwithhanif/claude-animation-skill, WinterArc21/Battle-of-Austerlitz-Film,
guanmo-ai/awesome-ai-motion and athemeroy/awesome-opus-5-5-videos, plus whatships.com. The rules below are ours,
drawn from measurements. The raw extraction, quotes, frames and per-film teardowns are in a private study on the
operator's machine (`~/Development/personal/opus-motion-studio-study/`, `KNOWLEDGE.md` first). Third-party
teardowns stay out of this public repo.

**Why it exists.** On 2026-09-28 the operator rejected the claude-infrastructure film as "looks very broken … a
basic 'prezi' high school slides presentation" (`operator-feedback.md`). That film already had everything the
course teaches: a `seek(t)` page, springs, a synthesized score, contact sheets, a purity check and a verify script.
**The engine was not the gap.** The gaps were the craft rules in §2 and gates that measure the picture (§4).

## 1. What the course teaches that we already do (keep)

A pure function-of-time page rendered frame by frame. Seeded noise only. Four subframes blended to 60 fps. One
timeline that both picture and sound read. Music synthesized on that timeline. A contact sheet before the full
render. Three additions from it are worth taking:
- **A value with several targets is a sum of springs.** Use one closed-form spring per change, each starting at its
  own time (`v = v0 + Σ Δᵢ·spring(t − tᵢ)`). Motion stays continuous, and frame N renders without simulating
  frames 0..N−1.
- **A rejection rewrites the shot list, not the code.** The approval gate is a document loop.
- **Reflow per format, never crop.** Write the layout as `layout(w, h)`: stacked in 9:16, side by side in 16:9.

## 2. The craft rules (measured in the films that read as designed)

1. **One invariant carries the whole film; nothing is ever a new layout.** The best films hold a single element
   through every shot and change everything else. Examples: one horizon line at one height across ~35 shots, one
   container pinned to screen centre for 14 s, one fixed broadcast HUD. A deck has no invariant, because every
   slide is its own layout. Build a *set* the camera moves through, not cards.
2. **Content is absent while its container transforms.** Measured in the best UI-morph film: type leaves within
   2–3 frames of the morph starting and returns 0.35–0.55 s later, when the spring is ~80 % settled, staggered
   35–60 ms top to bottom. Colour flips happen while the container is empty. Motion blur then only ever smears an
   empty edge. This rule prevents both of the 2026-09-28 defects: the smeared card and type crossed by lines.
3. **An anchor element survives each change and becomes the next state.** A progress bar becomes a volume slider;
   the selected row becomes the toast; one accent dot is carried through four states. This, more than the
   container, is what makes a sequence read as one continuous thing.
4. **The real product changes state in every beat.** Typed input, a click, a ✓, a count-up, a toggle, a commit
   landing. A panel that only appears is a slide. Break screenshots into components and animate the parts (the
   single prompt line that visibly turned one launch film from slides into motion design). Use the product's
   own strings, not slogans.
5. **Motion never stops, and reads never overlap.** The "prezi" signature is measurable. Measure static share,
   meaning the fraction of frames whose mean absolute difference from the previous frame is under 0.5/255: the
   best reels sit at 25–28 %, while the same prompt on a weaker model gave 87 % (hard cuts between held cards).
   The opposite failure, "can't read anything in time", is equally real, and studio dev-tool films hold a calm
   state for 5–7 s. Both constraints hold at once: keep the frame alive (camera drift, the object, data ticking)
   while each read gets at least 1.0 s + 0.3 s per word, and never start a read before the previous one ends.
   Write the reads down as a timed sheet before code, and let the reads set the film's length.
6. **Pace on a grid; change on bars.** Use 120–128 BPM. Put section changes on bar lines, small events on beats,
   and the first big visual on the bar-2 downbeat. Leave 80–100 ms of digital silence over an emptied frame
   before a drop. Make the film a whole number of bars.
7. **Springs with a little mass.** Measured on the best UI films: containers ζ 0.75–0.88, k ≈ 260–350 (unit mass,
   seconds), 2 % settle in 0.23–0.46 s, overshoot ≤ 5 % (about 9 % only on a big reveal). For an indicator, a
   stiffer leading edge (k≈460, ζ≈0.75) against a softer trailing one (k≈235, ζ≈0.96) gives about a 30 % stretch
   mid-move. The lockup is critically damped. Type never overshoots. A move that eases over 0.5 s reads as a
   slideshow transition: snap the change, and put the ease on the settle.
8. **Scale: the subject fills the frame.** The product's real unit takes ≥ 40 % of the frame in every beat. No
   frame is more than half empty field for over 1 s. Show UI flat or macro, never tilted past about 15°, and keep
   frame 0 on the subject.
9. **Type is a system with fixed jobs.** Use 3–4 voices at most: a display voice for claims, one emphasis voice,
   mono only for real data, and a text face for captions. Set copy in runs of 1–3 words that land on events.
   Vary scale on purpose, from caption size to type that fills the frame. Never let text alone be the shot.
10. **Prove the claim with one artefact changing state,** before → after, and build the film toward that frame.
    Studio examples: live canary numbers flipping, issue IDs flowing into a release, an empty notifications panel
    as proof that the system is healthy.
11. **Every seam is motivated, and no seam repeats.** Carry an object across the boundary: letters collapse into
    the dots of the next scene, or the camera pushes into an element and comes out in the next place. Allow at
    most one hard cut per two sections, and never the same transition twice in a row. A uniform flash-and-punch
    on every scene start is the slideshow tell (it is measured in a first-generation film that its second
    generation fixed).
12. **Hold the lockup,** small and alone, for 1.5–6 s.

## 3. The crowd's house look (what viewers now read as "AI-made")

On 2026-09-22 hundreds of near-identical prompts produced films that rhyme. Each of the following needs an explicit
reason in the brief before it appears:
- near-black `#131315` or cream `#EFEDE9` ground with a clay-orange accent;
- an italic-serif accent word, and a full stop in the accent colour;
- a HUD printing BPM, bar, fps or spring constants, and corner labels, brackets or timecodes;
- easing, or the model itself, as the subject;
- dotted spheres, circle → triangle → star morphs, chromatic fringes and full-frame colour flashes;
- an "open to new work" end card.

Bans remove tells and add no craft. The rejected film obeyed every ban and still read as a slide. Before the
storyboard, the one signature object gets a material study: several rendered variants with a reject log (studios
publish 10–20 such explorations for one launch).

References leak content. A reference folder or repo handed to the model carried its gags into both re-runs that
used it. **Never hand over our own previous film as a reference.** Write down what to take from a reference
(palette, type, pacing, transitions) and what never to take (subject, logos, characters).

## 4. Design gates (machine-checked; `verify` fails the film)

Every self-scored "8+" critique loop in the corpus shipped visible defects. One film had the overlap rule in its
own spec and still shipped overlaps. The course's own contact-sheet command reviews only the first 15 s, at 270 px
tiles. A 2 fps sheet misses a 0.1–0.3 s smear. So the gates measure the frame. Where the page can report its own
geometry, measure there; otherwise measure the decoded MP4.

| Gate | Fails when | Catches |
|---|---|---|
| Text vs line | a visible text box intersects a stroke, rule or another text box (0 px tolerance) | type crossed by lines; labels overrun by their leaders |
| Minimum type | text meant to be read renders under ~24 px cap height at 1080p (below that it is texture, and must not be words) | unreadable captions and axis labels |
| Text in transit | a text layer is drawn while its container's transform is changing | smeared, skewed cards mid-transform |
| Subject coverage | for more than 0.3 s the subject covers under ~15 % of the frame, or ink is under 2 % | subjectless frames, hairlines on empty paper |
| Static share | more than ~40 % of mid-film frames are static (mean abs diff < 0.5/255), or any hold outside the lockup is over ~1.2 s with no moving element | slide grammar |
| Coverage | the stills reviewed do not cover 100 % of the duration (`tiles × interval ≥ duration`) | reviewing only the first 15 s |
| Transition strips | a state change has no strip of every frame from 0.3 s before to 0.5 s after | pops, smears and overlaps between sampled frames |

The thresholds are starting values drawn from the measured films; calibrate them per film and record the values used.
Passing the gates is necessary and not sufficient. The last check is still a human read: after one viewing at phone
size, can someone say what the product does?

## 5. Review at three zoom levels

- **Sheet:** the first, middle and last frame of every shot, covering the whole film.
- **Strip:** every consecutive frame of each transition and key motion.
- **Crop:** full resolution on anything that carries the story (a string, a face, a contact point).

Look for contacts, z-order, see-through sets and cut-off words. A frame-diff or determinism gate cannot see these.
Give notes in camera words ("push in on the ✓", "hard cut here", "slow this zoom to 0.7×"), because vague notes
produce random changes.

## 6. The brief (what the long prompts actually contain)

The most-cited long brief (~9.6K characters, dictated) is mostly **taste**: a genre the audience already knows,
applied as a whole package; what not to be ("I think it's kind of slop"); composition rules for type and subject;
and a hook instruction. Around the taste it names resources (skills, reference folder, repo, keys, budget) and a
self-review order ("watch the entire video multiple times, take screenshots"). The tidy nine-part template that
circulates is a later synthesis, not the brief itself. When a film is built in parts, the director first writes an
animation guide and a storyboard. The storyboard names every shot's event, its timed reads and its **Out** (how it
hands over to the next shot). The style bible is pasted verbatim into every part, because paraphrase drifts.
Consistency comes mostly from shared code (one frozen API for type, colour and motion), not from adjectives.

## 7. Sound

- One clock: the score and the effects are synthesized from the picture's own cue sheet, and each effect is
  placed by its measured peak, about 0.03 s before contact.
- Heavy sounds (the thump, the transition swell) go on downbeats with the scene changes; light UI sounds go on the
  off-beats.
- Hold the kick for bar 1 and drop it on bar 2. Leave true silence before the drop.
- Master to about −14 to −16 LUFS, with true peak ≤ −1 dBTP.
- **The film must read with the sound off.** The strongest dev-tool launch films ship with the sound quiet or
  absent. Avoid the "clicky techy synth" bed that viewers now name as the default.
