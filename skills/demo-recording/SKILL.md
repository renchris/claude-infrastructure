---
name: demo-recording
description: Record a real screen demo — a live agent session, a terminal, a two-way exchange between panes — and land it in a README as an image GitHub will actually animate. Use when asked to record or re-record a demo, capture a live session on video for docs, shrink an oversized README GIF, or add a screen recording to a README. Covers the settled format decision (GitHub strips <video>; animated WebP is served byte-identical and is measurably better per byte than GIF), iTerm2 window sizing (font size is per-session and silently breaks pane matching), firing a two-way agent demo so the whole exchange is on camera, the mandatory contact-sheet review, caption strips as padded frames (this ffmpeg has no drawtext), and encode recipes with measured byte counts. NOT for understanding an existing video (that is video-understanding), and NOT for a scripted terminal clip where nothing live is needed — vhs + a .tape file is simpler and re-runnable (assets/demo/handoff-real.tape is the working reference).
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

## Encode recipes, with the numbers

Two different jobs. **Do not use one recipe for both.**

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

### A live screen recording → WebP: encode from the video master, not the GIF

```bash
ffmpeg -v error -i master.mp4 -vf "fps=20,scale=1200:716:flags=lanczos" frames/%04d.png
img2webp -min_size -loop 0 -d 50 -lossy -q 70 frames/*.png -o out.webp
```

`-d` is per-frame **milliseconds** and must match the fps (20 fps → `-d 50`).
`-min_size` is file-level and must come **before** the frame files.

Measured on the 1200×716 / 20 fps / 610-frame hero (`handoff-live`), all against
the same source frames:

| Encode | Bytes | vs GIF | SSIM ↑ | PSNR ↑ | Encode time |
| --- | --- | --- | --- | --- | --- |
| `handoff-live.gif` (64-colour baseline) | 3,483,666 | — | 0.975131 | 38.31 dB | — |
| `img2webp -lossy -q 70 -m 6` (no `-min_size`) | 3,130,182 | −10.1 % | — | — | 670 s |
| `img2webp -min_size -lossy -q 70` | 3,171,988 | −8.9 % | **0.978576** | **39.61 dB** | **45 s** |
| `img2webp -lossless -m 6` | 6,083,602 | +75 % | lossless | ∞ | 94 s |

Three things to take from that table:

- **Lossless loses badly** on photographic/anti-aliased screen content. It only
  wins on flat, few-colour terminal output (the `gif2webp` case above).
- **`-min_size` buys ~15× encode speed here, not size** (670 s → 45 s for the same
  ~3.1 MB). Its size effect is content-dependent — decisive for the VHS clip,
  neutral for the live recording. Always measure; never assume it helps size.
- **A live screen recording compresses far worse than a terminal clip**, because
  it has continuous subtle motion (cursor blink, streaming text, UI animation) and
  so almost no identical-frame redundancy — 610 frames in, 610 frames stored, zero
  deduplication. Expect **single-digit percent** from a format swap here, not the
  order-of-magnitude win the format's reputation suggests.

**Quality is a number, not an adjective.** Compare *both* candidates against the
**source frames**, never against each other:

```bash
ffmpeg -hide_banner -i cand/%04d.png -i source/%04d.png -lavfi ssim -f null - 2>&1 | grep -o 'SSIM.*'
ffmpeg -hide_banner -i cand/%04d.png -i source/%04d.png -lavfi psnr -f null - 2>&1 | grep -o 'PSNR.*'
```

At q70 the WebP beat the GIF on **both** metrics (SSIM +0.0034, PSNR +1.30 dB)
while being smaller — so the swap is a strict improvement, not a trade. If a
candidate merely *ties* the GIF, say so; do not call a tie an upgrade.

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
- SSIM/PSNR compare distortion *magnitude*, not distortion *kind*. GIF banding and
  WebP ringing can score alike and look different on text. Keep the side-by-side
  visual check at README width; the metrics narrow the candidates, they do not
  pick the winner alone.
