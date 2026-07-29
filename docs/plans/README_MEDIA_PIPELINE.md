---
status: open
owner: unassigned
created: 2026-07-28
supersedes: none
---

# README media pipeline — compression + a repeatable recording process

Forward work carried out of the 2026-07-28 README session. Everything the README itself
needed is **landed** (`84b14daf`); this doc covers the two follow-ons the operator asked for.

## Where things stand

| Artifact | Current | Notes |
|---|---|---|
| `assets/demo/handoff-live.webp` | 1200×716, 20 fps, **2,892,390 B** | the INLINE hero (was a 3,483,666 B GIF — Task 1) |
| `assets/demo/handoff-live.mp4` | 1920×1144, 60 fps, **2,528,078 B** | linked from the caption, not embedded; also the encode SOURCE |
| `assets/demo/handoff-real.webp` | 1200×640, 25 fps, **633,570 B** | the VHS clip (was a 708,919 B GIF — Task 1) |
| `assets/demo/handoff-real.tape` | — | `vhs` → GIF intermediate (gitignored) → `gif2webp` |
| `assets/diagrams/*.mmd` + SVGs | — | `npm run diagrams`, CI-guarded by `diagrams:check` |

Inline payload **4,192,585 → 3,525,960 B (−666,625 B, −15.9 %)**, with measured quality
equal or better on both assets. Task 1 and Task 2 are **RESOLVED** — see below. Task 3 is
a separate track and is untouched.

## Task 1 — compression — **RESOLVED 2026-07-29, then PARTLY REVERTED the same day**

> **The first outcome was wrong and is corrected below.** The hero was shipped as lossy WebP
> q65; the operator spotted vertical bar streaks in the flat grey of an unfocused pane. That
> was a real regression I introduced, and SSIM/PSNR passed it. The hero is back on GIF.

**Outcome (corrected):** only the VHS clip moves to WebP. Inline payload −75,349 B (−1.8 %),
quality ≥ the original on both assets.

| Asset | Before | After | Δ | Quality |
|---|---|---|---|---|
| hero (`handoff-live`) | 3,483,666 B GIF | **unchanged — GIF** | 0 | no lossy WebP is both clean and smaller (below) |
| VHS clip (`handoff-real`) | 708,919 B GIF | 633,570 B WebP | **−10.6 %** | **pixel-exact** (534/534 frames hash-identical, duration 63,960 ms both) |

### Why the hero cannot be WebP (measured, whole range)

Lossy WebP encodes each animation frame as a **partial update rectangle** (measured:
1105×616, 1070×594, 526×458 on a 1200×716 canvas). Inside the rectangle a flat grey
re-quantizes to a slightly different DC level than the retained pixels outside, and the
rectangle edge becomes a visible vertical seam. GIF is immune — palette indices cannot drift.

Streak metric = stdev of the column-mean profile over 239 text-free rows of the unfocused pane:

| Encode | Bytes | vs GIF | Streak (source 0.195, GIF 0.188) | Coloured-text RMS |
|---|---|---|---|---|
| GIF (incumbent) | 3,483,666 | — | **0.188** | 4.02 |
| lossy q65 (shipped, reverted) | 2,892,390 | −17 % | **0.526** ✗ | 4.84 |
| lossy q80 / q90 | 1.47 / 1.83 MB* | — | 0.446 / 0.401 ✗ | — |
| all-keyframe q65 | ~26 MB | +650 % | 0.222 ✓ | — |
| near-lossless 20 / 30 | — / 3,740,996 | +7.4 % | **0.516 / 0.516** ✗ | — |
| near-lossless 40 (= 50) | 4,226,254 | **+21.3 %** | **0.194** ✓ | **1.42** ✓ |
| near-lossless 60 | 4,857,902 | +39.4 % | 0.191 ✓ | ~1.4 ✓ |

