#!/usr/bin/env node
// Render assets/diagrams/*.mmd → <name>-dark.svg / <name>-light.svg via
// beautiful-mermaid (the ELK-based engine behind Cursor's agent panel), and keep
// every doc's interactive ```mermaid fence in sync with its .mmd source.
//
// Usage:  npm run diagrams          — (re)render all SVGs + sync fences
//         npm run diagrams:check    — exit 1 if any SVG or fence is stale (CI)
//
// To change a diagram: edit its .mmd in assets/diagrams/, run `npm run diagrams`,
// commit the .mmd + regenerated SVGs + synced docs.
//
// Semantic colors: .mmd classDef lines use @tokens (e.g. fill:@gold-bg) substituted
// per variant from PALETTE below, so ONE source renders with hand-tuned colors on
// BOTH GitHub color modes. Output is deterministic (zero-DOM, bundled font metrics),
// which is what makes the --check byte-equality guard sound.
//
// NOT generated here: assets/diagrams/handoff-choreography.svg is hand-authored
// (CSS-animated; motion is the fact it carries) and has no .mmd source.
import { renderMermaidSVG, THEMES } from 'beautiful-mermaid'
import { readdirSync, readFileSync, writeFileSync, existsSync, statSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { join } from 'node:path'

const ROOT = fileURLToPath(new URL('../', import.meta.url))
const DIR = join(ROOT, 'assets/diagrams/')
const CHECK = process.argv.includes('--check')

const PALETTE = {
  dark: {
    text: '#e6edf3',
    'gold-bg': '#2b2410', 'gold-fg': '#d4af37',
    'green-bg': '#12261a', 'green-fg': '#3fb950',
    'red-bg': '#2b1618', 'red-fg': '#f85149',
    'blue-bg': '#0d1d2e', 'blue-fg': '#58a6ff',
    'gray-bg': '#161b22', 'gray-fg': '#6e7681',
  },
  light: {
    text: '#1f2328',
    'gold-bg': '#fff8c5', 'gold-fg': '#9a6700',
    'green-bg': '#dafbe1', 'green-fg': '#1a7f37',
    'red-bg': '#ffebe9', 'red-fg': '#cf222e',
    'blue-bg': '#ddf4ff', 'blue-fg': '#0969da',
    'gray-bg': '#f6f8fa', 'gray-fg': '#59636e',
  },
}

const VARIANTS = [
  ['dark', THEMES['github-dark']],
  ['light', THEMES['github-light']],
]

function applyPalette(src, variant) {
  return src.replace(/@([a-z][a-z0-9-]*)/g, (match, token) => {
    const value = PALETTE[variant][token]
    if (!value) throw new Error(`unknown palette token ${match} in a .mmd source`)
    return value
  })
}

// .mmd sources stay native-mermaid-valid (angle brackets as &lt;/&gt; so the doc's
// interactive fence renders them); beautiful-mermaid does NOT decode entities, so
// decode before rendering. &amp; is decoded last.
function decodeEntities(src) {
  return src
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&amp;', '&')
}

// GitHub serves doc images through a proxy that blocks external loads, so the
// default Google-Fonts @import can never resolve there. Strip it and pin GitHub's
// own font stack for a native look.
const GITHUB_FONTS =
  '-apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif'
function githubReady(svg) {
  return svg
    .replace(/^\s*@import url\([^\n]*\);\s*$\n?/m, '')
    .replaceAll("'Inter', system-ui, sans-serif", GITHUB_FONTS)
}

// Docs carry a native ```mermaid fence inside <details> as the interactive fallback
// (zoom/pan/select on github.com). Fence bodies are auto-synced from the .mmd
// sources with the DARK palette baked in — native mermaid cannot switch per color
// mode. The marker path is repo-root-relative regardless of the doc's depth.
const FENCE_RE =
  /(<!-- mermaid-fence: (\S+) \(auto-synced by `npm run diagrams`\) -->\n```mermaid\n)([\s\S]*?)(```)/g
const SKIP_DIRS = new Set(['node_modules', '.git', 'tests', 'evolve-fixtures'])
function* walkMarkdown(dir) {
  for (const entry of readdirSync(dir)) {
    const p = join(dir, entry)
    if (statSync(p).isDirectory()) {
      if (!SKIP_DIRS.has(entry) && !entry.startsWith('.')) yield* walkMarkdown(p)
    } else if (entry.endsWith('.md')) yield p
  }
}
function syncDocFences() {
  const changed = []
  for (const doc of walkMarkdown(ROOT)) {
    const text = readFileSync(doc, 'utf8')
    const updated = text.replace(FENCE_RE, (_m, head, relPath, _body, tail) =>
      head + applyPalette(readFileSync(join(ROOT, relPath), 'utf8'), 'dark') + tail,
    )
    if (updated !== text) {
      changed.push(doc.slice(ROOT.length))
      if (!CHECK) writeFileSync(doc, updated)
    }
  }
  return changed
}

const sources = readdirSync(DIR).filter((f) => f.endsWith('.mmd')).sort()
if (sources.length === 0) {
  console.error(`no .mmd sources found in ${DIR}`)
  process.exit(1)
}

let stale = 0
for (const file of sources) {
  const src = readFileSync(join(DIR, file), 'utf8')
  for (const [variant, theme] of VARIANTS) {
    const out = file.replace(/\.mmd$/, `-${variant}.svg`)
    const svg = githubReady(
      renderMermaidSVG(decodeEntities(applyPalette(src, variant)), {
        ...theme,
        transparent: true,
      }),
    )
    const path = join(DIR, out)
    if (CHECK) {
      const current = existsSync(path) ? readFileSync(path, 'utf8') : null
      if (current !== svg) {
        console.error(`STALE: ${out} does not match ${file} — run \`npm run diagrams\``)
        stale++
      }
    } else {
      writeFileSync(path, svg)
      console.log(`rendered ${out} (${(svg.length / 1024).toFixed(1)} KB)`)
    }
  }
}

const fenceChanges = syncDocFences()
if (CHECK) {
  if (fenceChanges.length) {
    console.error(`STALE fences in: ${fenceChanges.join(', ')} — run \`npm run diagrams\``)
    stale++
  }
  if (stale) process.exit(1)
  console.log(`all ${sources.length * VARIANTS.length} SVGs + doc fences up to date`)
} else if (fenceChanges.length) {
  console.log(`synced fences in: ${fenceChanges.join(', ')}`)
}
