import type { EngineInterface, Register, RenderElement, RenderInput } from 'claude-code'

import type { Ladder } from '../types'
import { isLadder, isReadoutCommand, pickVariant, spans } from './ladder'

// THE /accounts READOUT, RE-LAID OUT ON RESIZE (2026-10-19). `claude-accounts --readout` used to
// reach the pane only as a PostToolUse systemMessage: static text, which Claude Code re-wraps when
// the pane narrows after the draw (operator screenshot: drawn at ~157 columns, viewed at ~35, every
// grid row in pieces). A `ui.render` hook is re-run at every width change, completed transcript
// rows included (docs/research/accounts-responsive-mod-2026-10-19/), so this mod draws the readout
// under its shell-command row from the renderer's width ladder, picking the widest layout that
// fits. Every fact and every layout is bin/claude-accounts's; nothing here lays anything out.
//
// The handshake with hooks/relay-verbatim.sh: before the command runs, `<sid>.mod` is stamped with
// this call's tool_use_id; the hook, seeing its own call named there, sends the model its
// do-not-paste note and draws no static copy. No stamp (mod not loaded) leaves the hook as it was.

const LADDERS = { plugin: 'accounts-readout', key: 'ladders' } as const
const STORE_KEEP = 4                       // ladders kept across sessions, for a resumed transcript
const FIRST = '  ⎿  '                      // the indent a hook message draws under a tool row
const REST = '     '

const paneDir = async ($: EngineInterface) =>
  (await $.env.get('CC_PANE_DIR')) || '/tmp/claude-accounts-pane'

const sidStem = (sid: string) => sid.replace(/[^A-Za-z0-9_-]/g, '')

const remember = async ($: EngineInterface, id: string, ladder: Ladder) => {
  await $.state.set({ ...LADDERS, id }, ladder)
  const recent = ((await $.store.get('recent')) as string[] | undefined) ?? []
  const keep = [id, ...recent.filter(x => x !== id)]
  for (const old of keep.slice(STORE_KEEP)) await $.store.delete(`ladder:${old}`)
  await $.store.set(`ladder:${id}`, ladder)
  await $.store.set('recent', keep.slice(0, STORE_KEEP))
}

const recall = async ($: EngineInterface, id: string): Promise<Ladder | undefined> => {
  const { value } = await $.state.get({ ...LADDERS, id })
  if (isLadder(value)) return value
  const stored = await $.store.get(`ladder:${id}`)
  return isLadder(stored) ? stored : undefined
}

const draw = ($: EngineInterface, e: RenderInput, ladder: Ladder, engine: RenderElement) => {
  const { Box, Text } = $.ui.resolve(e)
  const columns = e.viewport?.columns ?? 80
  const variant = pickVariant(ladder, columns)
  if (!variant) return engine
  return (
    <Box flexDirection="column">
      {engine}
      {variant.lines.map((line, i) => (
        <Text key={`l${i}`}>
          {i === 0 ? FIRST : REST}
          {spans(line).map((s, j) => (
            <Text key={`s${j}`} color={s.color} bold={s.bold}>{s.text}</Text>
          ))}
          {line === '' ? ' ' : ''}
        </Text>
      ))}
    </Box>
  )
}

export const register: Register = on => {
  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    if (!isReadoutCommand(e.command)) return next(e)
    let ladderPath: string | undefined
    let startedMs = 0
    try {
      const stem = sidStem(await $.session.id())
      if (stem) {
        const dir = await paneDir($)
        ladderPath = `${dir}/${stem}.ladder.json`
        startedMs = await $.clock.now()
        await $.fs.write(`${dir}/${stem}.mod`, e.tool_use_id)
      }
    } catch {
      ladderPath = undefined                 // no stamp: the hook keeps drawing its static copy
    }
    const ran = await next(e)
    if (ladderPath) {
      try {
        const ladder: unknown = JSON.parse(await $.fs.read(ladderPath))
        // Written by THIS run (2 s slack for the two clocks), never a previous readout's.
        if (isLadder(ladder) && ladder.written_ms >= startedMs - 2000) {
          await remember($, e.tool_use_id, ladder)
        }
      } catch {
        // no ladder: nothing to draw, and the hook (no fresh ladder) drew its static copy
      }
    }
    return ran
  }).catch(($, e, next) => next(e))          // never a guard: a fault here lets the call run

  // The folded "Ran 1 shell command" line: the readout goes under it.
  on('ui.render', { component: 'ToolGroup' }, async ($, e, next) => {
    const call = e.props.calls.find(
      c => c.tool === 'Bash' && !c.isRunning && !c.isErrored && c.tool_use_id !== undefined &&
        isReadoutCommand((c.input as { command?: unknown } | null)?.command),
    )
    const ladder = call?.tool_use_id ? await recall($, call.tool_use_id) : undefined
    if (!ladder) return next(e)
    return draw($, e, ladder, await next(e))
  })

  // An unfolded call (`--verbose`, the ctrl+o transcript): under its own row.
  on('ui.render', { component: 'ToolUse' }, async ($, e, next) => {
    const p = e.props
    if (p.tool !== 'Bash' || p.isRunning || p.isErrored ||
        !isReadoutCommand((p.input as { command?: unknown } | null)?.command)) return next(e)
    const ladder = await recall($, p.tool_use_id)
    if (!ladder) return next(e)
    return draw($, e, ladder, await next(e))
  })
}

