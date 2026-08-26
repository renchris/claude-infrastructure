# P8 — ATTRIBUTE: from a pixel finding to the source line that causes it

**Stage owner:** the bridge between P-detect (a finding at coordinates) and the coding agent that
must edit a file. **Nobody in the A1–A15 wave owned this.** A15's sharpest point is that the whole
wave assumed perception was the constraint and "the most probable failure is a system that sees
fine, critiques plausibly, and changes nothing." This stage is the answer to that: it is the only
stage whose output is a *write target*.

**Governing inversion.** Every other stage in the pipeline asks "what is wrong?" This one asks "who
wrote it?" — and those are different graphs. The rendered pixel is produced by a *cascade* over a
*component tree* over a *module graph*; a finding names a node in the first graph and an edit must
name a node in the third. This stage is three lookups, not one, and each one can fail
independently. **The failure mode to design against is not "no answer" — it is a plausible file
path that is wrong**, because the consumer is an agent that will edit it without a human reading
the diff first.

---

## 0. CONTRACT

### Inputs (all required unless marked)

```jsonc
{
  "schema": "attribute/1",
  "capture_id": "cap_2026-08-26T18-04-11Z_a91f",   // ties to the P-capture manifest
  "finding": {
    "id": "f_07",
    "rule": "xcheck-contrast-varies",              // or "vlm-advisory" for a judge finding
    "origin": "dom" | "xcheck" | "vlm",
    "backend_node_id": 217,                        // CDP DOM.BackendNodeId — PRESENT iff origin != "vlm"
    "rect_css": [412, 1180, 268, 44],              // x,y,w,h in CSS px, page coords
    "property_hint": ["color", "background-image"], // CSS properties the finding is ABOUT. optional
                                                    // but it is the single highest-value input
    "text_sample": "Reserve a table"               // optional; used only for the tie-break in §5.4
  },
  "session": {
    "app": "reso-management-app",
    "repo_root": "/Users/chrisren/Development/reso-management-app",
    "dev_origin": "http://localhost:3000",         // dev server, MUST be a dev build — see §1
    "build_mode": "dev",                           // "dev" | "prod"; prod caps confidence at LOW
    "git_sha": "bc77b22a9"                          // recorded so a stale attribution is detectable
  }
}
```

`backend_node_id` is the load-bearing input. It comes free from the same `DOMSnapshot.captureSnapshot`
pass P-capture already runs (A7: 32.7 ms for the whole tree). **A finding that arrives without one is
a VLM finding, and §5.1 has to resolve coordinates → node first, at a confidence penalty.**

### Output — one record per finding, written to `attribution.json` beside `findings.json`

```jsonc
{
  "schema": "attribute/1",
  "finding_id": "f_07",
  "verdict": "RESOLVED" | "AMBIGUOUS" | "UNATTRIBUTABLE" | "VENDOR" | "STALE",
  "confidence": "HIGH" | "MEDIUM" | "LOW",
  "targets": [                                     // ordered, best first; empty iff UNATTRIBUTABLE
    {
      "kind": "jsx-element" | "style-rule" | "token-definition" | "component-definition",
      "file": "src/components/reservation/TableCard.tsx",   // repo-relative, ALWAYS
      "line": 84, "column": 11,
      "end_line": 84,                              // optional, when the resolver knows the span
      "evidence": "owner-stack",                   // §4 table — the mechanism that produced this
      "excerpt": "  <Text className={css({ color: 'fg.muted' })}>",
      "shared_with": 1,                            // how many OTHER rendered elements resolve here
      "edit_hazard": null | "shared-utility" | "vendor-file" | "generated-file" | "runtime-computed"
    }
  ],
  "component_path": ["Page", "ReservationList", "TableCard", "Text"],  // owner chain, outermost first
  "declaring_rule": {                              // which CSS rule actually WINS the property
    "property": "color",
    "winning_value": "var(--colors-fg-muted)",
    "origin": "regular" | "user-agent" | "inline" | "injected",
    "stylesheet": "http://localhost:3000/_next/static/css/app.css",
    "sheet_line": 4127,
    "mapped": null                                 // §3.3: null when the sheet has no source map
  },
  "why_not_better": "panda styles.css is generated and carries no sourceMappingURL",
  "next_probe": "grep -rn \"fg.muted\" src/ | wc -l   # 214 call sites — needs the JSX anchor"
}
```

### Failure modes — the four that are NOT `RESOLVED`, and what each obliges the caller to do

| Verdict | Means | Caller MUST |
|---|---|---|
| `AMBIGUOUS` | ≥2 targets, none dominant (§5.6) | present all of them to the agent; **never pick one** |
| `UNATTRIBUTABLE` | no mechanism produced a repo-relative path | report the finding with `targets: []` and the `next_probe` string; the agent greps |
| `VENDOR` | resolved, but the file is under `node_modules/`, a purchased-template dir, or `styled-system/` | report the path AND the nearest first-party ancestor in `component_path`; **flag that the edit belongs upstream** |
| `STALE` | resolved, but `git_sha` ≠ current HEAD **and** the target file changed between them | re-run capture; do not edit |

🚨 **This stage never emits a guessed path.** A grep-derived candidate is not a target — it is a
`next_probe` string. The distinction is the whole safety property: an agent given `targets: []` plus
a grep command runs the grep and reads the result; an agent given a wrong `file:line` edits it.

---

## 1. The substrate, re-measured — three corrections to the brief

