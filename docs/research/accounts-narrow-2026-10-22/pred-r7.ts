// pred.ts <mod ladder.ts> <ladder.json> [ageS] : bandLayout per pane rows x columns, as a table row set
import { readFileSync } from 'fs'
const [modPath, ladderPath, age] = process.argv.slice(2)
const mod = await import(modPath)
const L = JSON.parse(readFileSync(ladderPath, 'utf8'))
const ageS = Number(age ?? 10)
const widths = [80, 40, 34, 30, 27, 22, 21, 20, 17, 16, 15, 13, 12]
for (const [rows, maxRows] of [[30, 10], [45, 17], [70, 30]]) {
  const cells: string[] = []
  for (const cols of widths) {
    const { head, variant: v } = mod.bandLayout(L, cols - 5, maxRows, ageS, 300, 3600)
    if (!v) { cells.push('—'); continue }
    const n = head.length + v.lines.length
    const vals = head.length + (v.values ?? v.lines.length)
    const ok = n <= maxRows || vals <= maxRows - 1
    const fam = v.terse ? 't' : v.dense ? 'd' : 'f'
    cells.push(`${ok ? '✓' : '✗'} ${fam}${v.cells}/${n}${head.length ? ` h${head.length}` : ''}`)
  }
  console.log(`| ${rows} (${maxRows}) | ${cells.join(' | ')} |`)
}
