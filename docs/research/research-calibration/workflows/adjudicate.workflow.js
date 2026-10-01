export const meta = {
  name: 'calib-a3-adjudicate',
  description: 'A3 calibration: adjudicate each unmatched material finding against the freeze snapshot and later history',
  phases: [{ title: 'Adjudicate', detail: 'one adjudicator per plan, history-informed ground truth' }],
}
const ADJ = { type: 'object', required: ['verdicts'], properties: { verdicts: { type: 'array', items: { type: 'object',
  required: ['iid', 'verdict', 'evidence'], properties: { iid: { type: 'string' },
    verdict: { type: 'string', enum: ['REAL_MATERIAL', 'REAL_NOT_MATERIAL', 'FALSE', 'UNDETERMINED'] },
    later_history: { type: 'string' }, evidence: { type: 'string' } } } } } }
const run = (p) => agent(`You are strictly read-only: never edit, write, move or delete any file; never run git checkout, switch, worktree, stash, reset, commit or fetch. Nobody can answer a permission prompt for you.

You are the ground-truth adjudicator for a calibration study. Each finding below was raised by a reviewer of a plan frozen at a known commit. Decide whether it was a true material defect of that frozen plan.
1. Read ${args.cache}/history/${p}.json for repo, plan path and freeze_sha. Read the frozen plan with git -C <repo> show <freeze_sha>:<path>, and any repo file at the freeze the same way.
2. Then look at what happened AFTER the freeze: git -C <repo> log -p --follow <freeze_sha>..origin/main -- <path> (or ..HEAD / --all if origin/main lacks it), the plan's research directory, and commit bodies that touch the topic. Later history is ground truth: a later fix, a later refutation, a build that hit the problem, or a build that shipped the very thing the finding says is wrong and it worked.
3. Verdict per finding:
   REAL_MATERIAL: the claim is true of the frozen plan AND it meets a materiality clause (a decision would flip, an acceptance check is wrong or cannot fail, sequencing or an interface is wrong, a population member is missing in a way that changes a row, a load-bearing premise is false, a safety or data hazard, or a missing decision or component something depends on).
   REAL_NOT_MATERIAL: true but minor (wording, a detail a builder would settle without the plan changing).
   FALSE: the claim is wrong about the frozen plan (the plan handles it, the quote is misread, the premise holds), or later history shows the plan's choice worked as written.
   UNDETERMINED: neither the snapshot nor later history settles it.
   Decide on evidence, not on how confident the finding sounds. In later_history, say in one line what history shows (or "nothing"). In evidence, give sha or file:line.
FINDINGS: read them from ${args.cache}/replay/adjudicate/${p}.json (a JSON list; give one verdict per iid, for every item in it).`, { label: `adjudicate:${p}`, phase: 'Adjudicate', schema: ADJ, effort: 'xhigh', agentType: 'workflow-lean' })
const res = await parallel(args.plans.map(p => () => run(p).then(r => r ? { plan: p, n: r.verdicts.length } : { plan: p, n: null })))
return res
