# Sidebar Patterns

The vertical sidebar is the single most differentiating structural choice in a SaaS redesign. Default-AI shells ship a top header; **this skill defaults to a left sidebar.** Below are the dimensions, states, and Vue 3 bindings.

## Dimensions

- **Expanded**: 256 px. (Default-AI ships 240 px — override.)
- **Collapsed (rail)**: 64 px — icon-only, labels hidden.
- **Mobile (under 1024 px)**: forced-collapsed off-canvas drawer, opened by a hamburger toggle in a slim top bar.
- **Row height**: 36 px. (Not 40 px; 36 reads as denser and more SaaS-grade.)
- **Row inline padding**: 10 px each side. Icon + label gap: 12 px.
- **Section gap**: 16 px between nav groups; group label `text-xs` mono uppercase.

```css
:root {
  --sidebar-width-expanded: 256px;
  --sidebar-width-collapsed: 64px;
  --sidebar-row-height: 36px;
  --sidebar-row-padding-inline: 10px;
  --sidebar-active-bar-width: 3px;
}
```

## Layout Grid

The shell is a CSS grid with two columns. The sidebar width is a CSS variable so it animates with one rule.

```vue
<!-- App.vue -->
<script setup>
import { ref, watch, onMounted, onUnmounted } from 'vue'
import SidebarNav from '@/components/nav/SidebarNav.vue'

const collapsed = ref(false)
const mq = window.matchMedia('(max-width: 1024px)')

function syncFromMq () { if (mq.matches) collapsed.value = true }

onMounted(() => {
  syncFromMq()
  mq.addEventListener('change', syncFromMq)
  window.addEventListener('keydown', handleKey)
})
onUnmounted(() => {
  mq.removeEventListener('change', syncFromMq)
  window.removeEventListener('keydown', handleKey)
})

function handleKey (e) {
  if (e.key === 'b' && (e.metaKey || e.ctrlKey)) {
    e.preventDefault()
    collapsed.value = !collapsed.value
  }
}
</script>

<template>
  <div class="shell" :data-collapsed="collapsed">
    <SidebarNav :collapsed="collapsed" @toggle="collapsed = !collapsed" />
    <main class="main">
      <RouterView />
    </main>
  </div>
</template>

<style scoped>
.shell {
  display: grid;
  grid-template-columns: var(--sidebar-width-expanded) 1fr;
  min-block-size: 100dvh;
  transition: grid-template-columns 180ms ease;
}
.shell[data-collapsed="true"] {
  grid-template-columns: var(--sidebar-width-collapsed) 1fr;
}
.main {
  background: var(--color-bg);
  overflow: hidden auto;
  min-inline-size: 0;
}
</style>
```

The `⌘B` / `Ctrl+B` keyboard shortcut is mandatory — it's the SaaS convention (Linear, Notion, Slack). The `matchMedia(1024px)` listener forces collapse on narrow viewports without breaking the explicit toggle on desktop.

## SidebarNav Structure

```vue
<!-- components/nav/SidebarNav.vue -->
<script setup>
import { LayoutDashboardIcon, BoxIcon, ShoppingCartIcon, BarChart3Icon, SettingsIcon, ChevronLeftIcon } from 'lucide-vue-next'
import NavRow from './NavRow.vue'
import SidebarFooter from './SidebarFooter.vue'

defineProps({ collapsed: Boolean })
defineEmits(['toggle'])

const groups = [
  {
    label: 'Overview',
    items: [
      { to: { name: 'dashboard' }, label: 'Dashboard', icon: LayoutDashboardIcon },
      { to: { name: 'inventory' }, label: 'Inventory', icon: BoxIcon },
      { to: { name: 'orders' }, label: 'Orders', icon: ShoppingCartIcon }
    ]
  },
  {
    label: 'Insights',
    items: [
      { to: { name: 'reports' }, label: 'Reports', icon: BarChart3Icon },
      { to: { name: 'settings' }, label: 'Settings', icon: SettingsIcon }
    ]
  }
]
</script>

<template>
  <aside class="sidebar" :aria-expanded="!collapsed" aria-label="Primary navigation">
    <header class="brand">
      <BrandMark />
      <span v-show="!collapsed" class="brand-name">Reso</span>
      <button class="collapse-toggle" :aria-label="collapsed ? 'Expand sidebar' : 'Collapse sidebar'" @click="$emit('toggle')">
        <ChevronLeftIcon :size="16" :stroke-width="1.5" />
      </button>
    </header>

    <nav class="nav-groups">
      <section v-for="group in groups" :key="group.label" class="group">
        <h2 v-show="!collapsed" class="group-label">{{ group.label }}</h2>
        <ul role="list" class="group-items">
          <li v-for="item in group.items" :key="item.label">
            <NavRow :to="item.to" :label="item.label" :icon="item.icon" :collapsed="collapsed" />
          </li>
        </ul>
      </section>
    </nav>

    <SidebarFooter :collapsed="collapsed" />
  </aside>
</template>

<style scoped>
.sidebar {
  background: var(--color-sidebar-bg, var(--color-surface-2));
  border-inline-end: 1px solid var(--color-border);
  display: grid;
  grid-template-rows: auto 1fr auto;
  min-inline-size: 0;
}
.brand {
  display: grid;
  grid-template-columns: 24px 1fr auto;
  align-items: center;
  gap: var(--space-3);
  padding: var(--space-4) var(--sidebar-row-padding-inline);
  border-block-end: 1px solid var(--color-border);
}
.brand-name {
  font-weight: var(--font-weight-semibold);
  letter-spacing: -0.015em;
}
.collapse-toggle {
  background: transparent; border: 0;
  inline-size: 28px; block-size: 28px;
  border-radius: var(--radius-sm);
  color: var(--color-text-muted);
  cursor: pointer;
}
.collapse-toggle:hover { background: var(--color-surface-3); color: var(--color-text); }
.shell[data-collapsed="true"] .collapse-toggle :deep(svg) { transform: rotate(180deg); }

.nav-groups {
  padding: var(--space-3) var(--space-2);
  display: flex; flex-direction: column; gap: var(--space-4);
  overflow-y: auto;
}
.group-label {
  font-family: var(--font-mono);
  font-size: var(--text-xs);
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--color-text-muted);
  padding-inline: var(--sidebar-row-padding-inline);
  margin-block: 0 var(--space-1);
  font-weight: var(--font-weight-regular);
}
.group-items { display: flex; flex-direction: column; gap: 2px; margin: 0; padding: 0; list-style: none; }
</style>
```

