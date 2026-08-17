# Accessibility

A redesign that drops a11y is not a redesign — it's a regression with new chrome. These are the non-negotiables this skill emits with every layout, navigation, and interactive component.

## Token: Focus Ring

```css
:root {
  --focus-ring: 0 0 0 2px var(--color-bg), 0 0 0 4px var(--color-accent);
  --focus-ring-inset: inset 0 0 0 2px var(--color-accent);
  --focus-outline: 2px solid var(--color-accent);
  --focus-outline-offset: 2px;
}
```

Every interactive element gets a visible `:focus-visible` style. Never use `outline: none` without a replacement — the focus indicator is the keyboard equivalent of a hover state. Use the `:focus-visible` selector so mouse clicks don't trigger the ring, but keyboard tab navigation does.

```css
button:focus-visible,
a:focus-visible,
[role="button"]:focus-visible {
  outline: var(--focus-outline);
  outline-offset: var(--focus-outline-offset);
  border-radius: var(--radius-sm);
}
```

## ARIA: Current State

Navigation links use `aria-current="page"` on the active route. Vue Router emits this automatically when you use `<RouterLink>` — bind your CSS to the attribute, never to a manually-toggled class. The attribute is a single source of truth for screen readers and styling.

```css
.nav-row[aria-current="page"] {
  background: var(--color-accent-tint);
  box-shadow: inset 3px 0 0 var(--color-accent);
}
```

Other current-state attributes:
- `aria-current="step"` for stepper progress.
- `aria-current="true"` on a generic current-item that isn't a page or step.
- `aria-selected` on listbox / tablist items.

## ARIA: Expanded / Hidden

Disclosure widgets (sidebar collapse toggle, accordion, dropdown, menu) MUST set `aria-expanded` on the trigger and (where relevant) `aria-controls` pointing to the target element's id.

```vue
<script setup>
import { ref } from 'vue'
const open = ref(false)
</script>

<template>
  <button
    class="disclosure-trigger"
    :aria-expanded="open"
    aria-controls="filter-panel"
    @click="open = !open"
  >
    Filters
  </button>
  <div id="filter-panel" v-show="open" role="region">
    <slot />
  </div>
</template>
```

The sidebar collapse toggle in this skill sets `aria-expanded` on the `<aside>` itself, not on the toggle button, because the sidebar element represents the disclosed region.

## Route Announcer

Vue Router does NOT announce route changes to screen readers by default. Mount a live-region in `App.vue` and write the new page title to it on every route navigation.

```vue
<!-- App.vue -->
<script setup>
import { ref, watch } from 'vue'
import { useRoute } from 'vue-router'

const route = useRoute()
const announcement = ref('')

watch(
  () => route.fullPath,
  () => {
    // Read after the route renders so the new title is in the DOM
    requestAnimationFrame(() => {
      announcement.value = `${document.title} loaded`
    })
  }
)
</script>

<template>
  <!-- ... shell layout ... -->
  <div role="status" aria-live="polite" aria-atomic="true" class="sr-only">
    {{ announcement }}
  </div>
</template>

<style scoped>
.sr-only {
  position: absolute;
  inline-size: 1px; block-size: 1px;
  padding: 0; margin: -1px;
  overflow: hidden;
  clip-path: inset(50%);
  white-space: nowrap;
  border: 0;
}
</style>
```

Pair this with a route-aware `useHead()` (or manual `document.title =` in a `beforeEach` guard) so each route updates the document title.

## Focus Restoration

After navigation, move keyboard focus to the new page's `<h1>` (or main landmark). This restores the screen-reader user's place in the document.

```js
// router/index.js
router.afterEach((to, from) => {
  if (to.path === from.path) return
  requestAnimationFrame(() => {
    const target = document.querySelector('main h1') || document.querySelector('main')
    target?.setAttribute('tabindex', '-1')
    target?.focus({ preventScroll: false })
  })
})
```

Use `tabindex="-1"` to make the heading programmatically focusable without putting it in the tab order. Strip it on blur if you care about clean DOM.

## Modal Focus Trap + Restore

When opening a modal: save `document.activeElement`, move focus into the dialog, trap tab navigation inside the dialog, and on close restore focus to the saved element.

```js
// composables/useFocusTrap.js
import { onMounted, onUnmounted } from 'vue'

export function useFocusTrap (containerRef) {
  let previouslyFocused = null

  function onKeyDown (e) {
    if (e.key !== 'Tab' || !containerRef.value) return
    const focusables = containerRef.value.querySelectorAll(
      'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'
    )
    if (!focusables.length) return
    const first = focusables[0]
    const last = focusables[focusables.length - 1]
    if (e.shiftKey && document.activeElement === first) {
      e.preventDefault(); last.focus()
    } else if (!e.shiftKey && document.activeElement === last) {
      e.preventDefault(); first.focus()
    }
  }

  onMounted(() => {
    previouslyFocused = document.activeElement
    document.addEventListener('keydown', onKeyDown)
    containerRef.value?.focus()
  })
  onUnmounted(() => {
    document.removeEventListener('keydown', onKeyDown)
    previouslyFocused?.focus?.()
  })
}
```

