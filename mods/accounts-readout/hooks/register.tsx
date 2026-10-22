import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, RenderElement, RenderInput } from 'claude-code'

import type { BoardBand, Ladder } from '../types'
import { bandHead, isLadder, isReadoutCommand, pickFit, pickVariant, spans } from './ladder'

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

// THE SESSIONSTART BOARD, AS A BAND ABOVE THE PROMPT (2026-10-21). hooks/accounts-board.sh draws
// the board as a SessionStart message: static text, hard-wrapped at the startup width, and Claude
// Code has no render component for that message, so a pane widened later keeps a ~45-cell board.
// So the band draws it from the producer's ladder, at the full band width, re-laid out at every
// width change, until the first prompt. The handshake (measured, docs/research/accounts-board-band-
// 2026-10-21/): `classic.SessionStart` runs above the settings hooks, so this mod stamps
// `<sid>.board-band.req` with the session id, runs them, and takes the snapshot the hook leaves at
// `<sid>.board-band.json` ONLY when it printed no grid. No snapshot, no band: the hook's text stands.
const board = atom({ plugin: 'accounts-readout', key: 'board' } as const, null)

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

const seconds = (v: string | undefined, fallback: number) =>
  v && /^[0-9]+$/.test(v) ? Number(v) : fallback

const drawBand = async ($: EngineInterface, e: RenderInput<'AbovePrompt'>, b: BoardBand) => {
  const { Box, Text } = $.ui.resolve(e)
  const ageS = Math.max(0, Math.floor(((await $.clock.now()) - b.mtimeMs) / 1000))
  const { head, grid } = bandHead(ageS, b.staleS, b.hardS)
  const variant = grid ? pickFit(b.ladder, e.props.bodyColumns) : undefined
  return (
    <Box flexDirection="column">
      {head.map((line, i) => <Text key={`h${i}`}>{line === '' ? ' ' : line}</Text>)}
      {/* WRAP, NEVER TRUNCATE (2026-10-22). truncate-end cut every countdown in a 27-column band to
          an ellipsis (operator screenshot). The ladder now reaches PANE_MIN (12 cells), so inside it
          pickFit always finds a layout that fits and this never acts; below it, or on a ladder an
          older producer wrote (35 cells and up), Ink wraps at whole words and nothing is hidden. */}
      {(variant?.lines ?? []).map((line, i) => (
        <Text key={`l${i}`} wrap="wrap">
          {spans(line).map((sp, j) => (
            <Text key={`s${j}`} color={sp.color} bold={sp.bold}>{sp.text}</Text>
          ))}
          {line === '' ? ' ' : ''}
        </Text>
      ))}
    </Box>
  )
}

export const register: Register = on => {
  let tick: { cancel: () => void } | undefined
  const stopTick = () => { tick?.cancel(); tick = undefined }

  // Every source the hook draws for (startup, resume, clear, fork); never compact, which it skips.
  on('classic.SessionStart', async ($, e, next) => {
    if (e.source === 'compact') return next(e)
    let armed: { req: string; snap: string } | undefined
    try {
      const stem = sidStem(e.session_id)
      const surfaces = await $.session.surfaces()
      if (stem && surfaces.some(s => s === 'terminal' || s === 'desktop')) {
        const dir = await paneDir($)
        armed = { req: `${dir}/${stem}.board-band.req`, snap: `${dir}/${stem}.board-band.json` }
        await $.fs.write(armed.snap, '')           // an earlier start's snapshot is not this one's
        await $.fs.write(armed.req, e.session_id)  // last: armed only once the stamp is down
      }
    } catch {
      armed = undefined
    }
    const out = await next(e)                    // the settings hooks, accounts-board.sh among them
    if (armed) {
      try {
        await $.fs.write(armed.req, '')
        const text = await $.fs.read(armed.snap)
        if (text) {
          const ladder: unknown = JSON.parse(text)
          const { mtimeMs } = await $.fs.stat(armed.snap)
          await $.fs.write(armed.snap, '')
          if (isLadder(ladder)) {
            const snap: BoardBand = {
              ladder, mtimeMs,
              staleS: seconds(await $.env.get('CC_BOARD_STALE_S'), 300),
              hardS: seconds(await $.env.get('CC_BOARD_HARD_S'), 3600),
            }
            await update($, board, () => snap)
            stopTick()
            // The age label must stay true while the band waits for a first prompt.
            tick = $.clock.every(30_000, () => $.ui.invalidate('ui.render'))
          }
        }
      } catch {
        // the hook printed no grid and this snapshot did not load: nothing more can be drawn
      }
    }
    return out
  }).catch(($, e, next) => next(e))          // replay-safe: a fault here never costs a hook's output

  on('prompt.submit', async ($, e, next) => {
    if (await read($, board)) {
      stopTick()
      await update($, board, () => null)
    }
    return next(e)
  }).catch(($, e, next) => next(e))

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e)
    const b = await read($, board)
    if (!b) return next(e)
    return drawBand($, e, b)
  })

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

