# Signal Aesthetic

The Signal palette is this skill's default aesthetic. It is deliberately **not** the cool-neutral + blue accent default that ships in every AI-generated SaaS shell. Signal is warm cream + dark island + burnt orange; the visual signature reads as bespoke, editorial, and analog-tinted.

Use Signal as the default; offer Foundry (cool neutral + blue), Meridian (high-contrast + violet), or Custom only when the user asks.

## Palette

```css
:root[data-theme="signal"] {
  /* Backgrounds */
  --color-bg: hsl(35 33% 95%);              /* #f7f4ef cream */
  --color-surface: hsl(35 33% 97%);          /* slightly lighter cream for cards */
  --color-surface-2: hsl(35 25% 91%);        /* wells */
  --color-surface-3: hsl(35 22% 87%);        /* hover-on-well */

  /* Dark "island" surface for sidebar / inverted panels */
  --color-island: hsl(20 12% 9%);            /* #1a1612 */
  --color-island-2: hsl(20 12% 13%);
  --color-on-island: hsl(35 33% 95%);        /* cream text on island */
  --color-on-island-muted: hsl(35 15% 65%);

  /* Text */
  --color-text: hsl(20 14% 12%);             /* deep warm near-black */
  --color-text-muted: hsl(20 8% 38%);
  --color-text-subtle: hsl(20 6% 55%);

  /* Borders */
  --color-border: hsl(20 12% 12% / 0.10);
  --color-border-strong: hsl(20 12% 12% / 0.20);
  --color-divider: hsl(20 12% 12% / 0.08);

  /* Accent: burnt orange */
  --color-accent: hsl(18 88% 40%);           /* #c2410c */
  --color-accent-2: hsl(18 88% 50%);
  --color-on-accent: hsl(35 33% 97%);
  --color-accent-tint: hsl(18 88% 40% / 0.12);

  /* Status */
  --color-success: hsl(140 45% 32%);
  --color-warning: hsl(35 92% 42%);
  --color-danger: hsl(8 70% 42%);
  --color-info: hsl(200 55% 40%);

  /* Shadows — warm-tinted */
  --shadow-xs: 0 1px 0 hsl(30 15% 10% / 0.04);
  --shadow-sm: 0 1px 2px hsl(30 15% 10% / 0.06), 0 1px 1px hsl(30 15% 10% / 0.05);
  --shadow-md: 0 4px 12px -2px hsl(30 15% 10% / 0.10), 0 2px 4px -1px hsl(30 15% 10% / 0.06);
  --shadow-lg: 0 16px 32px -8px hsl(30 15% 10% / 0.14), 0 6px 12px -4px hsl(30 15% 10% / 0.10);
  --shadow-ring: 0 0 0 1px hsl(30 15% 10% / 0.06);

  /* Scrim — warm */
  --color-scrim: hsl(30 15% 10% / 0.55);
}
```

Apply the theme by setting `data-theme="signal"` on `<html>` in `index.html` or via a runtime `useTheme()` composable.

## Sidebar Treatment — Dark Island

Signal's defining move: the sidebar is the **dark island** while the main content area is **cream**. This inversion is what makes Signal recognisable. Cool-neutral default ships cream-on-cream or white-on-gray; Signal ships cream-on-dark.

```css
:root[data-theme="signal"] {
  --color-sidebar-bg: var(--color-island);
}

/* Sidebar text overrides for the dark island */
:root[data-theme="signal"] .sidebar {
  color: var(--color-on-island);
}
:root[data-theme="signal"] .sidebar .group-label,
:root[data-theme="signal"] .sidebar .row {
  color: var(--color-on-island-muted);
}
:root[data-theme="signal"] .sidebar .row:hover {
  background: var(--color-island-2);
  color: var(--color-on-island);
}
:root[data-theme="signal"] .sidebar .row[aria-current="page"] {
  background: color-mix(in srgb, var(--color-accent) 18%, transparent);
  color: var(--color-on-island);
  box-shadow: inset 3px 0 0 var(--color-accent-2);
}
```

## Grain Texture

A subtle SVG grain on the main background is the second defining Signal move. It must be subtle — 4% opacity max, monochrome. Anything more reads as "themed" instead of "tactile."

```vue
<!-- components/SignalGrain.vue — decorative, mounted once in App.vue -->
<template>
  <svg class="grain" aria-hidden="true" focusable="false">
    <filter id="signal-grain">
      <feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves="2" stitchTiles="stitch" />
      <feColorMatrix type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 0.04 0" />
    </filter>
    <rect width="100%" height="100%" filter="url(#signal-grain)" />
  </svg>
</template>

<style scoped>
.grain {
  position: fixed;
  inset: 0;
  inline-size: 100%;
  block-size: 100%;
  pointer-events: none;
  z-index: 1;
  mix-blend-mode: multiply;
  opacity: 0.6;
}
</style>
```

