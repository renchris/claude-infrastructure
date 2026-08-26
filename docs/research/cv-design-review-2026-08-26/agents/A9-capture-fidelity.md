# A9 — Screenshot capture fidelity: does our pipeline preserve the evidence?

**Date:** 2026-08-26 · **Scope:** capture-side only (Playwright/Chromium + agent-browser on macOS → PNG → Claude vision).
**Verdict:** the pipeline as commonly configured **destroys evidence in three independent places, two of them silently**, and one of those manufactures a 1-pixel vertical misalignment that a design-review agent will report as a real layout bug. All three have exact fixes. Every number below is measured on this machine or quoted from a doc URL.

## Measurement environment

| | |
|---|---|
| Playwright | 1.60.0 (`/Users/chrisren/.npm/_npx/705bc6b22212b352/node_modules/playwright`), 1.61.1 also present |
| Bundled Chromium | 148.0.7778.96 (headless shell) / 148.0.0.0 (full, `channel:'chromium'`) |
| System Chrome | 152.0.7977.64 |
| agent-browser | 0.27.1 |
| Claude Code | 2.1.183 bundle, `…/claude-code-darwin-arm64/claude` (compiled; constants read with `strings`) |
| Host | macOS 24.6.0, Apple Silicon, Retina (backing scale 2) |
| Scratch artifacts | `/private/tmp/claude-501/-Users-chrisren-Development-claude-infrastructure/e0bd1d4c-.../scratchpad/` (`page.html`, `cap.mjs`, `metrics.mjs`, `dsf2.mjs`, `full.mjs`, `adv.mjs`, `shots/`) |

---

## 0. The two ceilings nobody configures for

There are **two** resamplers between Chromium and the model, and the tighter one is client-side.

### 0a. Claude Code clamps every image to 2000×2000 px and 3.75 MiB — before the API sees it

Read out of the 2.1.183 binary. The config object and the ladder:

```js
O5 = { maxWidth: 2000, maxHeight: 2000, maxBase64Size: 5242880, targetRawSize: 3932160 }
```

`mAe(buf, byteLen, fmt, O5)` — the image path behind the `Read` tool:

1. **Pass-through iff** `bytes ≤ 3,932,160` **and** `w ≤ 2000` **and** `h ≤ 2000`. Original bytes, original media type. *This is the only lossless path.*
2. Within dimensions but over bytes, PNG → re-encode `png({compressionLevel:9, palette:true})`. **`palette:true` quantises to ≤256 colours.**
3. Still over (or not PNG) → JPEG ladder `[80, 60, 40, 20]`, first that fits.
4. Over dimensions → `sharp.resize(d, p, {fit:'inside', withoutEnlargement:true})` down to 2000×2000 (Lanczos3 default kernel), aspect preserved.
5. Still over bytes after resize → palette PNG, then JPEG `[80,60,40,20]` at the resized dims.
6. Last resort → long edge to **1000 px**, **JPEG quality 20**.
7. On sharp failure → raw base64 iff `ceil(bytes*4/3) ≤ 5,242,880` and dims within limits, else hard error.

Telemetry events `tengu_image_resize` / `tengu_image_resize_failed` fire on every non-pass-through path — the clamp is instrumented but not surfaced to the session. **You never see it happen.**

### 0b. The API's own resize, on the tier Opus 5 is on

Claude views images as **28×28-px patches**; cost is `⌈w/28⌉ × ⌈h/28⌉` visual tokens.

| Resolution tier | Models | Max long edge | Max visual tokens |
|---|---|---|---|
| High-resolution | Claude 4.7 and later | **2576 px** | **4784** |
| Standard | all other models | 1568 px | 1568 |

Source: <https://platform.claude.com/docs/en/build-with-claude/vision> § Resolution and token cost. The exact rule + reference implementation: <https://platform.claude.com/docs/en/build-with-claude/vision-coordinates> § How Claude resizes and pads images. Images are then **padded to the next multiple of 28 on the bottom and right**, content-free.

**This corrects our corpus.** `docs/research/agent-video-understanding-2026-07-26.md:64` states "any image I read is resampled to roughly 1568px on its long edge" — that was the standard tier and is now the *wrong* tier for Opus 5. But it does not follow that we get 2576: **Claude Code's 2000-px client clamp binds first**, so the effective ceiling for a Claude Code design review is **2000 px, not 2576 and not 1568**.

Two further API limits that bite a contact-sheet workflow:
- **>20 image blocks in one request** ⇒ a stricter per-image dimension cap; the doc's own advice is "resize each image so that neither dimension exceeds **2000 px**, or keep the request to 20 or fewer image and document blocks." Images over it are **rejected**, not downscaled.
- "Claude might hallucinate or make mistakes when interpreting low-quality, rotated, or **very small images under 200 pixels**" — the documented floor, matching our prior finding.

