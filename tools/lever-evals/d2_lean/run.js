export const meta = {
  name: 'lever-d2-lean-run',
  description: 'd2-lean eval: one variant (default or workflow-lean) over one block of production briefs',
  phases: [{ title: 'Slots', detail: 'one agent() per case, all in this process\'s variant' }],
}

// d2-lean (docs/plans/USAGE_LEVERS.md § W7+ §2 D2 "Offline d2-lean"; wave S10). ONE PROCESS RUNS ONE
// VARIANT: the driver (flow.py run_model) launches a fresh headless `claude -p` lead per position of
// the ABBA order on one account per block, and that lead runs this script. A fresh process per
// variant because agent definitions are cached at session start; the lean definition under test is
// injected with `--agents` (wiring probe 2, 2026-10-25: a `--agents` workflow-lean overrides the
// user-level one for agentType 'workflow-lean'), and the lead waits for this workflow to finish
// (wiring probe 1: the -p lead takes a second turn on the completion notification, then exits).
//
// Scripts have no filesystem, so the driver writes a copy of this file with INPUT filled in:
//   { variant: 'default' | 'lean', rep: N, block: 'b0', cases: [{ case_id, prompt, schema }] }
// `prompt` is the case's brief with {{REPO}}/{{FIX}}/{{OUT}} already mapped to this run's clones,
// plus the harness rules — identical in both variants except the run's own paths.
// Labels are d2:<variant>:<case_id>:r<rep>; grade.py reads them back from journal.jsonl.
const INPUT = /*@@INPUT@@*/ null || args
if (!INPUT || !Array.isArray(INPUT.cases) || !['default', 'lean'].includes(INPUT.variant)) {
  throw new Error('run.js: INPUT must be {variant: default|lean, rep, block, cases: [...]}')
}

// F2's structured return (f2/workflow.js SCHEMA), used only for the F2 cases whose briefs ask for it
const SCHEMA = {
  type: 'object',
  properties: {
    answer_path: { type: 'string' },
    headline: { type: 'string' },
    numbers: { type: 'object' },
  },
  required: ['answer_path', 'headline', 'numbers'],
}

phase('Slots')
const results = await parallel(
  INPUT.cases.map((c) => () => {
    const opts = { label: `d2:${INPUT.variant}:${c.case_id}:r${INPUT.rep}`, phase: 'Slots' }
    if (INPUT.variant === 'lean') opts.agentType = 'workflow-lean'
    if (c.schema) opts.schema = SCHEMA
    return agent(c.prompt, opts).then((r) => ({ case_id: c.case_id, ok: r !== null, result: r }))
  })
)
const done = results.filter(Boolean)
log(`${done.length}/${INPUT.cases.length} slots returned (${INPUT.variant}, r${INPUT.rep}, ${INPUT.block})`)
return { variant: INPUT.variant, rep: INPUT.rep, block: INPUT.block, results: done }
