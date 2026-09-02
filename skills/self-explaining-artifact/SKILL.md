---
name: self-explaining-artifact
description: >
    Build a single self-contained HTML page that explains a body of source material while it plays —
    and measure it instead of asserting it. Use when asked to turn an article, dataset, research
    finding or mechanism into an interactive or animated explainer; when an explainer has been
    rejected as "walls of text", "click through all the boxes", "too many abstractions", "I got
    lost", or "not fun"; or when a visual artifact must pass a hard gate (word count, AA contrast,
    frame budget) rather than a reviewer's impression. Covers the rejection ladder and what each
    verdict actually diagnoses, the freeze-keep-and-cut step that stops a rebuild from carrying the
    payload forward, the four measured gates and the probe that produces them, the render-split
    decision that must be made before any sequence is authored, and the continuous-sweep review that
    catches defects living between held frames. NOT for chart/palette design (that is dataviz), NOT
    for animation library mechanics (that is motion), and NOT for a document that is meant to be
    read rather than watched.
---

# Building an artifact that explains itself

Distilled from six builds and five operator rejections of one page
(`claude-code-session-economics.html`, lakehouse-lecture, Aug 2026). Reader-facing word counts
across those builds ran **2,465 → 1,390 → 2,656 → 334 → 563 → 314**. The lesson is in that
sequence: the rebuilds that failed changed the *wrapper* and kept the *payload*.

---

## 1 · Diagnose the rejection before you rebuild

An operator's complaint names a symptom. Measure the last build before accepting the complaint's
own theory of the defect.

| The verdict | What it usually is |
|---|---|
| "walls of text" · "spam click through" | register — a document wearing an interaction |
| "I got lost" | no reference frame on screen. Look for a quantity the reader is asked to judge against nothing — an axis with no numbers, a bar with no scale |
| "too many abstractions / metaphors / analogies" | the unit is wrong. Change what is being counted, not how it is drawn |
| "not fun" / "isn't fun having right/wrong answers" | the interaction grammar, but check word count first — the build rejected as "not fun" carried **more** prose (2,656) than the one rejected as loose (1,390) |
| "zero learnings conveyed" | order — support stated before the point, so the reader must do the summarizing |

**Word count is the tell.** Count it mechanically every time (step 4). A complaint about
interaction that coincides with a word-count *rise* is a complaint about prose.

## 2 · Freeze KEEP and CUT before writing anything

Write both lists into the plan doc, explicitly, as the contract the build is judged against.
Without this the next build silently re-imports what was already rejected.

- **KEEP** — the hard-won things: the unit that survived review (money, not tokens; a receipt, not
  an area under a curve), the facts the piece exists to land, the real prices printed on its face,
  the honesty anchor (real data the page can parse), the build constraints.
- **CUT** — named forms, not vague intentions: "click-to-advance gates as the primary structure",
  "paragraph blocks", "the tick-boxes and the three-button bench **as the main event** — their
  content is right, their form is a form".
- **A word ceiling, as a number.** "Below the previous build's 563." A ceiling with no number is
  not a constraint.

## 3 · Decide the render split BEFORE authoring the sequence

This is the hazard that cannot be fixed afterwards. A DOM rebuild per frame will not survive a
real timeline.

- **Canvas owns the quantitative field** — retained data, one `fillRect` pass per frame, no
  `shadowBlur`, no per-frame allocation.
- **DOM owns every word** — animated on `opacity`/`transform` only. This is what keeps the text
  real text: a screen reader reads it, a language linter lints it, and a contrast probe can
  measure it off rendered pixels.
- **Make `seek(t)` pure.** The whole scene is a function of time. That single property is what
  makes a scrubber land on exactly the frame the film would have shown, and what lets a probe
  hold a moving picture still to measure it at a named moment. Expose it as
  `window.__probeSeek(ms)`.
- **Every animated quantity is a real number from the model.** Never decoration. If a lit ribbon
  shows $1.42 while the counter beside it says $0.75, the animation is of money nobody is
  counting — split the quantity until they agree.

## 4 · Measure the four gates — never assert them