## NavRow — Active State

The active row is the strongest signal of "current location" in a sidebar. The recipe:

- Soft accent tint at **12% opacity** as the background (not the full accent).
- A **3 px left bar** in the full accent color (inset shadow, not a border — preserves row width).
- Text color shifts from muted to default.
- Font weight does **not** change (changing weight reflows the row width — bad).

```vue
<!-- components/nav/NavRow.vue -->
<script setup>
defineProps({
  to: { type: [String, Object], required: true },
  label: { type: String, required: true },
  icon: { type: Object, required: true },
  collapsed: Boolean
})
</script>

<template>
  <RouterLink :to="to" class="row" :title="collapsed ? label : undefined">
    <component :is="icon" class="icon" :size="16" :stroke-width="1.5" aria-hidden="true" />
    <span v-show="!collapsed" class="label">{{ label }}</span>
  </RouterLink>
</template>

<style scoped>
.row {
  display: grid;
  grid-template-columns: 16px 1fr;
  align-items: center;
  gap: var(--space-3);
  block-size: var(--sidebar-row-height);
  padding-inline: var(--sidebar-row-padding-inline);
  border-radius: var(--radius-sm);
  color: var(--color-text-muted);
  text-decoration: none;
  font-size: var(--text-sm);
  transition: background-color 80ms ease, color 80ms ease;
}
.icon { color: currentColor; }
.label { min-inline-size: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

.row:hover {
  background: var(--color-surface-3);
  color: var(--color-text);
}

.row[aria-current="page"] {
  background: color-mix(in srgb, var(--color-accent) 12%, transparent);
  color: var(--color-text);
  box-shadow: inset var(--sidebar-active-bar-width) 0 0 var(--color-accent);
}

.row:focus-visible {
  outline: 2px solid var(--color-accent);
  outline-offset: -2px;
}

.shell[data-collapsed="true"] .row {
  grid-template-columns: 16px;
  justify-content: center;
  padding-inline: 0;
}
</style>
```

`aria-current="page"` is set automatically by Vue Router on the active route. Style off the attribute, never off a manually-bound `class="active"` — keeps a11y and visuals in lock-step.

## Sidebar Footer

The footer holds user-context controls. Default placement: language switcher + profile menu. Optional: workspace switcher, help, command palette trigger.

```vue
<!-- components/nav/SidebarFooter.vue -->
<script setup>
import { GlobeIcon } from 'lucide-vue-next'
defineProps({ collapsed: Boolean })
</script>

<template>
  <footer class="footer">
    <button class="footer-row" :title="collapsed ? 'Language' : undefined">
      <GlobeIcon :size="16" :stroke-width="1.5" aria-hidden="true" />
      <span v-show="!collapsed">English</span>
    </button>
    <button class="footer-row profile" :title="collapsed ? 'Profile' : undefined">
      <span class="avatar" aria-hidden="true">CR</span>
      <span v-show="!collapsed" class="profile-name">Chris Ren</span>
    </button>
  </footer>
</template>

<style scoped>
.footer {
  border-block-start: 1px solid var(--color-border);
  padding: var(--space-2);
  display: flex; flex-direction: column; gap: 2px;
}
.footer-row {
  display: grid;
  grid-template-columns: 16px 1fr;
  align-items: center;
  gap: var(--space-3);
  block-size: var(--sidebar-row-height);
  padding-inline: var(--sidebar-row-padding-inline);
  border: 0; background: transparent;
  border-radius: var(--radius-sm);
  color: var(--color-text-muted);
  font-size: var(--text-sm);
  text-align: start;
  cursor: pointer;
}
.footer-row:hover { background: var(--color-surface-3); color: var(--color-text); }
.avatar {
  inline-size: 24px; block-size: 24px;
  border-radius: var(--radius-pill);
  background: var(--color-accent);
  color: var(--color-on-accent);
  display: grid; place-items: center;
  font-size: 10px; font-weight: var(--font-weight-medium);
  margin-inline-start: -4px;
}
.shell[data-collapsed="true"] .footer-row { grid-template-columns: 16px; justify-content: center; padding-inline: 0; }
</style>
```

## Mobile Drawer

Below 1024 px, the sidebar collapses to an off-canvas drawer. Use a slim 56 px top bar with a hamburger toggle. The drawer reuses the sidebar component inside a `<Teleport to="body">` wrapper with a scrim.

## Anti-Patterns

- 240 px width (default-AI signature).
- Top horizontal nav as the primary structure for an app with 5+ destinations.
- Active state uses bold weight (reflows row).
- Active state uses full accent color as background (visually shouts).
- Border-left for the active bar (border changes element width; use inset box-shadow).
- Toggle without ⌘B keyboard shortcut.
- Forgetting the `matchMedia(1024px)` listener — desktop-toggle works but the drawer doesn't auto-engage on narrow viewports.
