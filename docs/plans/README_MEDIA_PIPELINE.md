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
| `assets/demo/handoff-live.gif` | 1200×~700, 20 fps, **3.3 MB** | the INLINE hero — the only thing GitHub will embed |
| `assets/demo/handoff-live.mp4` | 1920×1144, 60 fps, **2.4 MB** | linked from the caption, not embedded |
| `assets/demo/handoff-real.gif` | 1200×640, **692 KB** | the VHS terminal-mechanics clip |
| `assets/demo/handoff-real.tape` | — | regenerates the above via `vhs` |
| `assets/diagrams/*.mmd` + SVGs | — | `npm run diagrams`, CI-guarded by `diagrams:check` |

## Task 1 — compression (the inline GIF is the expensive artifact)

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

## Task 2 — harvest the recording process into a skill

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
