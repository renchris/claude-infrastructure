---
name: demo-recording
description: Record a real screen demo — a live agent session, a terminal, a two-way exchange between panes — and land it in a README as an image GitHub will actually animate. Use when asked to record or re-record a demo, capture a live session on video for docs, shrink an oversized README GIF or MP4, or add a screen recording to a README. Covers the settled format decision (GitHub strips <video>, so the inline slot is an image; it serves animated WebP byte-identical, and camo is not in the path for a relative README image) and the format rule that cost a shipped regression to learn — WebP wins on flat terminal output via lossless gif2webp, but LOSES on live screen capture, where lossy WebP seams every flat region and SSIM/PSNR do not catch it. Also iTerm2 window sizing (font size is per-session and silently breaks pane matching), firing a two-way agent demo so the whole exchange is on camera, the mandatory contact-sheet review, caption strips as padded frames (this ffmpeg has no drawtext), and encode recipes with measured byte counts. NOT for understanding an existing video (that is video-understanding), and NOT for a scripted terminal clip where nothing live is needed — vhs + a .tape file is simpler and re-runnable (assets/demo/handoff-real.tape is the working reference).
---

<!-- markdownlint-configure-file {
  "MD013": { "tables": false, "code_blocks": false }
} -->

# Recording a demo for a README

## The format decision is settled — do not re-derive it

GitHub's markdown sanitizer **strips `<video>` outright**. Re-verified against the
live API (`gh api /markdown`, 2026-07-29):

| Input | Rendered |
| --- | --- |
| `<video src="a.mp4" controls></video>` | `<p></p>` — tag gone |
| `<video><source src="a.mp4">fallback</video>` | `<p><source>fallback</p>` — orphaned |
| `<img src="a.gif">` | survives, auto-linked |
| `<img src="a.webp">` | survives, auto-linked **identically to GIF** |

So the inline slot holds **an image and nothing else**. An MP4 can only ever be a
*link* beside it.

**GitHub serves animated WebP untouched.** Measured end to end on a public repo:
a relative `<img src="x.webp">` is rewritten to `/{owner}/{repo}/raw/{ref}/{path}`
— GitHub's own raw endpoint. **camo is not in the path at all**; camo only proxies
*absolute external* URLs, so "will camo re-encode it?" is the wrong question for a
README image. Served bytes were **SHA256-identical** to source, `content-type:
image/webp`, `ANIM` chunk and all 60/60 `ANMF` frames intact. A real browser
animated it — 3 distinct frames across 6 screenshots, both at the raw URL and in
the rendered markdown page.

**That WebP is served perfectly does not mean you should use it.** Delivery was never
the constraint; the encoder is. See the two recipes below — they reach opposite
conclusions, and picking the wrong one is what shipped a visible regression.

## Encode recipes, with the numbers

Two different jobs, **opposite answers**. Do not use one recipe for both.

| Content | Format | Why |
| --- | --- | --- |
| Flat terminal output (VHS, `asciinema`-style) | **WebP** via `gif2webp` | lossless, and −10.6 % |
| Live screen capture (a real window, real UI) | **GIF** | every small-enough WebP seams flat regions |

### A GIF you already have → WebP: `gif2webp`, and `-min_size` is not optional

```bash
gif2webp -m 6 -min_size -mt in.gif -o out.webp
```

`gif2webp` is **lossless by default** — there is no `-lossless` flag, and passing
one just prints usage. Measured on a 1200×640 / 25 fps / 116-colour VHS clip:

| Encode | Bytes | vs GIF |
| --- | --- | --- |
| `handoff-real.gif` (baseline) | 708,919 | — |
| `gif2webp -m 6` | 1,996,878 | **+182 %** — worse than the GIF |
| `gif2webp -m 6 -min_size` | **633,570** | **−10.6 %**, pixel-exact |

`-min_size` is a **3.15× factor**. Without it the encoder inserts key frames
liberally and loses to GIF outright.

Verified pixel-exact: all 534 stored frames hash-identical to the GIF's frame at
that timestamp, total duration 63,960 ms against the GIF's 63,960 ms.

**The frame count will drop and that is correct.** 1,599 GIF frames became 534
stored frames: `img2webp`/`gif2webp` merge runs of identical consecutive frames
into one frame with a longer duration. Verify by **summed duration**, never by
frame count — and never compare frames by index across a deduplicated stream (that
produces confident, wrong "MISMATCH" output).

### A live screen recording → **keep the GIF**. WebP loses this one.

This is the counter-intuitive result, and it was learned by shipping the bug: a
lossy animated WebP **seams every large flat region**, and on a screen recording
the flat regions are exactly what the eye rests on — an unfocused pane's grey
background, a blank editor gutter.

**The mechanism.** WebP animation has **no motion compensation**. Every ANMF frame
is a standalone image, and the *only* temporal compression is cropping the frame to
a changed rectangle and blending it over the canvas (measured: 1105×616, 1070×594,
526×458 rectangles on a 1200×716 canvas). Inside the rectangle a flat grey
re-quantizes to a marginally different DC level than the retained pixels outside it,
and the rectangle edge becomes a **visible vertical seam**. GIF is immune: palette
indices cannot drift.

