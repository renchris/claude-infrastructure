// frame-critique.workflow.js — the frame critique (REPORT.md §3.2 step 6, §3.8), orchestrated ONLY
// through bin/cc-research by running round.workflow.js once per round with kind frame-critique.
// args: {program, round, plan, brief, repo, rater_brief?} — runs rounds args.round (default 1) to 2.
//
// ENFORCED IN CODE (lib/round.py plan_slots via cc-research open-round): exactly 2 rounds of 6
// reviewers across at least 3 vendor families, in order, never a third; and everything
// round.workflow.js lists (slot vendors, re-run cap, raters, the responding-model void).
// MERELY ORCHESTRATED HERE: running the two rounds in sequence and stopping when one fails to open.
export const meta = {
  name: 'research-frame-critique',
  description: 'The two frame-critique rounds, each through the round workflow with kind frame-critique',
  phases: [{ title: 'Rounds', detail: 'round.workflow.js with kind frame-critique, round by round' }],
}
phase('Rounds')
const out = []
for (let n = args.round || 1; n <= 2; n++) {
  const r = await workflow({ scriptPath: `${args.repo}/scripts/research-kit/workflows/round.workflow.js` },
    { ...args, round: n, kind: 'frame-critique' })
  out.push(r)
  if (!r || !r.opened) break
}
return { kind: 'frame-critique', rounds: out }
