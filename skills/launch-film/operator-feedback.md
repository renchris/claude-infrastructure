# Operator verdicts on launch films, verbatim

Two films. Natural TTS (2026-09-26/27) is below in full. claude-infrastructure (2026-09-25 → 10-13, with the sister repo
agent-context-sync's 2026-09-24 verdicts that set the bar) is the last section: one row per verdict that set a rule in
`SKILL.md`. Its full record (every verdict, the lead's calls, the timings) is private:
`~/Development/personal/launch-film-2026/BRIEF.md`, `STATUS.md` and `RETROSPECTIVE.md`.

Extracted 2026-09-27 from Claude Code transcripts (read-only). The operator's words are quoted exactly, including typos.
Film versions live under `~/Development/natural-text-to-voice-extension/`:
v1 `brag-output/` (the "reading room" version) · v2 `brag-output-2026-09-26-123925/` (the "launch keynote / voice orb" version) · v3 `brag-output-2026-09-26-151455/` (the "studio" version).

## Coverage: where the operator's words were found

| Session | Account | What it is | Operator prompts |
|---|---|---|---|
| 3345b730 | quaternary | v1 build, then the v2 lead | 1 opening prompt, 1 v1 critique, 2 mid-turn messages that the agent folded into the running turn |
| d81071ea, 81206bf5 | quaternary | `score` and `soundtrack` teammate sessions (music) | none |
| 60ccb8f4 | secondary | v2 build/deliver, then v3 research and orb | "Open for us", the v3 critique |
| 6ad56ebf | quaternary (cwd `…123925/work/sound`) | the origin pane, recycled | "Open for us", "I dont see it, open in finder", "Good to close?" |
| dac9bf63 | quaternary | v3 build/deliver | none (machine brief only) |
| ccec198f | tertiary, 2026-09-27 | v3 review, README embed | 1 re-ask, then acceptance, then README placement |

**How it was found.** Three kinds of transcript record carried the operator's words:
- `type=="user"` records with string content;
- `queue-operation` / `attachment.type=="queued_command"` records with `origin.kind=="human"`. These are messages typed while the agent was mid-turn, and the two v2 directions were found only here;
- `<bash-input>` records, where the operator ran `open …/brag.mp4` himself.

**What was not there:**
- No AskUserQuestion answers.
- No image-attached critiques of the film. The only operator image in these sessions, in 3afa727e, is about a stuck pane and has nothing to do with the film.
- No operator reactions to intermediate stills or storyboards.

**Every still and storyboard review was the agent's own.** v2's "5 review fixes" were the lead's own review. The v3 plan's "v3 — APPROVED" orb (`gltest/orb3.html`) was the lead's own decision (60ccb8f4, 21:04Z "The orb is designed."), and no operator message approved it.

## Chronology (UTC; CDT = UTC−5)

### 1. 2026-09-26T06:14:02Z · 3345b730 · before v1
> Create our launch video with https://github.com/latent-spaces/brag

- **Agent's response:** it ran `/brag-slim` and answered brag's intake questions itself (the operator gave no answers). It chose the tone "polished, in the project's own 'reading room' direction: Iowan Old Style, deep ink on light indigo, long holds, soft transitions".
- **The angle it chose:** "the voice is the product, so the music gets out of its way": music goes to digital silence under the real helper voice clips.
- **Delivered:** 07:49Z, 22.3 s.

### 2. 2026-09-26T17:35:39Z · 3345b730 · reacting to v1 (about 10 h after delivery)
> This is good. It's very "2000s classroom friendly" vibes. Can we make it more startup modern?
>
> We need the same energy as the latest and greatest innovation of a Apple launch product

- **Agent's response (17:39Z):** "The storyboard stays as you liked it; the restyle changes the look, the pacing and the sound, from gentle classroom to launch keynote."
- **What that meant:**
  - a black stage with the real UI floating in 3D;
  - big SF Pro kinetic type and a glow that breathes with the voice;
  - hard cuts to silence on every Speak click, on a 120 BPM grid;
  - the README pillars "Natural. Private. Fast.";
  - a new synthesized score. Brag's bundled music tracks were rejected because they had no documented licence.
- **Where it went:** a new folder (v2); v1 was kept.
- **Accepted?** Partially. "This is good" keeps v1's content and storyboard; its look was rejected as dated.

### 3. 2026-09-26T17:44:41Z · 3345b730 · mid-turn, while v2 was being planned
> Yeah, our product needs to compete with the design and brand guidelines of
>
> ElevenLabs
> SuperWhisper/WhisprFlow
> Awwwards
> Anthropic

### 4. 2026-09-26T17:45:52Z · 3345b730 · mid-turn, while v2 was being planned
> We need to showcase the ability of you the world class motion designer Opus 5.5

**Agent's response to items 3 and 4** (written into the v2 plan § "Operator direction, verbatim", 18:35Z), headed "Read as":
- a near-black stage;
- "one iridescent voice orb as the motif (ElevenLabs orb, SuperWhisper/Wispr glow)";
- an editorial Awwwards layout: SF Pro Display, an Iowan italic accent, mono uppercase labels, index numbers, grain;
- showy motion: per-character masked reveals with variable-weight swell, log-space zooms, damped springs, match cuts (orb takeovers, a shockwave), true motion blur.

**Delivered:** v2 at 19:44Z (60ccb8f4).

**Accepted?** No. The v3 critique (item 7) called the result "mvp ai template slop" with "purple gradient" vibes.

### 5. 2026-09-26T19:51:41Z · 60ccb8f4 · v2 just delivered
> Open for us

- **Agent's response:** it opened `brag.mp4` in the default player.
- **What this tells us:** the operator watches the delivered MP4 before judging it. No verdict came in this message.

### 6. 2026-09-26T21:19:58Z and 21:22:40Z · 6ad56ebf (origin pane) · v2
> Open for us

> I dont see it, open in finder

- **Agent's response:** it opened the mp4, jpg and share copy, then showed `brag.mp4` selected in Finder.
- **Then:** "Good to close?" → the agent answered yes (v2 folder complete).
- **Note:** this happened after the v3 direction below, in a different pane. It is only a delivery-access request, not taste.

### 7. 2026-09-26T20:13:50Z · 60ccb8f4 · reacting to v2
> Can we push the design quality from "mvp ai template slop" to "world-class design studio"
>
> Also can we well-design the orb? We need something world-class like what ElevenLabs and ChatGPT Voice has but EVEN BETTER
>
> Also we need less "purple gradient" prominent vibes whicih is the "AI slop" theme default.
>
> https://elevenlabs.io/
> https://chatgpt.com/features/voice/
> https://elements.ai-sdk.dev/components/persona
> /read-twitter https://x.com/dan__marek/status/2013219980838412664
> /read-twitter https://x.com/zzzzshawn/status/2080235762751361160
> /read-twitter https://x.com/insporadesign/status/2097733377650499861

**Agent's response:** research subagents, one per reference, each producing notes and a contact sheet. It then took the colour source from the product's own palette ("the film's colour should come from the product rather than a template default") and iterated the orb through four versions:
- v0 (lapis marble): self-rejected;
- v1 (glass marble / lava lamp that drifts toward lavender): self-rejected;
- v2 (pearl/chrome that landed on magenta): self-rejected, with the reasoning "the world-class references are SOFT: velvety volumes, no hard specular, grain, one hue";
- v3, adopted: "cobalt ink blooming in a milk-white sphere on paper", driven by the voice's real spectrum.

**v3 design system:**
- a warm light stage `#EFEDE8`, never dark;
- colour only in the orb, plus the product's real UI blue;
- near-black SF Pro at weight 400–500;
- no auras, vignette, glow blooms, iridescent or gradient text, streaks or shockwave, all named as "v2 'AI slop' tells";
- the mono uppercase labels and index numbers dropped;
- ink-wash transitions.

**Built and delivered** in dac9bf63 at 21:42Z (16:42 CDT), 22.5 s, VERIFY PASS.

**Accepted?** Yes, see item 9.

### 8. 2026-09-27T21:09:11Z · ccec198f · v3 (the operator had apparently not watched it yet)
> Investigate, locate, and pickup our work
> re-working our brag film for making it more startup focused and less purple gradient dominant

- **Agent's response:** it found v3 already finished and summarized v1→v2→v3.
- **One gradient deliberately kept:** the product's real icon tile and the popup button. It is kept for product truth ("Replacing them would mean showing an icon that isn't the one in the Chrome Web Store").
- **Its offer:** "Tell me which parts don't feel startup enough or still read as purple gradient, and I'll start a v4."
- **The operator's action:** at 21:11:25Z he ran `open …/brag-output-2026-09-26-151455/brag.mp4` himself.

### 9. 2026-09-27T21:12:32Z · ccec198f · after watching v3
> Great. Add to our README.md

- **Agent's response:** it uploaded the film as an attachment on GitHub issue #2 and embedded it as a player with a caption stating only verified facts.
- **Landed:** commit `03fe526`.
- **Accepted?** Yes. This is the only explicit acceptance of a film version.

### 10. 2026-09-27T21:22:37Z · ccec198f · v3 in the README
> position launch film as the first hero/header asset

- **Agent's response:** it moved the film directly under the title and badges, ahead of the existing Heart hero video.
- **Landed:** commit `0d3c429`.

### 11. 2026-09-27T21:24:18Z · ccec198f · about the whole process
> Great. Shall we distill the qualities of us coming down to this film output into notes/knowledge/skill? I want to take this essense and apply it to our films for our other repositories ie. claude-infrastructure.

This is the request that led to this extraction.

## Inferred taste rules (only rules the quotes support)

1. **The first competent pass is kept for its content and story; the look is judged separately.**
   Quote: "This is good. It's very "2000s classroom friendly" vibes." The storyboard, the two voice lines and the truth rules survived every version, and only the look, pace and sound changed.
2. **Aim for startup-modern at the level of a flagship Apple launch, not a gentle, classroom or reading-room tone.**
   Quote: "Can we make it more startup modern? … the same energy as the latest and greatest innovation of a Apple launch product". Reinforced a day later by "more startup focused".
3. **Benchmark against named best-in-class brands, not generic "good design".**
   Quote: "compete with the design and brand guidelines of ElevenLabs / SuperWhisper/WhisprFlow / Awwwards / Anthropic". For the orb: "like what ElevenLabs and ChatGPT Voice has but EVEN BETTER".
4. **Showing off craft is wanted, but visible AI-template tropes read as slop.**
   Quotes: "showcase the ability of you the world class motion designer Opus 5.5", then, about the result: "mvp ai template slop" → "world-class design studio".
   What satisfied him: v2's showy tropes (iridescent orb, glows, gradient text, mono index labels, shockwave) drew the "slop" verdict, and v3's restrained studio look drew "Great."
5. **Avoid purple gradients as the dominant look; the operator treats them as the AI-slop default.**
   Quotes: "less "purple gradient" prominent vibes whicih is the "AI slop" theme default", and again: "less purple gradient dominant".
6. **The motif, here the voice orb, must be designed world-class and should beat the references rather than imitate them.**
   Quote: "can we well-design the orb? … EVEN BETTER".
7. **The operator supplies references and expects them to be studied.**
   Quote: the six links and three `/read-twitter` calls in item 7.
8. **He judges by watching the delivered MP4, so make the deliverable easy to open.**
   Quotes: "Open for us" (twice), "I dont see it, open in finder", and his own `open …/brag.mp4` before "Great."
9. **An accepted film is a hero asset.**
   Quotes: "Great. Add to our README.md", then "position launch film as the first hero/header asset".

Not supported by any operator quote, and so not rules:
- the truth rules (real helper audio, nothing under speech, no invented UI);
- the warm light stage specifically;
- the cobalt-ink orb;
- the music choices.

These were all the agent's decisions. The operator only accepted the v3 whole with "Great." He never commented on individual elements.

**Status of the inferred rules on 2026-10-14.**
- **Rule 1 holds.** It is now the story gate (`SKILL.md` §1).
- **Rule 3 is narrowed.** Named brands and reference films set the finish bar only. Restaging them was rejected: "We are WAY to overfit exact copy cat of the original source film" (2026-10-02).
- **Rule 6 is generalised.** The carrier comes from the story's value points, through `SKILL.md` §1.5, not from a signature object chosen first.
- **Rule 9 is extended.** A hero film plays with sound (2026-10-13).

## claude-infrastructure, 2026-09-25 → 2026-10-13: the verdicts that set the rules

The first two rows are on the sister repo agent-context-sync; they set the bar the claude-infrastructure film was held
to. Section numbers refer to `SKILL.md`.

| Date | Shown | Verbatim | Rule |
|---|---|---|---|
| 09-24 | agent-context-sync: animated-SVG hero | "This needs to be more of a hero launch video rather than a secondary supplementary infographic" | §1.5 tutorial |
| 09-24 | agent-context-sync: canvas world, hard cuts | "This is cool but a) the scene is very abstract b) there is no 3d transpilation transitions from scene to scene to scene." | §1.5 abstract; §3 cuts on a match |
| 09-25 | 20 fps README loop | "make the film more smooth (ie. 60fps), and the transitions ease and smoother (everything moves and jars so fast I don't feel oriented nor I can read anything in time)" | §5 |
| 09-27 | Natural TTS look on this repo | "This is 'cleaner' like the NaturalTTS style but I think we overfit to the exact output style and not the methodology of design and composition" | Do NOT carry the look |
| 09-28 | day-sheet film, every encoding gate passed | "looks very broken, and reads more like a basic 'prezi' high school slides presentation … it inherits the same theme as what we did for naturalTTS" | §0.5 |
| 09-28 | bake-off film its own session scored BETTER | "This one isnt good -- overfit to that github example and its not relevant to us by being just fast moving and not actually good design or informational" | §0.5; §5 |
| 09-28 | three art-directed style frames | "All these looks so abstract and 'mvp demo slop' basic. NOT a 100M+ YC-backed company …" | §1 |
| 09-28 | (ruling; reversed on 10-04) | "We are more caring about the design of the shoot rather than the idea of the shoot itself, so we can apply the same theme against content agnostic to the content." | superseded by §1 |
| 09-29 | three.js room, borrowed accent | "The yellow text feels out of place. The enviroment looks very 'school project 3d render' 'ai slop'" | §2.2; Do NOT borrow an accent |
| 09-29 | Cycles room from scanned assets | "Quality has improved but it's still 'blender demo' quality and not world-class design/motion movie studio 'hyper-realism'." | §2.2 |
| 10-01 | film refined through nine critic rounds | "I don't think we signed off on this general idea before [the] refinement you've done for the past two days straight." | §0.5 |
| 10-01 | same film | "we arent looking for a tutorial walkthrough from the 2000s" | §1.5 |
| 10-01 | real capture naming another project | "it highlights 'TrueMemory 2.0' as its hero image which is another project not ours of claude-infrastructure which defeats the purpose" | §1.6 |
| 10-01 | licensed footage with type laid over it | "This is just stock footage with basic text overlay." | §0.11 |
| 10-01 | real screens lit in the dark | "No. so dark, b-roll abstract and gloomy." | §2.3 |
| 10-01 | narrated dark cards | "this looks like some cutscene narration. no." | §0.11 |
| 10-01 | reference shot vs "our shot" of screenshots | "we care about the VISUAL design presentation not the actual text content in our text" | §2.4 |
| 10-02 | six style frames restaging references | "We are WAY to overfit exact copy cat of the original source film" · "We need some ORIGINAL storyboarding not just exact copies from our sources" | Do NOT restage |
| 10-02 | 'Float' storyboard (a physical metaphor) | "Yes — take it to motion" (a story yes; the direction later died on its medium) | §1.5 |
| 10-02 | paid video key at its limit | "Use local LTX instead" · "We should definetly use free first especially since we are storyboarding" | §0.10 |
| 10-02 | generated-video motion test | "this entire avenue of video generation, not what we select within it, is a dead end" | §0.11 |
| 10-03 | UI objects acting out a metaphor | "No this is so weird and makes zero sense at all." | §1.5 |
| 10-03 | literal product walkthrough | "No. This is very "tutorial"" | §1.5 |
| 10-03 | object built in code | "The motion design is good but its abstract and i dont understand it" | §1.5 |
| 10-03 | grounded object, captions | "the caption text is just placed on top and doesn't feel integrated into the scene and enviroment. Still kind of feels like a tutorial video" | §2.4; §3 |
| 10-03 | three probes | "They are all so abstract. this is not a 100M+ company and product launch video." | §1 |
| 10-04 | (question) | "Why cant we see how we came to producing the NaturalTTS from prompts/first principles and not overfit to the actual output?" | §1 |
| 10-04 | first-principles v1 (walls of real terminal text) | "It still reads very noisy and confusing (the very thing claude-infrastructure is put against)" | §1.4 |
| 10-04 | (direction) | "First tell me the value points we will go through in the story, and how we are representing that in the video" | §1.3 |
| 10-04 | (idea) | "we should probably create some story with a "swarm" of efficiently self managing Clawds" | §1.5 |
| 10-04 | 23 s rough story film | "Yes" | §1 gate |
| 10-04 | look A/B (two 23 s films) | "We want higher fidelity the better, so 3D over 2D, but can we increase "hyperrealism" detail?" the pure white makes it look like purgatory rather than utopia." | §2 |
| 10-04 | look stills | "As a filmographer we need multiple shots at multiple angles/motions/transitions." | §3 |
| 10-04 | look stills | "Make sure that the text is somehow beautifully and (and still clearly presentable) into the scene rather than just text overlay." | §2.4 |
| 10-04/05 | words on cloth | "The text needs to be more creative than just text on a piece of paper which is not that much better than text overlay.  can we ideate before you generate?" | §2.4 |
| 10-05 | four unrelated lettering props, after four bare "Change it" | "Props feel random" | §2.4; §0.6 |
| 10-06 | signs built in the scene | "No. We need PIXAR STUDIO BOX OFFICE QUALITY. We need to BEAT the quality from nano banana frames -- we regressed in fidelity and detail to stock assets like stock text placed in" | §2.4 |
| 10-06 | storyboard, changes C1–C13 | "Approve all (Recommended)" · "What are all the MECE "features" we are presenting in our video?" | §3 |
| 10-06 | storyboard additions C14–C19 | "Ensure it looks organized at scale, not disorganized/mess/inefficient" · "Re-measure with a stated rule (Recommended)" | §3; §5 |
| 10-07 | lettering plates | "The text still reads as font, can we ensure the prompt ensures that no same character is identical" | §4 |
| 10-07 | board not in film order | "Does the storyobarding makes sense? It looks like we have the close up b roll at the end after the exit scene of claude infrastructure sign" | §3 |
| 10-07 | take-17 stills | "Render the full film (Recommended)", which started a 34.8 h render before any motion preview | §0.3; §5 |
| 10-08 | that render | "Yes this scene is right but everything in jumping so fast and jarring 'spawning' out of no where seems broken or like a low fidelity simulation" · "looks like clawd is standing inside/on the laptop" · "at 15 seconds the music just cuts out and then its dark and gloomy for no reason" | §5; §4; §6; §3 (the last note traces to board changes C8 and C16) |
| 10-09 | preview, music bed 10–25 dB down | "The halfway point cutoff without music is so jarring and the darkness makes it feel broken" · on which dark: "The mood" | §6; §5 |
| 10-09 | preview with the real system chime | "Using our real sound effects the two permission signs feel out of place and a "stop" from the movie immersiveness." | §5; §6 |
| 10-09 | in-stride preview | "it looks like a cloud appeared but there was no main clawd" · "i cant see a paint brush" · "turning around looks broken rather than an emote" | §5 |
| 10-09 | set | "i think the ocean is meant to be correct" · "right now they are both static like still images" | §4 |
| 10-09 | length | "Appropriate length for the best film, rather than trying to fit the best film within a set length" | §1.7; §5 |
| 10-10 | round-4 preview; sound A/B | "Yes, motion is right" · "Mix of them" · "Score + ElevenLabs effects (Recommended)" | §5; §6 |
| 10-13 | final film | "Yes" | §8 |
| 10-13 | README hero as an animated WebP | "How come the image quality looks crushed … also no sound, ensure that we have it to play sounds like we do with our NaturalTTS film" | §9 |