Reference implementation: `tools/probe.mjs` in lakehouse-lecture (zero dependencies — Chrome over
the DevTools Protocol, Node 22's built-in `WebSocket`, a PNG reader on `node:zlib`).

```bash
node tools/probe.mjs words <file.html>
node tools/probe.mjs aa    <file.html> [--theme=dark|light] [--t=12000]
node tools/probe.mjs fps   <file.html> [--seconds=6]
node tools/probe.mjs shot  <file.html> [--out=x.png] [--t=…] [--theme=…]
```

| Gate | What it must do to be trustworthy |
|---|---|
| **words** | **press every control before counting.** Prose hidden behind a press and inside script strings scored one build 155 against a hand count of 563 |
| **aa** | read **rendered pixels**, not computed styles — opacity, overlays and a canvas backdrop all hide failures from a style read. Sample many moments × both themes |
| **fps** | measure frame cost across the *whole* timeline (600 frames), and report median/p95/worst against the 16.7 ms budget — not an average |
| **shot** | a PNG at a named `--t`, so a claim about a moment can be looked at |

Run the project's language/style gate too (here `tools/slop-lint.sh`), plus the file-safety greps:
zero external references, zero network calls, no inline `style=`, no `on*=` handlers.

## 5 · Sweep continuously — held frames are blind to what lives between them

Every act's held frame can pass while the film is broken. Render the whole timeline at a fixed
interval (e.g. two seconds across 96 s) and read it as contact sheets. That sweep found three
real defects no held-frame check could see:

- the film **opened on a black stage for nearly a second** — first element at 700 ms. The worst
  frame in a piece is its first, and an empty box reads as a page that failed to load;
- a scanning read-head drawn as an **opaque fill** read as the content turning orange rather than
  as something crossing it (fix: a ~26% wash with a trailing band, bright leading edge kept);
- **a full second of dead stage** between two elements leaving and the closing line arriving — at
  the exact moment the piece delivers its conclusion.

Also record near-misses: one "blank" transition turned out to be the contact sheet being cut off,
not the film.

## 6 · Two traps in the data itself

- **Scale by the 95th percentile, not the maximum.** A real dropped dataset carried one item forty
  times the rest; scaling to it flattened the other 431 to a hairline. Draw anything above the cap
  to the top with a notch saying it ran off. Derived totals stay unaffected — build them from the
  quantity, not from drawn heights.
- **A theme change is watched, not handled.** A canvas holds resolved colours and cannot repaint
  itself the way a stylesheet does. Hooking the toggle button is not enough — a whole theme's worth
  of AA failures hid behind exactly that. Use a `MutationObserver` on `data-theme` so the stage
  follows the theme however it was set.

## 7 · Land it with the numbers in the commit body

Every commit states the gates as measured values, e.g.:

> Gates: slop-lint clean, 374 words (563 to beat), 0 below AA across 26 rendered moments in both
> themes, median frame 0.20 ms against 16.7 ms, real chat still parses and replays.

This is what makes the *next* rebuild's diagnosis possible. The word-count sequence that diagnosed
five rejections had to be reconstructed by hand from commits — because early builds did not print
it.

---

## Do NOT

- **Do NOT change the wrapper and keep the payload.** The standing failure mode. If the word count
  did not fall, the rebuild did not happen.
- **Do NOT put anything important behind a press.** The piece must work start to finish for someone
  who never touches a control. Controls may exist; they are secondary.
- **Do NOT reach for spectacle without argument.** Amplified feedback *reduces* perceived
  causality. Every mark is a real unit or it is not drawn.
- **Do NOT use internal vocabulary in reader-facing text** — no section signs, no beat numbers, no
  house jargon. Source-register leakage is worst immediately *after* deep research, when you are
  most fluent in the dialect the reader does not share.
- **Do NOT assert a figure the page cannot derive.** Declare a worked example as an example. One
  build invented a floor that was an order of magnitude wrong.
- **Do NOT animate `filter`, `mix-blend-mode` or gradient position on a moving element** — they
  flicker. `transform` and `opacity` only.
- **Do NOT restore an over-elaborate predecessor from git as a target.** An ambition reference is
  not a restore target; the 252 KB voxel artifact in this project's history was deleted as "way
  too hard to understand". The bar is impressive **and** legible in ≤10 seconds with zero
  instructions.
- **Do NOT trust a screenshot of one held frame as evidence the timeline is sound** (step 5).
- **Do NOT hand-count words.** It is the one number every diagnosis depends on.