Read from the three checkouts on 2026-08-26. **The wave's one-line stack descriptions are wrong in
two of three cases, and the errors change this stage's design, not just its prose.**

| App | Brief said | **Measured** | Attribution substrate |
|---|---|---|---|
| `reso-landing-app` | Next 14, purchased template | Next **14.2.11**, React 18, **Tailwind 3.4.7** | utility classes on JSX; `prettier-plugin-tailwindcss` only |
| `reso-management-app` | Next 16 / React 19 / Tailwind 4 | Next **16.2.6**, React **19.2.8**, Tailwind **4.2.4** **+ Panda CSS 1.9.0** (`@pandacss/dev`, `styled-system/` generated, `@park-ui/panda-preset`) | **hybrid**: two atomic-CSS engines in one PostCSS chain |
| `reso-web-app` | Next 13, "between the two" | Next **15.5.24**, React 18, **Emotion 11** (`@emotion/react` + `@emotion/styled`), **no Tailwind, no Panda** | CSS-in-JS with runtime-hashed class names |

`postcss.config.js` in the management app is literally:

```js
module.exports = { plugins: { '@tailwindcss/postcss': {}, '@pandacss/dev/postcss': {} } }
```

**Three consequences this stage has to absorb:**

1. **There is no single "Tailwind class provenance" problem** — three apps, three class-naming
   regimes (§3.2). A resolver written against Tailwind alone silently returns `UNATTRIBUTABLE` on a
   third of the fleet.
2. **`styled-system/styles.css` in the checkout is a stub** — 2 distinct class selectors, base layer
   only. The atomic utility layer is generated **in the PostCSS chain at build time from a static
   extraction of the source files**. There is no on-disk artefact of it, so nothing can carry a
   source map back to the TSX. §3.3.
3. **React 19.2.8 has deleted the mechanism most attribution tooling is built on.** §2.1. This is
   the single sharpest finding in this stage and it invalidates the obvious design.

---

## 2. Mechanism inventory — what actually exists, measured

### 2.1 `__source` / `_debugSource` — **DEAD on React 19. Do not build on it.**

The classic bridge is `@babel/plugin-transform-react-jsx-source`, which injects
`__source={{fileName, lineNumber, columnNumber}}` into every JSX element in dev; React stored it on
the fiber as `_debugSource`, and React DevTools' "view source" read it back. Every "click an element,
open the file" tool written before 2025 uses this.

Measured in `reso-management-app/node_modules`, React and react-dom **19.2.8**:

```
react-dom/cjs/react-dom-client.development.js   _debugSource: 0   __source: 0
                                                 fileName: 0   lineNumber: 0
                                                 _debugOwner: 26   _debugStack: 8   _debugTask: 38
react/cjs/react-jsx-dev-runtime.development.js  fileName: 0   lineNumber: 0   columnNumber: 0
```

and the dev JSX factory's own signature is now:

```js
function jsxDEVImpl(type, config, maybeKey, isStaticChildren, debugStack, debugTask)
```

Arguments 5 and 6 used to be `source` and `self`. They are now `debugStack` (a captured `Error`) and
`debugTask` (a console task for async stitching). **The `{fileName, lineNumber, columnNumber}` object
is not accepted, not stored, and not readable anywhere in the React 19 runtime.**

**But it is alive on React 18, and two of the three apps are on React 18.** Measured in the same
sweep: `reso-web-app` react/react-dom **18.2.0**, `reso-landing-app` **18.3.1**, and both dev bundles
carry `_debugSource` (11 occurrences) with the older factory signature
`jsxDEV(type, config, maybeKey, source, self)` — argument 4 is the source object. Next populates it:
`next/dist/build/swc/options.js:96-104` sets `react: { runtime: "automatic", development: !!development }`,
and SWC's `development: true` emits the `{fileName, lineNumber, columnNumber}` argument.

