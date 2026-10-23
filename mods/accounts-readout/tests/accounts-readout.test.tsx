import { describe, expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'

import { bandHead, bandHeads, bandLayout, fmtAge, isReadoutCommand, pickFit, pickVariant, spans, wrapWords } from '../hooks/ladder'
import type { Ladder, Variant } from '../types'

// A two-layout ladder in the renderer's shape: a stacked 35-cell layout and a 70-cell grid.
const GRID = '   account live   used resets   used  fable  resets  login'
// Its budget: 35 cells below a 100-column pane, 70 from there (the renderer ships the real one).
const LADDER: Ladder = {
  v: 1, written_ms: 1_000_000, gutter: 5,
  budget: { from: 40, cells: Array.from({ length: 161 }, (_, i) => (i + 40 >= 100 ? 70 : 35)) },
  variants: [
    { cells: 35, width: 35, lines: ['\x1b[1;38;2;230;237;243m➤ desk → next3\x1b[0m', '   next    5h    2%       3h 59m'] },
    { cells: 70, width: GRID.length, lines: ['\x1b[1;38;2;230;237;243m➤ desk (bare claude) → next3\x1b[0m', GRID] },
  ],
}
const SID = 'sid-123'
const TUID = 'toolu_accounts_1'
const COMMAND = 'claude-accounts --readout'

const world = (on: On, ladderText: string) => {
  const files: Record<string, string> = { [`/tmp/claude-accounts-pane/${SID}.ladder.json`]: ladderText }
  mock.clock(on, { now: 1_000_500 })
  mock.store(on)
  mock.env(on, {})
  on('session.id', () => ({ value: SID }))
  on('fs.write', (_$, e) => { files[e.path] = e.text; return { value: undefined } })
  on('fs.read', (_$, e) => {
    const text = files[e.path]
    return text === undefined ? { deny: `ENOENT ${e.path}` } : { value: text }
  })
  on('tool.call', () => ({ result: { stdout: 'readout', stderr: '' } }) as never)
  on('ui.render', { component: 'ToolGroup' }, ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>Ran 1 shell command</Text>
  })
  return files
}

const group = ($: Engine, columns: number, requestId = `collapsed-${columns}`) =>
  $.ui.mount({
    plugin: 'accounts-readout', surface: 'terminal', component: 'ToolGroup', requestId,
    viewport: { columns, rows: 50 },
    props: {
      calls: [{ tool_use_id: TUID, tool: 'Bash', input: { command: COMMAND }, isRunning: false, isErrored: false, isInterrupted: false }],
      isActive: false, isExpanded: false,
    },
  })

describe('ladder helpers', () => {
  test('the readout command is recognised as relay-verbatim.sh recognises it', () => {
    expect(isReadoutCommand('claude-accounts --readout')).toBe(true)
    expect(isReadoutCommand('~/bin/claude-accounts --fresh --readout')).toBe(true)
    for (const other of ['claude-accounts --readout --pane --cols 80', 'claude-accounts --readout --ladder',
      'claude-accounts --readout --json', 'claude-accounts --readout --narrow', 'claude-accounts --json', 42]) {
      expect(isReadoutCommand(other)).toBe(false)
    }
  })

  test('the layout is the renderer\'s own for that pane width; off the budget, its nearest end', () => {
    expect(pickVariant(LADDER, 160)?.cells).toBe(70)
    expect(pickVariant(LADDER, 100)?.cells).toBe(70)
    expect(pickVariant(LADDER, 99)?.cells).toBe(35)
    expect(pickVariant(LADDER, 40)?.cells).toBe(35)
    expect(pickVariant(LADDER, 20)?.cells).toBe(35)
    expect(pickVariant(LADDER, 999)?.cells).toBe(70)
    const tight = { ...LADDER, budget: { from: 40, cells: [20] } }
    expect(pickVariant(tight, 40)?.cells).toBe(35)
  })

  test('SGR becomes coloured spans, never a raw escape', () => {
    expect(spans('\x1b[1;38;2;230;237;243m➤ desk\x1b[0m rest')).toEqual([
      { text: '➤ desk', color: '#e6edf3', bold: true }, { text: ' rest' },
    ])
    expect(spans('\x1b[38;2;125;133;144mdim\x1b[0m')).toEqual([{ text: 'dim', color: '#7d8590' }])
    expect(spans('plain')).toEqual([{ text: 'plain' }])
  })
})

