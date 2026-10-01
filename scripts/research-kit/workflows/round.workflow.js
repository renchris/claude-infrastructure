// round.workflow.js — one certification (or, via frame-critique.workflow.js, frame-critique) round
// of a research program (REPORT.md §3.8, §8 item 11), orchestrated ONLY through bin/cc-research.
// args: {program, round, plan, brief, repo, rater_brief?, kind?: 'certification'|'frame-critique'}
//
// ENFORCED IN CODE (lib/cli_cert.py over lib/round.py and lib/courier.py), whatever this script does:
//   - the slot plan and every round cap: `open-round` runs round.plan_slots and refuses out of order,
//     past R_max, a third frame-critique round, or a round already open;
//   - each slot's vendor, strategy and role: `slot` takes a pid and looks the rest up in plan.json;
//   - the re-run cap per slot (kit.CAPS slot_reruns): `slot` refuses the attempt past it;
//   - the rater assignment (§3.8 step 2) and the void: `check-round` voids a panel whose responding
//     model differs from frame.json reviewer_pins, a rater on the wrong vendor, or an integrity hit,
//     appends rounds/<rid>/check.jsonl and writes the matrix.json the gate reads (exit 4 on a void).
// MERELY ORCHESTRATED HERE: the order open → reviewers → raters → check-round → re-runs, the fan-out,
// and relaying each exit code into the return. A step skipped here shows in the records as missing.
export const meta = {
  name: 'research-round',
  description: 'One certification round: plan, reviewer slots, raters, then the code check that voids pin breaches',
  phases: [
    { title: 'Open', detail: 'cc-research slots, then open-round (plan + bundle)' },
    { title: 'Review', detail: 'one agent per reviewer slot, each running cc-research slot' },
    { title: 'Rate', detail: 'the rater assignment computed in code, one agent per rater' },
    { title: 'Check', detail: 'cc-research check-round; re-runs only what reruns_left allows' },
  ],
}
const KIND = args.kind || 'certification'
if (KIND !== 'certification' && KIND !== 'frame-critique') throw new Error(`unknown round kind ${KIND}`)
const CR = `${args.repo}/bin/cc-research`
const P = `--program ${args.program}`
const RUN = { type: 'object', properties: { exit: { type: 'integer' }, output: { type: 'string' } },
  required: ['exit', 'output'] }
const SLOT = { type: 'object', properties: { pid: { type: 'string' }, vendor: { type: 'string' },
  strategy: { type: 'string' }, role: { type: 'string' }, round: { type: 'string' } }, required: ['pid'] }
const LIST = (key) => ({ type: 'object', properties: { exit: { type: 'integer' },
  [key]: { type: 'array', items: SLOT } }, required: ['exit', key] })
const CHECK = { type: 'object', properties: { exit: { type: 'integer' }, voided: { type: 'array', items: {
  type: 'object', properties: { pid: { type: 'string' }, reason: { type: 'string' },
    reruns_left: { type: 'integer' } }, required: ['pid', 'reason', 'reruns_left'] } } },
  required: ['exit', 'voided'] }

const run = (cmd, label, phase, schema = RUN, parsed = '') => agent(
  `Run exactly this one command with the Bash tool and nothing else:\n\n\`${cmd}\`\n\n` +
  `Do not edit, retry or interpret it. Return its exit code as exit${parsed ? `, and ${parsed}` : ', and its complete stdout as output'}.`,
  { label, phase, schema, agentType: 'workflow-lean', effort: 'low' })
const slotCmd = (rid, pid, brief) => `${CR} slot ${P} --round ${rid} --pid ${pid} --brief ${brief}`
const briefFor = (pid) => (/rater\d+$/.test(pid) ? (args.rater_brief || args.brief) : args.brief)

phase('Open')
const plan = await run(`${CR} slots ${P} --kind ${KIND} --round ${args.round} --json`, 'slots', 'Open',
  LIST('slots'), 'the JSON array it prints as slots')
if (!plan || plan.exit !== 0 || !plan.slots.length) return { kind: KIND, round: args.round, opened: false, plan }
const opened = await run(`${CR} open-round ${P} --kind ${KIND} --round ${args.round} --plan ${args.plan}`, 'open', 'Open')
if (!opened || opened.exit !== 0) return { kind: KIND, round: args.round, opened: false, refusal: opened }
const rid = plan.slots[0].round

phase('Review')
const reviews = await parallel(plan.slots.map(s => () =>
  run(slotCmd(rid, s.pid, args.brief), `slot:${s.pid}`, 'Review').then(r => ({ pid: s.pid, exit: r ? r.exit : null }))))

phase('Rate')
const rat = await run(`${CR} raters ${P} --round ${rid} --json`, 'raters', 'Rate', LIST('raters'),
  'the JSON array it prints as raters')
const rates = rat && rat.exit === 0 ? await parallel(rat.raters.map(r => () =>
  run(slotCmd(rid, r.pid, briefFor(r.pid)), `slot:${r.pid}`, 'Rate').then(x => ({ pid: r.pid, exit: x ? x.exit : null })))) : []

phase('Check')
const checkCmd = `${CR} check-round ${P} --round ${rid} --json`
let check = await run(checkCmd, 'check', 'Check', CHECK, 'the voided array of its JSON stdout as voided')
const reruns = []
for (let guard = 0; check && check.exit === 4 && guard < 10; guard++) { // runaway backstop; the cap is slot's refusal
  const again = check.voided.filter(v => v.reruns_left > 0)
  if (!again.length) break
  log(`re-running ${again.map(v => v.pid).join(', ')} (voided: ${again.map(v => v.reason).join('; ')})`)
  await parallel(again.map(v => () => run(slotCmd(rid, v.pid, briefFor(v.pid)), `rerun:${v.pid}`, 'Check')))
  reruns.push(...again.map(v => v.pid))
  check = await run(checkCmd, 'check', 'Check', CHECK, 'the voided array of its JSON stdout as voided')
}
return { kind: KIND, round: rid, opened: true, reviews, raters: rates, reruns,
  check_exit: check ? check.exit : null, voided: check ? check.voided : null }
