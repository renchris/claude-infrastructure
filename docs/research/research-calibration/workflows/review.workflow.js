export const meta = {
  name: 'calib-a3-review',
  description: 'A3 calibration replay: four Anthropic reviewer slots per held-out plan on its seeded freeze bundle',
  phases: [{ title: 'Review', detail: 'Opus slots A and D (frontier slots filled by Opus), full context and plan only' }],
}
const FIND = {
  type: 'object',
  properties: {
    lenses: { type: 'object' },
    findings: { type: 'array', items: { type: 'object', properties: {
      location: { type: 'string' }, quote: { type: 'string' }, clause: { type: 'string' }, claim: { type: 'string' },
      consequence: { type: 'string' }, receipt: { type: 'string' }, probability: { type: 'number' },
      falsifier: { type: 'string' }, omission: { type: 'boolean' } },
      required: ['location', 'quote', 'clause', 'claim', 'consequence', 'receipt', 'probability', 'omission'] } },
  },
  required: ['lenses', 'findings'],
}
const slots = []
for (const p of args.plans) for (const fam of ['A', 'D']) for (const strat of ['full', 'plan'])
  slots.push({ id: `${p}__${fam}_${strat}`, cwd: `${args.root}/${p}/${strat}` })
const prompt = (s) => `${args.brief}

YOUR WORKING DIRECTORY: ${s.cwd}
Every Read, Grep, Glob or Bash call must target a path under that directory (start Bash commands with cd "${s.cwd}" &&). Reading any other path voids your review. Return the JSON through the StructuredOutput tool.`
log(`${slots.length} reviewer slots`)
const res = await parallel(slots.map(s => () =>
  agent(prompt(s), { label: `review:${s.id}`, phase: 'Review', schema: FIND, effort: 'high', agentType: 'workflow-lean' })
    .then(r => r ? { id: s.id, n: r.findings.length } : { id: s.id, n: null })))
return res