describe('the drawn readout', () => {
  test('stamps the call, then draws the layout that fits and re-lays it out at a new width', async ($, on) => {
    const files = world(on, JSON.stringify(LADDER))
    await $.tool.call({ tool: 'Bash', tool_use_id: TUID, command: COMMAND } as never)
    expect(files[`/tmp/claude-accounts-pane/${SID}.mod`]).toBe(TUID)

    const wide = await group($, 160)
    expect((await wide.find({ text: /Ran 1 shell command/ }))).toBeDefined()
    expect((await wide.find({ text: /account live/ }))).toBeDefined()
    expect((await wide.find({ text: /desk \(bare claude\)/ }))).toBeDefined()

    const narrow = await group($, 40)
    expect((await narrow.find({ text: /account live/ }))).toBeUndefined()
    expect((await narrow.find({ text: /next    5h/ }))).toBeDefined()
  })

  test('a stale ladder (an earlier readout) is never drawn', async ($, on) => {
    world(on, JSON.stringify({ ...LADDER, written_ms: 1 }))
    await $.tool.call({ tool: 'Bash', tool_use_id: TUID, command: COMMAND } as never)
    const drawn = await group($, 160)
    expect((await drawn.find({ text: /account live/ }))).toBeUndefined()
    expect((await drawn.find({ text: /Ran 1 shell command/ }))).toBeDefined()
  })

  test('another shell command is left to the engine', async ($, on) => {
    const files = world(on, JSON.stringify(LADDER))
    await $.tool.call({ tool: 'Bash', tool_use_id: 'toolu_other', command: 'ls' } as never)
    expect(files[`/tmp/claude-accounts-pane/${SID}.mod`]).toBeUndefined()
  })
})

// ── the SessionStart board, as a band above the prompt ────────────────────────────────────────
const DIR = '/tmp/claude-accounts-pane'
const REQ = `${DIR}/${SID}.board-band.req`
const SNAP = `${DIR}/${SID}.board-band.json`
const NOW = 2_000_000_000

// `hookWrites` is what hooks/accounts-board.sh does beneath the mod: given the stamp naming this
// session, it leaves the snapshot (and so prints no grid); otherwise it leaves nothing.
const bandWorld = (on: On, opts: { hookWrites?: string; ageS?: number; env?: Record<string, string> } = {}) => {
  const files: Record<string, string> = {}
  const seen: { reqAtHook?: string } = {}
  const clock = mock.clock(on, { now: NOW })
  mock.store(on)
  mock.env(on, opts.env ?? {})
  on('session.surfaces', () => ({ value: ['terminal'] }) as never)
  on('fs.write', (_$, e) => { files[e.path] = e.text; return { value: undefined } })
  on('fs.read', (_$, e) => {
    const text = files[e.path]
    return text === undefined ? { deny: `ENOENT ${e.path}` } : { value: text }
  })
  on('fs.stat', (_$, e) => ({
    value: { kind: 'file', size: (files[e.path] ?? '').length, mtimeMs: NOW - (opts.ageS ?? 10) * 1000, isLink: false },
  }) as never)
  on('classic.SessionStart', (_$, e) => {
    seen.reqAtHook = files[REQ]
    if (opts.hookWrites !== undefined && files[REQ] === e.session_id) files[SNAP] = opts.hookWrites
    return {}
  })
  on('prompt.submit', (_$, e) => ({ text: e.text }) as never)
  on('ui.render', { component: 'AbovePrompt' }, ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine band</Text>
  })
  return { files, seen, clock }
}

const band = ($: Engine, columns: number, extra: { hasSurvey?: boolean; maxRows?: number } = {}) =>
  $.ui.mount({
    plugin: 'accounts-readout', surface: 'terminal', component: 'AbovePrompt',
    viewport: { columns, rows: 50 },
    props: {
      hasSurvey: extra.hasSurvey ?? false, isWorking: false, maxRows: extra.maxRows ?? 25, bodyColumns: columns - 5,
      scroll: { offset: 0, bodyRows: (extra.maxRows ?? 25) - 1 }, view: {},
    },
  } as never)

// A two-family ladder in the producer's shape since 2026-10-22 (bin/claude-accounts pane_ladder):
// the dense family first, each family narrowest first. Full: a 35-cell stack (20 rows) and a
// 70-cell grid (14 rows). Dense: 8 cells (27 rows), 22-cell cards (8 rows), 40-cell table (6 rows).
const rows = (n: number, first: string) => [first, ...Array.from({ length: n - 1 }, (_, i) => `row ${i}`)]
const v = (cells: number, width: number, n: number, first: string, dense?: true): Variant =>
  ({ cells, width, lines: rows(n, first), ...(dense ? { dense } : {}) })
