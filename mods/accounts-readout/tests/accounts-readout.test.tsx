import { describe, expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'

import { bandHead, fmtAge, isReadoutCommand, pickFit, pickVariant, spans } from '../hooks/ladder'
import type { Ladder } from '../types'

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
  mock.clock(on, { now: NOW })
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
  return { files, seen }
}

const band = ($: Engine, columns: number, extra: { hasSurvey?: boolean } = {}) =>
  $.ui.mount({
    plugin: 'accounts-readout', surface: 'terminal', component: 'AbovePrompt',
    viewport: { columns, rows: 50 },
    props: {
      hasSurvey: extra.hasSurvey ?? false, isWorking: false, maxRows: 25, bodyColumns: columns - 5,
      scroll: { offset: 0, bodyRows: 24 }, view: {},
    },
  } as never)

describe('band helpers', () => {
  test('the widest layout whose widest line fits the band, else the narrowest', () => {
    expect(pickFit(LADDER, 155)?.cells).toBe(70)
    expect(pickFit(LADDER, GRID.length)?.cells).toBe(70)
    expect(pickFit(LADDER, GRID.length - 1)?.cells).toBe(35)
    expect(pickFit(LADDER, 10)?.cells).toBe(35)
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
    bandWorld(on, { hookWrites: JSON.stringify(LADDER) })
    await $.classic.SessionStart({ source: 'startup', session_id: SID } as never)
    expect(await (await band($, 160)).find({ text: /account live/ })).toBeDefined()
    await $.prompt.submit({ text: 'hello' } as never)
    const after = await band($, 160)
    expect(await after.find({ text: /account live/ })).toBeUndefined()
    expect(await after.find({ text: /engine band/ })).toBeDefined()
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

  test('past the hard band the numbers are withheld', async ($, on) => {
    bandWorld(on, { hookWrites: JSON.stringify(LADDER), ageS: 100, env: { CC_BOARD_HARD_S: '60' } })
    await $.classic.SessionStart({ source: 'resume', session_id: SID } as never)
    const hard = await band($, 160)
    expect(await hard.find({ text: /numbers withheld/ })).toBeDefined()
    expect(await hard.find({ text: /account live/ })).toBeUndefined()
  })
})