## prefers-reduced-motion

Honor the user's motion preference. Wrap every transition and animation declaration in a `@media (prefers-reduced-motion: no-preference)` query, OR provide a global reset that disables animation under the reduced-motion query.

```css
/* Global reset — preferred approach */
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
    scroll-behavior: auto !important;
  }
}
```

For meaningful motion (a sidebar collapse that uses motion to convey state change), keep the motion but reduce its amplitude rather than removing it entirely. A 60ms tween instead of 180ms still communicates the state change without disorientation.

## Color Contrast (WCAG 1.4.3)

- **4.5:1** minimum for body text.
- **3:1** for large text (≥ 18px regular or 14px bold) and graphical elements.
- Verify with a contrast checker against the actual `--color-text` on `--color-bg` and on every surface (`--color-surface-2`, `--color-island`).

For Signal: `hsl(20 14% 12%)` on `hsl(35 33% 95%)` passes 4.5:1 by a wide margin. Verify the `--color-text-muted` pair too — muted text often slips below 4.5:1 when designers chase a "softer" feel.

Never use accent color alone to convey state. A red status badge needs a label ("Failed") or an icon (`<XCircleIcon />`), not just the color, because the color is invisible to color-blind users and meaningless to screen readers.

## Skip Links

The shell mounts a `Skip to main content` link as the first focusable element. It is `sr-only` until focused, then jumps into view.

```vue
<template>
  <a href="#main" class="skip-link">Skip to main content</a>
  <!-- ... rest of shell ... -->
  <main id="main">
    <RouterView />
  </main>
</template>

<style scoped>
.skip-link {
  position: absolute;
  inset-inline-start: var(--space-4);
  inset-block-start: var(--space-4);
  padding: var(--space-2) var(--space-3);
  background: var(--color-text);
  color: var(--color-bg);
  border-radius: var(--radius-sm);
  text-decoration: none;
  transform: translateY(-150%);
  transition: transform 120ms ease;
  z-index: var(--z-toast);
}
.skip-link:focus-visible { transform: translateY(0); }
</style>
```

## Landmarks

The shell uses semantic HTML landmarks so screen readers can navigate by region:

- `<aside aria-label="Primary navigation">` — sidebar
- `<main id="main">` — content
- `<header>` (page header inside main, not the shell header)
- `<nav>` inside the sidebar
- `<footer>` inside the sidebar

Avoid generic `<div>` for any of these regions. The landmark role is implicit on the semantic element.

## Form A11y

Every `<input>`, `<select>`, `<textarea>` has:
- A `<label for="id">` OR an `aria-label`. No placeholder-only inputs (placeholders disappear on focus and have low contrast).
- An `aria-describedby` pointing to error message and hint text.
- `aria-invalid="true"` when in error state.

```vue
<template>
  <div class="field">
    <label :for="id">{{ label }}</label>
    <input
      :id="id"
      :name="name"
      :type="type"
      :aria-invalid="!!error || undefined"
      :aria-describedby="error ? `${id}-error` : `${id}-hint`"
    />
    <p v-if="hint && !error" :id="`${id}-hint`" class="hint">{{ hint }}</p>
    <p v-if="error" :id="`${id}-error`" role="alert" class="error">{{ error }}</p>
  </div>
</template>
```

## Touch Targets

Interactive elements must have a minimum 44×44 px (WCAG 2.5.5) hit area. Visual size can be smaller — extend the touch area with absolutely-positioned hit-pads:

```vue
<style scoped>
.icon-button {
  position: relative;
  inline-size: 28px; block-size: 28px;
}
.icon-button::before {
  content: '';
  position: absolute;
  inset: 50% 50% 50% 50%;
  inline-size: max(100%, 44px);
  block-size: max(100%, 44px);
  transform: translate(-50%, -50%);
}
@media (pointer: fine) {
  .icon-button::before { display: none; }
}
</style>
```

## Anti-Patterns

- `outline: none` without a `:focus-visible` replacement.
- Active link styled via Vue `:class` instead of `aria-current="page"`.
- Modal that doesn't trap focus or restore on close.
- Route change with no screen-reader announcement.
- Placeholder used as the only field label.
- Color-only status signals (red dot for "failed", no icon or text).
- `prefers-reduced-motion` ignored on collapse/expand animations.
- `tabindex` greater than 0 (re-orders tab focus — never).