🚨 **So on the React 18 apps, rung 1 is free and exact: `fiber._debugSource` is a pre-bundling source
path, needing no source map and no HTTP round-trip at all.** On React 19 the identical question costs
a stack capture plus a source-map resolution. Same rung, two completely different implementations and
two different cost profiles — which is why §11's adapter table exists and why `_debugSource` must be
coded as a *fast path under* the owner-stack resolver, never as the primary (§11's closing note).

The React 19 replacement is `React.captureOwnerStack()` — confirmed exported from `react@19.2.8`
(`Object.keys(require('react')).filter(/owner/i)` → `['captureOwnerStack']`). It returns a **stack
string of bundled positions**, not source positions. That is the whole difference: `__source` gave
you `src/x.tsx:84:11` for free; owner stacks give you
`http://localhost:3000/_next/static/chunks/app_page.js:14022:71` and **you must resolve it through a
source map.** §2.3 is how.

> **UNVERIFIED:** whether `next dev --turbopack` (the management app's default on Next 16) preserves
> `debugStack` fidelity identically to the webpack dev path. **One probe:** in the browser console on
> a dev page, `React.captureOwnerStack()` inside a component render and check the top frame names a
> `_next/static` chunk rather than `<anonymous>`. If it returns `null` outside a render/DEV context
> that is expected, not a failure — §5.2 only calls it from a fiber's own `_debugStack`.

### 2.2 Fiber access from a DOM node — still stable, and it is the spine

`react-dom` attaches its fiber under a randomised key on the DOM node. Confirmed present in
19.2.8's dev bundle: `__reactFiber$`, `__reactProps$`, `__reactContainer$`, `__reactEvents$` — the
suffix is a per-build random string, so **discover it, never hardcode it**:

```js
const K = Object.keys(el).find(k => k.startsWith('__reactFiber$'));
const fiber = el[K];
```

From the fiber, three fields survive in React 19 dev and each carries different attribution value:

| Field | Type | Gives you | Cost |
|---|---|---|---|
| `fiber._debugOwner` | fiber \| null | the component that *created* this element (not the parent that contains it) | free, already in memory |
| `fiber._debugStack` | `Error` | a stack whose top frame is the **JSX call site** in bundled coordinates | free; `.stack` string materialises lazily |
| `fiber.type.name` / `.displayName` | string | the component's own name — survives minification only if not mangled | free |

Walking `_debugOwner` upward yields the `component_path` field of the output. That chain is the
*ownership* chain (who rendered whom), which is what a coder needs — deliberately not the DOM
ancestor chain, which is full of layout `<div>`s nobody wrote by name.

⚠️ **`_debugOwner` and `_debugStack` exist only in the DEVELOPMENT bundle.** A production build
strips them, which is why `build_mode: "prod"` caps confidence at `LOW` in the contract — in prod
this stage degrades to §3 (CSS-side) evidence only.

### 2.3 The Next.js dev source-map resolver — **already built, already running, use it**

Do not write a source-map resolver. `next dev` serves one, and it already knows the compilation's
stats, the ignore-list, and the repo root. Read out of `next@16.2.6`
(`dist/server/dev/middleware-webpack.js:383-420`, `dist/esm/next-devtools/shared/stack-frame.js`):

```http
POST http://localhost:3000/__nextjs_original-stack-frames
Content-Type: application/json

{"frames":[{"file":"http://localhost:3000/_next/static/chunks/app_page.js",
            "line1":14022,"column1":71,"methodName":"TableCard","arguments":[]}],
 "isServer":false,"isEdgeServer":false,"isAppDirectory":true}
```

Response is a `Promise.allSettled`-shaped array, index-aligned with `frames`:

```jsonc
[{"status":"fulfilled",
  "value":{"originalStackFrame":{"file":"src/components/reservation/TableCard.tsx",
                                 "line1":84,"column1":11,"methodName":"TableCard",
                                 "ignored":false,"arguments":[]},
           "originalCodeFrame":"…ANSI-coloured ±3 lines…"}}]
```

Four properties that make this the right primitive rather than a convenience:

- **`file` comes back repo-relative already**, computed against Next's own `rootDirectory`. No path
  arithmetic on our side, so no chance of pointing at the wrong worktree.
- **`ignored: true`** is Next's source-map ignore-list verdict — `node_modules`, framework internals,
  anything the sourcemap marks. That is exactly the `VENDOR` signal, computed by the framework
  instead of by a regex of ours. Map `ignored → verdict: "VENDOR"`.
- **`originalCodeFrame`** is a ready ±3-line excerpt. Strip ANSI (`\x1b\[[0-9;]*m`) and it is the
  `excerpt` field. Free context for the editing agent.
- **A no-source-map frame degrades explicitly**: the handler returns `defaultStackFrame` with the
  *bundled* file and line and `originalCodeFrame: null`. So "resolved" and "unresolvable" are
  distinguishable from the response alone — no heuristic needed. `originalCodeFrame === null` **and**
  a `file` still starting `http://` ⇒ `UNATTRIBUTABLE`, never a target.

The sibling endpoints, confirmed present in the same build and worth knowing: `__nextjs_source-map`
(raw map for a chunk URL, if you need to resolve outside the frame API),
`__nextjs_launch-editor?file=…&line1=…&column1=…&methodName=…&isAppRelativePath=1` (opens the editor;
irrelevant to an agent but proves the coordinate convention), and `__nextjs_original-stack-frame`
(singular, legacy — **do not use, Next 16 ships the plural**).

🚨 **Coordinate convention: Next 16 uses `line1` / `column1`, 1-based.** Older Next used
`lineNumber` / `column`. A resolver sending the old field names gets a `400`, not a wrong answer —
which is the good failure — but it must be pinned per Next major. `reso-landing-app` is Next 14 and
**will** need the legacy field names; that is a per-app adapter, not a shared code path.

> **UNVERIFIED:** whether the Turbopack middleware (`middleware-turbopack.js`, present in the same
> build) honours the identical request body. It registers the same pathname, which is strong
> evidence, but the frame-resolution internals differ. **One probe:** run `next dev` twice, once with
> and once without `--turbopack`, POST the same body, and diff the two `originalStackFrame` objects.

### 2.4 The accessibility tree — identity, never geometry, and never source

`Accessibility.getFullAXTree` gives role/name/value per node and a `backendDOMNodeId` on each. Its
attribution value is exactly one thing: **it is the only substrate that names an element the way a
human names it** ("the *Reserve* button"), which is what makes a `next_probe` grep string
searchable when the source-map chain fails (§5.5).

It has **no** relationship to component boundaries. An accessibility node is a *rendered role*; a
React component may render zero, one, or fifty of them, and a single `<button>` with a
`role="button"` wrapper collapses two components into one AX node. A7's rule stands: *the a11y tree
answers semantic conformance and element identity; never ask it anything perceptual* — and this
stage adds: **never ask it anything about source structure either.** Treat the AX name as a *string
for grepping*, and nothing more.

### 2.5 Dev-build data attributes — the option we are deliberately NOT taking

The tempting design is a dev-only Babel/SWC plugin injecting `data-src="file:line:col"` on every
element (the `@react-dev-inspector` / `vite-plugin-react-inspector` pattern). It would make this
stage a one-line DOM read. **Rejected, for three measured reasons:**

1. **It changes the artefact under review.** `[data-*]` participates in the cascade, and all three
   apps use attribute selectors (`[data-theme=dark] body` is line 2 of the management app's own
   `styled-system/styles.css`). Injecting attributes into the page whose *rendering* we are grading
   is a small, unbounded risk — the wrong shape of risk for an instrument.
2. **It requires a build-config change in three repos**, two of which are not ours to change freely.
   A stage that needs a PR merged into each app before it works is a stage that is never on.
3. **It is strictly redundant with §2.3 in dev, and equally absent in prod.**

**Where a data attribute IS the right answer, and we should ask for it:** a *stable component
identity* attribute (`data-component="TableCard"`), added by the app teams as a first-party
convention, not by our tooling. That is a design-system decision with independent value (it makes
E2E selectors stable), and it would raise §5's confidence on the whole `AMBIGUOUS` class. **Filed as
a recommendation to the app owners, not a dependency of this stage.**

---

## 3. The CSS side — which rule wins, and where that rule was written

§2 answers *which element*. It does not answer *which declaration*, and for a colour/spacing/typography
finding the declaration is the edit target. Two different questions, two different mechanisms.

### 3.1 `CSS.getMatchedStylesForNode` — the only substrate that knows the cascade

```jsonc
// one CDP round-trip per finding, not per page
{"method":"CSS.getMatchedStylesForNode","params":{"nodeId": 217}}
```

Returns `inlineStyle`, `attributesStyle`, `matchedCSSRules[]`, `pseudoElements[]`, `inherited[]`,
`cssKeyframesRules[]`. The fields this stage reads:

| Field | Use |
|---|---|
| `matchedCSSRules[].rule.origin` | `"user-agent"` ⇒ **nothing to edit, the browser wrote it** — a real and easily-missed outcome for a spacing finding on an unreset `<ul>`. `"injected"` ⇒ an extension or our own instrumentation; `"regular"` is the only editable origin. |
| `matchedCSSRules[].rule.styleSheetId` | joins to `CSS.getStyleSheetText` / the `CSS.styleSheetAdded` header, which is where `sourceURL` and `sourceMapURL` live |
| `matchedCSSRules[].rule.selectorList.text` | the selector — **the string that makes a grep exact** (§5.5) |
| `matchedCSSRules[].rule.style.cssProperties[].range` | line/col **within the stylesheet**, 0-based, `{startLine,startColumn,endLine,endColumn}` |
| `matchedCSSRules[].matchingSelectors` | which selectors in the list actually matched this node |

**Cascade order:** `matchedCSSRules` is returned lowest-priority first, so the winning declaration for
property *P* is **the last rule in the array whose `style.cssProperties` contains *P* with
`parsedOk !== false` and `disabled !== true`** — unless an `!important` earlier in the array beats it,
or `inlineStyle` carries *P*, which beats everything non-`!important`. **Do not re-implement cascade
resolution.** Compute the *winner* the way the browser already did: read the resolved value from the
`DOMSnapshot` computed styles P-capture already has, and then select the matched rule whose declared
value **equals that resolved value** after normalisation. If exactly one matches, that is the
declaring rule with certainty; if several do, emit them all and drop to `MEDIUM`. This is the
make-the-actuator-the-arbiter discipline: never re-derive a predicate the engine already evaluated.

⚠️ **Two constructs where `styleSheetId` resolves to nothing editable.** (a) **Constructed
stylesheets** (`adoptedStyleSheets` / `CSSStyleSheet()` — how several component libraries ship styles)
have `isConstructed: true` and **no `sourceURL`**. (b) **CSS-in-JS `<style>` injection** (Emotion, in
`reso-web-app`) produces an inline sheet with `isInline: true` and a `sourceURL` of the *document*,
not of any file. Both cases: `declaring_rule.mapped = null`, and attribution must come from §2's
component side alone. Detect them explicitly rather than letting them fall through as a path.

### 3.2 Class-name provenance — three regimes, three different answers

This is where the "utility class shared across hundreds of elements" problem lives, and **it is not
one problem.** Measured usage density in `reso-management-app` today: **337 source files** import from
`styled-system/css`, **973** literal `className="…"` attributes, and the single token `fg.muted`
appears **263 times**. A class name alone can never be an edit target at that density.

**(a) Panda CSS (management app) — invertible, and that is a genuine asset.** Panda's atomic class
name is a pure function of *(property, value, condition)* with **no hash**: `styled-system/css/css.mjs`
ships the whole map as a literal string, e.g. `color:c`, `backgroundColor:bg-c/bgColor`,
`paddingInline:px/paddingX/1`, `fontSize:fs`, `lineHeight:lh`. So `class="c_fg.muted"` inverts
**deterministically** to `{property: "color", value: "fg.muted"}` — no source map, no guesswork. That
gives a *high-precision grep string* (`fg.muted` → 263 hits) which is useless alone but **decisive as
a filter over the ~1–3 files §2 already named**. Ship the inverter: parse that `utilities` string out
of `css.mjs` at startup, build the reverse map, cache it keyed by the file's mtime.

**(b) Tailwind 3 / 4 (landing app; management app's second engine).** The class name *is* the
declaration (`text-slate-500`, `px-4`) — same invertibility, without needing a map file. But the
class lives on the JSX element, so **the edit target is the JSX element, not any stylesheet**: there
is no file where `.px-4` was authored. Attribution therefore routes entirely through §2, and the
class string is only the confirmation that §2 landed on the right element (§5.4). A Tailwind finding
that reaches §3 at all is a finding about `tailwind.config.js`'s `theme.extend` — a *token*
finding, `kind: "token-definition"`, and that file is exact and small.

**(c) Emotion (`reso-web-app`) — the hard case, and the only one where the class is opaque.**
Emotion emits `css-<hash>` where the hash is of the serialised styles. Not invertible. The one lever
is `@emotion/babel-plugin`'s `autoLabel`, which in development appends a human label derived from
the *variable or component name* — `css-1x2y3z-TableCard`. **Measured: `reso-web-app` has no
`@emotion/babel-plugin` dependency and no babel config**, so it is on Next's SWC path; Next enables
the SWC emotion transform only when `compiler.emotion` is set, and `reso-web-app/next.config` sets
`compiler` for `removeConsole` only. **So today there is no label and no attribution from the class
name in that app at all.** The remedy is one line — `compiler: { emotion: { autoLabel: 'dev-only',
labelFormat: '[local]' } }` — which costs nothing in production and turns opaque hashes into
component names. **File it as the single highest-leverage app-side change this stage wants.**

### 3.3 CSS source maps — where the chain actually breaks

`next dev` sets `sourceMap: true` on both `css-loader` and `postcss-loader`
(`next/dist/build/webpack/config/blocks/css/index.js:147,163`), so a stylesheet header will carry a
`sourceMapURL` and `CSS.getMatchedStylesForNode` → `styleSheetId` → header → map → original position
**does** work for hand-authored CSS. Three break points, all of them real here:

1. **Generated CSS has no map worth following.** `styled-system/styles.css` contains **0**
   `sourceMappingURL` occurrences, and — measured — the checked-in file holds only the base layer:
   **2 distinct class selectors.** The atomic utility layer does not exist on disk at all; it is
   produced inside the PostCSS chain from a static extraction of the source files. A map over it can
   only ever point back at the CSS entrypoint that invoked the plugin, never at the TSX that used the
   utility. **`why_not_better` for the whole Panda class of findings is this sentence.**
2. **`productionBrowserSourceMaps: false`** in `reso-web-app/next.config` (read today). In a prod
   capture, no JS map ⇒ §2.3 cannot resolve ⇒ everything falls to `LOW`. Another reason `build_mode`
   is a contract input rather than an inference.
3. **Purchased-template CSS.** `reso-landing-app` is Tailwind-only (`src/styles/tailwind.css` is the
   sole stylesheet outside `node_modules`), so the template's design lives in JSX class strings, not
   in a vendor CSS file. That is *better* for attribution than the usual purchased-template case —
   there is no opaque `theme.css` to be defeated by — but it means every landing-app finding is a
   JSX-element finding and `VENDOR` will fire on the *component* path, not a stylesheet path.

---

## 4. The evidence ladder

Every target carries an `evidence` tag naming the mechanism that produced it. This is the table the
resolver walks top-down, and the only thing that sets confidence.

| # | `evidence` | Gives | Cost | Requires | Breaks when |
|---|---|---|---|---|---|
| 1 | `owner-stack` | JSX call site, `file:line:col` | ~1 CDP eval + 1 HTTP POST, ~15–40 ms | dev build; React ≥19 `_debugStack`; `next dev` running | prod build; Turbopack fidelity UNVERIFIED (§2.3) |
| 2 | `component-def` | the component's *definition* site (not the call site) | same POST, +1 frame | `fiber.type` resolvable and not mangled | HOC/`forwardRef`/`memo` wrappers shift the frame; anonymous arrow components |
| 3 | `css-rule-map` | the CSS declaration's authored `file:line` | 2 CDP calls + map fetch, ~30–80 ms | stylesheet has `sourceMapURL`; not constructed/inline | generated CSS (Panda), constructed sheets, Emotion inline |
| 4 | `token-def` | the design-token definition | 1 grep in `panda.config.ts` / `tailwind.config.js` | token name recovered from §3.2 | token computed at runtime |
| 5 | `class-invert` | `{property, value}` — a **filter**, not a location | <1 ms, cached map | Panda or Tailwind | Emotion (opaque hash) |
| 6 | `ax-name` | a human-readable string to grep | free, already captured | AX tree populated | icon-only controls with no accessible name |

🚨 **Rungs 5 and 6 never produce a `target` on their own.** They exist to *narrow* or *confirm* a
rung 1–4 target, and to compose the `next_probe` string when everything above fails. A resolver that
promotes a grep hit to a target has re-introduced exactly the failure this stage exists to prevent.

---

## 5. The resolution algorithm

Run per finding. Steps are ordered by *decreasing certainty*, and the algorithm **stops at the first
rung that yields a unique target** — except for step 5.4, which always runs, because it is a check
rather than a source.

### 5.0 — Precondition: freeze the frame

Refuse to run unless the capture manifest's `git_sha` equals `git rev-parse HEAD` **and**
`git status --porcelain` is empty for the repo. A dirty tree between capture and attribution means
`line` numbers are fiction. Non-equal ⇒ emit `verdict: "STALE"` for every finding and stop; this is
one check for the whole batch, not per finding. *(Threshold is exact equality, not a time window: a
one-line edit above the target shifts it, and there is no tolerance below "one line".)*

### 5.1 — Coordinates → `backendNodeId` (VLM findings only)

DOM findings arrive with a node id. A VLM finding arrives with a rect. Resolve it with
`DOM.getNodeForLocation {x, y, includeUserAgentShadowDOM: false}` at the rect's **centroid**, then
**verify** with `DOM.getBoxModel` on the returned node: accept only if IoU(returned box, `rect_css`)
**≥ 0.5**.

*Why 0.5:* it is the loosest threshold that still forbids the common catastrophic case — the centroid
landing on a full-width parent container whose box is 10× the finding's area, which yields IoU ≈ 0.1.
A tighter 0.75 would reject legitimate text-node-vs-inline-box mismatches. On failure, walk *up* from
the hit node to the first ancestor whose IoU ≥ 0.5, and if none, walk *down* through
`DOM.querySelectorAll` on the hit node's children. Still none ⇒ `UNATTRIBUTABLE` with
`why_not_better: "no DOM node matches the reported rect within IoU 0.5"`.

**This step is the one place this stage inherits the VLM's localisation error**, and the IoU gate is
what converts that error into an abstention instead of a wrong file. A4's rule — *the grounder
supplies identity, the DOM supplies geometry* — is enforced here or nowhere.

### 5.2 — `backendNodeId` → JSX call site (rung 1)

```js
// CDP: Runtime.callFunctionOn against the DOM node object
// (DOM.resolveNode {backendNodeId} → objectId)
function attr() {
  const el = this;
  const k = Object.keys(el).find(s => s.startsWith('__reactFiber$'));
  if (!k) return null;
  let f = el[k], out = { frames: [], path: [] };
  // the element's own JSX call site
  if (f._debugStack) out.frames.push(String(f._debugStack.stack || ''));
  // ownership chain, innermost first
  let o = f._debugOwner, guard = 0;
  while (o && guard++ < 24) {
    const n = o.type && (o.type.displayName || o.type.name);
    if (n) out.path.push(n);
    if (o._debugStack && out.frames.length < 4) out.frames.push(String(o._debugStack.stack || ''));
    o = o._debugOwner;
  }
  return JSON.stringify(out);
}
```

*Why `guard < 24`:* the owner chain in a Next App Router tree runs 8–14 deep through layouts and
providers before reaching the route root; 24 is ~1.7× the observed depth, enough to never truncate a
real chain and small enough that a cyclic `_debugOwner` (which would otherwise hang the eval) costs
24 iterations. *Why `frames.length < 4`:* four frames is the call site plus three owners, which is
where a component boundary is always found in these codebases; each extra frame is a source-map
resolution the POST has to do.

Parse each stack's **topmost non-`node_modules`, non-`react-dom` frame** into
`{file, line1, column1, methodName}` and POST the batch to `__nextjs_original-stack-frames` (§2.3).
The first frame that resolves with `originalCodeFrame !== null` and `ignored: false` is the
`jsx-element` target, `evidence: "owner-stack"`.

### 5.3 — Declaring rule (rung 3/4)

Independently of 5.2 — **both run, they answer different questions** — resolve the CSS side for each
property in `finding.property_hint`:

1. `CSS.getMatchedStylesForNode` on the node.
2. Select the winning rule by *value equality against the already-captured computed style* (§3.1).
3. If the sheet has a `sourceMapURL` and is neither constructed nor inline: resolve
   `{styleSheetId, range.startLine, range.startColumn}` through the map → `css-rule-map` target.
4. Else, if the declared value is a token reference (`var(--colors-fg-muted)`, or a Panda/Tailwind
   token name recovered by rung 5): grep the token's definition in `panda.config.ts` /
   `tailwind.config.js` → `token-def` target. **This is the highest-value target for the management
   app**, because a design-system-conformance finding almost always wants the token changed, not the
   263 call sites.
5. Else `declaring_rule.mapped = null` and `why_not_better` names which of §3.3's three breaks fired.

### 5.4 — The consistency check (always runs, never a source)

Invert the element's class list (rung 5) and assert that the finding's `property_hint` appears among
the inverted properties. Example: finding is about `color`; element carries `c_fg.muted`; inverter
says `c` → `color`. **Agreement raises confidence one step. Disagreement drops it one step and
appends a `why_not_better` note** — it means the winning declaration came from somewhere other than
this element's own utility classes (an inherited rule, a parent's `*` selector, a UA default), which
is exactly the case where a naive resolver edits the wrong file.

*Why one step and not a veto:* disagreement is a legitimate outcome for inherited properties
(`color` is inherited, and the management app's base layer sets it on `body`), so a veto would fire
on a large, correct population.

### 5.5 — Composing `next_probe` when everything above fails

Never a path. Always a **runnable command**, in this precedence:

```
# Panda/Tailwind token recovered:
grep -rn "fg.muted" src/ --include=*.tsx | head -40
# CSS selector recovered but unmapped:
grep -rn "\.card-header" src/ styled-system/ --include=*.{css,ts,tsx} | head -40
# only an accessible name recovered:
grep -rn "Reserve a table" src/ --include=*.{tsx,ts,json} | head -40
# component name from the owner chain, but no resolvable frame:
grep -rn "function TableCard\|const TableCard" src/ --include=*.tsx
```

*Why `head -40`:* it bounds the agent's read cost while staying above the observed hit counts for a
*narrowed* grep; the unnarrowed `fg.muted` grep returns 263 and would blow past it, which is the
signal that the probe is too weak to be worth emitting — **if the estimated hit count exceeds 40,
emit the count instead of the command** (`"263 call sites — too many to grep; needs the JSX anchor"`),
because a probe an agent cannot act on is worse than an admitted gap.

### 5.6 — Ambiguity and dominance

After 5.2–5.4, if ≥2 targets survive at the same rung, emit `AMBIGUOUS` unless one **dominates**:
its `shared_with` count is **0** while every rival's is **≥1**. A target no other rendered element
maps to is the one an edit cannot break by accident. `shared_with` is computed by running 5.2 across
every node in the captured `DOMSnapshot` **once per page**, not per finding, and bucketing by
resolved `file:line` — it costs one extra pass over an in-memory structure and turns the single most
dangerous edit hazard (`shared-utility`) into a number in the output.

---

## 6. Confidence — three levels, each with a mechanical definition

Confidence is **not** a model's self-report and **not** a score. It is a function of which rungs
agreed, computed by the resolver:

| Level | Mechanical definition | What the consumer may do |
|---|---|---|
| `HIGH` | rung 1 resolved (`originalCodeFrame !== null`, `ignored: false`) **and** 5.4 agreed **and** `shared_with == 0` **and** tree clean | **edit the file directly** |
| `MEDIUM` | rung 1 resolved but 5.4 disagreed, **or** `shared_with ≥ 1`, **or** only rung 3/4 resolved | **read the file, confirm the finding is visible in it, then edit** |
| `LOW` | prod build; or only rung 2 (component definition, no call site); or ≥2 targets with no dominance | **do not edit from this alone** — treat as a pointer for a human or for a second capture in dev |

**Why exactly three.** A finer scale invites the consumer to threshold it, and any threshold would be
uncalibrated: **no benchmark certifies attribution quality.** A6 found every ScreenSpot variant scores
point-in-box rather than IoU; there is no published web-UI *attribution* benchmark at all. Three
levels map onto three distinct agent behaviours, and nothing finer is defensible — a plausible number
nobody checked is this wave's named failure mode (README §2, the centroid arm).

🚨 **`HIGH` requires all four conditions, and `shared_with == 0` is the one that will most often
deny it.** In `reso-management-app` that is the honest answer: 337 files import the same `css()` and
one token appears 263 times. A stage that reported `HIGH` on those would be lying by construction.
**Expect `MEDIUM` to be the modal verdict on the management app, and design the consumer prompt for
`MEDIUM`, not for `HIGH`.**

---

## 7. What this stage CANNOT do, and who owns each

| Not ours | Why | Owning stage |
|---|---|---|
| Decide whether the finding is real | This stage attributes; it never adjudicates. A false positive attributed to `HIGH` confidence is a *faster* wrong edit. | P-detect / P-judge (and the ~20% FP budget lives there) |
| Attribute anything on a `<canvas>`, WebGL surface, or rasterised image | There is no DOM node under the pixel — `DOM.getNodeForLocation` returns the canvas itself for every point inside it | **nobody** — report `UNATTRIBUTABLE` with `why_not_better: "pixel is inside a canvas; no per-pixel DOM node exists"` |
| Attribute a **runtime-computed** style | An inline style written by JS at runtime (`el.style.top = …`, a virtualiser, a chart library) has `origin: "inline"` and no authored site. The *writer* is a JS call site, not a CSS location | P-attribute reports `edit_hazard: "runtime-computed"` and names the component from the owner chain; the **agent** must read that component |
| Attribute across a Server/Client boundary in a way that names the *server* file | Server Components render on the server; the browser fiber's `_debugStack` frames for them point at the RSC payload, not the server module | UNVERIFIED — §10 |
| Say whether editing the target is *safe* | `shared_with` is a count, not a blast radius. Whether changing `fg.muted` is correct is a design-system decision | the operator — the June 2026 ruling holds: **taste stays human** |
| Rank findings | Attribution is per-finding and order-free, deliberately: rubric ordering causes 16–39% top-1 reversals (README §6) | P-report |

**The single most important non-capability:** this stage cannot tell a coding agent *what to change*.
It emits a location and a hazard; the edit is the agent's.

---

## 8. Cost, and the CLI surface

**Per finding:** 1 `DOM.resolveNode` + 1 `Runtime.callFunctionOn` + 1 `CSS.getMatchedStylesForNode`
≈ 3 CDP round-trips. **Per page:** one batched POST to `__nextjs_original-stack-frames` carrying
every unresolved frame from every finding, plus one `shared_with` pass over the existing
`DOMSnapshot`. Budget **≤ 250 ms for a 20-finding page**, dominated by the source-map POST — which is
the same work the Next error overlay does on every dev error, so it is a warm path.

**Token cost to the judge: zero.** This stage runs *after* judgement and its output goes to the
*editing* agent. That is deliberate — putting file paths in front of the judge would let a model
reason about the code instead of looking at the page, which is the one thing the pixel stage exists
to prevent.

Surface follows A11's settled decision — **a plain CLI writing JSON to disk, not an MCP server**:

```bash
design-review attribute \
  --capture out/cap_2026-08-26T18-04-11Z_a91f/ \
  --findings out/cap_.../findings.json \
  --dev-origin http://localhost:3000 \
  --repo /Users/chrisren/Development/reso-management-app \
  > out/cap_.../attribution.json
```

Exit codes, fail-closed: `0` all findings resolved or explicitly abstained · `3` `STALE` (tree moved
under us) · `4` no dev server reachable at `--dev-origin` · `5` dev server reachable but
`__nextjs_original-stack-frames` returned non-2xx (⇒ wrong Next major, §2.3's `line1` trap). **`4`
and `5` are distinct on purpose** — one says "start the server", the other says "the adapter is wrong
for this app", and collapsing them would send the agent to retry a command that cannot work.

---

## 9. Acceptance test — the corpus this stage needs, and it is not the existing one

**The existing `bench/corpus/` cannot serve.** It renders one hand-written HTML page: no React tree,
no owner stack, no Next dev server, no source map. Attribution is untestable against it.

**The instrument:** extend `bench/` with `attrib_corpus/` — a route in a scratch Next 16 + Panda app,
~12 elements, each defect injected by a *build script that records the line it wrote to*, so the
answer key is **generated, not transcribed**. That is the README's own hard-won rule (a corpus needs
its own control run before it grades anything — the `optical-centering` null item scored two
detectors as failures for correctly abstaining) applied before the first grade rather than after.

**Four acceptance criteria, each a number with its reason:**

| # | Criterion | Threshold | Why this number |
|---|---|---|---|
| A1 | Exact-line accuracy on `HIGH` verdicts | **100%** | `HIGH` licenses a direct edit. Any wrong `HIGH` is a wrong committed diff; there is no acceptable rate above zero for a verdict that means "edit this". |
| A2 | Exact-**file** accuracy on `HIGH` + `MEDIUM` | **≥ 95%** | `MEDIUM` requires a read-and-confirm first, so a wrong file costs a wasted read, not a bad edit. 95% is the point where the agent's confirmation step is still cheap relative to the win. |
| A3 | Abstention correctness — of the findings the stage *could* have attributed, how many did it wrongly call `UNATTRIBUTABLE` | **≤ 20%** | Symmetric with the pipeline's FP budget (README §8: ~20% is where an AI reviewer loses credibility). An over-abstaining attributor is annoying; an over-confident one is dangerous, so the asymmetry is deliberate — A1 is absolute, A3 is a budget. |
| A4 | **Zero** attributions on the clean control | **0** | Same discipline as the detector layer. A control page has no findings, so the stage must emit an empty array — if it emits anything it is inventing input, not attributing it. |

**Run A1–A4 against the clean control before any rule change ships**, exactly as the deterministic
layer does. And run them **three times per app**, because the three regimes (§3.2) exercise
disjoint code paths and a green run on Panda says nothing about Emotion.

---

## 10. UNVERIFIED register — five items, one probe each

| # | Claim | One probe that settles it |
|---|---|---|
| U1 | Turbopack's `middleware-turbopack.js` accepts the identical `__nextjs_original-stack-frames` body as webpack's | `next dev` with and without `--turbopack`; POST the same body; diff the two `originalStackFrame` objects |
| U2 | `_debugStack` on a **Server Component**'s fiber yields a frame that source-maps to the server module, not to the RSC payload | Render one obviously-attributable Server Component; read `fiber._debugStack.stack` in the browser; POST it with `isServer: true` and see whether `file` is a `src/` path |
| U3 | `React.captureOwnerStack()` and `fiber._debugStack` give the same top frame | Call both inside one component render, string-compare frame 0 |
| U4 | Next 14 (`reso-landing-app`) requires `lineNumber`/`column` rather than `line1`/`column1` | POST both shapes to that app's dev server; the wrong one should 400, not silently mis-resolve |
| U5 | `CSS.getMatchedStylesForNode`'s `matchedCSSRules` ordering is reliably low→high priority in this Chrome build | Take a node with a known specificity conflict; assert the last-matching rule equals the computed value |

**U2 is the one that most changes the design.** If server-component frames do not resolve, then every
finding on server-rendered markup — which in a Next 16 App Router app is *most of the page* — falls to
rung 3/4 and the modal confidence drops from `MEDIUM` to `LOW`. That would make the `data-component`
convention in §2.5 a dependency rather than a recommendation. **Probe U2 first.**

---

## 11. Per-app adapter table — the only per-app configuration

| | `reso-landing-app` | `reso-management-app` | `reso-web-app` |
|---|---|---|---|
| Next / React | 14.2.11 / 18 | 16.2.6 / 19.2.8 | 15.5.24 / 18 |
| Frame API fields | `lineNumber`/`column` *(U4)* | `line1`/`column1` | `line1`/`column1` *(verify)* |
| Fiber debug fields | `_debugSource` **present** (18.3.1, 11 hits; `jsxDEV(type,config,key,source,self)`) — exact, no source map needed | `_debugStack` + `_debugOwner` only; source map **required** | `_debugSource` present (18.2.0), same as landing |
| Class inverter | Tailwind 3 literal | Panda map from `css.mjs` **+** Tailwind 4 literal | **none** — needs `compiler.emotion.autoLabel` |
| Expected modal verdict | `MEDIUM` (`VENDOR` on template components) | `MEDIUM` (`shared_with ≥ 1` dominates) | `LOW` until Emotion labels are on |
| Highest-value app-side change | none | a `data-component` convention (§2.5) | **`compiler: { emotion: { autoLabel: 'dev-only' } }`** — one line |

⚠️ **React 18 keeps `_debugSource`, React 19 does not.** Two of the three apps are on React 18 today,
so the *simplest* mechanism still works on them — and will stop working the moment either upgrades.
Build rung 1 as owner-stack-first with `_debugSource` as a **fast path**, never the reverse: a
resolver written against `_debugSource` is a resolver with a scheduled expiry date, and the upgrade
that kills it will look like an unrelated regression.
