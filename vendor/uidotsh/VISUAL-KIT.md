# Using this mirror for VISUAL work, not just code rules

The guideline corpus reads as behind-the-scenes engineering — semantics, Tailwind
authoring, accessibility. That is the smaller half of what is here. The visual
half is real but it is scattered across four places and none of them announces
itself. This file names them.

## 1. The two runtime dependencies that die with the vendor — both now survivable

These are not documentation. They are live HTTP dependencies baked into the rules,
and UI generated under those rules breaks when ui.sh goes dark.

**`ui-picker.js`** — the `ideas` skill tells the agent to inject
`<script src="https://ui.sh/ui-picker.js">`. That is the in-browser variant picker:
a floating toolbar (`◀ 1/4 "Large avatar on left" ▶`) that cycles hidden
`data-uidotsh-option` siblings so you can *look* at 4 designs instead of reading 4
descriptions.

Measured: the file makes **zero** network calls and contains **zero** `ui.sh`
references. It binds only to `data-uidotsh-pick` / `data-uidotsh-option`. So it is
fully self-hostable — the vendor URL is the only tie, and it is one string:

```
-  <script src="https://ui.sh/ui-picker.js"></script>
+  <script src="/vendor/uidotsh/ui-picker.js"></script>
```

Re-verify before relying on it (never trust this paragraph):
`grep -c 'ui\.sh\|fetch(' ui-picker.js` must print 0.

**`assets.ui.sh`** — `placeholder-content.md` says *"Always use
`https://assets.ui.sh/screenshots/1.webp`"* and routes every placeholder logo,
avatar and mark through that host. All 77 of those files are in `assets/`.
Self-host and rewrite the base URL the same way.

## 2. The aesthetic-direction engine — `ui/ideas.md`, not `ideas.md`

The **legacy** `ideas` carries a seven-axis style-definition framework the current
one dropped: layout · typography · color · spacing · surfaces · shape ·
personality, with a worked bad-vs-good pair. Its own example shows the bar:

> Bad: "Minimal and clean — a simple layout with plenty of whitespace"
>
> Good: "Editorial and asymmetric — oversized serif headline (DM Serif Display,
> ~72px) with dramatic scale contrast against small body text. Warm stone neutrals
> with a single saturated terracotta accent on the CTA only… No cards, no borders,
> no shadows — hierarchy through type scale and weight alone."

That is the most directly reusable visual artifact in the mirror, and it is
model-agnostic: it is a prompt discipline, not a ui.sh feature.

## 3. The brand generator — `brand-kit/brand-kit-prompt.md`

A 12KB production-ready image prompt for a fixed 3840×2160 board: 40% homepage
mockup / 40% supporting page / 20% design-system rail carrying only typography and
hierarchical color. `reference/emails-2026-06/brand-kit.jpg` is the vendor's own
output — a matte-black barbell brand whose rail names Druk Wide Bold, Neue Haas
Grotesk Text 55 Roman, Söhne Mono, and hex-labelled core + accent palettes.

**Caveat, and it is the load-bearing one:** `brand-kit.md` renders this through the
`imagegen` skill, which is **host-side and NOT in this mirror** (probed:
`uidotsh://imagegen` → `Skill resource not found`). The *prompt* is fully portable;
the renderer is whatever image model you have.

## 4. The color and type libraries hiding in reference files

- `design/guidelines/font-recommendations.md` — 15 typefaces with sourcing URLs,
  pairing notes, weight restrictions, and OpenType feature settings.
- `design/guidelines/assets-api.md` — 45 wallpaper variants, each with a written
  color direction (*"muted heather purple, deep moss green, weathered peat brown,
  soft charcoal grey"*). Read as prose it is a named palette library; the matching
  images are in `assets/wallpapers/`.

## What could NOT be mirrored, and what that costs

One surface is a **generator**, not a set of files, so no crawl can hold it: the marks
endpoint composes a wordmark from arbitrary text and bakes the glyphs into **vector
paths server-side** (measured — the response is `<path>` data, not `<text>`). Its
parameter space is any brand name x 6 fonts x weights x colours, so it is infinite by
construction.

**Mitigation, and why this is re-implementable rather than lost:** the mark glyph
itself is `assets/marks/1.svg` and is trivially recolourable, all six fonts are
publicly obtainable (Google Fonts / Fontshare, sourcing URLs in
`design/guidelines/font-recommendations.md`), and `assets/marks/mark-sample-*.svg`
holds one specimen per font so the lockup's proportions, spacing and baseline are on
record. Setting the text locally in the real typeface and converting to outlines
reproduces the same artifact. What dies is the convenience, not the capability.

Everything else in the parameter space IS derivable locally from what is here: logo
`color`/`accent-color` are fill swaps on SVGs we hold; avatar `size`/`w`/`h`/`grayscale`
are transforms of originals we hold; wallpaper `variant` was enumerable and all 45 are
captured.

## Reference images

`reference/emails-2026-06/` — the four embeds from the 2026-06-10 announcement,
the only visual record of what these skills produce: `skills.jpg`, `ideas.jpg`
(the picker in use), `brand-kit.jpg` (a full board), `add-dark-mode.jpg`.