### 0c. The resulting frontier (computed with the doc's own reference implementation)

`eff` = model pixels per CSS pixel actually delivered. "CC clamp" = Claude Code's 2000-px step.

| CSS viewport | DPR | raster | Claude Code clamp | API tokens | API resize | eff |
|---|---|---|---|---|---|---|
| 1440×900 | 1 | 1440×900 | no | 1716 | no | **1.00×** |
| 1440×900 | 2 | 2880×1800 | YES → 2000×1250 | 3240 | no | **1.39×** |
| 1440×900 | 3 | 4320×2700 | YES → 2000×1250 | 3240 | no | **1.39×** |
| 1280×800 | 1 | 1280×800 | no | 1334 | no | 1.00× |
| 1280×800 | 1.5 | 1920×1200 | no | 2967 | no | **1.50×** |
| 1280×800 | 2 | 2560×1600 | YES → 2000×1250 | 3240 | no | 1.56× |
| **1000×625** | **2** | **2000×1250** | **no** | **3240** | **no** | **2.00×** |
| 1024×640 | 2 | 2048×1280 | YES → 2000×1250 | 3240 | no | 1.95× |
| 390×844 (phone) | 2 | 780×1688 | no | 1708 | no | 2.00× |
| 390×844 | 3 | 1170×2532 | YES → 924×2000 | 2376 | no | 2.37× |
| **1440×2500 (full-page)** | **1** | 1440×2500 | YES → 1152×2000 | 3024 | no | **0.80×** |
| 1440×2500 (full-page) | 2 | 2880×5000 | YES → 1152×2000 | 3024 | no | **0.80×** |

Three conclusions fall straight out:

1. **DPR 3 is never better than DPR 2.** Identical delivered pixels, 2.25× the encode/transfer cost. Never use it for desktop.
2. **DPR 2 is never worse than DPR 1** — the clamp still leaves you 1.39× at 1440 CSS. But the gain arrives *through a Lanczos downsample*, which softens hairlines (see §5).
3. **A 2500-px-tall full-page capture delivers 0.80× — worse than a plain DPR-1 viewport shot, at any DPR.** Height is the binding constraint on tall pages, and no capture setting fixes it. The fix is to stop sending one tall image (§ Q(e)).

**The real lever is cropping, not DPR.** The 2000-px cap is on the *image*, not on the page. Capture at the true breakpoint and DPR, then `clip` the region under review to ≤1000×1000 CSS px @2 (= ≤2000×2000 raster) so nothing resamples anywhere.

---

## 1. Fidelity-risk table