const TWO: Ladder = {
  ...LADDER,
  variants: [
    v(8, 8, 27, 'DENSE floor', true), v(22, 22, 8, 'DENSE cards', true), v(40, 40, 6, 'DENSE table', true),
    v(35, 35, 20, 'FULL stack'), v(70, 70, 14, 'FULL grid'),
  ],
}
const first = (x: Variant | undefined) => x?.lines[0]

describe('band helpers', () => {
  test('the widest layout whose widest line fits the band, else the narrowest', () => {
    expect(pickFit(LADDER, 155)?.cells).toBe(70)
    expect(pickFit(LADDER, GRID.length)?.cells).toBe(70)
    expect(pickFit(LADDER, GRID.length - 1)?.cells).toBe(35)
    expect(pickFit(LADDER, 10)?.cells).toBe(35)
  })

  test('under a height cap: the widest layout that fits maxRows, the full family first', () => {
    expect(first(pickFit(TWO, 80))).toBe('FULL grid')                 // no cap: the widest
    expect(first(pickFit(TWO, 80, 0))).toBe('FULL grid')              // 0 reads as no cap
    expect(first(pickFit(TWO, 80, 25))).toBe('FULL grid')
    // A tree of exactly maxRows shows whole (measured): no row is kept free for the cue.
    expect(first(pickFit(TWO, 80, 14))).toBe('FULL grid')
    expect(first(pickFit(TWO, 80, 13))).toBe('DENSE table')           // one over: the dense family
    expect(first(pickFit(TWO, 80, 14, 1))).toBe('DENSE table')        // a head row counts too
    // Both families fit: the full one, though the dense table is wider (no family flip-flop).
    expect(first(pickFit(TWO, 50, 25))).toBe('FULL stack')
    expect(first(pickFit(TWO, 30, 25))).toBe('DENSE cards')           // only dense fits the width
    expect(first(pickFit(TWO, 30, 7))).toBe('DENSE cards')            // nothing fits: fewest rows
    expect(first(pickFit(TWO, 5, 10))).toBe('DENSE floor')            // nothing fits the width: narrowest
    const tie: Ladder = { ...TWO, variants: [v(30, 30, 12, 'tie narrow', true), v(20, 20, 30, 'tall'), v(34, 34, 12, 'tie wide', true)] }
    expect(first(pickFit(tie, 80, 5))).toBe('tie wide')               // fewest rows, ties: the widest
  })

  // `values`: the rows through the last account. When no layout fits whole, the one whose ACCOUNTS
  // fit above the cue row beats the one with the fewest rows, whose cut would fall in its accounts.
  const ALERTS: Ladder = {
    ...LADDER,
    variants: [{ ...v(30, 30, 20, 'DENSE alerts', true), values: 8 }, v(70, 70, 14, 'FULL grid')],
  }

  test('nothing fits whole: the layout whose accounts fit above the cue, else the fewest rows', () => {
    expect(first(pickFit(ALERTS, 80, 9))).toBe('DENSE alerts')        // 8 account rows + the cue
    expect(first(pickFit(ALERTS, 80, 8))).toBe('FULL grid')           // the cue would take row 8
    expect(first(pickFit(ALERTS, 80, 9, 1))).toBe('FULL grid')        // a head row counts too
    // A stale band keeps its accounts on screen under a one-row head, its alerts cut, rather than
    // the two-row head over a layout whose accounts fall under the fold.
    expect(bandLayout(ALERTS, 80, 10, 400, 300, 3600))
      .toEqual({ head: ['⚠ stale 6m · live: claude-accounts'], variant: ALERTS.variants[0] })
  })

  // THE CUE ROW, SETTLED BY MEASUREMENT (docs/research/accounts-narrow-2026-10-22/, rounds 4 and 6):
  // a tree of at most maxRows rows shows whole with no cue, and a taller one shows maxRows - 1 rows
  // and the `↓ N more` cue (9 + 1 on a 30-row pane, 16 + 1 on 45, 29 + 1 on 70). So "every account
  // shown" for a tree that is cut means head + account rows <= maxRows - 1, in bandLayout as in
  // pickFit. Each case kills one mutant of bandLayout's own term: `room` (the 2-row hook sentence
  // over 8 account rows, the 8th then under the cue, would read as all accounts shown) and
  // `room - 2` (the one-row head that does keep every account would read as cutting one).
  test('a cut band shows maxRows - 1 rows: account rows count against that, not maxRows', () => {
    const cut: Ladder = { ...LADDER, variants: [{ ...v(30, 30, 12, 'DENSE cut', true), values: 8 }] }
    expect(bandLayout(cut, 80, 10, 400, 300, 3600))
      .toEqual({ head: ['⚠ stale 6m · live: claude-accounts'], variant: cut.variants[0] })
    const two: Ladder = {
      ...LADDER,
      variants: [v(20, 20, 11, 'DENSE short'), { ...v(30, 30, 12, 'DENSE cut', true), values: 8 }],
    }
    expect(bandLayout(two, 80, 10, 400, 300, 3600))
      .toEqual({ head: ['⚠ stale 6m · live: claude-accounts'], variant: two.variants[1] })
  })

  // TERSE (2026-10-22): the column form's labelled `reset` key costs a row under ~17 cells, so the
  // producer ships a terse sibling at the same width. Labels wherever the band's height holds them,
  // the terse one only where it does not: a label never costs an account the first screen.
  test('a terse sibling is drawn only where the labelled layout does not fit the height', () => {
    const T: Ladder = {
      ...LADDER,
      variants: [
        v(12, 12, 14, 'DENSE three rows', true),
        v(15, 15, 11, 'DENSE labelled', true), { ...v(15, 15, 10, 'DENSE terse', true), terse: true },
        v(35, 35, 20, 'FULL stack'),
      ],
    }
    expect(first(pickFit(T, 15, 11))).toBe('DENSE labelled')          // both fit: the labelled one
    expect(first(pickFit(T, 15, 17))).toBe('DENSE labelled')
    expect(first(pickFit(T, 15, 10))).toBe('DENSE terse')             // one row short: every account shown
    expect(first(pickFit(T, 15, 8))).toBe('DENSE terse')              // nothing fits: the fewest rows
    expect(first(pickFit(T, 80))).toBe('FULL stack')                  // the transcript family is untouched
    // the ladder's order does not decide it
    const R: Ladder = { ...T, variants: [T.variants[0], T.variants[2], T.variants[1], T.variants[3]] }
    expect(first(pickFit(R, 15, 11))).toBe('DENSE labelled')
    expect(first(bandLayout(R, 15, 11, 10, 300, 3600).variant)).toBe('DENSE labelled')
    expect(first(bandLayout(R, 15, 10, 10, 300, 3600).variant)).toBe('DENSE terse')
    // The labelled layout for a width may be an earlier, narrower variant (the ladder dedups
    // identical lines): it still beats a wider terse sibling wherever it fits the height.
    const D: Ladder = {
      ...LADDER,
      variants: [v(28, 26, 8, 'DENSE labelled 28', true), { ...v(30, 30, 7, 'DENSE terse 30', true), terse: true }],
    }
    expect(first(pickFit(D, 30, 10))).toBe('DENSE labelled 28')
    expect(first(pickFit(D, 30, 7))).toBe('DENSE terse 30')
    // A labelled layout whose cut falls only in its alerts outranks a terse one that fits whole
    // (2026-10-22: the fixture's split-lane terse sibling took a 70-row band from the full layout).
    const A: Ladder = {
      ...LADDER,
      variants: [{ ...v(29, 29, 30, 'DENSE terse whole', true), terse: true }, { ...v(29, 29, 45, 'FULL alerts cut'), values: 20 }],
    }
    expect(first(pickFit(A, 29, 30))).toBe('FULL alerts cut')
    expect(first(bandLayout(A, 29, 30, 10, 300, 3600).variant)).toBe('FULL alerts cut')
    expect(first(pickFit(A, 29, 20))).toBe('DENSE terse whole')       // no labelled one shows every account
  })

  test('a ladder from before the dense family picks as it always did', () => {
    expect(pickFit(LADDER, 155, 10)?.cells).toBe(70)
    expect(pickFit(LADDER, 155, 1)?.cells).toBe(70)                   // none fits: fewest, then widest
    expect(pickFit(LADDER, GRID.length - 1, 10)?.cells).toBe(35)
    expect(pickFit(LADDER, 10, 10)?.cells).toBe(35)
  })

  test('the transcript readout ignores the dense family', () => {
    // Budget 35 below 100 columns: the old reader took the LAST variant within it, which here is
    // a dense one; the full family's own pick is the 35-cell stack.
    const after: Ladder = { ...TWO, variants: [v(35, 35, 20, 'FULL stack'), v(30, 30, 8, 'DENSE late', true), v(70, 70, 14, 'FULL grid')] }
    expect(first(pickVariant(after, 60))).toBe('FULL stack')
    expect(first(pickVariant(after, 160))).toBe('FULL grid')
    expect(first(pickVariant(TWO, 60))).toBe('FULL stack')
    // A budget under every full variant: the narrowest FULL one, never the 8-cell dense floor.
    expect(first(pickVariant({ ...TWO, budget: { from: 40, cells: [20] } }, 40))).toBe('FULL stack')
    // A ladder with no full family at all still draws something.
    expect(first(pickVariant({ ...TWO, variants: TWO.variants.filter(x => x.dense) }, 160))).toBe('DENSE table')
  })

  test('narrow heads are short and pre-wrapped at word boundaries, never mid-word', () => {
    const stale = bandHeads(400, 300, 3600, 22).forms
    expect(stale[0]).toEqual(['⚠ stale 6m', 'live: claude-accounts'])
    expect(stale.flat().some(l => /STALE by/.test(l))).toBe(false)
    expect(bandHeads(400, 300, 3600, 12).forms[0]).toEqual(['⚠ stale 6m', 'live:', 'claude-', 'accounts'])
    expect(bandHeads(400, 300, 3600, 8).forms[0]).toEqual(['⚠ stale', '6m', 'live:', 'claude-', 'accounts'])
    expect(bandHeads(7300, 300, 3600, 20).forms[0]).toEqual(['numbers withheld', '(2h old)', 'run claude-accounts'])
    expect(bandHeads(7300, 300, 3600, 8).forms[0]).toEqual(['numbers', 'withheld', '(2h old)', 'run', 'claude-', 'accounts'])
    // From SHORT_HEAD_CELLS up the hook's own sentence leads, wrapped; with no width, as the hook prints it.
    expect(bandHeads(400, 300, 3600, 40).forms[0]?.[0]).toBe('⚠ STALE by 6m — the numbers below are')
    expect(bandHead(400, 300, 3600).head[0]).toBe('⚠ STALE by 6m — the numbers below are last-known, not current.')
  })

  // THE 7-CELL FLOOR (2026-10-22): `accounts` and `withheld` are 8 cells, and the short heads drew
  // `account` / `s` and `withhel` / `d` at a 12-column pane's band. Only forms whose every word a
  // row holds are offered there; at 8 the fuller ones come back.
  test('no head cuts a word at the row edge, down to the 7-cell floor', () => {
    expect(bandHeads(400, 300, 3600, 7).forms).toEqual([['⚠ stale', '6m']])
    expect(bandHeads(7300, 300, 3600, 7).forms).toEqual([['numbers', 'hidden', '(2h', 'old)']])
    expect(bandHeads(86_400, 300, 3600, 7).forms).toEqual([['numbers', 'hidden', '(24h', 'old)']])
    expect(bandLayout(TWO, 7, 40, 7300, 300, 3600)).toEqual({ head: ['numbers', 'hidden', '(2h', 'old)'] })
    expect(bandHeads(7300, 300, 3600, 8).forms[0]).toEqual(['numbers', 'withheld', '(2h old)', 'run', 'claude-', 'accounts'])
  })

  test('every head row fits its band, and unwraps to the words it came from', () => {
    const norm = (f: string[]) => f.filter(l => l !== '').join('\n').replace(/-\n\s*/g, '-').replace(/\s*\n\s*/g, ' ').trim()
    for (const age of [400, 7300, 86_400]) {
      const whole = new Set(bandHeads(age, 300, 3600).forms.map(norm))
      for (let cells = 7; cells <= 80; cells++) {
        for (const form of bandHeads(age, 300, 3600, cells).forms) {
          for (const row of form) expect([...row].length).toBeLessThanOrEqual(cells)
          expect(whole.has(norm(form))).toBe(true)
        }
      }
    }
    expect(wrapWords('aaaa bbbbbbbbbbbb', 5)).toEqual(['aaaa', 'bbbbb', 'bbbbb', 'bb'])  // no hyphen: the row edge
    expect(wrapWords('  Live table: claude-accounts', 20, '  ')).toEqual(['  Live table:', '  claude-accounts'])
  })

  test('the head and the board share the band\'s rows', () => {
    // 30 cells, stale: a 10-row band holds the 2-row short head over the 8-row cards exactly; a
    // 9-row band only the one-row head.
    expect(bandLayout(TWO, 30, 10, 400, 300, 3600))
      .toEqual({ head: ['⚠ stale 6m', 'live: claude-accounts'], variant: TWO.variants[1] })
    expect(bandLayout(TWO, 30, 9, 400, 300, 3600)).toEqual({ head: ['⚠ stale 6m'], variant: TWO.variants[1] })
    // 80 cells, 15 rows: only the one-row sentence keeps the 14-row FULL grid (the exact head, not
    // just its length: the age-only head would also be one row), over the 3-row sentence's dense table.
    expect(bandLayout(TWO, 80, 15, 400, 300, 3600))
      .toEqual({ head: ['⚠ stale 6m · live: claude-accounts'], variant: TWO.variants[4] })
    // 80 cells, 14 rows: the board fits only beside no head at all, so every head takes the dense
    // table, and the whole band stays inside its rows (the head's rows count against the board's).
    const tight = bandLayout(TWO, 80, 14, 400, 300, 3600)
    expect(first(tight.variant)).toBe('DENSE table')
    expect(tight.head.length + (tight.variant?.lines.length ?? 0)).toBeLessThanOrEqual(14)
    // A 30-row band affords the hook's sentence, blank row and all, over the same cards.
    const tall = bandLayout(TWO, 30, 30, 400, 300, 3600)
    expect(tall.head[0]).toBe('⚠ STALE by 6m — the numbers')
    expect(tall.head.at(-1)).toBe('')
    expect(first(tall.variant)).toBe('DENSE cards')
    // Fresh: no head, the whole budget is the board's.
    expect(bandLayout(TWO, 80, 10, 10, 300, 3600)).toEqual({ head: [], variant: TWO.variants[2] })
    // Past the hard band: no board, and the hook's sentence where it fits the band.
    const hard = bandLayout(TWO, 80, 10, 7300, 300, 3600)
    expect(hard.variant).toBeUndefined()
    expect(hard.head[0]).toMatch(/^accounts board is 2h old — numbers withheld/)
  })

  // THE STALE TAG SHARES A ROW (2026-10-22). Dense variants carry each lane row's cells (`lanes`);
  // where no head on its own row keeps the board whole, `⚠ stale 6m` (else `⚠ 6m`) joins the end of
  // a lane row, or, the full tag only, the legend's blank lead. The shapes are the probe's failing
  // cells: live rows at 17 cells on a 30-row pane (`➤ use next2`, 10 rows), the fixture at 22 on a
  // 45-row pane (three lane rows, a legend led by 12 blanks, next3's weekly row the 16th).
  const dv = (cells: number, lanes: number[], lines: string[], extra: Partial<Variant> = {}): Variant =>
    ({ cells, width: cells, dense: true, lanes, lines, ...extra })
  const acct = (n: number) => Array.from({ length: n }, (_, i) => `acct row ${i}`)

  test('a stale tag joins a lane row or the legend\'s lead where its own row would cut an account', () => {
    const live: Ladder = { ...LADDER, variants: [dv(17, [11], ['➤ use next2', 'used     5h    wk', ...acct(8)])] }
    // its own row: 11 rows, one over a 10-row band; `⚠ stale 6m` does not fit beside the lane (22 > 17)
    expect(bandLayout(live, 17, 10, 400, 300, 3600))
      .toEqual({ head: [], variant: { ...live.variants[0], lines: ['➤ use next2\x1b[0m ⚠ 6m', ...live.variants[0].lines.slice(1)] } })
    // a band with room for the head's own row keeps it, words and all
    expect(bandLayout(live, 17, 11, 400, 300, 3600).head).toEqual(['⚠ stale 6m'])
    const fx: Ladder = {
      ...LADDER,
      variants: [dv(22, [18, 17, 17], ['L1', 'L2', 'L3', '\x1b[38;2;1;2;3m            used reset\x1b[0m', ...acct(12), ...acct(25)],
        { values: 16 })],
    }
    const got = bandLayout(fx, 22, 17, 400, 300, 3600)
    expect(got.head).toEqual([])
    expect(got.variant?.lines[3]).toBe('⚠ stale 6m\x1b[38;2;1;2;3m  used reset\x1b[0m')
    expect(spans(got.variant?.lines[3] ?? '')).toEqual([{ text: '⚠ stale 6m' }, { text: '  used reset', color: '#010203' }])
    // a lead with room only for `⚠ 6m` takes nothing: there it read as one of the legend's labels
    // (lane rows too full for even `⚠ 6m`, so the lead is the only place left)
    const narrowLead: Ladder = {
      ...fx,
      variants: [{ ...fx.variants[0], lanes: [20, 20, 20], lines: fx.variants[0].lines.map((l, i) => (i === 3 ? '      used reset' : l)) }],
    }
    expect(bandLayout(narrowLead, 22, 17, 400, 300, 3600).head).toEqual(['⚠ stale 6m'])
    // the same lane rows with room for `⚠ 6m` take it at the end of the first that has it
    const room: Ladder = { ...narrowLead, variants: [{ ...narrowLead.variants[0], lanes: [20, 17, 17] }] }
    expect(bandLayout(room, 22, 17, 400, 300, 3600).variant?.lines.slice(0, 2)).toEqual(['L1', 'L2\x1b[0m ⚠ 6m'])
    // a hard band withholds the board and so merges nothing; a fresh one has no tag
    expect(bandLayout(live, 17, 10, 7300, 300, 3600).variant).toBeUndefined()
    expect(bandLayout(live, 17, 10, 10, 300, 3600)).toEqual({ head: [], variant: live.variants[0] })
  })

  test('where the head\'s own row fits as well, it keeps it: the merge wins only on more shown', () => {
    // 30 cells, 10 rows: the 2-row head over 8 rows fits, and so would the tag beside the lane.
    // A tie keeps the head's own row (and a merged layout ranks on its own width, not the tag's).
    const T: Ladder = { ...LADDER, variants: [dv(24, [19], ['➤ all lanes → next2', ...acct(7)])] }
    expect(bandLayout(T, 30, 10, 400, 300, 3600))
      .toEqual({ head: ['⚠ stale 6m', 'live: claude-accounts'], variant: T.variants[0] })
    // A labelled layout under the head's own row, its cut in its alerts, outranks a terse one the
    // tag fits whole beside, as in pickFit: the terse sibling is the last resort.
    const L: Ladder = {
      ...LADDER,
      variants: [dv(20, [19], ['➤ all lanes → next2', 'used', ...acct(10)], { values: 8 }),
        dv(20, [7], ['➤ next2', 'used', ...acct(8)], { terse: true })],
    }
    expect(bandLayout(L, 20, 10, 400, 300, 3600)).toEqual({ head: ['⚠ stale 6m'], variant: L.variants[0] })
  })

  test('ages and staleness bands are the hook\'s', () => {
    expect([fmtAge(5), fmtAge(119), fmtAge(120), fmtAge(7199), fmtAge(7200)]).toEqual(['5s', '119s', '2m', '119m', '2h'])
    expect(bandHead(299, 300, 3600)).toEqual({ grid: true, head: [] })
    expect(bandHead(300, 300, 3600).head[0]).toBe('⚠ STALE by 5m — the numbers below are last-known, not current.')
    expect(bandHead(3600, 300, 3600).grid).toBe(false)
  })
})

