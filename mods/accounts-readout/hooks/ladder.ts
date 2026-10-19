import type { Ladder, Variant } from '../types'

// The same test hooks/relay-verbatim.sh makes (`*claude-accounts*--readout*`, less the surfaces
// that print their own output), so the mod draws exactly the calls the hook stops drawing.
export const isReadoutCommand = (command: unknown): boolean =>
  typeof command === 'string' &&
  /claude-accounts[\s\S]*--readout/.test(command) &&
  !/--(pane|narrow|json|ladder)\b/.test(command)

export const isLadder = (value: unknown): value is Ladder => {
  const l = value as Partial<Ladder> | null
  return (
    typeof l === 'object' && l !== null && l.v === 1 && typeof l.written_ms === 'number' &&
    typeof l.gutter === 'number' && Array.isArray(l.variants) && l.variants.length > 0 &&
    typeof l.budget?.from === 'number' && Array.isArray(l.budget.cells) && l.budget.cells.length > 0
  )
}

// The layout the renderer itself would draw for a pane `columns` wide: its budget for that width
// (pane_width, shipped in the ladder), then the widest variant laid out within it. A width off
// the budget's ends takes the nearest end. Nothing is measured or computed here but an index.
export const pickVariant = (ladder: Ladder, columns: number): Variant | undefined => {
  const { from, cells } = ladder.budget
  const at = Math.max(0, Math.min(cells.length - 1, Math.floor(columns) - from))
  const budget = cells[at] ?? 0
  let best = ladder.variants[0]
  for (const v of ladder.variants) if (v.cells <= budget) best = v
  return best
}

export type Span = { text: string; color?: string; bold?: boolean }

// The renderer's palette is three SGR forms (reset, `38;2;r;g;b`, `1;38;2;r;g;b`); read every
// parameter list generically so a new one degrades to plain text, never to a raw escape.
export const spans = (line: string): Span[] => {
  const out: Span[] = []
  let color: string | undefined
  let bold = false
  const re = /\x1b\[([0-9;]*)m/g
  let at = 0
  const push = (text: string) => {
    if (text) out.push({ text, ...(color ? { color } : {}), ...(bold ? { bold } : {}) })
  }
  for (let m = re.exec(line); m; m = re.exec(line)) {
    push(line.slice(at, m.index))
    at = re.lastIndex
    const ps = !m[1] ? [0] : m[1].split(';').map(Number)
    for (let i = 0; i < ps.length; i++) {
      const p = ps[i]
      if (p === 0) { color = undefined; bold = false }
      else if (p === 1) bold = true
      else if (p === 22) bold = false
      else if (p === 39) color = undefined
      else if (p === 38 && ps[i + 1] === 2 && i + 4 < ps.length) {
        const hex = ps.slice(i + 2, i + 5).map(n => Math.max(0, Math.min(255, n)).toString(16).padStart(2, '0'))
        color = `#${hex.join('')}`
        i += 4
      } else if ((p === 38 || p === 48) && ps[i + 1] === 5) i += 2
      else if (p === 48 && ps[i + 1] === 2) i += 4
    }
  }
  push(line.slice(at))
  return out
}