| # | Capture variable | Failure it causes | How to detect it | Correct setting |
|---|---|---|---|---|
| R1 | **Host display scale not pinned** (`--force-device-scale-factor` absent) | Headless lays out line boxes on whole CSS px; headed on a Retina Mac lays them out on half px. Baselines drift up to **1.5 px** by the 4th paragraph. Agent reports vertical-rhythm / icon-label misalignment that no human sees. | `getBoundingClientRect().top` per paragraph in both modes: headed `[102, 118, 136.5, 157.5]` vs headless `[102, 119, 138, 158]`. Fractional tops ⇒ modes disagree. | `--force-device-scale-factor=2` on **both** modes. Measured: headed-native, headless+flag, headed+flag all produced **sha `7b6dad0a1399`, 85 393 bytes — byte-identical**. |
| R2 | **`scale` left at default `'css'`** | `deviceScaleFactor: 2` is silently discarded at encode. Output is 1× px. Half the resolution you paid to render. | Compare PNG dims to `viewport × DPR`. Measured: viewport 720×400 + `deviceScaleFactor:2` + default scale → **720×400** PNG, byte-identical (sha `ebaca0f07161`) to the DPR-1 capture. With `scale:'device'` → **1440×800**. | `screenshot({ scale: 'device' })`. Non-negotiable whenever DPR ≠ 1. |
| R3 | **Image over 2000 px or 3.75 MiB** | Claude Code silently Lanczos-downsamples, or palette-quantises to 256 colours, or JPEGs at q80→q20. Gradients band; shadows posterise; 1-px borders soften. Agent reports banding/blur/soft-edges that the browser never produced. | Compute `w>2000 || h>2000 || bytes>3 932 160` on the file **before** `Read`. Any true ⇒ what the model sees is not what you captured. | Keep every image ≤2000×2000 and ≤3.75 MiB by construction (crop/tile), never by trusting the resizer. |
| R4 | **Full-page capture of a scroll-animated page** | `IntersectionObserver` / scroll-reveal content is captured in its pre-reveal state. Measured: **1 of 8** reveal targets had fired on a naive `fullPage:true`; 7 sections captured at `opacity:0`. Agent reports "sections are empty / content missing". | Count revealed elements before capture (`document.querySelectorAll('.in').length`) or diff naive vs scroll-primed capture — ours differed 47 991 B → 58 960 B. | Scroll the full height in ≤0.8·viewport steps with a settle delay, return to 0, await image decode, **then** capture. |
| R5 | **`position:fixed` element in a full-page shot** | Rendered **once**, anchored to the scroll-0 viewport — so it lands mid-document. Measured: the fixed badge appears at y≈560 of a 5120-px-tall page, floating over section 0. Agent reports "floating element overlaps body copy at 11% scroll depth". | Locate known-fixed elements' y in the PNG vs their `getBoundingClientRect()`. Mismatch ⇒ artifact of full-page. | Neutralise before capture via `screenshot({ style: '.fixed{position:absolute!important}' })`, or review fixed chrome only in viewport captures. |
| R6 | **`prefers-color-scheme` unset** | Defaults to **light** (measured). A dark-mode design is reviewed in the wrong theme; every contrast finding is void. | `matchMedia('(prefers-color-scheme: dark)').matches` at capture time. | `newContext({ colorScheme: 'dark' \| 'light' })` — set it explicitly, capture both. |
| R7 | **Animations / caret / transitions live** | Non-reproducible frames; a mid-flight transform reads as a layout bug. | Two consecutive captures differ. | `screenshot({ animations:'disabled', caret:'hide' })` (defaults are `'on'` / `'hide'`). |
| R8 | **Web fonts not settled** | Fallback-font metrics captured; every measurement in the review is against the wrong typeface. | Capture at `commit` vs `load`: measured different shas (`b43bf29cfc` → `977698be3c`). Note `document.fonts.status === 'loaded'` and `fonts.check()` **already returned true** at the differing frame — status is not a paint gate. | `await page.evaluate(() => document.fonts.ready)` **plus** a two-consecutive-identical-capture stability check (§3). |
| R9 | **Cross-platform scrollbar** | On macOS Chromium the scrollbar is **0 px** (overlay) with or without `--hide-scrollbars` (measured: `innerWidth − clientWidth = 0` both ways). On Linux/Windows CI it is ~15 px, so the *same page* lays out 15 px narrower. Agent reports a phantom width regression. | `innerWidth - document.documentElement.clientWidth` at capture time; record it in the manifest. | Always pass `--hide-scrollbars`; it is a no-op on macOS and a correctness fix everywhere else. |
| R10 | **Mixing a Chromium PNG with a macOS-native screenshot in a diff** | Chromium PNGs carry **no colour chunk at all** (verified: zero `iCCP`/`sRGB`/`cHRM`, `icc=0B`, in all 8 captures). `screencapture`/`sips` output is tagged Display P3. A diff tool that honours tags will convert one and not the other — 100 % false positives. | `python3 -c "from PIL import Image; print(Image.open(p).info.get('icc_profile'))"` — `None` for Chromium. | Never diff across capture tools. If you must, strip/normalise profiles first. |
| R11 | **Headless shell as the review renderer** | `headless:true` launches `chromium_headless_shell`, a *different binary* from the headed browser ("expect different behavior in some cases" — Playwright docs). | UA string: shell reports `Chrome/148.0.7778.96`, full reports `Chrome/148.0.0.0`. | `channel:'chromium'` for the new headless mode — **but see Q(d): this fixes almost nothing on its own.** |
| R12 | **Timestamps, `Math.random`, video posters, focus rings** | Non-deterministic frames misread as UI churn. | Two-capture stability check catches all of them. | Freeze the clock / seed RNG before capture, or exclude via `mask:`. |

---

## 2. Canonical capture spec

Exact code. `--force-device-scale-factor` must equal the context `deviceScaleFactor`, and `scale:'device'` must be set, or R1/R2 fire.

