# Vue 3 Patterns for SaaS Redesign

Vue-native architecture for design-token-driven UIs. **Never** import Tailwind, shadcn, or utility-class systems — this skill emits scoped styles and CSS-variable tokens only.

## Component Foundation

Use `<script setup>` Composition API. Single-file components with scoped styles. No Options API in new code.

```vue
<script setup>
import { computed } from 'vue'
import { useFilters } from '@/composables/useFilters'

const props = defineProps({ label: { type: String, required: true } })
const emit = defineEmits(['select'])
const { active } = useFilters()
const isActive = computed(() => active.value === props.label)
</script>

<template>
  <button class="chip" :data-active="isActive" @click="emit('select', props.label)">
    {{ label }}
  </button>
</template>

<style scoped>
.chip {
  padding: var(--space-2) var(--space-3);
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-sm);
  color: var(--color-text);
  font: inherit;
}
.chip[data-active="true"] {
  background: color-mix(in srgb, var(--color-accent) 12%, transparent);
  border-color: var(--color-accent);
}
</style>
```

## Singleton Composables (state at MODULE scope)

The **only** correct singleton-composable pattern in Vue 3: declare reactive state at module scope, OUTSIDE the exported function. Multiple components calling `useFilters()` then share the same `state` ref. State declared inside the function body creates a fresh instance per call — that is a subtle bug, not a singleton.

```js
// composables/useFilters.js — CORRECT singleton pattern
import { ref, computed } from 'vue'

// State at MODULE scope — shared across all callers
const warehouse = ref('all')
const category = ref('all')
const month = ref(null)

export function useFilters () {
  // Returned refs are the same instances every call
  const queryParams = computed(() => ({
    warehouse: warehouse.value,
    category: category.value,
    month: month.value
  }))

  function reset () {
    warehouse.value = 'all'
    category.value = 'all'
    month.value = null
  }

  return { warehouse, category, month, queryParams, reset }
}
```

Anti-pattern (do not write this):

```js
// composables/useFilters.js — WRONG; creates a new state per caller
export function useFilters () {
  const warehouse = ref('all') // re-created every call — NOT a singleton
  return { warehouse }
}
```

For composables that *should* be per-instance (e.g. `useFocusTrap(modalRef)`), declare state inside the function body deliberately and document the choice in a one-line comment.

## Base Components — Slot APIs

Build reusable layout primitives with named slots. Consumers compose; the base component owns nothing but layout, spacing tokens, and a11y.

```vue
<!-- components/BaseCard.vue -->
<script setup>
defineProps({ as: { type: String, default: 'section' } })
</script>

<template>
  <component :is="as" class="card">
    <header v-if="$slots.header" class="card-header">
      <slot name="header" />
      <div v-if="$slots.actions" class="card-actions"><slot name="actions" /></div>
    </header>
    <div class="card-body"><slot /></div>
    <footer v-if="$slots.footer" class="card-footer"><slot name="footer" /></footer>
  </component>
</template>

<style scoped>
.card {
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  display: grid;
  grid-template-rows: auto 1fr auto;
}
.card-header {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
  padding: var(--space-4) var(--space-5);
  border-bottom: 1px solid var(--color-border);
}
.card-body { padding: var(--space-5); }
.card-footer { padding: var(--space-3) var(--space-5); border-top: 1px solid var(--color-border); }
</style>
```

The four canonical slots: `#header` (title row), default (body), `#footer` (terminal action row), `#actions` (header-right cluster — buttons, menus, filters).

## Teleport for Modals, Drawers, Popovers

Modals MUST render outside the main app DOM tree. Use `<Teleport to="body">` so the dialog escapes stacking-context and overflow ancestors. Pair with the inert/focus-trap pattern (see `references/accessibility.md`).

