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
// The transcript readout has no height cap (it scrolls with the transcript), so it draws the FULL
// family only; the dense one exists for the height-capped band (pickFit).
export const pickVariant = (ladder: Ladder, columns: number): Variant | undefined => {
  const { from, cells } = ladder.budget
  const at = Math.max(0, Math.min(cells.length - 1, Math.floor(columns) - from))
  const budget = cells[at] ?? 0
  const full = ladder.variants.filter(v => !v.dense)
  const pool = full.length > 0 ? full : ladder.variants
  let best = pool[0]
  for (const v of pool) if (v.cells <= budget) best = v
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

// THE SESSIONSTART BOARD AS A BAND (2026-10-21). A band never scrolls away, so it needs no
// survive-one-split budget (docs/research/accounts-board-band-2026-10-21/): the widest layout whose
// widest line fits the band's own cells; failing any fit, the narrowest there is, which drawBand
// WRAPS (2026-10-22: the ladder starts at 7 cells, so that is a band under 7, or an old ladder).
//
// AND ITS HEIGHT (2026-10-22). Claude Code caps the band at `maxRows` (about half the pane: 10 on a
// 30-row pane, 17 on 45, 30 on 70, measured on 2.1.293, docs/research/accounts-narrow-2026-10-22/)
// and scrolls a taller tree inside it behind a `↓ N more` row, accounts below the fold. A tree of
// exactly `maxRows` rows shows whole, with no cue (measured, captures/r4x-live-rows45-roomfull/):
// the cue takes a row only from a tree that is already too tall. So among the layouts that fit the
// width, the widest whose rows (with `headRows` above it) fit `maxRows`; failing that, the fullest
// whose ACCOUNT rows fit above the cue (`values`: the rows through the last account, so the cut
// falls in its alerts); failing that, the one with the fewest rows (ties: the widest). Both
// families compete: the dense one (`dense: true`) is how a narrow band keeps every account on its
// first screen. No `maxRows` (0, absent) is no height cap. Where both families fit, the FULL one
// wins at any width: it says more, and ranking on width alone flipped the family as a tall band
// widened (live rows, maxRows 30: full at 17 cells, dense at 20 for one cell of width, full again
// at 22).
const wider = (a: Variant, b: Variant) =>
  a.width !== b.width ? a.width > b.width
    : !!a.dense !== !!b.dense ? !a.dense
      : a.cells > b.cells
// TERSE (2026-10-22): a dense layout that spends rows on saying what its numbers are (the column
// form's `reset` key row under ~17 cells) ships a `terse` sibling without them. Any labelled layout
// is fuller than any terse one, whatever their widths: the labelled layout for a width may be an
// earlier, narrower variant the ladder deduplicated into (identical lines), so a width-first rank
// would hand a wider terse sibling a band its labelled one fits. The terse one is drawn only where
// no labelled one fits the height (or keeps its accounts above the cue), and wins on rows alone.
const fuller = (a: Variant, b: Variant) =>
  !!a.dense !== !!b.dense ? !a.dense
    : !!a.terse !== !!b.terse ? !a.terse
      : wider(a, b)
// The rows through the last account row; a ladder that does not say is all accounts.
const valueRows = (v: Variant) => v.values ?? v.lines.length

export const pickFit = (ladder: Ladder, cells: number, maxRows?: number, headRows = 0): Variant | undefined => {
  const all = ladder.variants
  const fitW = all.filter(v => v.width <= cells)
  if (fitW.length === 0) {
    return all.reduce<Variant | undefined>((best, v) =>
      !best || v.width < best.width || (v.width === best.width && v.lines.length < best.lines.length)
        ? v : best, undefined)
  }
  const room = maxRows && maxRows > 0 ? maxRows - headRows : Infinity
  const fullest = (vs: Variant[]) => (vs.length > 0 ? vs.reduce((best, v) => (fuller(v, best) ? v : best)) : undefined)
  // Labelled layouts first, whole, then with every account above the cue (a tree taller than the
  // band shows one row fewer: the cue takes its last); a terse sibling only where no labelled one
  // does either (2026-10-22: split lanes gave the fixture a 30-row terse sibling, which took a
  // 70-row band from the full layout whose cut fell only in its alerts).
  for (const fam of [fitW.filter(v => !v.terse), fitW.filter(v => v.terse)]) {
    const got = fullest(fam.filter(v => v.lines.length <= room)) ?? fullest(fam.filter(v => valueRows(v) <= room - 1))
    if (got) return got
  }
  return fitW.reduce((best, v) =>
    v.lines.length < best.lines.length || (v.lines.length === best.lines.length && wider(v, best))
      ? v : best)
}

// Greedy word wrap for the band's own head lines, so Ink never hard-wraps one (`claude-acc|ounts`
// mid-word at a 12-cell band, operator goal 2026-10-22). Words split on spaces; a NBSP binds its
// neighbours (`(5m old)`) unless the bound word is wider than a row, when it gives its NBSPs back.
// A word still wider than a row breaks after a `-` that leaves a fitting piece (`claude-` /
// `accounts`), else at the row edge. Every row after the first takes `cont` as its indent; the
// first keeps the line's own leading spaces. Cells are code points: the head is all single-cell.
const NB = '\u00a0'
const cw = (s: string) => [...s].length

// `edge`: whether a piece was cut at the row edge rather than after a `-` (`withhel` / `d`).
const splitLong = (word: string, width: number): { pieces: string[]; edge: boolean } => {
  const pieces: string[] = []
  let rest = word
  let edge = false
  while (cw(rest) > width) {
    const head = [...rest].slice(0, width).join('')
    const cut = head.lastIndexOf('-')
    const at = cut > 0 ? cut + 1 : head.length
    if (cut <= 0) edge = true
    pieces.push(rest.slice(0, at))
    rest = rest.slice(at)
  }
  if (rest) pieces.push(rest)
  return { pieces, edge }
}

// The rows, and whether any word had to be cut at the row edge (bandHeads offers no such form).
const wrapRows = (line: string, cells: number, cont = ''): { rows: string[]; cut: boolean } => {
  const width = Math.max(1, Math.floor(cells))
  const lead = line.slice(0, line.length - line.trimStart().length)
  const fresh = Math.max(1, width - cw(cont))           // what a continuation row holds
  // `piece`: the rest of a word broken at the row edge, which must start its own row.
  const words: { t: string; piece: boolean }[] = []
  let cut = false
  for (const word of line.trimStart().split(' ')) {
    if (word === '') continue
    const bound = word.split(NB)
    for (const p of cw(word) > fresh && bound.length > 1 ? bound : [word]) {
      const s = cw(p) > fresh ? splitLong(p, fresh) : { pieces: [p], edge: false }
      cut = cut || s.edge
      s.pieces.forEach((t, i) => words.push({ t, piece: i > 0 }))
    }
  }
  const rows: string[] = []
  let cur: string | undefined
  for (const { t, piece } of words) {
    if (cur === undefined) cur = cw(lead + t) <= width ? lead + t : t
    else if (!piece && cw(`${cur} ${t}`) <= width) cur += ` ${t}`
    else { rows.push(cur); cur = cont + t }
  }
  rows.push(cur ?? '')
  return { rows: rows.map(r => r.split(NB).join(' ')), cut }
}

export const wrapWords = (line: string, cells: number, cont = ''): string[] =>
  wrapRows(line, cells, cont).rows

// hooks/accounts-board.sh's fmt_age, so the band labels an age exactly as the hook would.
export const fmtAge = (s: number): string =>
  s < 120 ? `${s}s` : s < 7200 ? `${Math.floor(s / 60)}m` : `${Math.floor(s / 3600)}h`

// The hook's own staleness bands, applied to a band that may sit above the prompt for hours: fresh
// shows the board alone (as the hook does), stale puts the hook's age line over it, and past the
// hard band the numbers are withheld. `grid` false means draw no board lines.
//
// NARROW HEADS (2026-10-22). The hook's sentences cost a 12-cell band 9-15 rows and broke
// `claude-accounts` mid-word, so `forms` lists each head fullest first, every one pre-wrapped to
// `cells` by wrapWords: the hook's own sentences (the stale one with, then without, its blank
// row), and from SHORT_HEAD_CELLS down only the short form (`⚠ stale 5m` / `live:
// claude-accounts`; `numbers withheld (2h old)` / `run claude-accounts`). bandLayout picks one.
export const SHORT_HEAD_CELLS = 25

const wrapHead = (lines: string[], cells: number) => {
  let cut = false
  const rows = lines.flatMap(l => {
    if (l === '') return ['']
    const w = wrapRows(l, cells, l.startsWith('  ') ? '  ' : '')
    cut = cut || w.cut
    return w.rows
  })
  return { rows, cut }
}

// NO HEAD SPLITS A WORD (2026-10-22). At the 7-cell floor (a 12-column pane) `accounts` and
// `withheld` are 8 cells, so the short heads drew `account` / `s` and `withhel` / `d`. A form that
// must cut a word at the row edge is not offered; a cut after a `-` (`claude-` / `accounts`) is a
// word break and stays. Should every form need a cut, the last, the shortest, is kept: a band never
// loses its head.
const wholeForms = (forms: string[][], cells: number): string[][] => {
  const w = forms.map(f => wrapHead(f, cells))
  const whole = w.filter(x => !x.cut).map(x => x.rows)
  return whole.length > 0 ? whole : [w[w.length - 1].rows]
}

export const bandHeads = (ageS: number, staleS: number, hardS: number, cells = Infinity):
    { forms: string[][]; grid: boolean } => {
  const age = fmtAge(ageS)
  const wide = cells >= SHORT_HEAD_CELLS
  if (ageS >= hardS) {
    const long = [
      `accounts board is ${age} old${NB}— numbers withheld as unsafe to read (the 5h window it reports rolls every 5h, so a board this old can describe a window that has ended).`,
      '  For the live table, run: claude-accounts',
    ]
    const short = [`numbers withheld (${age}${NB}old)`, 'run claude-accounts']
    // the verdict and the age in words a 7-cell row holds whole: `numbers` / `hidden` / `(2h` / `old)`
    const tiny = [`numbers hidden (${age}${NB}old)`]
    return { grid: false, forms: wholeForms(wide ? [long, short, tiny] : [short, tiny], cells) }
  }
  if (ageS >= staleS) {
    const long = [`⚠${NB}STALE by ${age}${NB}— the numbers below are last-known, not current.`, '  Live table: claude-accounts']
    const short = [`⚠${NB}stale ${age}`, 'live: claude-accounts']
    // Last resort, for a band whose board fits whole only under a one-row head (30-row pane: the
    // 9-row dense board plus the 2-row short head is 11, one over): the age stays, the hint goes.
    // The short form on one row where it fits (same words, one row fewer) goes before it.
    const one = `⚠ stale ${age} · live: claude-accounts`
    const forms = [...(wide ? [[...long, ''], long] : []), ...(cw(one) <= cells ? [[one]] : []), short,
      [`⚠${NB}stale ${age}`]]
    return { grid: true, forms: wholeForms(forms, cells) }
  }
  return { grid: true, forms: [[]] }
}

// The fullest form, as the hook prints it (a band with no width yet, and the tests' fixed text).
export const bandHead = (ageS: number, staleS: number, hardS: number, cells = Infinity): { head: string[]; grid: boolean } => {
  const { forms, grid } = bandHeads(ageS, staleS, hardS, cells)
  return { grid, head: forms[0] ?? [] }
}

// What the band draws: a head and the board under it, together inside `maxRows`. Each head form
// takes the layout pickFit gives it (the head's rows count against the board's, `headRows`), and
// the pair is ranked: everything shown, over every ACCOUNT shown (the cut in the alerts, 2026-10-22:
// a stale head pushed the last account's weekly row under the fold), over neither; a terse layout
// under every labelled one on either of the first two, as in pickFit. Within a tier, the fuller
// layout (ties: the fuller head, so the hook's sentence stays wherever the board can afford it);
// within the last, the fewest rows in all.
//
// THE STALE TAG SHARES A ROW (2026-10-22). A stale head on a row of its own was the row a 30-row
// pane's band did not have at 15-22 cells (next3 under `↓ 2 more`), and a 45-row one at 22 on the
// fixture. So where no head on its own row keeps the board whole, the tag (`⚠ stale 6m`, else
// `⚠ 6m`) may join a dense layout: at the end of its first lane row with room for it (the renderer
// ships each lane row's cells, `lanes`, so nothing here measures a name), else, the full tag only,
// in the blank lead of the row under the lanes, the legend's, two cells clear of its first word (a
// bare `⚠ 6m` there, judged on screen at 20 cells, read as one of the legend's labels). It is
// ranked with the heads above and wins only on a better tier or a fuller layout: where both tie,
// the head keeps its own row and its words.
const SGR = /\x1b\[[0-9;]*m/y
const leadBlanks = (line: string) => line.replace(/\x1b\[[0-9;]*m/g, '').match(/^ */)?.[0].length ?? 0

// `line` with its first `n` cells, blanks, given to `tag`; its colour sequences kept, after the tag
const setLead = (line: string, tag: string, n: number) => {
  let codes = ''
  let i = 0
  for (let skip = n; i < line.length;) {
    SGR.lastIndex = i
    const m = SGR.exec(line)
    if (m) { codes += m[0]; i += m[0].length; continue }
    if (skip === 0) break
    skip--; i++
  }
  return tag + codes + line.slice(i)
}

const mergeTag = (v: Variant, tag: string, cells: number, lead: boolean): Variant | undefined => {
  const lw = v.dense ? v.lanes : undefined
  if (!lw || lw.length === 0 || lw.length > v.lines.length) return undefined
  const t = cw(tag)
  const lines = [...v.lines]
  // `width` stays the layout's own: it ranks the layout (pickFit), and the row already fits `cells`
  const r = lw.findIndex(w => w + 1 + t <= cells)
  if (r >= 0) {
    lines[r] = `${lines[r]}\x1b[0m ${tag}`
    return { ...v, lines }
  }
  const k = lw.length
  if (lead && k < lines.length && leadBlanks(lines[k]) >= t + 2) {
    lines[k] = setLead(lines[k], tag, t)
    return { ...v, lines }
  }
  return undefined
}

export const bandLayout = (ladder: Ladder, cells: number, maxRows: number | undefined,
    ageS: number, staleS: number, hardS: number): { head: string[]; variant?: Variant } => {
  const { forms, grid } = bandHeads(ageS, staleS, hardS, cells)
  const room = maxRows && maxRows > 0 ? maxRows : Infinity
  const cands: { head: string[]; variant?: Variant }[] = forms.map(head =>
    ({ head, variant: grid ? pickFit(ladder, cells, maxRows, head.length) : undefined }))
  if (grid && ageS >= staleS && ageS < hardS) {
    const age = fmtAge(ageS)
    for (const [tag, lead] of [[`⚠ stale ${age}`, true], [`⚠ ${age}`, false]] as const) {
      const merged = ladder.variants.flatMap(v => (v.width <= cells ? [mergeTag(v, tag, cells, lead)] : []))
        .filter((v): v is Variant => v !== undefined)
      if (merged.length > 0) cands.push({ head: [], variant: pickFit({ ...ladder, variants: merged }, cells, maxRows, 0) })
    }
  }
  let best: { head: string[]; variant?: Variant; tier: number; rows: number } | undefined
  for (const { head, variant } of cands) {
    const rows = head.length + (variant?.lines.length ?? 0)
    // cut, the band shows one row fewer than `maxRows` (the cue takes the last); a terse layout
    // ranks under every labelled one that shows its accounts, as in pickFit
    const shown = rows <= room ? 2 : head.length + (variant ? valueRows(variant) : 0) <= room - 1 ? 1 : 0
    const tier = shown === 0 ? 0 : variant?.terse ? shown : shown + 2
    const better = !best || tier > best.tier || (tier === best.tier && (tier > 0
      ? !!(variant && best.variant && fuller(variant, best.variant))
      : rows < best.rows))
    if (better) best = { head, variant, tier, rows }
  }
  const out = best ?? { head: [] }
  return out.variant ? { head: out.head, variant: out.variant } : { head: out.head }
}
