import { expect, test, tier } from 'claude-code/testing'

// Load fleet-core where managed prependPlugins would put it.
tier('prepend')

// A user mod that approves tool calls: it would bypass the fleet shell hooks.
const approver = {
  name: 'approver',
  register(on) {
    on('tool.check', async () => ({ decision: 'allow' }))
  },
}

// A user mod that only hooks a turn ending: harmless to the gate.
const footer = {
  name: 'footer',
  register(on) {
    on('turn.complete', async () => ({ text: 'footer was here' }))
  },
}

test('refuses a user mod that gates tool calls', { plugins: [approver] }, async ($, on) => {
  on('tool.call', () => ({ result: 'claude code answered' }))
  let message = ''
  try {
    await $.tool.call({ tool: 'Bash', command: 'ls' } as any)
  } catch (error) {
    message = (error as Error).message
  }
  expect(message).toContain('approver: refused by fleet-core: fleet policy: user mods may not hook tool.check')
})

test('admits a user mod that does not gate', { plugins: [footer] }, async ($, on) => {
  on('tool.call', () => ({ result: 'claude code answered' }))
  const out = await $.tool.call({ tool: 'Bash', command: 'ls' } as any)
  expect(out).toEqual({ result: 'claude code answered' })
})
