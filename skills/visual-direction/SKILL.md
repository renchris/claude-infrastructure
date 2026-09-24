---
name: visual-direction
description: Studio-quality visual design with a committed aesthetic, for building or redesigning UI (pages, dashboards, decks, landing pages) or when a design looks generic. Decides the look first, then routes to the ui.sh corpus for mechanics.
---

# Visual direction — decide the look, then enforce the mechanics

**The failure this exists to prevent.** Asked for design, an agent reaches for the nearest
design-named thing and starts tweaking markup and a11y semantics. The page ends up correct and
forgettable. On this machine that reflex has a specific cause, and it is measured: ui.sh's
`/design` skill and its 37 guideline files carry **0 hex values and 2 aesthetic adjectives across
347 bullets**. It is a Tailwind implementation linter wearing a design skill's name. It cannot
tell you what anything should look like, and running it first pulls every choice toward a safe
default — *never indigo, prefer zinc/neutral, never font-bold* — which prevents ugly and equally
prevents memorable.

**The stack has two halves and the ORDER is the whole technique.**

## 1. DECIDE — commit to an aesthetic before any markup

Load the `frontend-design` skill (it auto-triggers on build-UI requests; load it explicitly if it
did not). Name the subject, audience and job first — distinctive choices come from the subject's
vernacular, not from a palette generator. Produce a token plan:

- **Color** — 4-6 named hex values, with roles.
- **Type** — one or two families, roles stated. Two only if clearly distinct.
- **Layout** — a concept in one sentence plus an ASCII wireframe; state alignment.
- **Principles** — what makes this page unlike any other page.

Then **review that plan against the brief and revise anything that is a default.** `frontend-design`
ships the named cliché list (cream `#F4F1EA` + terracotta `#D97757`, the SaaS-card kit, ALL-CAPS
eyebrows, `→` appended to buttons). If your plan reads like what you would produce for any similar
brief, it is not yet a design.

## 2. DIVERSIFY — 3-4 genuinely different directions, not variants of one

Use the **seven axes** from the mirrored legacy skill — `vendor/uidotsh/ui/ideas.md` (this exists
ONLY in our mirror; the vendor dropped it from the current `ideas` skill): layout · typography ·
color · spacing · surfaces · shape · personality. Its own calibration bar:

> Bad: "Minimal and clean — a simple layout with plenty of whitespace"
>
> Good: "Editorial and asymmetric — oversized serif headline (DM Serif Display, ~72px) with dramatic
> scale contrast against small body text. Warm stone neutrals with a single saturated terracotta
> accent on the CTA only. No cards, no borders, no shadows — hierarchy through type scale and weight
> alone."

The second is a decision; the first is a mood. If your directions differ only in accent colour, you
generated one direction four times.

Concrete inputs, both in the mirror: `design/guidelines/font-recommendations.md` (17 typefaces with
sourcing URLs, pairing notes, weight restrictions, OpenType feature settings) and
`design/guidelines/assets-api.md` (45 wallpaper variants, each with a written colour direction —
read as prose it is a named palette library).

## 3. LOOK — choose visually, never from descriptions

Render the directions and **look at them**; a picture is worth 1000 tokens. For in-browser
comparison use the picker: annotate `data-uidotsh-pick` / `data-uidotsh-option` per
`vendor/uidotsh/ui/ideas.md`, and serve the script **from our copy**, not the vendor:

```html
<script src="/vendor/uidotsh/ui-picker.js"></script>
```

It is self-hostable — measured zero network calls and zero `ui.sh` references. Re-verify before
relying on it: `grep -c 'ui\.sh\|fetch(' ui-picker.js` must print 0.

## 4. CONSTRAIN — now, and only now, run the mechanics

With a direction chosen, apply `vendor/uidotsh/design/design-guidelines.md` and its rule files to
the winner. This is where those 347 rules earn their keep: concentric radii, `min-w-0` on shrinking
flex children, `shrink-0` on icons, 48×48 touch targets, table overflow, the responsive and dark-mode
floors. Load every rule file that could apply — the corpus tells you to err toward loading too many.

## 5. CUT — remove one thing

Spend boldness in one place: one memorable element, everything around it quiet. Then take one
accessory off.

## Hard-won notes

- **`imagegen` is NOT in the mirror.** `brand-kit` renders through it and it is host-side
  (`uidotsh://imagegen` → `Skill resource not found`). `brand-kit/brand-kit-prompt.md` is a fully
  portable *art-direction generator* — the prompt survives, the renderer does not. Its output shape
  is worth copying even by hand: two page mockups plus a rail carrying only typography and a
  hierarchical hex palette. See `vendor/uidotsh/reference/emails-2026-06/brand-kit.jpg` for what
  that looks like finished.
- **The assets the guidelines hardcode are local.** `placeholder-content.md` says "always use
  `https://assets.ui.sh/screenshots/1.webp`"; all 77 of those files are in `vendor/uidotsh/assets/`.
  Self-host and rewrite the base URL — the CDN dies with the vendor.
- **Mirror root:** `~/.claude/vendor/uidotsh/` (live) = `vendor/uidotsh/` in claude-infrastructure.
  `VISUAL-KIT.md` there is the map. The corpus is frozen at 2026-09-19; the vendor's own installer
  needs an account token and would supersede it.