```js
import { chromium } from 'playwright';

// One flag set. Everything here is either measured-load-bearing or a no-op that is
// cheap to keep for cross-platform parity. See notes below for what was measured inert.
const CAPTURE_ARGS = [
  '--force-device-scale-factor=2',   // R1 — THE load-bearing flag. Must match DPR below.
  '--hide-scrollbars',               // R9 — no-op on macOS, correctness fix on Linux/Windows.
  '--force-color-profile=srgb',      // Q(b) — pins output gamut; measured inert on macOS today.
  '--disable-lcd-text',              // measured inert on macOS (CoreText grayscale AA). Keep for Linux.
  '--font-render-hinting=none',      // measured inert on macOS (FreeType-only). Keep for Linux.
  '--disable-font-subpixel-positioning',
  '--run-all-compositor-stages-before-draw',
  '--disable-partial-raster',
  '--disable-skia-runtime-opts',     // pins Skia to a fixed code path across CPUs
  '--deterministic-mode',
];

const browser = await chromium.launch({
  channel: 'chromium',               // R11 — new headless = the real browser, not the shell
  headless: true,
  args: CAPTURE_ARGS,
});

const ctx = await browser.newContext({
  viewport: { width: 1440, height: 900 },  // the real desktop breakpoint under review
  deviceScaleFactor: 2,                    // MUST equal --force-device-scale-factor
  colorScheme: 'light',                    // R6 — never leave implicit; capture 'dark' too
  reducedMotion: 'reduce',                 // R7 — belt-and-braces with animations:'disabled'
  timezoneId: 'UTC',
  locale: 'en-US',
});

const page = await ctx.newPage();
await page.goto(url, { waitUntil: 'load' });
await page.evaluate(() => document.fonts.ready);          // R8
await page.evaluate(() => new Promise(requestAnimationFrame));

// R4 — prime scroll-driven content, then return to the top.
await page.evaluate(async () => {
  const h = document.documentElement.scrollHeight;
  for (let y = 0; y < h; y += Math.floor(innerHeight * 0.8)) {
    window.scrollTo(0, y);
    await new Promise(r => setTimeout(r, 120));
  }
  window.scrollTo(0, 0);
  await new Promise(r => setTimeout(r, 400));
});
await page.evaluate(() => Promise.all([...document.images].map(i => i.complete ? 0 : i.decode().catch(() => 0))));

const SHOT = {
  scale: 'device',            // R2 — without this deviceScaleFactor is DISCARDED
  animations: 'disabled',     // R7 (default is 'on')
  caret: 'hide',              // default, stated for the record
  type: 'png',
  style: '.js-fixed, [data-fixed] { position: absolute !important }',  // R5
};

// Region pass — ≤1000x1000 CSS px @2 == ≤2000x2000 raster == NO resample anywhere.
await page.screenshot({ ...SHOT, path: 'hero@2x.png',
                        clip: { x: 0, y: 0, width: 1000, height: 625 } });

// Breakpoint pass — 2880x1800; Claude Code WILL clamp to 2000x1250 (1.39x eff).
// Acceptable for layout/structure judgements, NOT for hairline/gradient judgements.
await page.screenshot({ ...SHOT, path: 'viewport@2x.png' });
```

**Device-scale-factor set to review.** Match the human. The operator reads on a Retina Mac, so `2` is correct here. If the review target is a 1× display, set both to `1` — but set them, and set them equal.

**Viewport set.** Four, in priority order: `1440×900` (desktop breakpoint truth) · `1000×625` @2 (lossless detail pass) · `768×1024` (tablet) · `390×844` @2 (phone — 780×1688, under every cap, fully lossless). Every one at `deviceScaleFactor: 2`, `scale:'device'`.

**Colour profile.** `--force-color-profile=srgb`. Values are `srgb`, `display-p3-d65`, `color-spin-gamma24`, `scrgb-linear`. It was **measured inert on macOS today** (identical sha with and without) — keep it as a pin against a future Chromium default flip and against non-macOS hosts, not because it changes anything now.

**Font settings.** Nothing to configure on macOS: `--disable-lcd-text`, `--font-render-hinting=none` and `--disable-font-subpixel-positioning` all produced byte-identical output (sha `ebaca0f07161` unchanged). They are FreeType-facing. The macOS lever that *does* exist is the CSS one (`-webkit-font-smoothing`), which is the page's choice, not the harness's.

**CDP equivalent** (for the agent-browser / raw-CDP path). `Page.captureScreenshot` params, <https://chromedevtools.github.io/devtools-protocol/tot/Page/#method-captureScreenshot>: `format` (png default), `quality` (jpeg only), `clip: {x, y, width, height, scale}` — **x/y/width/height are in device-independent px, `scale` is the page scale factor**, so `scale: 2` is the CDP analogue of `scale:'device'` at DPR 2; `fromSurface` (default `true`); `captureBeyondViewport` (default `false` — set `true` for full-page without scrolling); `optimizeForSpeed` (default `false` — leave it, it trades bytes for determinism-irrelevant speed). Size the clip from `Page.getLayoutMetrics().cssContentSize` (CSS px), not the deprecated `contentSize` (device px).

**agent-browser (0.27.1).** `set viewport <w> <h> [scale]` now reaches the raster — verified: `set viewport 720 400 2` produced a **1440×800** PNG, `… 1` produced 720×400. GH `vercel-labs/agent-browser#255` ("set device does not apply deviceScaleFactor") is **closed** by PR #270. The CLI still exposes no `--scale css|device` and no launch-arg passthrough for `--force-device-scale-factor`, so **agent-browser cannot currently produce an R1-clean capture** — use raw Playwright for review captures.