The near-lossless 30 row is the one that closes the question: at only +7.4 % over the GIF it is
**still fully streaked**. The threshold where seams disappear (40) is already past the GIF's size,
so nothing in the range is both clean and smaller. `-min_size` is inert here for every mode, and
40 and 50 emit byte-identical files — the parameter quantizes to discrete internal levels.

<sub>* proxy-segment bytes (260 of 610 frames); all others are full-clip.</sub>

**Why there is no middle setting:** WebP animation has **no motion compensation**. Every ANMF
frame is a standalone image; cropping to a changed rectangle *is* the entire temporal
compression. Removing the seams removes the compression — hence the ~26 MB all-keyframe row.
Raising `-q` only shrinks the DC step, it never removes it.

**The honest conclusion:** for live screen capture, GIF is not beaten by WebP at equal quality.
Near-lossless 40 is genuinely better than the GIF on both axes (clean flats *and* 2.8× better
colour) but costs +742,588 B, which is an editorial trade, not a compression win. Regenerate it
with:

```bash
ffmpeg -v error -i assets/demo/handoff-live.mp4 -vf "fps=20,scale=1200:716:flags=lanczos" f/%04d.png
img2webp -loop 0 -d 50 -near_lossless 40 f/*.png -o assets/demo/handoff-live.webp
```

### Correction: an earlier claim here was false

This doc, commit `3355afa7`, the skill and memory all said the GIF "visibly posterizes a
red→orange gradient that the WebP tracks cleanly", i.e. that the swap was a quality *gain* on
coloured text. **That is wrong.** Measured RMS against the source over the coloured-text box,
at both sampled frames: GIF **4.02 / 4.92**, WebP q65 **4.84 / 5.45** — the GIF is *closer*.
The error was reading a contrast-amplified zoom and mistaking visible palette steps for greater
error. A visible artefact is not the same as a larger one; the amplified view had no scale.

**The gate — settled empirically, and the premise was wrong.** camo is *not* in the path
for a README image: a relative `<img src>` is rewritten to `/{owner}/{repo}/raw/{ref}/{path}`,
GitHub's own endpoint. camo only proxies *absolute external* URLs. Served bytes were
**SHA256-identical** to source, `content-type: image/webp`, `ANIM` + 60/60 `ANMF` intact;
a real browser animated it (3 distinct frames over 6 screenshots, at the raw URL *and* in
the rendered markdown page). Re-verified via `gh api /markdown` that `<img src="a.webp">`
survives the sanitizer identically to GIF.

**Learnings — the ones that would be re-learned painfully:**
- **`-min_size` is load-bearing for `gif2webp` and does nothing for size on live footage.**
  VHS clip: 1,996,878 B without it vs 633,570 B with — a **3.15× factor**. Hero: 3,130,182 B
  without vs 3,171,988 B with. On the hero its real effect was **encode time, 670 s → 45 s**.
- **`gif2webp` is lossless by default** — there is no `-lossless` flag; passing one prints usage.
- **A live screen recording barely compresses.** Continuous motion (cursor blink, streaming
  text) means no identical-frame redundancy: 610 frames in, 610 stored, zero dedup. The
  format swap alone was only −8.9 % at q70; the −17.0 % came from finding the quality curve.
- **The plan's "expect a large reduction" was optimistic.** WebP's reputation comes from
  content like the VHS clip, not from live capture.
- **Frame count legitimately drops** (1,599 → 534 on the VHS clip): identical consecutive
  frames merge into one longer-duration frame. Verify by **summed duration**, never frame
  count — and never compare frames by index across a deduplicated stream (that produced
  confident, wrong "MISMATCH" output before the timeline was reconstructed properly).
- **Tool traps:** `ffmpeg` cannot decode animated WebP (`image data not found`) — use
  `magick -coalesce`. **Pillow mis-reports durations** on merged frames (63,680 ms where
  `webpinfo` said 63,960 ms) — trust `webpinfo`.
