export const meta = { name: 'x', description: 'agent( in a string' }
// agent('in a comment')
const a = await agent(`Research the ${topic} landscape`, {label: 'r1', schema: S})
const b = await agent('Fix the bug, then git commit it', {label: 'fix'})
const c = await agent(brief(d), {label: 'opq'})
const e = await agent(`read files`, {label: 'lean', agentType: 'workflow-lean'})
const f = await agent("x", {...BASE})
const g = items.map(i => () => agent(`Use the Skill tool for ${i}`, {label: `s-${i}`}))
obj.agent('not this')