---

## 3. Determinism checklist — making two captures byte-comparable

Everything here was verified: with the checklist applied, repeated captures across *separate browser launches* were byte-identical (sha `ebaca0f07161` across three independent launches with different flag sets).

1. **Pin the display scale.** `--force-device-scale-factor=N` **and** context `deviceScaleFactor: N`, equal. Without it, headed and headless disagree on layout, not just on pixels.
2. **Pin the encoder path.** `scale:'device'`, `type:'png'`. Never `jpeg`, never `quality`.
3. **Pin the binary.** Same Playwright version and same `channel` on both sides. `chromium_headless_shell` and `chromium` are different builds — measured 7.85 % of pixels different between them (though at **max channel delta 2**, i.e. invisible).
4. **Freeze motion.** `animations:'disabled'`, `caret:'hide'`, `reducedMotion:'reduce'`, plus `style: '*{animation:none!important;transition:none!important}'` for anything JS-driven.
5. **Freeze the clock and RNG** before first paint (`page.addInitScript`) — `Date.now`, `performance.now`, `Math.random`.
6. **Freeze the environment.** `timezoneId`, `locale`, `colorScheme`, `--hide-scrollbars`.
7. **Gate on fonts, then on stability.** `document.fonts.ready` → one `requestAnimationFrame` → capture twice → require `sha256(a) === sha256(b)`. This single check subsumes gates 4–6 as a *detector*: it caught the pre-`load` webfont frame (`b43bf29cfc` ≠ `977698be3c`) that `document.fonts.status === 'loaded'` had already declared safe.
8. **Prime scroll-driven content** (R4) and neutralise `position:fixed` (R5) identically on both sides.
9. **Record a capture manifest** beside every PNG: playwright version, chromium UA, channel, flags, viewport, DPR, colorScheme, scrollbar width, `sha256`, `w×h`, bytes. A diff between captures with different manifests is not evidence.
10. **Gate the file before `Read`.** Assert `w ≤ 2000 && h ≤ 2000 && bytes ≤ 3 932 160`. If it fails, tile or clip — do not let the client resizer decide.
11. **Never diff across capture tools** (R10) and never diff a Chromium PNG against a macOS `screencapture` PNG.
12. **Compare with a tolerance, and report the tolerance.** Use `expect(page).toHaveScreenshot()` (`maxDiffPixelRatio` / `threshold`) or an explicit `>8` per-channel threshold. Raw byte equality across *machines* is not achievable and is not the goal; a ±1-LSB dither field is normal (measured: 7.85 % of pixels differ at max delta 2 between two Chromium builds — zero of it perceptible).

---

## 4. Answers to the five questions

### (a) Does capturing at DPR 2 or 3 help, or does the model's downscaling waste it?

**DPR 2 helps. DPR 3 is pure waste. And the binding constraint is Claude Code's 2000-px clamp, not the API's tier limit.**

The chain is: browser raster → **Claude Code clamp at 2000×2000 / 3.75 MiB** → API tier resize (2576 edge / 4784 tokens for Opus 5) → 28×28 patching → pad to a multiple of 28. Because 2000 < 2576 and a 2000×1250 image costs 3240 of the 4784 available tokens, **the API layer never fires for a Claude-Code-clamped desktop screenshot** — the client did the damage first.

Consequences, from the §0c table:
- At 1440 CSS width, DPR 1 delivers **1.00×**, DPR 2 delivers **1.39×**, DPR 3 delivers **1.39×**. DPR 3 costs 2.25× the pixels for identical delivered detail.
- At 1000 CSS width, DPR 2 delivers a **clean 2.00×** with no resample at any stage — the only desktop configuration that is lossless end to end.
- On phone viewports (390×844) DPR 2 is already lossless (780×1688) and DPR 3 still nets 2.37×, because the *height* has room. Mobile is the one place DPR 3 pays.

**Recommendation:** always `deviceScaleFactor: 2` + `scale:'device'` (DPR 2 is never worse than DPR 1, even after the clamp). Get the remaining detail by **clipping to ≤1000×1000 CSS px**, not by raising DPR. Reserve DPR 3 for tall narrow mobile viewports.

**Tiling caveat:** if a review sends >20 image blocks in one request, the per-image cap tightens and oversized images are **rejected, not downscaled**. A 25-tile contact sheet is a request that fails, not one that degrades. Keep waves ≤20 images.

### (b) Colour — P3 vs sRGB, profile tagging, headless vs headed, false positives in a pixel diff?

