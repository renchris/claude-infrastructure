export const meta = {
  name: 'lever-d2-lean-keygen',
  description: 'd2-lean answer keys: per case, the asks and the facts checkable by code',
  phases: [{ title: 'Keys', detail: 'one Sonnet key-builder per case over its frozen fixture' }],
}

// d2-lean key builder (docs/plans/USAGE_LEVERS.md § W7+ §2 D2 "Grader"; wave S10). For each case a
// Sonnet 5.5 slot (never the model under test) reads the brief and the FROZEN fixture and returns:
//   asks   the separate things the brief asks for, one sentence each — the judge scores each ask
//   facts  claims an answer must state that code can verify: a read-only shell command whose stdout,
//          run with cwd = the fixture root, IS the expected value, and how to match it
// It never sees an answer. The driver (flow.py keys) runs every check_cmd itself on the fixture and
// keeps only commands that exit 0 with a non-empty value, so a wrong key is dropped, not trusted.
// key.json is written under ~/.claude/hillclimb/d2_lean/, outside every fixture.
// INPUT (filled in by the driver, scripts have no filesystem): { cases: [{ case_id, brief, root }] }
const INPUT = /*@@INPUT@@*/ null || args
if (!INPUT || !Array.isArray(INPUT.cases)) throw new Error('keygen.js: INPUT must be {cases: [...]}')

const KEY = {
  type: 'object',
  properties: {
    asks: { type: 'array', items: { type: 'string' } },
    facts: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          claim: { type: 'string' },
          check_cmd: { type: 'string' },
          match: { type: 'string', enum: ['number', 'substring'] },
        },
        required: ['claim', 'check_cmd', 'match'],
      },
    },
  },
  required: ['asks', 'facts'],
}

const brief = (c) =>
  `You are building an ANSWER KEY for a task another agent will be given. You never answer the task.\n\n` +
  `The task's files are a frozen copy at ${c.root} (the task text writes it as {{REPO}}; outputs it asks ` +
  `for are written under {{OUT}}, which does not exist yet). Read only; write nothing anywhere.\n\n` +
  `THE TASK:\n<<<\n${c.brief}\n>>>\n\n` +
  `Return:\n` +
  `- asks: each separate thing the task asks the agent to deliver, one plain sentence each (3-8 usually). ` +
  `A grader will check an answer against each ask.\n` +
  `- facts: up to 6 specific values a CORRECT answer must state that a shell command can compute from the ` +
  `frozen copy: counts, line numbers, file names, highest/lowest values, exact strings. For each: claim ` +
  `(what the value is), check_cmd (a read-only bash command run with cwd = ${c.root}, using relative paths, ` +
  `that prints ONLY the expected value on stdout — no labels, one line), and match ("number" if the value is ` +
  `a number, else "substring"). Only include a fact when the task clearly requires that exact value in the ` +
  `answer; an empty list is correct for judgement or prose tasks. Verify each check_cmd by running it.`

phase('Keys')
const keys = await parallel(
  INPUT.cases.map((c) => () =>
    agent(brief(c), { label: `keygen:${c.case_id}`, phase: 'Keys', model: 'sonnet', agentType: 'workflow-lean', schema: KEY })
      .then((k) => ({ case_id: c.case_id, key: k }))
  )
)
return { keys: keys.filter(Boolean) }