```vue
<script setup>
import { ref, watch } from 'vue'

const props = defineProps({ open: Boolean })
const emit = defineEmits(['close'])
const dialogRef = ref(null)

watch(() => props.open, (v) => {
  if (v) requestAnimationFrame(() => dialogRef.value?.focus())
})
</script>

<template>
  <Teleport to="body">
    <div v-if="open" class="modal-scrim" @click.self="emit('close')">
      <div ref="dialogRef" class="modal" role="dialog" aria-modal="true" tabindex="-1">
        <slot />
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
.modal-scrim {
  position: fixed; inset: 0;
  background: var(--color-scrim);
  display: grid; place-items: center;
  z-index: var(--z-modal);
}
.modal {
  background: var(--color-surface);
  border-radius: var(--radius-lg);
  padding: var(--space-6);
  max-inline-size: min(560px, 92vw);
  box-shadow: var(--shadow-lg);
}
</style>
```

## SVG Components: role="img"

Every inline `<svg>` that conveys meaning gets `role="img"` and `<title>`. Decorative SVGs (separators, gradients, grain textures) get `aria-hidden="true"` and no title.

```vue
<template>
  <svg viewBox="0 0 24 24" width="20" height="20" role="img" aria-labelledby="t-rev">
    <title id="t-rev">Revenue trending up</title>
    <path d="M3 17 9 11l4 4 8-8" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" />
  </svg>
</template>
```

Stroke-width default: **1.5** for Lucide-style icons (override Lucide's default of 2 — the lighter weight reads as more refined and breaks the AI-slop visual signature).

## Router-Link Active State

Vue Router emits `aria-current="page"` automatically when using `<RouterLink>`. **Bind to it in CSS**, not to a Vue class binding — this preserves a11y semantics and styling in one selector.

```vue
<template>
  <RouterLink :to="{ name: 'dashboard' }" class="nav-row">
    <DashboardIcon />
    <span>Dashboard</span>
  </RouterLink>
</template>

<style scoped>
.nav-row {
  display: grid;
  grid-template-columns: 16px 1fr;
  gap: var(--space-3);
  height: 36px;
  padding-inline: 10px;
  border-radius: var(--radius-sm);
  color: var(--color-text-muted);
  text-decoration: none;
}
.nav-row[aria-current="page"] {
  background: color-mix(in srgb, var(--color-accent) 12%, transparent);
  color: var(--color-text);
  box-shadow: inset 3px 0 0 var(--color-accent);
}
.nav-row:hover { background: var(--color-surface-2); }
</style>
```

## Provide/Inject Over Prop-Drilling

For app-wide concerns (current theme, dense-mode toggle, user role), use `provide`/`inject` with a `Symbol` key. Reserve props for component-local state; reserve Pinia for true global stores.

```js
// app/keys.js
export const ThemeKey = Symbol('theme')
```

```vue
<!-- App.vue -->
<script setup>
import { provide, ref } from 'vue'
import { ThemeKey } from '@/app/keys'

const theme = ref('signal')
provide(ThemeKey, theme)
</script>
```

## Reactivity Discipline

- Raw data in `ref()`; derived data in `computed()`. Never compute in templates beyond trivial expressions.
- `watch` with explicit sources; never `watchEffect` in component setup for anything that touches the DOM (it fires before mount).
- Use `shallowRef` for large arrays/objects when deep reactivity is wasteful (chart datasets, table pages).

## Token Imports

`src/tokens.css` is imported **once** in `main.js` before `app.mount()`. Components reference variables via `var(--token-name)`. Never inline hex literals in component styles — every color, radius, shadow, and spacing value resolves to a token.

```js
// main.js
import { createApp } from 'vue'
import App from './App.vue'
import router from './router'
import './tokens.css' // BEFORE component imports
import './app.css'

createApp(App).use(router).mount('#app')
```

## File Structure

```
src/
  tokens.css            ← design-token CSS variables
  app.css               ← global resets + base typography
  main.js
  App.vue               ← grid layout (sidebar + main)
  router/index.js
  composables/          ← useFilters.js, useTheme.js, etc.
  components/
    base/               ← BaseCard, BaseButton, BaseDialog
    nav/                ← SidebarNav, NavRow, NavGroup
    data/               ← DataTable, StatTile, SparkLine
  views/                ← route components
```