**Measured, all eight captures:** `color(display-p3 1 0 0)` and `#ff0000` both encode to **(255, 0, 0)**; `color(display-p3 0 1 0)` encodes to **(0, 255, 0)**. Identical. And **no PNG carried any colour chunk** — zero `iCCP`, `sRGB`, `cHRM`; PIL reports `icc_profile = None` in every file, headless and headed alike.

Three consequences:

1. **A screenshot cannot testify about gamut.** Chromium rasterises to an untagged sRGB-numeric buffer; a P3 colour is clipped into sRGB before it reaches the file. An agent asked "is this brand red out of sRGB gamut?" is being asked a question the evidence cannot answer — that is a **false negative**, and the honest answer is "not determinable from a screenshot; read the computed style."
2. **`--force-color-profile=srgb` changed nothing on macOS today** — identical sha with and without, headless and headed. It is a pin, not a fix. Values: `srgb`, `display-p3-d65`, `color-spin-gamma24`, `scrgb-linear`.
3. **The real false-positive risk is cross-tool.** Because Chromium output is *untagged*, and macOS `screencapture`/`sips` output is *tagged Display P3*, any pixel diff that mixes the two will convert one side and not the other and light up on every saturated region. Never mix capture tools inside a diff.

Headless vs headed made **no colour difference**: the gradient band differed on 30.6 % of pixels at **max channel delta 1** — dither, not colour.

### (c) Text rendering — smoothing, subpixel AA, fallback, web-font races

**Subpixel/LCD antialiasing is a non-issue here.** Coloured-fringe probe (count of text-band pixels where R≠G or G≠B): **0 out of 9 303 non-white pixels**, in every mode — headless shell, new headless, headed, with and without `--disable-lcd-text`. macOS dropped subpixel AA in Mojave and Chromium captures are grayscale-AA. The flags everyone recommends (`--disable-lcd-text`, `--font-render-hinting=none`, `--disable-font-subpixel-positioning`) are **measurably inert on macOS** — identical sha in every combination. They belong in the arg list for Linux parity only.

**Font fallback is not the variance source either.** Canvas advance widths were identical across all modes (`-apple-system` 273.29 px, `Georgia` 295, `Helvetica` 295.76 for the same string), and so were vertical metrics (`16px -apple-system` → ascent 14, descent 4, actualAscent 10.59) in headless shell, new headless and headed alike. Same faces, same metrics.

**The actual text variance is layout snapping, and it is fixed by one flag.** See Q(d) and R1.

**Web-font race:** a capture taken before `load` differed from every later capture, *even though* `document.fonts.status` already read `"loaded"` and `document.fonts.check("34px 'Playfair Display'")` already returned `true` at that frame. `fonts.ready` is necessary but is **not a paint gate**. The exact wait that eliminated the variance:

```js
await page.goto(url, { waitUntil: 'load' });
await page.evaluate(() => document.fonts.ready);
await page.evaluate(() => new Promise(requestAnimationFrame));
// then: capture twice, require identical sha256
```

With that, three successive captures were byte-identical (`977698be3c` ×3).

### (d) Headless vs headed on macOS — does new headless close the gap?

**No. New headless removes only the imperceptible half of the difference; the visible half survives untouched.** Measured on the same page, same page-level flags:

| Comparison | pixels differing | differing by **>8** per channel | max channel delta |
|---|---|---|---|
| `headless_shell` vs headed | 29 567 / 288 000 (**10.27 %**) | 8 363 (**2.90 %**) | 255 |
| `channel:'chromium'` headless vs headed | 9 325 / 288 000 (**3.24 %**) | 8 364 (**2.90 %**) | 255 |
| `channel:'chromium'` headless vs `headless_shell` | 22 604 (7.85 %) | **0 (0.00 %)** | **2** |

Read the third row first: the two headless binaries differ on 7.85 % of pixels at **max delta 2** — pure LSB dither, invisible. Switching to `channel:'chromium'` moves the headline number from 10.27 % → 3.24 % by removing exactly that dither, and leaves the **2.90 % of pixels that differ by up to 255 completely unchanged**. That residue is the whole problem, and it is concentrated in text (14.1 % of the text band, delta up to 229) and in a fallback-font line (15.8 %, delta 255).

**Root cause, isolated.** Not the binary, not the fonts, not the rasteriser — **the host display's backing scale factor leaking into layout**:

```
headed   (Retina, DSF 2) : #txt p tops = [102, 118, 136.5, 157.5]   ← fractional
headless (no display)    : #txt p tops = [102, 119, 138,   158  ]   ← integer
```

Font metrics are byte-identical in both. Headed Chromium snaps line boxes at half-device-pixel granularity; headless has no display, snaps at whole CSS pixels, and the error accumulates to **1.5 px by the fourth paragraph**. Note that Playwright's context `deviceScaleFactor` does **not** control this — it drives `Emulation.setDeviceMetricsOverride` (`window.devicePixelRatio` reported 1 in both) while the compositor's raster scale still follows the host window. Only the command-line switch reaches it.

