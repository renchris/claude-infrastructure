<!-- markdownlint-configure-file { "MD013": false } -->

# Boundary: launch-video, launch-film and demo-recording

Source: METHOD §6, which rests on `skills/launch-film/SKILL.md` (§0.11, §1.6, §9, "Do NOT"), `skills/launch-film/operator-feedback.md` and `skills/demo-recording/SKILL.md`. Everything in §2 below is INFERRED in METHOD itself: nothing in the sources tests how the skills coexist.

## 1. Which skill

- **launch-video** (this skill): whenever the founder's own voice or face shows the real product on a social feed. That covers every shipped feature, every "check this out" moment, the team update, learning which message and channel convert, and the polished quarterly launch. Farza's quarterly launch is "something I'm really proud of" [15:57]-[16:02], made with a filmmaker and with the founder on camera, so it is this skill's produced register at higher effort. It is not launch-film, which rules out "a human shoot or studio" (launch-film §0.11; METHOD §6).
- **launch-film**: a README hero film with sound, or a product's first public face on GitHub. Use it when no founder will be seen or heard, or when the piece must stand unchanged for months. METHOD §6 says "when no founder will be on camera", but §8 q1 maps a voice-only founder to the raw screen take, so a voice-only founder's social demo stays in launch-video (INFERRED resolution of a tension inside METHOD).
- **demo-recording**: a silent animated WebP loop of a flow in a README, below the hero (§6).
- **Neither seen nor heard**: launch-video does not apply. Route to launch-film for a hero film or demo-recording for a silent loop (§8 q1).
- **One-shot channels** (Launch HN, Product Hunt): spend them only on substantive releases (X1's advice, matching his "maybe once a quarter" [15:57]). Each takes whatever finished asset the release has, the produced demo or a launch-film hero. The copy follows each channel's own rules (§3.1 step 11; `copy.md` §4).

**The words "launch video" are ambiguous here.** The operator has used them for a launch-film hero: "Create our launch video with https://github.com/latent-spaces/brag" (launch-film §10; operator-feedback item 1), "This needs to be more of a hero launch video rather than a secondary supplementary infographic" (operator-feedback, 09-24) and "this is not a 100M+ company and product launch video" (operator-feedback, 2026-10-03). Triage by what the piece is, not by the words:

| Signal in the request | Skill |
| --- | --- |
| README, a GitHub page as the destination, "hero", "first public face", no founder seen or heard, a README or GitHub piece that must last for months | launch-film |
| "Create our launch video with <repo URL>" that names no feed, voice or face | launch-film, with no question (its §10 precedent) |
| A silent loop of a flow for the README | demo-recording |
| The founder's voice or face, a social feed (X, Instagram, YouTube, TikTok, LinkedIn), a shipped feature, "check this out"; a voice-only founder's demo; a YouTube library demo | launch-video |
| A finished, approved launch film going to social feeds | launch-video, Stages 6-9 only (§2 rule 7) |
| None of these is clear | Ask one question: "Is this for a social feed in your own voice, or the README hero with no founder seen or heard?" |

**HyperFrames' own `/product-launch-video` route is a name collision.** Its triggers include "launch video for X"; its input is a website URL or a script naming a site; it captures brand assets and builds a promo, site tour or showcase; and it maps "X / LinkedIn / Instagram feed" to 1:1 (`~/.claude/skills/hyperframes/references/routes/product-launch-video.md`). That is neither this method nor launch-film. Never route a founder demo there, and keep X exports at 16:9: his measured X demos are horizontal, and he says X wants 16:9 [33:35]-[33:39] (step 45). HyperFrames is still the mandatory entry for any composition this skill builds (`edit-export.md`).

| | launch-film | demo-recording | launch-video |
| --- | --- | --- | --- |
| Unit | One high-craft film with sound: a README hero or a product's first public face | A silent animated WebP of a screen, terminal or agent flow | Many small demo posts, plus a produced quarterly launch |
| Cadence | Per product or major release | Per README change | Daily to weekly; a team update weekly or every two weeks; quarterly polish |
| On screen | Nobody real (§0.11) | The product's own screen | The founder's voice (and face, if on camera) and the real product |
| Approval | One operator yes at story, look (then each element), board, motion, sound (a mix pick) and the final film; the stills check is internal, with no operator question unless the look changed (launch-film §4); README is a measured check (§9) | Its own gates: pane parity, contact sheet, streak metric, scratch-branch verify | Only the founder's stop and mute tests and the step-46 checks |
| Time | Days to weeks (one 2026-10 film: a 70.6 h look stage, an 81.4 h final render) | Not measured | Minutes to hours to make; deciding to post can take weeks (§7.5) |
| Truth rule | Every on-screen number measured under a written rule (§1.6) | No leaked content | His practice is mostly honest caveats (P20); this skill adopts launch-film's rule |
| Success | The operator's yes, and a hero that lasts | The README renders and animates | Downloads, retention and conversion per channel |
| Lives in | README hero (a GitHub attachment video), the project's `BRIEF.md` and `STATUS.md` | README body | Social channels, `post-log.md`, optionally a demos or changelog section |

## 2. How they coexist on one product (METHOD §6, INFERRED)

1. **Demos first, film later.** The demo cadence finds the message: which hook stopped people, which use kept users. launch-film's story gate (§1) may take its value points and "most impressive true claim" from `post-log.md` and `claims.md`.
2. **Separate outputs.** The film owns the README hero slot and its project files; demo-recording owns the silent loops below it; demos live on the channels and in the post log. No demo replaces the hero URL or writes to the film's `BRIEF.md` or `STATUS.md`. A raw screen take may be re-cut into a silent README loop through demo-recording, never into the hero. Keep each post's HyperFrames project inside that post's `work/`, so the `BRIEF.md` HyperFrames' intent layer writes never lands in a film's project directory (INFERRED).
3. **Separate looks.** Demos stay raw and never wear the film's look. The film never cuts in demo footage: launch-film rules out human footage and wants real UI "translated into the film's material, never pasted in" (§1.6). The film borrows claims from demos, never pictures.
4. **One claims rule, one ledger per product.** A number appears in either only if it is measured under a written rule. Claims that stay true go in the film; fast-moving numbers (views, customers) belong in demos, which date themselves (`claims.md`'s `lasts` field). Before adding a number to `claims.md`, read the product's launch-film project (board and script, read-only) for the same quantity. If the film shows it, copy the film's value, rule and date into `claims.md` with the film as the source. If the take measures something different, show both to the founder and post neither until it is settled. Never write into the film's files (METHOD §6.2).
5. **One one-line description.** The product's one-line value proposition is the same in the film and in the demos' "what it is" line. Change it in one place, on purpose: `setup.md` `one_liner` (`script.md` §5, "Who writes").
6. **One music rule.** No music without a documented license, in either (launch-film "Do NOT"; step 46).
7. **Nobody waits, and approvals do not transfer.** Demos keep running through the film's gates. When the film ships, post it like any demo: copy in his order (step 21), the feed test (step 23) and a tagged link (step 4). A demo doing well is not a film gate's yes, and a film yes does not approve demo copy. **Posting a finished launch film:** run only Stages 6-9 (copy in his order, the stop and mute tests, a tagged link and self-reply, package, log), on the approved master as delivered. Do no Stage 3-5 work on it: no trim, captions, crop, letterbox, loudness change or music. A 9:16 or captioned version is a launch-film change (studio-method §1 reflow; launch-film §2.4 words), made there under its own operator yes.

## 3. How each launch-film operator verdict applies here

The verdicts in `skills/launch-film/operator-feedback.md` are about one kind of artifact: a hero film with nobody real on screen. This skill does not contradict them, and it does not stretch them onto demos. Row by row:

| launch-film verdict or rule | In launch-video |
| --- | --- |
| "we arent looking for a tutorial walkthrough from the 2000s" (2026-10-01); "No. This is very "tutorial"" (10-03): a UI walkthrough fails as a hero film | Holds for the film. A demo shows the real product in use, but as a mini story with a turn, not a tour (P12, §3.8); K1 warns that an agent-driven run "reads as a product tour". So never offer a demo as the hero, and do not make a demo a feature tour either |
| "the caption text is just placed on top and doesn't feel integrated into the scene and enviroment. Still kind of feels like a tutorial video" (10-03) | About the hero film's words. It does not ban burned-in captions on feed posts, which his edited videos carry and step 42 asks for |
| Taste rules 2-5: startup-modern, named best-in-class brands, no AI-template tropes ("mvp ai template slop"), no dominant purple gradient | Hold for the film's look. Demos wear no designed look (§2 rule 3). Any end card, title or thumbnail a demo does carry avoids the AI-template tells (`skills/launch-film/studio-method.md` §3; inferred rules 4-5) |
| Rule 8: he judges by watching the delivered MP4 ("Open for us") | Adopted: Stage 5 opens the master and Stage 8 opens the post folder |
| "Use music without a documented licence" is a Do NOT | Adopted as hard rule 5 |
| §1.6 truth: every number measured under a written rule; every mechanic shown is real; stakes are true; names on screen belong to this product ("it highlights 'TrueMemory 2.0' as its hero image which is another project not ours", 10-01) | Adopted whole as hard rule 4, and checked in the leak pass (`measure.md` §5) and the Truth rows of `package.md` §2, which are never waived |
| 10-02 "We are WAY to overfit exact copy cat of the original source film" / "We need some ORIGINAL storyboarding not just exact copies from our sources"; Do NOT restage a reference's shot | Holds as a caution. The templates carry his structure (first word at once, the thing named early, the pivot, a soft CTA), not his shots or lines. Never restage his frames (the peace sign, the blackboard, the outdoor table) and never post his lines word for word; he warns against copying his hook [09:54] |
| 09-25, on a 20 fps README loop: "make the film more smooth (ie. 60fps) … I don't feel oriented nor I can read anything in time" | A caution: export screen takes at the recording's native frame rate, never resampled lower, and hold any inserted on-screen text long enough to read (launch-film §5's ≥ 1.0 s + 0.3 s per word as an INFERRED caution, not a gate) |
| "It still reads very noisy and confusing" (10-04), on walls of real terminal text | A caution for terminal demos (large type, few lines, `capture.md` §3), not a rule: the verdict was about a film |
| §0.11: no human shoot, no stock footage with type over it, no generated video as the base | Not carried over: a demo is a real person and a real product. Stock or generated footage that viewers could read as the product or the founder stays out of demos too (hard rule 6; K1 credibility risk; INFERRED) |
| §6 sound: "the score never drops out" | Not carried over as a rule: set for films. In a demo the background music sits well under the voice and the founder sets it by ear; raw takes carry none (`edit-export.md` §7) |
| 10-09 "The halfway point cutoff without music is so jarring" | A caution beside the row above: if a produced cut has background music, do not drop it to silence mid-piece unless the founder chooses to |
| 10-09 "Using our real sound effects the two permission signs feel out of place and a "stop" from the movie immersiveness"; launch-film §6 translates system chimes into the score | Not carried: a demo plays the product's real sounds as they are (hard rule 6) |
| §9: a hero film with sound is a GitHub attachment video, never an animated WebP ("crushed … also no sound", 10-13) | A demo with sound placed in a README's demos or changelog section (§6 table, "Where it lives") goes below the hero, never in or replacing the hero slot (§6.2), and follows §9's medium rule as an attachment video (INFERRED). Only when the founder asks. The README edit goes through that repo's own change process (hard rule 9). The upload follows launch-film §9 steps 1-4 (issue attachment, `gh api markdown` check) under the founder's publish go; the agent never uploads from the founder's logged-in session on its own (hard rule 1). A silent loop goes through demo-recording |
| One operator yes at each launch-film gate (story, look, board, motion, sound, final), "(yes / what to change)"; a recommended pick stays provisional | Not carried over: approvals do not transfer (§2 rule 7), and launch-video's only gates are the founder's own tests and the step-46 checks (§6 table, "Approval") |
