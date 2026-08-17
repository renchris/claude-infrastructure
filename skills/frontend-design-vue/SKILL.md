---
name: frontend-design-vue
description: Redesign Vue 3 applications into modern SaaS-style interfaces — vertical sidebar navigation, design-token CSS architecture, Signal-aesthetic defaults. Use when user asks to "redesign UI", "modernize Vue app", "apply SaaS design", or invokes /frontend-design.
allowed-tools: Read, Edit, Write, Glob, Grep, Bash, AskUserQuestion, Agent
---

# frontend-design-vue

Vue 3 SaaS redesign skill. Vue-native, framework-agnostic, design-token-based. Not bound to Tailwind, shadcn, or any utility-class system — every value resolves to a CSS variable.

## Aesthetic defaults

The skill ships an opinionated Signal aesthetic (warm cream + dark island sidebar + burnt orange accent) because the dominant AI-generated SaaS shell signature is so recognisable that it now reads as low-effort. Override any default by user request.

**Banned anti-patterns (compose into shadcn-default AI-slop — override at minimum 2 of 4):**
- Inter font.
- `blue-600` (or any saturated blue) as the brand accent.
- 240 px sidebar width.
- Default Lucide `stroke-width: 2` icons.

**Required:**
- Design-token CSS file at `src/tokens.css` (or framework equivalent), imported in `main.js` BEFORE `app.mount()`.
- CSS grid shell with `grid-template-columns: 256px 1fr` expanded, `64px 1fr` collapsed.
- Geist sans + Geist Mono, with monospace on numeric data.
- `aria-current="page"` driving the active nav state (CSS bound to attribute, not class).
- `prefers-reduced-motion` honored globally.

## Reference files

