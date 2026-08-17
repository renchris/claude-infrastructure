# Surfaces, Shadows, Border Radius

Surface hierarchy is the foundation of a SaaS UI. The default mistake is reaching for a white card on a gray background; this skill's defaults invert that and reserve cards for genuinely standalone units.

## Tokens

```css
:root {
  --color-bg: hsl(0 0% 100%);
  --color-surface: hsl(0 0% 100%);
  --color-surface-2: hsl(220 14% 96%);   /* wells, secondary panels */
  --color-surface-3: hsl(220 13% 91%);   /* inset, hover-on-surface-2 */
  --color-border: hsl(220 13% 91%);
  --color-border-strong: hsl(220 9% 80%);
  --color-divider: hsl(220 13% 91% / 0.5);
}
```

## Hierarchy Rules

Use the lightest separation that still works. Climb the ladder only when the lower rung fails to separate the content:

1. **Whitespace** — first choice. Padding and gap carry the visual grouping. Use when sibling items already have inherent type contrast (large numerals vs small labels, headings vs body).
2. **Dividers / borders** — subtle 1px lines, low-opacity. Use for sibling content that needs separation in a shared context (stat grids, metric rows).
3. **Wells** — recessed `var(--color-surface-2)` panels. Use for secondary or nested content that should read as supporting, not equal.
4. **Cards** — bordered surfaces with their own background. Reserve for **independently interactive** units (clickable to navigate) or **fundamentally different content** types.

```vue
<!-- Whitespace-first stat row (preferred for KPI strips) -->
<template>
  <div class="stat-row">
    <div v-for="kpi in kpis" :key="kpi.id" class="stat">
      <div class="stat-label">{{ kpi.label }}</div>
      <div class="stat-value">{{ kpi.value }}</div>
      <div class="stat-delta" :data-direction="kpi.delta > 0 ? 'up' : 'down'">
        {{ kpi.delta }}%
      </div>
    </div>
  </div>
</template>

<style scoped>
.stat-row {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 0;
}
.stat {
  padding: var(--space-5) var(--space-6);
  border-inline-start: 1px solid var(--color-divider);
}
.stat:first-child { border-inline-start: none; padding-inline-start: 0; }
.stat:last-child { padding-inline-end: 0; }
.stat-label { font-size: var(--text-xs); color: var(--color-text-muted); }
.stat-value {
  font-size: var(--text-3xl);
  font-weight: 500;
  font-variant-numeric: tabular-nums;
  margin-block-start: var(--space-2);
}
</style>
```

## Divider Discipline

- Use opacity-based colors for dividers, never solid grays. `hsl(220 13% 50% / 0.12)` reads as a hairline; `hsl(220 13% 80%)` reads as a line.
- Reset padding per row/column position. The first child in a row has no leading divider and no leading padding; the last child has no trailing padding.
- When a grid recomputes columns at a breakpoint, the divider pattern MUST recompute too. Don't carry desktop dividers into a single-column mobile layout — switch to horizontal dividers between rows.

```css
@container (max-width: 640px) {
  .stat { border-inline-start: none; border-block-start: 1px solid var(--color-divider); }
  .stat:first-child { border-block-start: none; }
}
```

## Cards

Cards are the heaviest separation. Use them deliberately. Three valid card scenarios:

1. The card represents an entity that links elsewhere (clickable card navigates to detail view).
2. The card contains content of a fundamentally different shape (chart inside a text-heavy page).
3. The card represents a primary action surface (form, prompt, dialog).

Anti-pattern: a grid of white cards on a gray page where each card just contains text and numbers — this is the default-SaaS-card-blanket signature. Strip the cards; let the page background hold the content and use dividers between rows.

```vue
<!-- Card surface — used for a clickable entity tile -->
<template>
  <RouterLink :to="to" class="entity-card">
    <h3 class="title">{{ name }}</h3>
    <p class="meta">{{ summary }}</p>
  </RouterLink>
</template>

<style scoped>
.entity-card {
  display: block;
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  padding: var(--space-5);
  text-decoration: none;
  color: inherit;
  transition: border-color 120ms ease, box-shadow 120ms ease;
}
.entity-card:hover {
  border-color: var(--color-border-strong);
  box-shadow: var(--shadow-sm);
}
.entity-card:focus-visible {
  outline: 2px solid var(--color-accent);
  outline-offset: 2px;
}
</style>
```

## Shadow Tokens

```css
:root {
  --shadow-xs: 0 1px 0 hsl(220 13% 10% / 0.04);
  --shadow-sm: 0 1px 2px hsl(220 13% 10% / 0.05), 0 1px 1px hsl(220 13% 10% / 0.04);
  --shadow-md: 0 4px 10px -2px hsl(220 13% 10% / 0.08), 0 2px 4px -1px hsl(220 13% 10% / 0.05);
  --shadow-lg: 0 12px 28px -6px hsl(220 13% 10% / 0.12), 0 6px 12px -4px hsl(220 13% 10% / 0.08);
  --shadow-ring: 0 0 0 1px hsl(220 13% 10% / 0.06);
}
```

## Shadow Rules

- **Never pair a shadow with a solid border.** The two read as redundant containment. Use the shadow with `--shadow-ring` (a 1px inset hairline ring) for definition, or use the border alone.
- **Elevated surfaces are never darker than the canvas.** A shadowed card on white is white, not gray-50. If the design calls for a darker recessed area, drop the shadow — that's a well, not an elevation.
- **Warm-tinted shadows for Signal aesthetic.** When using the Signal palette, shadows use `hsl(30 15% 10% / X)` instead of neutral. A cool shadow under a warm cream surface reads as off.

```vue
<!-- Elevated popover — shadow + ring, no solid border -->
<style scoped>
.popover {
  background: var(--color-surface);
  border-radius: var(--radius-md);
  box-shadow: var(--shadow-lg), var(--shadow-ring);
  padding: var(--space-4);
}
</style>
```

## Border Radius Tokens

```css
:root {
  --radius-xs: 4px;
  --radius-sm: 6px;
  --radius-md: 10px;
  --radius-lg: 14px;
  --radius-xl: 20px;
  --radius-pill: 999px;
}
```

## Radius Rules

- **Concentric radii on nested rounded elements.** When a rounded element sits inside another rounded element with padding `p`, the inner radius is `outer - p`. Enforce with `calc()`:

```css
.card {
  --pad: var(--space-4);
  --radius: var(--radius-lg);
  border-radius: var(--radius);
  padding: var(--pad);
}
.card-image {
  border-radius: calc(var(--radius) - var(--pad));
}
```

- **Viewport-scaling radii for large media.** Hero images and screenshots use `min()` with viewport units so they shrink gracefully on narrow screens:

```css
.hero-screenshot { border-radius: min(1vw, 14px); }
```

- Pills (`--radius-pill`) are for badges, chips, and avatars. They are not a default — use `--radius-sm` or `--radius-md` for buttons and inputs.

## Anti-Patterns

- White cards on gray-50 pages. (Use white-on-white with dividers, or skip the cards.)
- Solid `1px gray` divider with `--shadow-sm` together on a card.
- Outer card uses `--radius-lg`; inner image uses the same `--radius-lg` (looks chunky and misaligned).
- Pill-radius buttons mixed with rounded-rectangle inputs in the same form — pick one shape per surface.
