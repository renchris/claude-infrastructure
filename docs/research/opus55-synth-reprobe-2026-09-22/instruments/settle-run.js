export const meta = {
  name: 'o55-synth-reprobe-settle',
  description: 'Blind judged A/B/C of workflow_synthesis_worker: Sonnet 5 @max vs Opus 5.5 @high/@xhigh on 6 frozen repo briefs',
  phases: [{ title: 'Arms' }, { title: 'Judge' }],
}
const REPO = '/tmp/o55probe-repo-47c3317eb'
const BRIEFS = ['T1-custody', 'T2-recycle-goal', 'T3-frontier-budget', 'T4-stop-arms', 'T5-deploy-live-exec', 'T6-choose']
const ARMS = [
  { arm: 'A', model: 'claude-sonnet-5', effort: 'max' },
  { arm: 'B', model: 'claude-opus-5-5', effort: 'high' },
  { arm: 'C', model: 'claude-opus-5-5', effort: 'xhigh' },
]
const PERMS = [['A','B','C'],['A','C','B'],['B','A','C'],['B','C','A'],['C','A','B'],['C','B','A']]
const LBL = ['X', 'Y', 'Z']

const armPrompt = id => `You are a synthesis worker in a research workflow.

Repository: ${REPO} — a read-only snapshot of the claude-infrastructure repo, pinned at sha 47c3317eb. Read only files under that path. Paths you cite are relative to that root.

Your brief is in the file /tmp/o55-briefs/${id}.md — Read it first; it is the whole task.

Rules:
- Tools: use Read, and Bash for READ-ONLY search and inspection only (grep, find, ls, cat, sed -n, head, tail, wc). Never write, move or delete anything, never run a script from the repo, do not spawn agents. (The Grep/Glob tools do not exist in this harness.) Stay inside the repository path above.
- Saturation bound: after reading the brief, make at most 25 further tool calls, then write your answer from what you have read.
- Cite path:line for every claim, and cite only lines you actually read.
- Your final message IS the deliverable: a complete markdown answer to the brief. No preamble.`

const JUDGE_SCHEMA = {
  type: 'object',
  properties: {
    outputs: { type: 'array', items: { type: 'object', properties: {
      label: { type: 'string', enum: LBL },
      key_hits: { type: 'array', items: { type: 'string' }, description: 'answer-key item ids this output states correctly (substance, not just a matching line)' },
      key_contradicted: { type: 'array', items: { type: 'string' }, description: 'key ids this output states WRONGLY' },
      citations_checked: { type: 'integer' },
      citations_bad: { type: 'array', items: { type: 'object', properties: { cite: { type: 'string' }, problem: { type: 'string', description: 'e.g. line does not contain the claimed code; file absent; wrong file; fabricated symbol' } }, required: ['cite', 'problem'] } },
      wrong_claims: { type: 'array', items: { type: 'string' } },
      extra_correct: { type: 'array', items: { type: 'string' }, description: 'verified correct, material claims NOT in the key' },
      score_1_10: { type: 'integer' },
    }, required: ['label', 'key_hits', 'key_contradicted', 'citations_checked', 'citations_bad', 'wrong_claims', 'extra_correct', 'score_1_10'] } },
    xy: { type: 'string', enum: ['X', 'tie', 'Y'] },
    xz: { type: 'string', enum: ['X', 'tie', 'Z'] },
    yz: { type: 'string', enum: ['Y', 'tie', 'Z'] },
    pair_reasons: { type: 'string', description: 'one short paragraph per pair naming the specific verified differences' },
  },
  required: ['outputs', 'xy', 'xz', 'yz', 'pair_reasons'],
}

const judgePrompt = (id, outs) => `You are a blind judge in a model evaluation. Three anonymous workers (X, Y, Z) answered the same repo-grounding synthesis brief.

Repository snapshot they read (read-only; you may read it too): ${REPO} (pinned sha 47c3317eb).
The brief: /tmp/o55-briefs/${id}.md
The verified answer key: /Users/chrisren/Development/claude-infrastructure/docs/research/opus55-synth-reprobe-2026-09-22/corpus/keys/${id}.md — read BOTH files first.

Your job, default-to-refute (treat every claim as unverified until you check it):
1. For each output, mark which key items it states correctly in substance (key_hits) and which it states wrongly (key_contradicted). The key is a floor, not a ceiling.
2. SPOT-CHECK CITATIONS BYTE-FOR-BYTE: for each output open at least 8 cited path:line locations (all of them if fewer), prioritising load-bearing claims, and confirm the cited line actually contains what the output says it does. Record every bad one (wrong line, wrong file, nonexistent symbol, fabricated quote).
3. List material wrong claims and verified correct material claims beyond the key.
4. Pairwise verdicts X vs Y, X vs Z, Y vs Z. Call a winner only on a specific, verified, material difference (a key fact one got and the other missed or got wrong, a fabricated or wrong citation, a wrong claim, a material verified insight the other lacks). If you cannot find one, call tie. Length and polish are not quality.
Do not guess which model wrote which output; it is irrelevant.

=== OUTPUT X ===
${outs[0]}

=== OUTPUT Y ===
${outs[1]}

=== OUTPUT Z ===
${outs[2]}`

const retryOnce = async (fn, label) => {
  let r = await fn(label)
  if (r == null || r === '') { log(`${label}: null/empty — one retry`); r = await fn(label + ':retry'); return { r, retried: true } }
  return { r, retried: false }
}

const results = await pipeline(BRIEFS,
  (id) => parallel(ARMS.map(a => () =>
    retryOnce(lbl => agent(armPrompt(id), { label: lbl, phase: 'Arms', model: a.model, effort: a.effort }), `arm:${id}:${a.arm}`)
      .then(x => ({ arm: a.arm, model: a.model, effort: a.effort, text: x.r, retried: x.retried })))),
  (arms, id, i) => {
    const by = Object.fromEntries(arms.filter(Boolean).map(a => [a.arm, a]))
    return parallel([0, 1, 2].map(j => () => {
      const perm = PERMS[(i * 3 + j) % 6]
      const fable = j === i % 3
      const model = fable ? 'claude-fable-5-1' : 'claude-opus-5'
      const effort = fable ? 'high' : 'xhigh'
      const outs = perm.map(arm => (by[arm] && by[arm].text) || '(this worker produced no output)')
      return retryOnce(lbl => agent(judgePrompt(id, outs), { label: lbl, phase: 'Judge', model, effort, schema: JUDGE_SCHEMA }), `judge:${id}:J${j}`)
        .then(x => ({ j, model, effort, perm, verdict: x.r, retried: x.retried }))
    })).then(judges => ({ id, arms, judges }))
  })
return results
