// sheet.ts <ladder.ts> <out.ans> <maxRows> <ageS> <ladder.json> <cells...> : the band's first
// screen per band width, side by side (each tile `cells` wide plus a 2-cell gutter), labelled.
import { readFileSync, writeFileSync } from 'fs'
const [modPath, out, mr, age, lp, ...cs] = process.argv.slice(2)
const mod = await import(modPath)
const L = JSON.parse(readFileSync(lp, 'utf8'))
const maxRows = Number(mr), ageS = Number(age)
const vis = (s: string) => [...s.replace(/\x1b\[[0-9;]*m/g, '')].length
const tiles = cs.map(Number).map(c => {
  const { head, variant: v } = mod.bandLayout(L, c, maxRows, ageS, 300, 3600)
  const all = [...head, ...(v?.lines ?? [])]
  const rows = all.length > maxRows ? [...all.slice(0, maxRows - 1), `\x1b[38;2;120;120;140m↓ ${all.length - maxRows + 1} more\x1b[0m`] : all
  const tag = `${c}c ${v ? (v.terse ? 't' : 'd') + v.cells : '-'} ${all.length}r`
  return { c, rows: [`\x1b[1;38;2;121;192;255m${tag.slice(0, c)}\x1b[0m`, ...rows] }
})
const H = Math.max(...tiles.map(t => t.rows.length))
const lines: string[] = []
for (let y = 0; y < H; y++) {
  lines.push(tiles.map(t => {
    const r = t.rows[y] ?? ''
    return r + '\x1b[0m' + ' '.repeat(Math.max(0, t.c - vis(r))) + '\x1b[38;2;248;81;73m│\x1b[0m'
  }).join(' '))
}
writeFileSync(out, lines.join('\n') + '\n')
console.log(tiles.reduce((a, t) => a + t.c + 2, 0))
