// predict.ts <mod ladder.ts> <ladder.json> — what the mod's own bandLayout (and the readout's
// pickVariant) picks over a real ladder, at every band width the probe drives and at the band
// heights measured on Claude Code 2.1.293 (maxRows 10 / 17 / 30 on a 30 / 45 / 70-row pane).
// Fresh board (ageS 10), so no head. Prints one JSON object for summarize.py.
import { readFileSync } from 'fs'

const [modPath, ladderPath] = process.argv.slice(2)
const mod = await import(modPath)
const L = JSON.parse(readFileSync(ladderPath, 'utf8'))
const out: Record<string, unknown> = {}
for (const maxRows of [10, 17, 30]) {
  for (let cols = 10; cols <= 90; cols++) {
    const cells = cols - 5
    const { head, variant } = mod.bandLayout(L, cells, maxRows, 10, 300, 3600)
    out[`${maxRows}:${cols}`] = variant
      ? { head: head.length, cells: variant.cells, width: variant.width, dense: !!variant.dense, lines: variant.lines.length }
      : { head: head.length }
  }
}
for (let cols = 10; cols <= 90; cols++) {
  const v = mod.pickVariant(L, cols)
  out[`readout:${cols}`] = v ? { cells: v.cells, width: v.width, dense: !!v.dense, lines: v.lines.length } : null
}
console.log(JSON.stringify(out))
