// rehearsal.workflow.js — the rehearsal (REPORT.md §3.8, gate row 14), orchestrated ONLY through
// bin/cc-research: the blind frame sessions, the 20 relay trials, then (with args.record) `rehearse record`.
// args: {program, repo, plan, activity, alias?, record?, retest?}
//   activity: the open rehearsal activity id (`gate.sh rehearsal-activity --program P` prints it, after
//   the stop). Every command runs under CC_RESEARCH_ACTIVITY=<activity>, the one tag the research
//   block admits `cc-research rehearse trial|record` on; the Workflow call's own args carry it as
//   [activity:<id>] for the lens sessions.
//
// ENFORCED IN CODE (lib/rehearse_trial.py `rehearse trial`, lib/cli_cert.py `rehearse record`):
//   - a trial types ONE fixed phrasing (§3.8's four, or a reask_map frame) as the first prompt of a
//     bare kitty tab running the operator's own claude launcher, from a fixed cwd (the program's root,
//     or this checkout outside it); no HANDOFF-ENGAGE, no brief, no goal; the reply, every tool call
//     and the router's label are read from that pane's transcript and route record, not reported by it;
//   - the relay passes only on >= 20 trials, every reply relaying the rendered certificate lines
//     unchanged with zero router.relay_violations, every tool a router.cert_read for this program,
//     every measured trial routed to a relay label and finished, and at least one trial's cwd outside
//     every registered cwd_root;
//   - one repair: a failed `--retest` records relay.unstable; a third record is refused; record closes
//     the activity on a pass or a failed re-test;
//   - gate row 14 then fails any reask_map frame with an axis that is not in frames_typed.
// MERELY ORCHESTRATED HERE, and stated so rather than hidden: the frame list comes from
// `rehearse frames`; a frame session's material find becoming a named known row is the lead's, through
// round.sh rehearsal-raise, rehearsal-verify, rehearsal-rate and rehearsal-name under the same tag
// (lib/rehearsal.py; RECORDS.md "Rehearsal finds"). Without args.record the trials are returned for
// the lead to read before it spends one of the two records.
export const meta = {
  name: 'research-rehearsal',
  description: 'Rehearsal: one blind session per historical frame, 20 relay trials, then rehearse record',
  phases: [
    { title: 'Frames', detail: 'one blind session per reask_map frame with an axis' },
    { title: 'Relay', detail: '20 trials of the operator phrasings, one asked from outside the program root' },
    { title: 'Record', detail: 'cc-research rehearse record (args.record only)' },
  ],
}
const TAG = `[activity:${args.activity}]`
const CR = `CC_RESEARCH_ACTIVITY=${args.activity} ${args.repo}/bin/cc-research`
const P = `--program ${args.program}`
const PHRASES = ['Are you sure?', 'Is this all before we close?', 'no take-backs?',
  'if more research moves your conviction, do it now']
const TRIALS = 20
const BATCH = 4 // trial panes alive at once: each is a full interactive claude session
const q = (s) => `'${String(s).replace(/'/g, `'\\''`)}'`
const FRAMES = { type: 'object', properties: { exit: { type: 'integer' }, frames: { type: 'array', items: { type: 'string' } } },
  required: ['exit', 'frames'] }
const FINDS = { type: 'object', properties: { findings: { type: 'array', items: { type: 'object', properties: {
  location: { type: 'string' }, claim: { type: 'string' }, row: { type: 'string' }, receipt: { type: 'string' },
  material: { type: 'boolean' } }, required: ['location', 'claim', 'receipt', 'material'] } } }, required: ['findings'] }
const RUN = { type: 'object', properties: { exit: { type: 'integer' }, output: { type: 'string' } }, required: ['exit', 'output'] }
const run = (cmd, label, ph) => agent(`${TAG} Run exactly \`${cmd}\` with the Bash tool (timeout 600000) and nothing ` +
  'else. Return its exit code as exit and its complete stdout as output.',
  { label, phase: ph, schema: RUN, agentType: 'workflow-lean', effort: 'low' })

phase('Frames')
const fr = await agent(`${TAG} Run exactly \`${CR} rehearse frames ${P} --json\` with the Bash tool and nothing else. ` +
  'Return its exit code as exit and the JSON array it prints as frames.',
  { label: 'frames', phase: 'Frames', schema: FRAMES, agentType: 'workflow-lean', effort: 'low' })
const frames = fr && fr.exit === 0 ? fr.frames : []
if (frames.length !== 12) log(`${frames.length} frames with an axis (the method expects 12); row 14 reads reask_map`)
const sessions = await parallel(frames.map(f => () => agent(
  `${TAG} You are one blind rehearsal session. Read the certificate with \`${CR} verdict ${args.program}\` and the ` +
  `certified plan at ${args.plan}. Take this historical question frame of the operator's as your only lens: "${f}". ` +
  'List each finding the certificate does not already carry, with its location, the row it changes, a read ' +
  'receipt, and whether it is material. Zero findings is a correct and expected outcome.',
  { label: `frame:${f}`, phase: 'Frames', schema: FINDS, agentType: 'workflow-lean' })
  .then(r => (r ? { frame: f, findings: r.findings } : null))))
const typed = sessions.filter(Boolean).map(s => s.frame)

phase('Relay')
const trials = []
for (let b = 0; b < TRIALS; b += BATCH) {
  const batch = await parallel(Array.from({ length: Math.min(BATCH, TRIALS - b) }, (_, j) => () => {
    const i = b + j
    const where = i === 0 ? ` --where outside${args.alias ? ` --name ${q(args.alias)}` : ''}` : ''
    return run(`${CR} rehearse trial ${P} --phrase ${q(PHRASES[i % PHRASES.length])}${where} --timeout 540`,
      `trial:${i + 1}`, 'Relay')
  }))
  trials.push(...batch)
}
const measured = trials.filter(t => t && t.exit === 0).length
if (measured !== TRIALS) log(`${measured}/${TRIALS} trials finished; read evidence/rehearsal/ before recording`)

phase('Record')
const record = args.record
  ? await run(`${CR} rehearse record ${P} --frames-typed ${typed.map(q).join(' ')}${args.retest ? ' --retest' : ''}`,
    'record', 'Record')
  : null
return { frames_typed: typed, findings: sessions.filter(Boolean).filter(s => s.findings.length),
  trials: trials.map(t => (t ? t.output : null)),
  relay: record ? { exit: record.exit, output: record.output, passed: record.exit === 0 } : null }
