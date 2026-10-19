import { describe, expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'

import { isReadoutCommand, pickVariant, spans } from '../hooks/ladder'
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