- `references/surfaces.md` — surface hierarchy, shadows, border radius. Whitespace > dividers > wells > cards.
- `references/typography.md` — anti-Inter rule, Geist defaults, tabular-nums for data, no `font-weight: 700` headings.
- `references/sidebar-patterns.md` — 256/64 px sidebar dimensions, 36 px row height, 12% accent tint + 3 px left bar active state, ⌘B collapse, matchMedia 1024 px forced collapse.
- `references/signal-aesthetic.md` — full Signal palette (cream #f7f4ef bg, island #1a1612 sidebar, orange #c2410c accent), SVG grain texture, warm-tinted shadow tokens.
- `references/dashboards.md` — KPI strips with container queries, bare tables (no card wrappers, no vertical lines), inline SVG charts, empty states.
- `references/accessibility.md` — focus-visible rings, route announcer live-region, modal focus trap + restore, color-contrast thresholds, skip link, landmarks.
- `references/vue3-patterns.md` — Composition API + `<script setup>`, singleton composables (state at MODULE scope), base-component slot APIs (#header / default / #footer / #actions), Teleport for modals, role="img" inline SVG.

## Invocation flow

### Phase A — Assess

Read the target project:
- `package.json` — confirm Vue 3, check for Vite, identify icon and router libraries, note any css framework.
- `src/main.js` (or `main.ts`) — see what's mounted, what's imported globally.
- `src/App.vue` — current layout primitive (top-nav vs sidebar vs none).
- `src/views/*.vue` — page structure and existing patterns.
- `src/components/*.vue` — reusable primitives in play.
- `src/composables/*.js` — existing state patterns; check for module-scope-vs-function-scope state per the `vue3-patterns.md` singleton rule.

Inventory: layout type, font choice, color palette (look for hex literals), component patterns, router setup, store (Pinia / Vuex / none), icon library (Lucide / Heroicons / inline SVG).

### Phase B — Ask

Use `AskUserQuestion` for three blocking questions:

1. **Aesthetic direction.** Options: Signal (warm cream + dark island + orange — DEFAULT), Foundry (cool neutral + blue), Meridian (high-contrast + violet), Custom (user provides palette).
2. **Web font.** Options: Geist (DEFAULT), Inter (only if user has a stakeholder reason), System default (no web font).
3. **Scope.** Options: Full redesign (sidebar + tokens + components + views), Sidebar-only, Tokens-only.

Skip the questions only if the invoking prompt already names all three values explicitly.

### Phase C — Plan

Generate a phased plan referencing the appropriate `references/*.md` files. List the files to create or modify with rough line counts.

Typical plan shape for a full redesign:
- Create `src/tokens.css` (~120 LOC) and `src/app.css` reset (~40 LOC).
- Update `src/main.js` to import tokens BEFORE app.mount().
- Rewrite `src/App.vue` to a CSS grid shell with `<SidebarNav>` and `<main><RouterView /></main>` (~80 LOC).
- Create `src/components/nav/SidebarNav.vue` (~120 LOC), `NavRow.vue` (~60 LOC), `SidebarFooter.vue` (~50 LOC).
- Create `src/components/base/BaseCard.vue`, `BaseButton.vue`, `BaseDialog.vue` per `vue3-patterns.md`.
- Migrate views in dependency order: shared layout components first, then leaf views.
- Add route-announcer live-region and skip-link to `App.vue` per `accessibility.md`.

### Phase D — Implement

Write the token CSS file first; everything downstream depends on it. Then restructure the App.vue layout to the CSS grid. Then add components. Then migrate views.

**Delegate `.vue` file writes to the `vue-expert` Agent when the target project's CLAUDE.md names that agent.** Check the project's CLAUDE.md for the rule before writing any `.vue` file directly. When delegating, the brief MUST embed the relevant `references/*.md` content inline (the subagent does not have access to this skill's references unless they're in the brief).

Replace every hex literal in component styles with a `var(--token-name)` lookup. Grep for `#[0-9a-fA-F]{3,8}` in `src/**/*.vue` and `src/**/*.css` to find them.

### Phase E — Verify

Start the dev server (use the script defined in `package.json` — typically `npm run dev` or `pnpm dev`). Visit each route in a browser. Check:

- Lucide icons render at the new `stroke-width: 1.5` (not the default `2`).
- Web font loads (`fonts.googleapis.com` request succeeds; element computed-style shows `Geist`).
- No hex literals remain in component styles (grep `src/` for `#[0-9a-fA-F]{3,8}` excluding the tokens file).
- No console errors.
- `⌘B` toggles the sidebar collapse.
- Viewport narrower than 1024 px forces the sidebar collapsed.
- Tab through the page — every interactive element shows a visible focus ring.
- Activate VoiceOver / NVDA briefly — page title is announced after route change.

Report visual issues to the user with a screenshot or description, but never inline-loop on visual verification — defer follow-up visual checks to a separate `Explore` subagent run.

## Naming conflict policy

This skill was renamed from `frontend-design` to `frontend-design-vue` because the `frontend-design` name is already owned by a marketplace plugin at `~/.claude/plugins/marketplaces/claude-plugins-official/plugins/frontend-design/`. If a future user installs that marketplace plugin alongside this skill, both will coexist without conflict.

## When to delegate

- `.vue` file writes — `vue-expert` Agent if the project's CLAUDE.md names it.
- Visual verification after the redesign lands — `Explore` subagent with Playwright / BrowserMCP access.
- A11y audit on a complex page — `vercel-design-guidelines` skill or a dedicated `Explore` pass.

## Default-AI signature avoidance check

Before declaring a redesign complete, audit against the four AI-slop signals. Failing two or more means the redesign hasn't escaped the default-shadcn shell:

- [ ] Font is NOT Inter (or is Inter with `cv02 cv03 cv04 cv11 ss01 ss03` features enabled).
- [ ] Accent is NOT a saturated blue (#3b82f6 / blue-600 territory).
- [ ] Sidebar width is NOT 240 px (use 256 / 224 / 280 — anything but 240).
- [ ] Icon stroke-width is NOT the default Lucide 2 (use 1.5 or 1.25).