**Fix, verified byte-for-byte.** With `--force-device-scale-factor=2` plus context `deviceScaleFactor: 2` plus `scale:'device'`:

| configuration | rect tops | bytes | sha256 (12) |
|---|---|---|---|
| headed, native Retina | `[102, 118, 136.5, 157.5]` | 85 393 | `7b6dad0a1399` |
| **headless + `--force-device-scale-factor=2`** | `[102, 118, 136.5, 157.5]` | **85 393** | **`7b6dad0a1399`** |
| headed + `--force-device-scale-factor=2` | `[102, 118, 136.5, 157.5]` | 85 393 | `7b6dad0a1399` |
| headless, flag absent | `[102, 119, 138, 158]` | 85 402 | `c5b351dac7dd` |

Three configurations converge on the identical file. **The gap is not "headless vs headed"; it is "display scale pinned vs unpinned", and one flag closes it completely.** Symmetrically, `--force-device-scale-factor=1` on a *headed* Retina browser reproduces the headless integer layout — proving the flag, not the mode, is the variable.

### (e) Full-page vs viewport

Full-page is the wrong default for a design review, on four independent grounds.

1. **Resolution.** A 2500-px-tall page delivers **0.80×** after the 2000-px clamp — *worse than a DPR-1 viewport shot*, at any DPR (§0c). Height is the binding constraint and no capture setting fixes it.
2. **Scroll-driven content.** Naive `fullPage:true` fired **1 of 8** `IntersectionObserver` reveals; 7 sections were captured at `opacity:0` / `translateY(20px)`. Priming the scroll first took it to 8 of 8 (47 991 B → 58 960 B).
3. **`position:fixed`.** Rendered once, anchored at the scroll-0 viewport position — the badge landed at y≈560 in a 5120-px image, reading as a floating element that overlaps section 0's body copy.
4. **`position:sticky` is fine.** Measured: the sticky header rendered exactly once, at its natural y=0..56, not repeated per screenful. Modern Playwright `fullPage` uses `captureBeyondViewport` rather than scroll-and-stitch, so the classic "header repeated 8 times" artifact does **not** occur on 1.60. Do not carry that assumption forward from older tooling.

**Correct procedure:**

```
1. goto(url, {waitUntil:'load'}) → fonts.ready → rAF
2. scroll 0 → scrollHeight in 0.8·viewport steps, ~120 ms settle per step
3. scrollTo(0,0), settle ~400 ms
4. await Promise.all([...document.images].map(i => i.complete ? 0 : i.decode()))
5. neutralise fixed:  screenshot({ style: '.fixed{position:absolute!important}' })
6. capture VIEWPORT TILES, not one tall image:
   for (y = 0; y < scrollHeight; y += viewportHeight)
     screenshot({ clip:{x:0, y, width:1000, height:625}, scale:'device' })
   → each tile is 2000x1250 raster: no client clamp, no API resize, 2.00x effective
7. keep the wave ≤20 images per request (over 20 ⇒ oversized images are REJECTED)
8. optionally ONE fullPage:true at DPR 1 as a low-res structural index only
```

The full-page shot is a *table of contents*, not evidence. Judgements about spacing, hairlines, type and colour are made on tiles.

---

## 5. Adversarial pass — the one defect most likely to make the agent report a bug that isn't there

**It is R1: the unpinned display scale factor, producing a 1-px vertical offset that reads as a real alignment defect.**

Why this one and not the others: it is the only defect that **shifts geometry** rather than degrading it. Blur, banding and JPEG artifacts make an agent hedge ("this looks slightly soft"); a 1-px baseline offset makes it *assert* — "the label's baseline sits 1 px below the icon's centre", "vertical rhythm breaks between the second and third paragraph". Those are exactly the findings a design reviewer is hired to produce, they are specific, they are falsifiable-sounding, and they are wrong. Measured magnitude: **1.5 px of accumulated drift over four consecutive paragraphs**, from a mechanism with no error message and no visible symptom.

The near-miss runner-up is R3's silent Lanczos downsample of a 2880-px capture to 2000 px, which softens 1-px borders and can be reported as "the divider looks 1.5 px and blurry, not a crisp hairline". That one is real but self-limiting — it degrades uniformly, so a reviewer that sees *every* edge softened will usually attribute it to the image.

**How to prove a finding is an artifact — a three-step falsification, in cost order:**

