# Dashboards, Tables, and Data Density

A SaaS dashboard's job is to surface signal at a glance, then let the user drill in. Density is what makes it feel professional; restraint with color and chrome is what keeps it from feeling cluttered.

## KPI Strip

The header KPI row carries the top-level summary. Four to six tiles, single line, divider-separated. No icons in stat tiles (icons add visual noise without information).

```vue
<!-- components/data/StatRow.vue -->
<script setup>
defineProps({
  stats: { type: Array, required: true }
})
</script>

<template>
  <section class="stat-row" aria-label="Summary metrics">
    <div v-for="stat in stats" :key="stat.id" class="stat">
      <h3 class="label">{{ stat.label }}</h3>
      <p class="value">
        <span class="number">{{ stat.value }}</span>
        <span v-if="stat.unit" class="unit">{{ stat.unit }}</span>
      </p>
      <p v-if="stat.delta != null" class="delta" :data-direction="stat.delta >= 0 ? 'up' : 'down'">
        {{ stat.delta >= 0 ? '+' : '' }}{{ stat.delta }}%
        <span class="period">vs {{ stat.period }}</span>
      </p>
    </div>
  </section>
</template>

<style scoped>
.stat-row {
  container-type: inline-size;
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 0;
  border-block: 1px solid var(--color-border);
  padding-block: var(--space-5);
}
@container (max-width: 720px) {
  .stat-row { grid-template-columns: repeat(2, 1fr); row-gap: var(--space-5); }
}
@container (max-width: 420px) {
  .stat-row { grid-template-columns: 1fr; }
}
.stat {
  padding-inline: var(--space-6);
  border-inline-start: 1px solid var(--color-divider);
  display: flex; flex-direction: column; gap: var(--space-2);
  min-inline-size: 0;
}
.stat:first-child { border-inline-start: 0; padding-inline-start: 0; }
.stat:last-child { padding-inline-end: 0; }

.label {
  font-size: var(--text-xs);
  font-family: var(--font-mono);
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--color-text-muted);
  margin: 0;
  /* Stat tile titles must never wrap */
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.value { display: flex; align-items: baseline; gap: var(--space-1); margin: 0; }
.number {
  font-size: var(--text-3xl);
  font-weight: var(--font-weight-medium);
  font-variant-numeric: tabular-nums slashed-zero;
  letter-spacing: -0.02em;
  color: var(--color-text);
}
.unit { font-size: var(--text-sm); color: var(--color-text-muted); }
.delta {
  font-size: var(--text-xs);
  font-variant-numeric: tabular-nums;
  display: flex; align-items: baseline; gap: var(--space-2);
  margin: 0;
}
.delta[data-direction="up"] { color: var(--color-success); }
.delta[data-direction="down"] { color: var(--color-danger); }
.period { color: var(--color-text-subtle); }
</style>
```

Rules:
- **Container queries**, not media queries. Dashboard tiles re-flow on the container width, not the viewport — they live inside main content that may be narrowed by a collapsible sidebar.
- **No icons** in stat tiles. The plain text label communicates the metric; the icon competes with the value.
- **`white-space: nowrap` + `text-overflow: ellipsis`** on the label. KPI labels must not wrap.
- **`tabular-nums` + `slashed-zero`** on the value. Always.

## Tables

Tables go directly on the page background — **not** inside a card. A card-wrapped table reads as a widget; a bare table reads as a list. The dataset is the content.

```vue
<!-- components/data/DataTable.vue -->
<script setup>
defineProps({
  columns: { type: Array, required: true },
  rows: { type: Array, required: true },
  caption: { type: String, default: '' }
})
</script>

<template>
  <div class="table-scroll">
    <table class="data-table">
      <caption v-if="caption" class="sr-only">{{ caption }}</caption>
      <thead>
        <tr>
          <th v-for="col in columns" :key="col.key" :class="['col-' + col.align]" scope="col">
            {{ col.label }}
          </th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="row in rows" :key="row.id">
          <td v-for="col in columns" :key="col.key" :class="['col-' + col.align]">
            <slot :name="`cell-${col.key}`" :row="row" :value="row[col.key]">
              {{ row[col.key] }}
            </slot>
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>

<style scoped>
.table-scroll {
  overflow-x: auto;
  margin-inline: calc(-1 * var(--space-6));
  padding-inline: var(--space-6);
}
.data-table {
  inline-size: 100%;
  border-collapse: collapse;
  font-size: var(--text-sm);
}
.data-table th,
.data-table td {
  padding: var(--space-3) var(--space-4);
  text-align: start;
  white-space: nowrap;
}
.data-table th {
  font-weight: var(--font-weight-medium);
  color: var(--color-text-muted);
  text-transform: none;
  border-block-end: 1px solid var(--color-border);
}
.data-table tbody tr {
  border-block-end: 1px solid var(--color-divider);
}
.data-table tbody tr:hover { background: var(--color-surface-2); }
.data-table .col-numeric {
  text-align: end;
  font-variant-numeric: tabular-nums;
}
.data-table .col-monospace { font-family: var(--font-mono); }
</style>
```

