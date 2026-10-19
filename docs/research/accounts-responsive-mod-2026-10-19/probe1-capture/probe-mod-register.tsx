import type { Register } from 'claude-code'

const LOG = '/tmp/acct-probe/render.log'
const lines: string[] = []

const cmdOf = (input: unknown): string => {
  const c = (input as { command?: unknown } | null)?.command
  return typeof c === 'string' ? c : ''
}

export const register: Register = on => {
  on('ui.render', async ($, e, next) => {
    const cols = e.viewport?.columns ?? -1
    let digest = ''
    const p = e.props as Record<string, unknown>
    if (e.component === 'ToolGroup') {
      digest = JSON.stringify((p.calls as Array<{ tool: string; input: unknown }>).map(c => [c.tool, cmdOf(c.input).slice(0, 40)])) + ` expanded=${String(p.isExpanded)} active=${String(p.isActive)}`
    } else if (e.component === 'ToolUse') {
      digest = `${String(p.tool)} ${cmdOf(p.input).slice(0, 40)}`
    } else if (e.component === 'ToolResult') {
      digest = String(p.tool)
    } else if (e.component === 'InfoNotice') {
      digest = String(p.text).slice(0, 60)
    }
    lines.push(`${new Date().toISOString()} ${e.surface} ${e.component} ${e.requestId} cols=${cols} ${digest}`)
    void $.fs.write(LOG, lines.join('\n') + '\n').catch(() => undefined)

    const isMark =
      (e.component === 'ToolGroup' && JSON.stringify(p.calls).includes('PROBEMARK')) ||
      ((e.component === 'ToolUse') && cmdOf(p.input).includes('PROBEMARK'))
    if (!isMark || cols < 0) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    const width = Math.max(10, cols - 6)
    return (
      <Box flexDirection="column">
        <Text>{`PROBEMOD ${e.component} cols=${cols}`}</Text>
        <Text>{'#'.repeat(width)}</Text>
        <Text>{`PROBEEND w=${width}`}</Text>
      </Box>
    )
  })
}