Because the rectangles *are* the compression, there is no setting that keeps the
savings and drops the seams. Measured on the 1200×716 / 20 fps / 610-frame hero:

| Encode | Bytes | vs GIF | Flat-region streak | Coloured-text RMS |
| --- | --- | --- | --- | --- |
| source master | — | — | 0.195 | — |
| **GIF (winner)** | **3,483,666** | — | **0.188** | 4.02 |
| lossy q65 | 2,892,390 | −17 % | **0.526** ✗ | 4.84 |
| lossy q80 / q90 | — | — | 0.446 / 0.401 ✗ | — |
| all-keyframe q65 | ~26 MB | +650 % | 0.222 ✓ | — |
| near-lossless 30 | 3,740,996 | +7.4 % | **0.516** ✗ | — |
| near-lossless 40 (= 50) | 4,226,254 | +21.3 % | 0.194 ✓ | **1.42** |
| near-lossless 60 | 4,857,902 | +39.4 % | 0.191 ✓ | ~1.4 |

Near-lossless 30 is the row that settles it: at only +7.4 % it is **still fully
seamed**, and the threshold where seams vanish (40) is already bigger than the GIF.
Raising `-q` only shrinks the DC step; it never removes it.

`-near_lossless 40` *is* higher quality than the GIF on both axes — but it costs
+21 %, so it is an editorial upgrade, not a compression win. Say which one you mean.

**Measure the seam, because SSIM and PSNR will not.** The artefact is low-amplitude
but structured over a large area, so aggregate metrics average it away — q65 scored
*better* than the GIF on both SSIM and PSNR while visibly streaking. Take the
column-mean profile over text-free rows of a flat region and report its stdev:

```python
# rows with no text: row stdev across x is tiny in the SOURCE frame
rows = [y for y in range(Y0,Y1) if pstdev([src.getpixel((x,y)) for x in range(X0,X1,4)]) < 1.5]
prof = [mean(cand.getpixel((x,y)) for y in rows) for x in range(X0,X1)]
print(pstdev(prof))          # ~source ⇒ clean;  2×+ ⇒ seams
```

Then still compare against the **source frames**, never against the incumbent:

```bash
ffmpeg -hide_banner -i cand/%04d.png -i source/%04d.png -lavfi ssim -f null - 2>&1 | grep -o 'SSIM.*'
ffmpeg -hide_banner -i cand/%04d.png -i source/%04d.png -lavfi psnr -f null - 2>&1 | grep -o 'PSNR.*'
```

Other measured facts about live capture: `-min_size` is **inert** here (byte-identical
output; on the VHS clip it was a 3.15× factor — never carry a flag's reputation across
content classes), `-sharp_yuv` changes nothing (the artefact is luma, not chroma), and
there is almost no identical-frame redundancy — 610 frames in, 610 stored, zero
deduplication, because cursor blink and streaming text keep every frame slightly different.

**ffmpeg cannot decode animated WebP** (`image data not found`). Use
`magick in.webp -coalesce out/%04d.png` to get frames, and `webpinfo` for the
authoritative per-frame durations. **Pillow mis-reports durations** on
duration-merged frames — its timeline summed to 63,680 ms where `webpinfo` said
63,960 ms. Trust `webpinfo`.

**ffmpeg cannot decode animated WebP** (`image data not found`). Use
`magick in.webp -coalesce out/%04d.png` to get frames, and `webpinfo` for the
authoritative per-frame durations. **Pillow mis-reports durations** on
duration-merged frames — its timeline summed to 63,680 ms where `webpinfo` said
63,960 ms. Trust `webpinfo`.

**Animated AVIF is not worth the risk yet** — smaller in principle, but browser
support for *animated* AVIF is uneven where animated WebP is universal, and the
inline slot has no fallback once `<video>` is stripped.

## Setup: size the WINDOW, never the font

iTerm2 font size is **per-session**. `⌘+` on one pane does not reach a pane created
later — a `handoff-fire.sh` split inherits the *profile* default. Different font ⇒
different row grid ⇒ different composer offset ⇒ mismatched panes and a chat box
that falls outside the crop.

Verify before every shoot — the two panes must report identical `cols`/`rows`:

```bash
it2 session list --json | python3 -c "import json,sys; [print(s['window_id'], s['tab_id'], s['cols'], 'x', s['rows'], s['name'][:40]) for s in json.load(sys.stdin)]"
```

This is not hypothetical: a live check found two panes **in the same window** at
`75×78` and `68×83`.

Capture the **whole window** (title bar → status footer); crop = window bounds × 2
on Retina. AppleScript `bounds` is top-left origin; `it2 window list` is
bottom-left — they disagree, so pick one and stay in it. `it2 window resize` +
`move` in sequence collapsed a window to zero size; set `bounds` **atomically** via
AppleScript instead.