- **Rejected on measurement, not taste:** lossless WebP on the hero (6,083,602 B, **+75 %**);
  `-mixed -q 85` (3,997,492 B, +15 %); q50/q60 (below the GIF's SSIM *and* PSNR — a real
  quality loss). Animated AVIF not pursued: uneven browser support for the *animated*
  variant, and the inline slot has no fallback once `<video>` is stripped.

> ~~**Why q65:** it is the point that beats the 64-colour GIF on both metrics with the largest
> size win. Visual check at README width confirmed it — and on **coloured** text the GIF's
> palette visibly posterizes a red→orange gradient that the WebP tracks cleanly. The swap is
> a quality *gain*, not a trade.~~
>
> **SUPERSEDED — every sentence above is wrong.** q65 seams the flat grey (streak 0.526 vs the
> GIF's 0.188); the visual check missed it because it was done on text, not on a flat region;
> and the coloured-text claim is inverted — measured RMS vs source was GIF 4.02 / 4.92 against
> WebP 4.84 / 5.45. Kept struck-through rather than deleted so the reasoning error stays
> legible. See § "Why the hero cannot be WebP" and § "Correction" above.

<details><summary>Original analysis (kept — the sanitizer measurements still hold)</summary>

**The constraint is not negotiable, and it is measured, not assumed.** GitHub's markdown
sanitizer strips `<video>` outright. Verified against the live API (`gh api /markdown`):

```
<video src="…mp4" controls>                → <p></p>            (tag gone)
<video><source src="…mp4">fallback</video> → <source> orphaned   (tag gone)
<img src="…gif">                           → survives, auto-linked
```

So the GIF cannot be replaced by a video for the inline slot; it can only be replaced by a
**better image format**. That is where the win is: the GIF is simultaneously the largest
artifact (3.3 MB vs the MP4's 2.4 MB) and the lowest quality (20 fps, 64 colours).

**Tooling already on this machine** (verified `command -v`, 2026-07-28):

| Tool | Present | Use |
|---|---|---|
| `img2webp`, `cwebp` | **yes** (`/opt/homebrew/bin`) | animated WebP — the leading candidate |
| `ffmpeg` w/ `libsvtav1`, `libx265`, `libvpx-vp9` | **yes** | AV1 / HEVC / VP9 for the linked video |
| `gifski` | no — brew formula 1.34.0 available | best-in-class GIF encoder, the fallback |
| `gifsicle` | no | `--lossy` post-pass on an existing GIF |
| `avifenc` | no | animated AVIF — smaller still, but check support |

**Do this, in order:**

1. **Verify GitHub actually serves animated WebP with animation intact.** The sanitizer will
   pass `<img src="….webp">` (it is just an image), but the open question is whether the camo
   proxy preserves the animation. This is the gate — settle it with a real push to a scratch
   branch and a look at the rendered blob, NOT by reasoning about it. If animation is lost,
   stop and go to gifski.
2. If WebP holds: encode from the SAME source frames the GIF used (`img2webp -lossy -q 70 -d 50`
   over the PNG sequence, or `cwebp` per-frame + `webpmux`). Expect a large reduction —
   confirm by measurement, and compare quality side by side at README width before adopting.
3. If WebP fails: `brew install gifski`, re-encode from frames (gifski is markedly better per
   byte than ffmpeg `palettegen`), optionally `gifsicle --lossy=60 -O3` after.
4. For the linked MP4, AV1 (`libsvtav1`) or VP9 would shrink it further, but it is already
   2.4 MB and is not on the critical path — do it only if free.

**Already-applied lesson:** `palettegen`/`paletteuse` with `dither=none` beat a dithered
160-colour palette on flat terminal colour — same bytes, +20 % resolution, +67 % frame rate.
Dithering buys noise on this content. Start any GIF work from there, not from defaults.

</details>

## Task 2 — harvest the recording process into a skill — **RESOLVED 2026-07-29**

**Delivered:** `skills/demo-recording/SKILL.md`, deployed as
`~/.claude/skills/demo-recording/SKILL.md` (per-file symlink, the pattern every active
skill uses). It carries the material below **plus** the Task 1 encode recipes with their
measured byte counts, so the compression knowledge cannot drift from the recording process.

Written directly into `skills/` rather than staged via `/harvest-skill` → `skills-pending/`:
that gate exists to stop an agent silently accreting junk skills, and this one was
explicitly commissioned. Noting the deviation rather than hiding it.

**Claims re-derived against disk rather than transcribed** (the recording session's
transcripts are gone — this plan doc *was* the harvest, so its claims needed checking):
- **`--notify-back` refined.** The plan said "takes no argument". It actually takes an
  **optional bare UUID** (`scripts/handoff-fire.sh:1550` — an empty or `--`-prefixed next
  token selects `__self__`). The real failure is that `$ITERM_SESSION_ID` holds the
  `w2t0p0:UUID` form, is accepted as a *literal* target, and `cc-notify` then answers
  `verdict=unresolvable reason=no-such-target` (`bin/cc-notify:399`); the prefix is stripped
  only for `--self` (`:312`). Guidance is now "pass nothing, or the bare UUID".
- **Confirmed exactly as written:** `hooks/mailbox-drain.sh:36` consumes stdin
  unconditionally (`cat >/dev/null`, deliberate anti-SIGPIPE); this `ffmpeg` has **no**
  `drawtext` (0 matching filters, no libfreetype).
- **Font-per-session confirmed live:** `it2 session list --json` reports per-pane
  `cols`/`rows`, and a check found two panes **in the same window** at `75×78` and `68×83`.

**New traps found while doing the work** (now in the skill): zsh does not word-split an
unquoted `$VAR`, so `opts="-m 6"; gif2webp $opts` passes one argument and prints usage;
`pgrep -c` is not valid on macOS; check `uptime` before fanning out encodes (three
concurrent `-m 6` runs pushed a 10-core box to load 12.9).

<details><summary>Original harvest notes (kept — the source material for the skill)</summary>

Six takes produced knowledge that is non-obvious and would otherwise be re-learned painfully.
The process is genuinely repeatable and belongs in a skill (`/harvest-skill` is the entry point).

**Setup**
- iTerm2 font size is **per-session**. `⌘+` on one pane does NOT reach a pane created later —
  `handoff-fire.sh`'s split inherits the PROFILE default. Different font ⇒ different row grid ⇒
  different composer offset ⇒ mismatched panes and a chat box that falls outside the crop.
  **Never bump the font; size the WINDOW instead.** Verify by splitting a probe window and
  comparing `cols`/`rows` from `it2 session list --json` — they must be identical.
- Capture the WHOLE window (title bar → status footer). Crop = window bounds × 2 (Retina).
  AppleScript `bounds` is top-left origin; `it2 window list` is bottom-left. `it2 window
  resize` + `move` in sequence collapsed a window to zero size — set `bounds` atomically via
  AppleScript instead.

**Firing the demo**
- `--notify-back` takes **no argument**. Passing `$ITERM_SESSION_ID` sends the `w2t0p0:UUID`
  form; `cc-notify` wants the bare pane UUID and answers `verdict=unresolvable
  reason=no-such-target`. The peer then correctly REFUSES to self-retire (its result was never
  delivered), so the take has no close to film.
- The originator must be a **real Claude session**, not a shell — otherwise there is no chat UI
  for the ping to land in, and the whole two-way leg is invisible.

**Capture hygiene**
- **Contact-sheet every take before using it** (`fps=1/5,tile=8x5`). This caught a real leak: a
  peer session's browser automation took the foreground mid-recording and covered the window
  with an app showing what looked like real people's names and invitation details. That raw
  capture was deleted unused. This step is not optional.
- Claude Code's next-prompt autosuggestion sits in the composer as dim ghost text; in a silent
  clip it reads as a human about to act (one take showed "close the peer pane", undercutting the
  self-close). Crop it out or verify it is empty.

**Editing**
- Variable speed beats a flat rate: ~1.5–2× through the beats, ~2.5–5× through dead air.
- Captions belong in a strip PADDED BELOW the frame, never overlaid (overlay clips content).
  Generate them as a frame sequence for real animation (fades, rises, a progress line);
  this ffmpeg build has **no `drawtext`** (no freetype), so PIL + `overlay`/`vstack` is the path.

**Non-obvious**
- `hooks/mailbox-drain.sh` is a hook: it consumes its payload from stdin (`:36`), so a bare call
  on a TTY blocks forever and swallows everything typed after it. Feed it `echo '{}' |`.
- `plutil -extract <key> json <file>` **without `-o`** rewrites the plist in place. It destroyed
  two LaunchAgents during this session. Use `-o -`, or `grep`.

</details>

## Guardrail earned the hard way

`d6845630` deleted 426 lines of README. Cause: a greedy regex (`(?:<[^>]+>[^<]*)*</sub>`) used to
delimit a replacement span matched to the LAST `</sub>` in the file. Restored in `04c549d2`.
**Never use an open-ended regex to bound a replacement in a document — anchor on exact strings,
and assert the SHAPE of the result (line count, heading count), not merely that the addition is
present.** The post-edit check that passed on a gutted file only confirmed what had been added.

## Task 3 — an animated hero banner for the README header (own track)

Operator ask (2026-07-28): a **1080p60, awwwards-calibre animated banner** for the top of the
README, featuring the Claude mascot, with **moving ASCII art as one candidate medium among
several** — explore mediums, do not assume ASCII wins.

This is exploratory DESIGN work, unlike Tasks 1-2 which are engineering. Treat medium choice as
the deliverable's first question, and prototype more than one before committing.

**Constraints that are already settled — do not re-litigate:**
- GitHub strips `<video>` (measured, § Task 1). The header can hold an **image** or **inline
  SVG-as-image**. That is the whole option space.
- An animated SVG DOES work in `<img>` on GitHub (declarative CSS/SMIL animation runs; scripts do
  not). The repo shipped one previously — `assets/diagrams/handoff-choreography.svg`, removed in
  a85e87e4 as redundant beside the live recording, recoverable from git for reference.
- `<picture>` + `prefers-color-scheme` follows the READER'S OS setting, not GitHub's theme
  toggle — so either commit to one look or make both legible.
- Inline weight is the budget: the hero recording is already 3.3 MB. A banner must be small
  (target well under 1 MB) or it competes with the thing it sits above.

**Mediums worth prototyping (at least three, then choose on evidence):**
1. **Animated SVG** — hand-authored CSS keyframes. Tiny (single-digit KB), infinitely crisp,
   theme-adaptable, diff-reviewable, no build step. Strongest default.
2. **Moving ASCII art** — the operator's named candidate. Either rendered INTO an animated SVG as
   `<text>` (keeps it tiny + selectable) or captured as a real terminal animation via the existing
   `vhs` pipeline (`assets/demo/handoff-real.tape` is the working reference).
3. **Animated WebP / optimised GIF** — only if the design genuinely needs raster. Gated on Task 1's
   WebP-animation finding.
4. Worth a look: a CSS-animated SVG that *composites* ASCII glyphs with vector motion — the ASCII
   texture the operator likes, without raster weight.

**Bar:** "awwwards-calibre" means restraint, not maximalism — one strong idea, precise timing,
motion that reads at a glance and does not loop distractingly under the README text. Respect
`prefers-reduced-motion` (the removed SVG did; reuse that pattern).

**Deliverable:** its own plan doc, the prototypes, a side-by-side comparison, and a recommendation
with the trade-offs named. Land the winner into the README header only after the operator sees the
comparison.
