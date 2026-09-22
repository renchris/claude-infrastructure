export const meta = {
  name: 'o55-synth-pincheck',
  description: 'Step 0: verify Workflow agent() honors each model+effort pin used by the synth re-probe',
  phases: [{ title: 'Pin check' }],
}
phase('Pin check')
const PINS = [
  ['A-sonnet5-max', 'claude-sonnet-5', 'max'],
  ['B-opus55-high', 'claude-opus-5-5', 'high'],
  ['C-opus55-xhigh', 'claude-opus-5-5', 'xhigh'],
  ['J-fable51-high', 'claude-fable-5-1', 'high'],
  ['J-opus5-xhigh', 'claude-opus-5', 'xhigh'],
]
const out = await parallel(PINS.map(([label, model, effort]) => () =>
  agent(`Reply with exactly: PIN-OK ${label}. Do not use any tools.`, { label, model, effort, phase: 'Pin check' })))
return PINS.map((p, i) => ({ label: p[0], model: p[1], effort: p[2], reply: out[i] }))