## Firing a two-way agent demo

- **`--notify-back` takes an *optional* bare pane UUID** (`handoff-fire.sh:1550`:
  an empty or `--`-prefixed next token selects `__self__`). Passing
  `$ITERM_SESSION_ID` is the trap — that variable holds the `w2t0p0:UUID` form, it
  is accepted as a *literal* target, and `cc-notify` then answers
  `verdict=unresolvable reason=no-such-target` (`bin/cc-notify:399`). `cc-notify`
  strips the `wNtNpN:` prefix only for `--self` (`:312`). **Pass nothing, or pass
  the bare UUID.**
  When the ping is never delivered the peer correctly **refuses to self-retire** —
  so the take has no close to film, and the failure looks like a directing problem
  rather than a flag problem.
- The originator must be a **real Claude session, not a shell**. A shell has no
  chat UI for the ping to land in, so the entire two-way leg is invisible on camera.

## Capture hygiene: contact-sheet every take

**Not optional. Do this before any take is used.**

```bash
ffmpeg -i take.mov -vf "fps=1/5,tile=8x5" -frames:v 1 contact.png
```

This caught a real leak: a peer session's browser automation took the foreground
mid-recording and filled the window with an app showing what looked like real
people's names and invitation details. That capture was deleted unused.

Also check the composer: Claude Code's next-prompt autosuggestion sits there as dim
ghost text. In a silent clip it reads as a human about to act — one take showed
"close the peer pane", which undercut the self-close the clip was demonstrating.
Crop it out or confirm it is empty.

## Editing

- **Variable speed beats a flat rate**: ~1.5–2× through the beats, ~2.5–5× through
  dead air.
- **Captions belong in a strip padded BELOW the frame**, never overlaid — an
  overlay covers the content the clip exists to show.
- **This ffmpeg has no `drawtext`** (built without libfreetype; `ffmpeg -filters |
  grep -w drawtext` returns nothing). Render caption frames with PIL and composite
  with `overlay`/`vstack`, or label with ImageMagick's `-font`.

## Landing it in the README

Swap **only the `src` token**, by exact string:

```bash
# assets/demo/handoff-live.gif  ->  assets/demo/handoff-live.webp
```

Then assert the **shape** of the file, not merely that your change is present:

```bash
wc -l README.md          # must be unchanged
grep -c '^#' README.md   # heading count must be unchanged
```

**`d6845630` deleted 426 lines of README** because a greedy regex
(`(?:<[^>]+>[^<]*)*</sub>`) used to bound a replacement matched to the *last*
`</sub>` in the file. Restored in `04c549d2`. The post-edit check passed, because
it only confirmed what had been *added*. **Never bound a document replacement with
an open-ended regex; anchor on exact strings and assert line and heading counts
after every edit.**

Update the caption's own claims too — resolution, fps and format are usually
written out in the `<sub>` line next to the image.

## Traps that cost real time

- **`plutil -extract <key> json <file>` without `-o` rewrites the plist in place.**
  It destroyed two LaunchAgents. Use `-o -`, or `grep`.
- **`hooks/mailbox-drain.sh` is a hook and consumes stdin unconditionally**
  (`:36`, `cat >/dev/null` — deliberate, so the writer never SIGPIPEs). A bare call
  on a TTY blocks forever and swallows everything typed after it. Feed it
  `echo '{}' |`.
- **zsh does not word-split unquoted `$VAR`.** `opts="-m 6"; gif2webp $opts …`
  passes `"-m 6"` as one argument and the tool prints usage. Use explicit
  arguments or an array.
- **`pgrep -c` is not valid on macOS.** Use `pgrep -f pat | wc -l`.
- **Check `uptime` before fanning out encodes.** `-m 6` saturates a core for
  minutes; three concurrent encodes on a 10-core box already sharing load with
  other sessions pushed the load average to 12.9.

## Honest limits

- The size win from a format swap on a **live** recording is small (−8.9 % here).
  The real levers are duration, frame rate and crop — all of which change the
  artifact's content, so they are an editorial decision, not a compression one.
- SSIM/PSNR compare distortion *magnitude*, not distortion *kind*, and they are
  **area-averaged** — which is how a lossy WebP that visibly streaked every flat
  grey scored *better* than the GIF on both. Add a targeted metric for the artefact
  class you actually care about (the column-profile stdev above). A global score
  cannot fail a local defect.
- **A visible artefact is not the same as a large one.** This skill previously
  claimed the GIF "posterizes a gradient the WebP tracks cleanly". It was wrong:
  measured RMS against the source over the coloured-text box was GIF 4.02 / 4.92
  vs WebP q65 4.84 / 5.45 at two frames — the GIF was *closer* both times. The
  mistake was reading a contrast-amplified zoom, where palette steps are obvious
  and diffuse ringing is not, and treating obviousness as error. **If you amplify
  to see a difference, you have destroyed the scale — go back and measure it.**