1. **DOM truth.** Ask the page, not the picture: `getBoundingClientRect()` on the two elements the agent says are misaligned. If the rects agree to the pixel and the image disagrees, the image is lying. This is one `page.evaluate`, costs nothing, and settles it outright.
2. **Shift search.** Crop the disputed band from two captures made under different launch configs and minimise mean-absolute-difference over `dx, dy ∈ [-3, 3]`. If the minimum sits at a non-zero `dy`, the "defect" is a whole-image translation, not a layout error. Measured on our own case: mean abs error fell from **10.26 at dy=0 to 2.83 at dy=+1**, and >8-delta pixels from 6 547 to 1 761 — an unambiguous 1-px translation signature.
3. **Flag flip.** Re-capture with `--force-device-scale-factor` set to the reviewer's real display scale. If the finding evaporates, it was R1. Our control: three configurations that disagreed on layout converged on **sha `7b6dad0a1399`, 85 393 bytes** once the flag was set.

Build step 1 into the review loop unconditionally: **every geometric finding must be seconded by a `getBoundingClientRect()` read before it is reported.** A vision model measuring pixels is a sampling instrument; the DOM is the ground truth, and it is free.

---

## 6. Blockers, uncertainties, and what I did not verify

- **Claude Code version drift.** The 2000-px / 3.75-MiB constants were read from the **2.1.183** bundle at `/Users/chrisren/.claude-versions/2.1.183/node_modules/@anthropic-ai/claude-code-darwin-arm64/claude`. `~/.claude-versions/current` points at **2.1.114**. I did not read 2.1.114's constants, and a newer bundle may raise the cap toward the 2576 high-res tier. **Re-read `strings <bundle> | grep maxWidth:` before trusting the number.** The *shape* of the ladder (pass-through → palette → JPEG → resize) is what generalises; the constants perish.
- **Tier membership of Opus 5 is inferred, not stated.** The doc says "Claude 4.7 and later models" are high-resolution. Opus 5 is later than 4.7, so the inference is safe, but the doc does not enumerate it. If wrong, the standard tier (1568/1568) applies and the API layer becomes the binding constraint again at 1568 rather than 2000 — which would make the `1000×625 @2` recommendation *more* right, not less (2000×1250 would then be resized to ~1389×868).
- **`--force-device-scale-factor` was tested at 1 and 2 only**, on one machine, one page, one Chromium (148). I did not test 1.5, non-Retina hosts, or Linux. The mechanism (host backing scale reaching layout snapping) predicts the same behaviour, but it is a prediction.
- **The 3.75-MiB byte cap was never actually hit** in my real-page tests (`playwright.dev/docs/screenshots` full-page at DPR 2 = 0.48 MiB). It will bite on image-heavy marketing pages; I have not found the crossover empirically. The palette-quantisation path (R3, step 2) is therefore **read from the binary, not observed firing.**
- **Not investigated:** WebGL/canvas content (compositor path differs and is a known determinism hazard), `<video>` poster frames, cross-origin iframe capture, `mask:`/`maskColor` interaction with pixel diffs, and Chrome 152 (the system browser) — all measurements used Playwright's bundled Chromium 148.
- **agent-browser gap is a real blocker for our sanctioned path.** 0.27.1 passes DPR through (verified: 720×400 @2 → 1440×800) but exposes no way to set `--force-device-scale-factor`, so every agent-browser capture on this machine carries the R1 defect. Review captures must go through raw Playwright until that is exposed.

---

## Sources

- Anthropic — Vision (limits, tiers, token cost, <200 px caveat, >20-image rule): <https://platform.claude.com/docs/en/build-with-claude/vision>
- Anthropic — Coordinates and bounding boxes (exact resize/pad rule + reference implementation, `transformations: {oversized_image: "error"}`): <https://platform.claude.com/docs/en/build-with-claude/vision-coordinates>
- Playwright — `page.screenshot()` options (`scale`, `animations`, `caret`, `style`, `mask`): <https://playwright.dev/docs/api/class-page#page-screenshot>
- Playwright — Browsers (chromium headless shell vs `channel:'chromium'` new headless): <https://playwright.dev/docs/browsers>
- CDP — `Page.captureScreenshot` / `Page.getLayoutMetrics`: <https://chromedevtools.github.io/devtools-protocol/tot/Page/#method-captureScreenshot>
- Chromium `--force-color-profile` values (`srgb`, `display-p3-d65`, `color-spin-gamma24`, `scrgb-linear`): <https://chromium.googlesource.com/chromium/src/+/ceb8727d80e9ddd671577494ddeb1c182645833e%5E%21/>
- agent-browser GH #255 "set device does not apply deviceScaleFactor — HiDPI screenshots not possible" (closed, PR #270): <https://github.com/vercel-labs/agent-browser/issues/255>
- Prior corpus finding this document corrects: `docs/research/agent-video-understanding-2026-07-26.md:62-90` (the "1568 px long edge" constraint — right tier, wrong model class, and superseded by the client-side 2000-px clamp)