Table rules:
- **Horizontal lines only.** No vertical lines, no outer border. Rule by row, not by cell.
- **No uppercase headings.** Sentence case (`Order ID`, not `ORDER ID`).
- **No wrap on `<th>`.** Use `white-space: nowrap`.
- **`<table>` fills its container** via `inline-size: 100%` and an outer scroll wrapper that handles narrow viewports.
- **Right-align numeric columns**, left-align text. Mixed alignment makes the table easier to scan.
- **Tabular nums on numeric cells.**
- **Sentence-case headers** with `font-weight: var(--font-weight-medium)`.

## Inline SVG Charts

This skill uses inline SVG for charts — no chart library by default. Inline SVG keeps the design token-driven and avoids a 100KB dependency.

```vue
<!-- components/data/SparkLine.vue -->
<script setup>
import { computed } from 'vue'

const props = defineProps({
  values: { type: Array, required: true },
  height: { type: Number, default: 32 },
  width: { type: Number, default: 120 },
  ariaLabel: { type: String, required: true }
})

const path = computed(() => {
  const min = Math.min(...props.values)
  const max = Math.max(...props.values)
  const range = max - min || 1
  const stepX = props.width / (props.values.length - 1)
  return props.values
    .map((v, i) => {
      const x = i * stepX
      const y = props.height - ((v - min) / range) * props.height
      return `${i === 0 ? 'M' : 'L'}${x.toFixed(1)},${y.toFixed(1)}`
    })
    .join(' ')
})

const direction = computed(() => {
  const first = props.values[0]
  const last = props.values[props.values.length - 1]
  return last >= first ? 'up' : 'down'
})
</script>

<template>
  <svg
    :viewBox="`0 0 ${width} ${height}`"
    :width="width"
    :height="height"
    role="img"
    :aria-label="ariaLabel"
    :data-direction="direction"
    class="sparkline"
  >
    <path :d="path" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" />
  </svg>
</template>

<style scoped>
.sparkline { color: var(--color-text-muted); }
.sparkline[data-direction="up"] { color: var(--color-success); }
.sparkline[data-direction="down"] { color: var(--color-danger); }
</style>
```

## Chart Discipline

- **One categorical color per series.** Use `var(--chart-1)` through `var(--chart-5)`.
- **Use `currentColor`** for single-series sparklines so the chart inherits the parent's color (and the dashboard semantic-color rules apply).
- **Grid lines at low contrast.** `var(--color-divider)` or weaker.
- **Don't tint area-fills.** A bare stroke is more legible than a stroke + 10%-opacity fill for sparklines.
- **`role="img"` + `aria-label`** on every chart. The aria-label describes the value, not the visual ("Revenue increased 14% this week" — not "Line chart").

## Empty States

Empty states are the most-skipped surface and the most-revealing detail when done well. Use first-person framing and an action.

```vue
<template>
  <div class="empty">
    <p class="title">No orders to show yet.</p>
    <p class="hint">Create your first order or import from CSV.</p>
    <div class="actions">
      <button class="btn-primary">New order</button>
      <button class="btn-secondary">Import CSV</button>
    </div>
  </div>
</template>

<style scoped>
.empty {
  display: flex; flex-direction: column; align-items: center; gap: var(--space-4);
  padding: var(--space-12) var(--space-6);
  text-align: center;
}
.title { font-size: var(--text-lg); color: var(--color-text); margin: 0; }
.hint { color: var(--color-text-muted); max-inline-size: 40ch; margin: 0; }
.actions { display: flex; gap: var(--space-3); }
</style>
```

## Page Header Pattern

Every dashboard page opens with a header containing a title, optional eyebrow, and a right-side action cluster.

```vue
<template>
  <header class="page-header">
    <div class="title-block">
      <p class="eyebrow">{{ section }}</p>
      <h1>{{ title }}</h1>
    </div>
    <div class="actions">
      <slot name="filters" />
      <slot name="primary-action" />
    </div>
  </header>
</template>

<style scoped>
.page-header {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: var(--space-4);
  padding-block-end: var(--space-5);
  border-block-end: 1px solid var(--color-border);
  flex-wrap: wrap;
}
.title-block { display: flex; flex-direction: column; gap: var(--space-1); }
.eyebrow {
  font-family: var(--font-mono);
  font-size: var(--text-xs);
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--color-text-muted);
  margin: 0;
}
h1 {
  font-size: var(--text-2xl);
  font-weight: var(--font-weight-semibold);
  letter-spacing: -0.015em;
  color: var(--color-text);
  margin: 0;
}
.actions { display: flex; align-items: center; gap: var(--space-3); }
</style>
```

## Anti-Patterns

- Stat tiles inside cards on a gray page (the default-AI-card-blanket).
- Tables wrapped in `<div class="card">` (table-as-widget).
- Vertical lines in tables.
- Uppercase table headers.
- Sparkline area-fills that compete with the line.
- Charts without `aria-label`.
- KPI labels that wrap to two lines.
- Numeric columns without tabular-nums.
- Stat-tile icons (`<TrendingUpIcon />` next to the value — pure noise).
- Media queries on dashboard widgets (use container queries).
