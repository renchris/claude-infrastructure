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
// NOT generated here: assets/diagrams/convergence-timeline-{dark,light}.svg are built by
// tools/timeline/gen.py (`npm run timeline`) — a hand-authored, CSS-animated two-lane timeline
// that mermaid has no primitive for. This script only ever touches *.mmd-derived outputs, so
// --check neither sees nor reports them; `npm run timeline:check` is their staleness guard.
// (The name previously carried here, handoff-choreography.svg, has never existed in this tree.)
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
// A fence is GENERATED from its .mmd, so a hand-edit to a fence is DISCARDED by the next
// sync. Until 2026-08-11 that discard was silent and the staleness report named only the
// file: 6a55cdf4d landed a re-measured land-lock figure (p50 3s / p90 5s) in README.md's
// fence and never touched parallel-lanes.mmd, so `--check` printed
// "STALE fences in: README.md — run `npm run diagrams`" for 56 consecutive runs while the
// prescribed cure's ONLY effect would have been to delete the newer number and restore the
// figure the commit had just falsified. A cure that reverts the fix is worse than the drift.
// So the report now names the drifting LINES and which side loses them: the reader can see
// that the doc holds the newer truth and port it into the .mmd, which is the actual repair.
const DRIFT_MAX = 12
function fenceDrift(docBody, mmdBody) {
  const a = docBody.split('\n')
  const b = mmdBody.split('\n')
  const out = []
  for (let i = 0; i < Math.max(a.length, b.length) && out.length < DRIFT_MAX; i++) {
    if (a[i] === b[i]) continue
    if (a[i] !== undefined) out.push(`    doc  │ ${a[i]}`)
    if (b[i] !== undefined) out.push(`    mmd  │ ${b[i]}`)
  }
  return out
}

function reportDrift(doc, drifts) {
  console.error(`STALE fence: ${doc}`)
  for (const d of drifts) {
    console.error(`  ${d.relPath} → this fence; the .mmd is the source and OVERWRITES the doc:`)
    for (const line of d.lines) console.error(line)
  }
  console.error(
    '  If a `doc` line is the NEWER truth, port it into the .mmd FIRST — ' +
      '`npm run diagrams` would delete it.',
  )
}

function syncDocFences() {
  const changed = []
  for (const doc of walkMarkdown(ROOT)) {
    const text = readFileSync(doc, 'utf8')
    const drifts = []
    const updated = text.replace(FENCE_RE, (_m, head, relPath, body, tail) => {
      const rendered = applyPalette(readFileSync(join(ROOT, relPath), 'utf8'), 'dark')
      if (rendered !== body) drifts.push({ relPath, lines: fenceDrift(body, rendered) })
      return head + rendered + tail
    })
    if (updated !== text) {
      changed.push(doc.slice(ROOT.length))
      // Print BEFORE the write, on both paths: the sync path is where the doc edit is
      // actually lost, and a loss nobody is shown is the one that reaches trunk.
      reportDrift(doc.slice(ROOT.length), drifts)
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
    // The per-fence drift is already printed by syncDocFences(); this is the summary line.
    console.error(`STALE fences in: ${fenceChanges.join(', ')} — see the drift above`)
    stale++
  }
  if (stale) process.exit(1)
  console.log(`all ${sources.length * VARIANTS.length} SVGs + doc fences up to date`)
} else if (fenceChanges.length) {
  console.log(`synced fences in: ${fenceChanges.join(', ')}`)
}
