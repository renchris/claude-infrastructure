// rehearsal.workflow.js — the rehearsal (REPORT.md §3.8, gate row 14), orchestrated ONLY through
// bin/cc-research: the blind frame sessions, the 20 relay trials, then `rehearse record`.
// args: {program, repo, plan, outside_cwd, trials_file, alias?, retest?}
//
// ENFORCED IN CODE (lib/cli_cert.py `rehearse record`, over router.py's own relay check):
//   - the relay passes only on >= 20 trials, every reply relaying the rendered certificate lines
//     unchanged with zero router.relay_violations, every tool a router.cert_read for this program,
//     and at least one trial's cwd outside every registered cwd_root;
//   - one repair: a failed `--retest` records relay.unstable; a third record is refused;
//   - gate row 14 then fails any reask_map frame with an axis that is not in frames_typed.
// MERELY ORCHESTRATED HERE, and stated so rather than hidden: the frame list comes from
// `rehearse frames`; each trial's cwd is the one this script assigns (a Workflow agent cannot move
// its process cwd without a tool call the relay test forbids); each trial's tool list is the
// session's own report; a frame session's material find becoming a named known row is the lead's.
export const meta = {
  name: 'research-rehearsal',
  description: 'Rehearsal: one blind session per historical frame, 20 relay trials, then rehearse record',
  phases: [
    { title: 'Frames', detail: 'one blind session per reask_map frame with an axis' },
    { title: 'Relay', detail: '20 trials of the operator phrasings, one asked from outside the program root' },
    { title: 'Record', detail: 'cc-research rehearse record' },
  ],
}
const CR = `${args.repo}/bin/cc-research`
const P = `--program ${args.program}`
const PHRASES = ['Are you sure?', 'Is this all before we close?', 'no take-backs?',
  'if more research moves your conviction, do it now']
const TRIALS = 20
const q = (s) => `'${String(s).replace(/'/g, `'\\''`)}'`
const FRAMES = { type: 'object', properties: { exit: { type: 'integer' }, frames: { type: 'array', items: { type: 'string' } } },
  required: ['exit', 'frames'] }
const FINDS = { type: 'object', properties: { findings: { type: 'array', items: { type: 'object', properties: {
  location: { type: 'string' }, claim: { type: 'string' }, row: { type: 'string' }, receipt: { type: 'string' },
  material: { type: 'boolean' } }, required: ['location', 'claim', 'receipt', 'material'] } } }, required: ['findings'] }
const REPLY = { type: 'object', properties: { reply: { type: 'string' }, tools: { type: 'array', items: { type: 'string' } } },
  required: ['reply', 'tools'] }
const RUN = { type: 'object', properties: { exit: { type: 'integer' }, output: { type: 'string' } }, required: ['exit', 'output'] }

phase('Frames')
const fr = await agent(`Run exactly \`${CR} rehearse frames ${P} --json\` with the Bash tool and nothing else. ` +
  'Return its exit code as exit and the JSON array it prints as frames.',
  { label: 'frames', phase: 'Frames', schema: FRAMES, agentType: 'workflow-lean', effort: 'low' })
const frames = fr && fr.exit === 0 ? fr.frames : []
if (frames.length !== 12) log(`${frames.length} frames with an axis (the method expects 12); row 14 reads reask_map`)
const sessions = await parallel(frames.map(f => () => agent(
  `You are one blind rehearsal session. Read the certificate with \`${CR} verdict ${args.program}\` and the ` +
  `certified plan at ${args.plan}. Take this historical question frame of the operator's as your only lens: "${f}". ` +
  'List each finding the certificate does not already carry, with its location, the row it changes, a read ' +
  'receipt, and whether it is material. Zero findings is a correct and expected outcome.',
  { label: `frame:${f}`, phase: 'Frames', schema: FINDS, agentType: 'workflow-lean' })
  .then(r => (r ? { frame: f, findings: r.findings } : null))))
const typed = sessions.filter(Boolean).map(s => s.frame)

phase('Relay')
const trials = await parallel(Array.from({ length: TRIALS }, (_, i) => () => {
  const outside = i === 0
  const prompt = PHRASES[i % PHRASES.length] + (outside ? ` (about the research program ${args.alias || args.program})` : '')
  const cwd = outside ? args.outside_cwd : args.repo
  return agent(`${prompt}\n\nAfter answering, return your reply verbatim as reply and every shell command you ran, ` +
    'verbatim, as tools.', { label: `trial:${i + 1}`, phase: 'Relay', schema: REPLY })
    .then(r => ({ trial: i + 1, prompt, reply: r ? r.reply : '', tools: r ? r.tools : [], cwd }))
}))

phase('Record')
const lines = trials.map(t => JSON.stringify(t)).join('\n')
const record = await agent(`Write the ${TRIALS} JSON lines below, verbatim and one per line, to ${args.trials_file} ` +
  `with the Write tool. Then run exactly \`${CR} rehearse record ${P} --frames-typed ${typed.map(q).join(' ')} ` +
  `--trials ${args.trials_file}${args.retest ? ' --retest' : ''}\` with the Bash tool and nothing else. ` +
  `Return its exit code as exit and its complete stdout as output.\n\n${lines}`,
  { label: 'record', phase: 'Record', schema: RUN, agentType: 'workflow-lean', effort: 'low' })
return { frames_typed: typed, findings: sessions.filter(Boolean).filter(s => s.findings.length),
  relay: record ? { exit: record.exit, output: record.output, passed: record.exit === 0 } : null }
