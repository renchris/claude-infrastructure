# Banner narrative spec — cause / behaviour / exit for every event

Operator ruling, 2026-07-29 (binding, supersedes the timing half of S9). Two critiques:

- **(a) Volume dilutes significance.** So much content — the starfield above all — that no single
  element carries weight. Awwwards-grade means restraint: every element earns its place or goes.
- **(b) Every rare occasion needs a CAUSE, a BEHAVIOUR, and an EXIT.** Named non-sequiturs in the
  current v5a: the orange asterisk that passes clawd; the "horns" that appear and vanish; clawd
  becoming sleepy with no reason, doing nothing distinct while `Zzz`, and waking for no reason; a
  shooting star that lands and does nothing; a second smaller mascot that appears and leaves
  unexplained.

## Why it reads as random — measured, not guessed

Duty cycles over the P=240 s master period, read off the keyframe percentages in
`assets/banner/v5a-long-walk.svg`:

| event (class) | window | duty | verdict |
|---|---|---|---|
| `balloon` (`bo`, 120 s) | 4.8–60.0 s, **twice per loop** | **46.0%** | not rare — nearly ambient |
| `rCheer` (`rc`, 120 s) — the "horns" | 34.8–42.0 s | 6.0% | fires **inside** the balloon pass |
| `peek` (`pk`, 240 s) | 98.4–122.4 s | 10.0% | 24 s is long for a "peek" |
| `rSleep` (`rs`, 240 s) | 148.8–175.2 s | 11.0% | overlaps the balloon's 2nd pass |
| `shoot` (`sh`, 240 s) | 231.4–238.8 s | 3.1% | the only genuinely rare one |

Three structural faults:

1. **The rare events are not rare.** S1 sells a 1.7% duty cycle. The balloon is on screen 46% of
   the time, so it is scenery that happens to move — it cannot read as an event.
2. **Events stack instead of sequencing.** `rCheer` lands mid-balloon; `rSleep` lands inside the
   balloon's second pass. Two unrelated things at once, so neither reads as caused by anything.
3. **Nothing causes anything.** Five independent timers on one shared period. Simultaneity is the
   only relationship the composition can express, and it expresses it by accident.

## The fix: one causal chain, sequenced across the loop

The conceit that makes every element explicable: **clawd is a session; the sky is the work that
arrives.** Events do not fire on timers — each is *triggered by the previous one*, so the 240 s
loop is a story that closes rather than a reset.

The shooting star is the **prime mover** — the only uncaused arrival, and the thing that both opens
and closes the cycle.

| # | beat | CAUSE | BEHAVIOUR (what it does while present) | EXIT |
|---|---|---|---|---|
| 1 | **Shooting star** | uncaused — the one external arrival | streaks down across the sky, behind the clouds, never crossing the type | **lands**: does not vanish. It becomes a small ember on the ground at the impact point, which persists |
| 2 | **Ember** | the landing | sits on the ground, faint slow pulse — the only warm light in the frame | consumed by beat 5 |
| 3 | **Visitor peeks** | *something landed* — curiosity | emerges from behind the mound **nearest the ember**, edges toward it, looks at it, looks at clawd | retreats behind **the same mound it came from** — a symmetric exit reads as intent, not a despawn |
| 4 | **clawd cheers** | it saw the visitor | whole-body gesture — a hop with a body tilt, **not two pixels above the head** | settles back to stride |
| 5 | **clawd sleeps** | the sky has gone quiet: star landed, visitor gone, nothing overhead | sits, `Zzz` drifts up; a 1 px body rise/fall for breathing; **the ground keeps scrolling** — the world moves while the session rests | woken by beat 1 of the next cycle: the next streak. Stands, stride resumes |

That last row is what closes the loop causally: the event that starts the story is the event that
ends the sleep, so t=P is both the seam and the narrative return.

**Sequence them, do not stack them.** One event visible at a time, with clear empty air between.
Phase must live in **keyframe percentages**, never authored `animation-delay` — the freeze in
`banner-shots.sh` overrides delay on `*`, so an authored delay is discarded and every frozen frame
shows the wrong phase (and the t=0 vs t=P hash test cannot fail on the phase question).
`scripts/banner-build.py hold_cycle()` already rotates events inside a period; reuse it.

## Specific rulings

- **Cut the balloon.** It is the single largest volume offender at 46% duty and it explains nothing.
  If it must survive, re-cause it: the visitor *releases* it as it leaves, so it has an origin and a
  direction. Cutting is preferred — restraint over addition.
- **Fix the cheer's legibility.** Arms-up currently reads as horns/antennae because the arms clear
  the head silhouette as two loose pixels. `clawd-sprite.py` measured the cliff (rise −3; −4 reads
  as antennae). Either scale clawd up so arms read as arms, or make the cheer a whole-body gesture.
  A gesture nobody can name is not an emote.
- **Sleep needs a distinct state, not a badge.** Today `Zzz` is the only difference. Asleep must
  differ in posture (sitting/lower silhouette), in breathing, and in *absence* of the walk stride.
- **Thin the starfield hard.** Cut the count substantially. Make the three depth tiers genuinely
  different in size and opacity so depth reads as depth. Prefer 1 px dots for the far tier and
  reserve the asterisk glyph for only the few nearest stars: an asterisk is six strokes of ink, so
  forty of them is forty competing marks, and it also stops the sky from being a field of Claude
  marks competing with the wordmark.
- **Thin the sky furniture.** Three cloud bands + ground mounds + ground rule + moon is a lot of
  simultaneous texture. Every band that is not carrying the parallax should go.
- **Unchanged and still binding:** clawd present and alive; side-scrolling ground like dino-run;
  wordmark legible at every t with nothing behind it; 100% seamless loop; stars never touch the
  type; moon subtle, behind the clouds, no solid-white cell; vector only; reduced-motion freezes
  legibly. Do **not** run `scripts/banner-apply-header.sh` — the README edit is the operator's call.

## Acceptance

An event passes only if a viewer can answer all three of *why did it appear*, *what did it do*, and
*how did it leave* — from the animation alone, without reading this file.
