---
name: beautiful-mermaid-docs
description: Pre-render Mermaid diagrams as beautiful-mermaid SVGs (the ELK-based engine behind Cursor's agent panel, MIT by Craft/Luki Labs) for READMEs and human-facing docs, with adaptive dark/light <picture> embeds, an npm render script, and a CI staleness guard. Use when asked to "use beautiful-mermaid", "beautify the README diagrams", "Cursor-style/quality diagrams", "pre-render mermaid", or to add high-quality diagrams to a repo's README/docs that GitHub will display. NOT for app-runtime diagram rendering (just `npm install beautiful-mermaid` and call renderMermaidSVG directly) or terminal output (renderMermaidASCII).
---

# beautiful-mermaid docs pipeline

Replace native ` ```mermaid ` blocks in README/docs with pre-rendered beautiful-mermaid
SVGs so GitHub (which can't swap its dagre-based renderer) shows Cursor-agent-quality,
theme-adaptive diagrams. Reference implementation (proven end-to-end):
`/Users/chrisren/Development/mistral-4-fable-ocr` commits `ddc4540` (research) +
`4ceac24` (pipeline). Full background:
`mistral-4-fable-ocr/docs/research/beautiful-mermaid-cursor-renderer.md`.

## Load-bearing facts (verified 2026-07-10, beautiful-mermaid 1.1.3)

- **Supported types (published 1.1.3)**: `flowchart`/`graph` (TD|TB|LR|BT|RL),
  `stateDiagram(-v2)`, `xychart` ONLY. Sequence/class/ER exist upstream but are
  unreleased. Anything else → keep as native ` ```mermaid ` block (GitHub fallback).
  Re-check `npm view beautiful-mermaid version` — newer releases may widen this.
- **HTML entities are NOT decoded** (`&middot;` renders literally). Policy for `.mmd`
  sources (must stay valid for BOTH engines, since the README interactive fence feeds
  native mermaid): typographic entities → literal Unicode (`&middot;`→`·`, `&equiv;`→`≡`,
  `&rarr;`→`→`); but **angle-bracket text stays entity-encoded** (`&lt;cmd&gt;`) because
  native mermaid swallows literal `<cmd>` as an unknown HTML tag. The render script
  decodes entities (`decodeEntities()` — `&lt; &gt; &quot;` then `&amp;` last) before
  calling beautiful-mermaid. `<br/>`, `<i>`, `<b>` pass through both engines correctly.
- **Parser needs the header on its own line** (`graph LR; A-->B` one-liners throw).
- **ESM-only package** — script must be `.mjs` or repo `"type": "module"`.
- **Default font is a Google-Fonts `@import`** which GitHub's image proxy blocks —
  strip it and pin GitHub's system font stack (the render script below does this).
- **`THEMES['github-dark']` / `THEMES['github-light']`** are GitHub's exact palettes
  (`#0d1117`/`#e6edf3`, `#ffffff`/`#1f2328`); render with `transparent: true` so the
  page background shows through.
- **Output is deterministic** (zero-DOM, bundled font metrics) — safe for a CI
  byte-equality staleness check. Verify once per version bump: render twice, diff.
- Generated SVGs are GitHub-`<img>`-safe: one inline `<style>`, CSS vars +
  `color-mix()`, no scripts/foreignObject/external refs (after `@import` strip).

### Syntax matrix (probed empirically, 1.1.3 — second application: agent-secrets)

- **Works**: `-->|"l"|`, `-.->|"l"|`, `-. "l" .->`, chained `A --> B ==> C`,
  bidirectional `<-->`, subgraph→subgraph labeled edges, `<br/>` in node AND
  edge labels, `<i>`/`<b>` (render as real italic/bold), emoji, cylinder
  `[( )]`, circle `(( ))`, stadium `([ ])`, diamond `{ }`, `subgraph` with
  quoted titles (titled group boxes; `direction` inside a subgraph is honored
  when the subgraph has internal edges), `linkStyle`. (Third application,
  doc_classifier: 10 flowcharts across 5 docs at 3 directory depths — its
  `scripts/render-diagrams.mjs` has the multi-document fence-sync walker;
  marker paths stay repo-root-relative regardless of embedding depth.)
- **Breaks silently — fix in source**:
  - Trailing `;` on `classDef`/`class` lines → parsed as a phantom node named
    "class", styles dropped. Strip all trailing semicolons.
  - `x--x` cross edges → the edge AND its target node vanish. Replace with a
    labeled dotted edge (e.g. `-.->|"✗ never written"|`).
  - Literal `[` `]` inside a `[...]` node label (e.g. `ENC[…]`) → bracket
    matcher corrupts the label (stray quote, truncation). Use fullwidth
    `［ ］` (U+FF3B/FF3D) — visually equivalent, parser-safe.
  - `%%{init: ...}%%` directives are ignored (harmless) — delete them; theming
    comes from render options.
- **Degrades gracefully**: `==>` thick edges render as normal edges.

### Per-variant semantic colors (@palette tokens)

If diagrams carry semantic `classDef` colors (green=ok, red=leak, gold=key…),
hardcoded hex values tuned for one GitHub mode look wrong in the other. Use
the token pattern from `agent-secrets/scripts/render-diagrams.mjs`: `.mmd`
classDefs reference `@tokens` (`fill:@green-bg,stroke:@green-fg,color:@text`),
and the script substitutes a per-variant PALETTE (dark/light) before
rendering. One source, hand-tuned colors on both modes; determinism and the
CI check are unaffected.

## Procedure

1. **Inventory.** Find all ` ```mermaid ` blocks in README + human-facing docs
   (`grep -rn '```mermaid' README.md docs/`). Classify each: supported type → migrate;
   unsupported → leave native, note it.
2. **Sources.** Create `assets/diagrams/<name>.mmd` per diagram (kebab-case, named by
   meaning not position), entities converted. These stay the reviewable source of truth.
3. **Tooling.** Add root `package.json` (`"private": true`, `"type": "module"`, exact-pin
   `beautiful-mermaid`) with scripts `diagrams` / `diagrams:check`. Non-Node repos: this
   self-contained addition is fine (proven in a docs/shell repo). Node repos: use the
   repo's existing package manager per its lockfile, add as devDependency. Commit the
   lockfile — CI `npm ci` requires it. Add `node_modules/` to `.gitignore` if absent.
4. **Render script.** Copy `scripts/render-diagrams.mjs` from the reference repo
   verbatim (≈65 lines; renders every `.mmd` → `<name>-dark.svg` + `<name>-light.svg`,
   github themes + `transparent: true`, strips `@import`, pins GitHub font stack,
   `--check` mode exits 1 on stale). Run `npm run diagrams`.
5. **Embed.** Replace each migrated block with (use Edit, never rewrite the file):

   ```html
   <!-- Diagram source: assets/diagrams/<name>.mmd — edit it, run `npm run diagrams`, commit the regenerated SVGs. -->
   <picture>
     <source media="(prefers-color-scheme: dark)" srcset="assets/diagrams/<name>-dark.svg">
     <img src="assets/diagrams/<name>-light.svg" alt="<full prose description of the flow>">
   </picture>
   ```

   Paths are relative to the embedding file — adjust for docs in subdirectories.
5b. **Interactivity fallback (recovers native mermaid's zoom/pan/text-selection,
   full-screen, and copy-source).** Static `<img>` SVGs are inert — GitHub strips all
   JS from READMEs. Under each `<picture>`, add a collapsed `<details>`:

   ```html
   <details>
   <summary>Interactive Diagram</summary>

   <!-- mermaid-fence: assets/diagrams/<name>.mmd (auto-synced by `npm run diagrams`) -->
   ```mermaid
   ```

   <sup><a href="assets/diagrams/<name>-dark.svg?raw=true">full-screen dark</a> · <a href="assets/diagrams/<name>-light.svg?raw=true">light</a> · <a href="assets/diagrams/<name>.mmd">source</a></sup>

   </details>
   ```

   Keep the `<summary>` to exactly "Interactive Diagram" — no feature explanation
   (user feedback 2026-07-10: don't explain the affordances in the summary; and
   "Interactive version" was rejected as misleading — version of what?). The compact
   `<sup>` footer inside the expanded body carries the full-screen SVG links and
   the source link (its blob page's "Copy raw file" = the mermaid markdown).

   The fence body is FILLED AND KEPT IN SYNC by the render script (`syncReadmeFences()`
   in either reference repo — regex on the `mermaid-fence:` marker; `--check` fails on
   drift). Expanded, GitHub renders it as native interactive mermaid (zoom/pan controls,
   selectable text); `?raw=true` links open the SVG full-tab (browser zoom, selectable);
   the `.mmd` blob page's "Copy raw file" button copies the markdown. For repos with
   @palette tokens, sync the fence with the DARK palette baked (native mermaid can't
   switch per color mode).
6. **CI guard.** Copy `.github/workflows/diagrams.yml` from the reference repo
   (path-filtered on diagram files; `npm ci` + `npm run diagrams:check`). This makes
   "edited .mmd, forgot to re-render" a CI failure instead of tribal knowledge.
7. **Verify.** (a) `npm run diagrams:check` passes; (b) run `npm run diagrams` twice —
   `git diff` stays clean (determinism); (c) screenshot both variants via headless
   Chrome on GitHub bg colors (`--default-background-color=0d1117ff` / `ffffffff`) and
   LOOK at them: entities as real glyphs, labels unclipped, classDef colors intact.
8. **Repo-specific wiring.** If the repo mirrors/syncs docs elsewhere (e.g.
   mistral-4-fable-ocr's `sync-to-github.sh`), add package.json, lockfile, render
   script, and workflow to the sync list. Commit everything as one atomic commit.

## Do NOT

- Do NOT feed sequence/class/ER/gantt/pie to beautiful-mermaid 1.1.3 — parse error.
  Gate by header; keep unsupported diagrams as native mermaid blocks.
- Do NOT leave `&middot;`-style entities in `.mmd` sources — they render literally.
- Do NOT hand-edit generated `-dark.svg`/`-light.svg` files — they're build outputs;
  the CI check will (correctly) fail.
- Do NOT delete the `.mmd` when embedding the SVG — it is the only reviewable diff
  and the only path back to native mermaid.
- Do NOT rely on the library's font `@import` on GitHub — external loads are blocked
  in `<img>` contexts; strip it (script handles this).
- Do NOT run repo sync/publish scripts that push — pushing is the user's explicit call.
- Do NOT reach for `@mermaid-js/layout-elk` expecting the same look — it swaps layout
  only (still dagre-era visuals/theming); beautiful-mermaid is parser+layout+SVG+theme.
