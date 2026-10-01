export const meta = {
  name: 'calib-a3-triage',
  description: 'A3 calibration: dedup, blind verify, Opus rating, scoring against history, and history-hole audit per plan',
  phases: [{ title: 'Adjudicate' }, { title: 'Verify' }, { title: 'Rate' }, { title: 'Score' }, { title: 'Audit' }],
}
const C = args.cache
const ITEMS = { type: 'object', required: ['items'], properties: { items: { type: 'array', items: { type: 'object',
  required: ['iid', 'title', 'claim', 'consequence', 'location', 'quote', 'clause', 'omission', 'members'],
  properties: { iid: { type: 'string' }, title: { type: 'string' }, claim: { type: 'string' }, consequence: { type: 'string' },
    location: { type: 'string' }, quote: { type: 'string' }, clause: { type: 'string' }, omission: { type: 'boolean' },
    members: { type: 'array', items: { type: 'string' } } } } } } }
const VER = { type: 'object', required: ['verdicts'], properties: { verdicts: { type: 'array', items: { type: 'object',
  required: ['iid', 'verdict', 'consequence_reproduced', 'receipt', 'reason'],
  properties: { iid: { type: 'string' }, verdict: { type: 'string', enum: ['CONFIRMED', 'REFUTED', 'CONTACT'] },
    consequence_reproduced: { type: 'boolean' }, receipt: { type: 'string' }, reason: { type: 'string' } } } } } }
const RATE = { type: 'object', required: ['ratings'], properties: { ratings: { type: 'array', items: { type: 'object',
  required: ['iid', 'rating', 'clause', 'reason'],
  properties: { iid: { type: 'string' }, rating: { type: 'string', enum: ['MATERIAL', 'REFINEMENT', 'COSMETIC', 'GENERIC'] },
    clause: { type: 'string' }, reason: { type: 'string' } } } } } }
const SCORE = { type: 'object', required: ['item_matches', 'holes', 'seeds'], properties: {
  item_matches: { type: 'array', items: { type: 'object', required: ['iid', 'match', 'ref', 'confidence'], properties: {
    iid: { type: 'string' }, match: { type: 'string', enum: ['hole', 'seed', 'none'] }, ref: { type: 'string' }, confidence: { type: 'number' } } } },
  holes: { type: 'array', items: { type: 'object', required: ['hole_id', 'detected_by_iids', 'partial'], properties: {
    hole_id: { type: 'string' }, detected_by_iids: { type: 'array', items: { type: 'string' } }, partial: { type: 'boolean' } } } },
  seeds: { type: 'array', items: { type: 'object', required: ['seed_id', 'detected_by_iids'], properties: {
    seed_id: { type: 'string' }, detected_by_iids: { type: 'array', items: { type: 'string' } } } } } } }
const AUD = { type: 'object', required: ['audits'], properties: { audits: { type: 'array', items: { type: 'object',
  required: ['hole_id', 'real', 'material', 'present_at_freeze', 'found_by_ok', 'evidence_ok', 'note'],
  properties: { hole_id: { type: 'string' }, real: { type: 'boolean' }, material: { type: 'boolean' }, present_at_freeze: { type: 'boolean' },
    found_by_ok: { type: 'boolean' }, evidence_ok: { type: 'boolean' }, note: { type: 'string' } } } } } }