describe('the SessionStart band', () => {
  test('stamps before the settings hooks run, then draws the full-width layout and re-lays it out', async ($, on) => {
    const { files, seen } = bandWorld(on, { hookWrites: JSON.stringify(LADDER) })
    await $.classic.SessionStart({ source: 'startup', session_id: SID } as never)
    expect(seen.reqAtHook).toBe(SID)
    expect(files[REQ]).toBe('')                  // consumed
    expect(files[SNAP]).toBe('')                 // consumed: an earlier start's never draws

    const wide = await band($, 160)
    expect(await wide.find({ text: /account live/ })).toBeDefined()
    expect(await wide.find({ text: /STALE/ })).toBeUndefined()
    const narrow = await band($, 40)
    expect(await narrow.find({ text: /account live/ })).toBeUndefined()
    expect(await narrow.find({ text: /next    5h/ })).toBeDefined()
    const wideAgain = await band($, 160)
    expect(await wideAgain.find({ text: /account live/ })).toBeDefined()
  })

  test('the first prompt takes the band away', async ($, on) => {
    const { clock } = bandWorld(on, { hookWrites: JSON.stringify(LADDER) })
    await $.classic.SessionStart({ source: 'startup', session_id: SID } as never)
    expect(await (await band($, 160)).find({ text: /account live/ })).toBeDefined()
    await clock.advance(45_000)                  // the quickest manual first prompt measured
    await $.prompt.submit({ text: 'hello' } as never)
    const after = await band($, 160)
    expect(await after.find({ text: /account live/ })).toBeUndefined()
    expect(await after.find({ text: /engine band/ })).toBeDefined()
  })

  test('a brief submitted at launch leaves the band up; the next prompt takes it away', async ($, on) => {
    const { clock } = bandWorld(on, { hookWrites: JSON.stringify(LADDER) })
    await $.classic.SessionStart({ source: 'startup', session_id: SID } as never)
    await clock.advance(3_400)                   // the slowest handoff brief measured: 3.3 s
    await $.prompt.submit({ text: '[locate] cd /repo …' } as never)
    expect(await (await band($, 160)).find({ text: /account live/ })).toBeDefined()
    await clock.advance(60_000)
    await $.prompt.submit({ text: 'status?' } as never)
    expect(await (await band($, 160)).find({ text: /account live/ })).toBeUndefined()
  })

  test('the launch grace is the CC_BOARD_BAND_GRACE_S knob', async ($, on) => {
    const { clock } = bandWorld(on, { hookWrites: JSON.stringify(LADDER), env: { CC_BOARD_BAND_GRACE_S: '60' } })
    await $.classic.SessionStart({ source: 'startup', session_id: SID } as never)
    await clock.advance(45_000)                  // past the default 20 s, inside this 60 s
    await $.prompt.submit({ text: 'hello' } as never)
    expect(await (await band($, 160)).find({ text: /account live/ })).toBeDefined()
    await clock.advance(15_000)
    await $.prompt.submit({ text: 'hello' } as never)
    expect(await (await band($, 160)).find({ text: /account live/ })).toBeUndefined()
  })

  test('no snapshot (the hook printed its grid) draws no band', async ($, on) => {
    bandWorld(on, {})
    await $.classic.SessionStart({ source: 'startup', session_id: SID } as never)
    expect(await (await band($, 160)).find({ text: /account live|desk/ })).toBeUndefined()
  })

  test('compact is left alone, as the hook leaves it', async ($, on) => {
    const { files, seen } = bandWorld(on, { hookWrites: JSON.stringify(LADDER) })
    await $.classic.SessionStart({ source: 'compact', session_id: SID } as never)
    expect(seen.reqAtHook).toBeUndefined()
    expect(files[SNAP]).toBeUndefined()
    expect(await (await band($, 160)).find({ text: /account live/ })).toBeUndefined()
  })

  test('a survey holds the band', async ($, on) => {
    bandWorld(on, { hookWrites: JSON.stringify(LADDER) })
    await $.classic.SessionStart({ source: 'startup', session_id: SID } as never)
    expect(await (await band($, 160, { hasSurvey: true })).find({ text: /account live/ })).toBeUndefined()
  })

  test('a band left waiting goes STALE, then withholds its numbers, on the hook\'s knobs', async ($, on) => {
    bandWorld(on, { hookWrites: JSON.stringify(LADDER), ageS: 400 })
    await $.classic.SessionStart({ source: 'clear', session_id: SID } as never)
    const stale = await band($, 160)
    expect(await stale.find({ text: /STALE by 6m/ })).toBeDefined()
    expect(await stale.find({ text: /account live/ })).toBeDefined()
  })

  test('the band draws the dense layout where the full one would scroll accounts below the fold', async ($, on) => {
    bandWorld(on, { hookWrites: JSON.stringify(TWO) })
    await $.classic.SessionStart({ source: 'startup', session_id: SID } as never)
    expect(await (await band($, 85, { maxRows: 30 })).find({ text: /FULL grid/ })).toBeDefined()
    const short = await band($, 85, { maxRows: 10 })
    expect(await short.find({ text: /DENSE table/ })).toBeDefined()
    expect(await short.find({ text: /FULL/ })).toBeUndefined()
  })

  test('a narrow stale band says so in its short head, words whole', async ($, on) => {
    bandWorld(on, { hookWrites: JSON.stringify(TWO), ageS: 400 })
    await $.classic.SessionStart({ source: 'startup', session_id: SID } as never)
    const narrow = await band($, 17, { maxRows: 40 })                 // a 12-cell band
    expect(await narrow.find({ text: /⚠ stale 6m/ })).toBeDefined()
    expect(await narrow.find({ text: /^claude-$/ })).toBeDefined()
    expect(await narrow.find({ text: /^accounts$/ })).toBeDefined()
    expect(await narrow.find({ text: /STALE by/ })).toBeUndefined()
    expect(await narrow.find({ text: /DENSE floor/ })).toBeDefined()
  })

  test('past the hard band the numbers are withheld', async ($, on) => {
    bandWorld(on, { hookWrites: JSON.stringify(LADDER), ageS: 100, env: { CC_BOARD_HARD_S: '60' } })
    await $.classic.SessionStart({ source: 'resume', session_id: SID } as never)
    const hard = await band($, 160)
    expect(await hard.find({ text: /numbers withheld/ })).toBeDefined()
    expect(await hard.find({ text: /account live/ })).toBeUndefined()
  })
})
