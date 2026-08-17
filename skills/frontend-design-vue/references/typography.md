# Typography

Type is the first chance to signal that this app isn't AI-default. Inter is the AI-default signature; Geist, DM Sans, and Host Grotesk are the practical alternatives.

## Anti-Inter Rule

Inter is the correct safe choice — and that's the problem. Every AI-generated SaaS shell ships Inter + blue-600 + 240px sidebar; the visual signature reads as "shadcn template" within a glance. **Prefer Geist as the default.** Use Inter only when the user explicitly asks for it or when a stakeholder constraint mandates it.

Distinctive defaults, in order of preference:

1. **Geist** (Vercel) — Swiss-inspired, precise, paired with Geist Mono for data.
2. **DM Sans** — low-contrast geometric, large x-height, distinctive single-storey `a`.
3. **Host Grotesk** — uniwidth, letter widths stay stable across weights (good for tabs/buttons).
4. **Satoshi** — double-storey `a` and `g`, more personality.
5. *Inter* — only on explicit request.

## Font Loading

Load fonts in `index.html` `<head>` with `font-display: swap`. Self-host when possible; Google Fonts is acceptable for prototypes.

```html
<!-- index.html -->
<link rel="preconnect" href="https://fonts.googleapis.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Geist:wght@300..700&family=Geist+Mono:wght@400;500&display=swap">
```

```css
/* tokens.css */
:root {
  --font-sans: 'Geist', system-ui, -apple-system, 'Segoe UI', sans-serif;
  --font-mono: 'Geist Mono', ui-monospace, 'SF Mono', Menlo, monospace;
  --font-display: var(--font-sans);
}
```

## Type Scale Tokens

Use a `clamp()`-based scale for fluid sizing. Body text is at least 16px on mobile, can step down to 14px at the `sm:` breakpoint. Headings stay roughly the same or get **smaller** on mobile, never bigger.

```css
:root {
  --text-xs: 0.75rem;     /* 12px — only for meta, eyebrows, labels */
  --text-sm: 0.875rem;    /* 14px — desktop body, table cells */
  --text-base: 1rem;      /* 16px — mobile body, default */
  --text-lg: 1.125rem;    /* 18px — lead paragraphs */
  --text-xl: 1.25rem;     /* 20px — section subheads */
  --text-2xl: 1.5rem;     /* 24px */
  --text-3xl: 1.875rem;   /* 30px — KPI values */
  --text-4xl: clamp(1.875rem, 4vw, 2.5rem);
  --text-5xl: clamp(2.25rem, 5vw, 3.5rem);

  /* Weights — never use bold for headings */
  --font-weight-regular: 400;
  --font-weight-medium: 500;
  --font-weight-semibold: 600;

  /* Line heights — bare numbers */
  --leading-tight: 1.15;
  --leading-snug: 1.3;
  --leading-normal: 1.5;
  --leading-relaxed: 1.65;
}
```

## Heading Rules

- **Never use `font-weight: 700`** for headings. Use `--font-weight-medium` (500) or `--font-weight-semibold` (600). Bold reads as heavy and template-y.
- **Letter-spacing**: tighten headings ≥ `--text-xl` with `letter-spacing: -0.015em`. Skip the tighten if the font is already condensed.
- **Line-height**: let the font's default ride for headings. Don't override with a leading value — overrides push headings to designer-default `1.1`, which feels squat.
- **No uppercase** unless monospace. When monospace, pair with `letter-spacing: 0.04em`.

```vue
<template>
  <header class="page-header">
    <p class="eyebrow">Operations</p>
    <h1 class="title">Inventory overview</h1>
    <p class="lead">Stock by warehouse and category, with order velocity.</p>
  </header>
</template>

<style scoped>
.page-header { display: flex; flex-direction: column; gap: var(--space-2); }
.eyebrow {
  font-family: var(--font-mono);
  font-size: var(--text-xs);
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--color-text-muted);
}
.title {
  font-size: var(--text-3xl);
  font-weight: var(--font-weight-semibold);
  letter-spacing: -0.015em;
  text-wrap: balance;
  color: var(--color-text);
  margin: 0;
}
.lead {
  font-size: var(--text-lg);
  color: var(--color-text-muted);
  text-wrap: pretty;
  max-inline-size: 56ch;
  margin: 0;
}
</style>
```