const RO = 'You are strictly read-only: never edit, write, move or delete any file; never run git checkout, switch, worktree, stash, reset, commit or fetch; nobody can answer a permission prompt for you.'
const chunks = (xs, n) => { const o = []; for (let i = 0; i < xs.length; i += n) o.push(xs.slice(i, i + n)); return o }
const blind = (it) => ({ iid: it.iid, title: it.title, claim: it.claim, consequence: it.consequence, location: it.location, quote: it.quote, clause: it.clause, omission: it.omission })
const run = async (p) => {
  const bundle = `${C}/bundles/${p}/full`
  const adj = await agent(`${RO}
You are the deduplication adjudicator for one plan's review round. Read ${C}/replay/findings/${p}.json: a list of findings from several independent reviewers of the same frozen plan (each has fid and reviewer). Merge findings that describe the SAME defect (same location or same underlying fault) into one item; never merge two different defects that merely share a section. Every fid must appear in exactly one item's members. Give each item iid I1, I2, ... in order of first appearance, a short title, a merged claim and consequence, the best location and verbatim quote, the clause (a-g) most reviewers gave, and omission. You may read the frozen plan under ${bundle}/plan to check whether two findings point at the same text. Return through StructuredOutput.`,
    { label: `adjudicate:${p}`, phase: 'Adjudicate', schema: ITEMS, effort: 'high', agentType: 'workflow-lean' })
  if (!adj) return { plan: p, error: 'adjudicate' }
  const items = adj.items
  const vparts = await parallel(chunks(items, 12).map((ch, k) => () => agent(`${RO}
You are a verifier. Below are candidate defects in a frozen plan. You do not know who raised them or how many times. For each, reproduce it from the primary source: the frozen plan and its cited research/code under ${bundle} (read only that directory). Verdict CONFIRMED if the sources show the claim is true as stated; REFUTED if the sources show it false, if the quoted text does not exist, or if the plan already handles it elsewhere (search the whole plan before confirming an omission); CONTACT if its truth needs a live run, production data or a measurement that no file here can settle. consequence_reproduced: true only if you can show from the sources that the stated consequence for the plan follows. Give a file:line receipt and a one-line reason. Default to REFUTED when the sources do not support the claim.
ITEMS:
${JSON.stringify(ch.map(blind))}`, { label: `verify:${p}:${k}`, phase: 'Verify', schema: VER, effort: 'high', agentType: 'workflow-lean' })))
  const verdicts = vparts.filter(Boolean).flatMap(v => v.verdicts)
  const conf = new Set(verdicts.filter(v => v.verdict === 'CONFIRMED').map(v => v.iid))
  const toRate = items.filter(it => conf.has(it.iid))
  const rparts = await parallel(chunks(toRate, 15).map((ch, k) => () => agent(`${RO}
You are rater 2 (Anthropic) for confirmed findings on a frozen plan. You do not know the round, how many reviewers raised each item, or any other rater's view. Rate each item under this rubric, reading the plan under ${bundle}/plan as needed.
${args.rubric}
ITEMS:
${JSON.stringify(ch.map(blind))}`, { label: `rate:${p}:${k}`, phase: 'Rate', schema: RATE, effort: 'high', agentType: 'workflow-lean' })))
  const ratings = rparts.filter(Boolean).flatMap(r => r.ratings)
  const score = await agent(`${RO}
You are the scorer. Match a round's findings to known ground truth for one plan.
1. Read the known later holes: ${C}/history/${p}.json (field holes; each has id, summary, receipt, fix_born). Fix-born holes did not exist at the freeze, so no finding can match them; skip those.
2. Read the planted seeds: ${C}/seeds/${p}.json (seed_id, defect, detection_span, anchor, replacement).
3. For each finding below decide match: 'seed' if it detects a planted seed's defect (ref = seed_id), 'hole' if it identifies the same defect as a known hole (ref = hole id; the same underlying fault, not merely the same topic), else 'none'. Give confidence 0-1.
4. For every non-fix-born hole list detected_by_iids (empty if none) and partial=true if a finding touches it but misses the material point. For every seed list detected_by_iids.
FINDINGS:
${JSON.stringify(items.map(blind))}`, { label: `score:${p}`, phase: 'Score', schema: SCORE, effort: 'high', agentType: 'workflow-lean' })
  return { plan: p, n_items: items.length, n_confirmed: conf.size, n_rated: ratings.length, scored: !!score }
}
const audit = (p) => agent(`${RO}
You are an adversarial auditor of a historical record. Read ${C}/history/${p}.json. Audit ONLY these holes: ${JSON.stringify(args.sample[p])}. For each, try to REFUTE the record using the repo named in the file (read-only git: git show <sha>:<path>, git log, git blame, git diff). Answer: real (the defect truly existed or was truly missing in the plan at freeze_sha), material (it meets one of the REPORT §3.11 clauses a-g: flips a decision, changes an acceptance verdict, changes sequencing or an interface, adds a census member that changes a row, moves a premise, is a safety/data hazard, or is a missing decision/component), present_at_freeze (the defective or missing text is in the plan at freeze_sha, not added later), found_by_ok and evidence_ok (the recorded found_by and evidence_at_freeze labels are right). Default to false when the receipts do not support the record.`,
  { label: `audit:${p}`, phase: 'Audit', schema: AUD, effort: 'high', agentType: 'workflow-lean' })
const [main, aud] = await Promise.all([
  pipeline(args.plans, run),
  parallel(args.plans.map(p => () => audit(p))),
])
return { main, audits: aud.filter(Boolean).length }