The grain is `position: fixed` and `pointer-events: none`. It sits above the page background but below interactive content (assign a higher `z-index` on the shell's content layer).

## Typography Pairing

Signal pairs Geist (sans) with Geist Mono (data + eyebrows). Geist Mono on numerics is what locks in the editorial-data feel.

```css
:root[data-theme="signal"] {
  --font-sans: 'Geist', system-ui, sans-serif;
  --font-mono: 'Geist Mono', ui-monospace, monospace;
}

:root[data-theme="signal"] .kpi-value,
:root[data-theme="signal"] .table td.numeric,
:root[data-theme="signal"] .timestamp {
  font-family: var(--font-mono);
  font-weight: var(--font-weight-medium);
  letter-spacing: -0.02em;
}
```

## Accent Use

The burnt orange `--color-accent` is **scarce by design**. Reserve for:
- The single primary action button per view.
- Active-state markers (sidebar bar, tab underline, filter chip selection).
- Brand mark in the sidebar header.
- Critical data callouts (over-threshold KPI, hot alert).

Do **not** use accent on:
- Body links (use `--color-text` underlined, or `--color-accent` at reduced saturation).
- Chart strokes (use a separate categorical palette — see below).
- Hover states for secondary controls (use surface-3 instead).

## Chart Palette (categorical)

Signal's data viz palette runs warm-neutral with one accent. Categorical sequence:

```css
:root[data-theme="signal"] {
  --chart-1: var(--color-accent);            /* burnt orange — primary series */
  --chart-2: hsl(200 55% 40%);                /* deep teal — secondary */
  --chart-3: hsl(140 30% 38%);                /* moss */
  --chart-4: hsl(35 70% 45%);                 /* mustard */
  --chart-5: hsl(280 25% 45%);                /* aubergine */
  --chart-grid: var(--color-divider);
}
```

## Component Snippet: Filter Chip

```vue
<script setup>
defineProps({ label: String, active: Boolean })
defineEmits(['toggle'])
</script>

<template>
  <button class="chip" :data-active="active" @click="$emit('toggle')">
    {{ label }}
  </button>
</template>

<style scoped>
.chip {
  display: inline-flex; align-items: center; gap: var(--space-2);
  block-size: 28px;
  padding-inline: var(--space-3);
  border-radius: var(--radius-pill);
  background: transparent;
  border: 1px solid var(--color-border-strong);
  color: var(--color-text);
  font: inherit;
  font-size: var(--text-sm);
  cursor: pointer;
}
.chip:hover { background: var(--color-surface-2); }
.chip[data-active="true"] {
  background: var(--color-accent-tint);
  border-color: var(--color-accent);
  color: var(--color-text);
}
</style>
```

## Required + Banned

**Required for Signal:**
- Cream background (#f7f4ef territory).
- Dark island sidebar.
- Burnt orange accent at restraint.
- Geist + Geist Mono pairing.
- Tabular-nums + monospace on data values.
- Warm-tinted shadows.

**Banned in Signal:**
- Pure white backgrounds (#ffffff) — washes out the warmth.
- Blue accents.
- Neutral-cool gray text (`hsl(220 9% …)`).
- Cool shadows (`hsl(220 13% 10% / X)`).
- Inter — pair-mismatched with the cream warmth.

## Component Snippet: Data Tile (Signal-styled)

```vue
<template>
  <article class="signal-tile">
    <header>
      <p class="eyebrow">{{ category }}</p>
      <h3>{{ label }}</h3>
    </header>
    <p class="value">{{ value }}<span class="unit">{{ unit }}</span></p>
    <footer class="meta">{{ meta }}</footer>
  </article>
</template>

<style scoped>
.signal-tile {
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  padding: var(--space-5);
  box-shadow: var(--shadow-xs);
  display: grid;
  gap: var(--space-3);
}
.eyebrow {
  font-family: var(--font-mono);
  font-size: var(--text-xs);
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: var(--color-accent);
  margin: 0;
}
h3 { font-size: var(--text-sm); font-weight: var(--font-weight-medium); color: var(--color-text-muted); margin: 0; }
.value {
  font-family: var(--font-mono);
  font-size: var(--text-3xl);
  font-weight: var(--font-weight-medium);
  font-variant-numeric: tabular-nums;
  letter-spacing: -0.025em;
  color: var(--color-text);
  margin: 0;
}
.unit { font-size: var(--text-sm); color: var(--color-text-muted); margin-inline-start: var(--space-1); }
.meta { font-size: var(--text-xs); color: var(--color-text-subtle); margin: 0; }
</style>
```