## Body Text

- Constrain measure with `max-inline-size` in `ch` units, not pixels. Targets by size: `--text-base` → 56ch, `--text-lg` → 48ch, `--text-xl` → 40ch.
- Use `text-wrap: pretty` on paragraphs and `text-wrap: balance` on headings.
- `font-variant-numeric: tabular-nums` on every element that displays values that change over time (counters, prices, dashboard KPIs) — prevents horizontal layout shift as digits update.

## Tabular Numerals for Data

Every numeric value in a dashboard, table, or counter gets tabular-nums. This is non-negotiable for the Signal aesthetic and a general SaaS-quality signal.

```css
.tabular { font-variant-numeric: tabular-nums; }

.kpi-value,
.table td.numeric,
.timer,
.price {
  font-variant-numeric: tabular-nums slashed-zero;
}
```

## Monospace for Data + Code

Use `var(--font-mono)` for:
- Code blocks and inline code (`<code>`).
- Eyebrow labels in card headers (gives a technical signal).
- Compact tabular dashboards where the design intentionally signals "data dense" (Signal aesthetic).

Do **not** use monospace for general body copy.

## OpenType Features (Inter only)

If the user explicitly chooses Inter, opt into stylistic features that reduce the default-Inter signature:

```css
:root {
  --font-sans: 'InterVariable', system-ui, sans-serif;
  font-feature-settings: 'cv02', 'cv03', 'cv04', 'cv11', 'ss01', 'ss03';
}
```

These enable single-storey `a`, open `6`/`9`, open `4`, single-storey `l`, and open digits — collectively making Inter look less like default Inter.

## Component Snippet: Stat Tile

```vue
<script setup>
defineProps({
  label: String,
  value: [String, Number],
  unit: { type: String, default: '' },
  delta: { type: Number, default: null }
})
</script>

<template>
  <div class="stat-tile">
    <div class="label">{{ label }}</div>
    <div class="value">
      <span class="number">{{ value }}</span>
      <span v-if="unit" class="unit">{{ unit }}</span>
    </div>
    <div v-if="delta !== null" class="delta" :data-direction="delta >= 0 ? 'up' : 'down'">
      {{ delta >= 0 ? '+' : '' }}{{ delta }}%
    </div>
  </div>
</template>

<style scoped>
.stat-tile { display: flex; flex-direction: column; gap: var(--space-2); }
.label {
  font-size: var(--text-xs);
  font-family: var(--font-mono);
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--color-text-muted);
}
.value { display: flex; align-items: baseline; gap: var(--space-1); }
.number {
  font-size: var(--text-3xl);
  font-weight: var(--font-weight-medium);
  font-variant-numeric: tabular-nums slashed-zero;
  letter-spacing: -0.015em;
}
.unit { font-size: var(--text-sm); color: var(--color-text-muted); }
.delta {
  font-size: var(--text-xs);
  font-variant-numeric: tabular-nums;
  color: var(--color-text-muted);
}
.delta[data-direction="up"] { color: var(--color-success); }
.delta[data-direction="down"] { color: var(--color-danger); }
</style>
```

## Anti-Patterns

- `font-weight: 700` headings.
- `letter-spacing: 0` left on a 48px heading (looks loose).
- Body text at `text-sm` on mobile (12-14px is too small for mobile body).
- Inter as the default choice with no override considered.
- Numeric columns without `tabular-nums` (digits jitter on update).
- Uppercase eyebrows in a sans-serif font without letter-spacing.
