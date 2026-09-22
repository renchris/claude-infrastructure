export const meta = {
  name: 'o55-synth-corpus',
  description: 'Draft + adversarially verify 6 repo-grounded synthesis briefs and answer keys for the Opus 5.5 synth re-probe',
  phases: [{ title: 'Draft' }, { title: 'Refute' }],
}
const REPO = '/tmp/o55probe-repo-47c3317eb'
const TOPICS = [
  { id: 'T1-custody', hard: true, topic: 'The custody-debt lifecycle: when a fire arms --notify-back a custody DEBT is recorded; how/where it is recorded and keyed, every path that discharges it (return / abandon / peer self-close / deathwatch or anything else), and every CONSUMER that reads open custody and what it does with it (close ledger rung, completion/done-claim gate, Stop/wake floors, readouts). Seeds (not exhaustive): bin/cc-custody, scripts/handoff-fire.sh, scripts/wrap-ledger.sh, hooks/completion-assert.sh, hooks/session-continue.sh, scripts/custody-deathwatch.sh.' },
  { id: 'T2-recycle-goal', hard: true, topic: 'How `scripts/handoff-fire.sh --recycle` carries the predecessor session\'s live /goal condition onto the successor: where the predecessor goal is read from (which store/file/lib), precedence vs an explicit --goal, the opt-out, what happens to terminal/absent goals, what validation an inherited condition goes through and what happens if it is refused, and where in the recycle flow it is invoked. Seeds: scripts/handoff-fire.sh (inherit_recycle_goal), hooks/lib/goal-state.sh, hooks/goal-inert-watch.sh.' },
  { id: 'T3-frontier-budget', hard: true, topic: 'How the per-session frontier (Fable) spawn budget is enforced: which hook(s) gate Agent-tool spawns AND handoff-fire `--model <frontier>` session fires, where the budget number is read from (and its value), how spawns are counted and keyed/stored per session, what happens at/over the cap, kill switches/bypasses, and what determines whether the Bash (session-fire) arm is actually live (registration). Seeds: hooks/frontier-spawn-gate.sh, model-config.yaml, scripts/handoff-fire.sh, migrations/, settings templates.' },
  { id: 'T4-stop-arms', hard: true, topic: 'Every condition under which hooks/session-continue.sh BLOCKS a Stop (feeds the model another turn): enumerate each arm (agent-armed sentinel, mechanical uncommitted-writes arm, ship floor, custody/mail wake floors, anything else), and for each: the trigger predicate, the counter/cap and its env var(s) and default, how authorship/attribution is decided (which lib), and the exemptions/kill switches. Seeds: hooks/session-continue.sh, hooks/lib/session-writes.sh.' },
  { id: 'T5-deploy-live-exec', hard: false, topic: 'A find-every-site brief: every site in hooks/, scripts/, bin/ (top level and lib subdirs; exclude tests/, docs/, vendor/) that EXECUTES scripts/deploy-live.sh (invokes it as a command, directly or via a variable/path), as opposed to merely MENTIONING it in a comment, a help/message string shown to a human, or a grep pattern. Exclude deploy-live.sh invoking itself unless it genuinely re-execs itself.' },
  { id: 'T6-choose', hard: false, topic: 'Choose ONE find-every-site predicate over hooks/ that is crisp, deterministic to key, and needs reading (not a single grep) to answer correctly — e.g. "every top-level hook in hooks/ that can emit a Stop-blocking decision (decision:block) — give file:line of each emission", or "every file that sources hooks/lib/origin-identity.sh and which of its functions it calls". Pick whichever yields 6-15 sites and has at least one trap (a near-miss that a lazy grep would wrongly include or exclude).' },
]
const KEY_SCHEMA = {
  type: 'object',
  properties: {
    brief: { type: 'string', description: 'Final self-contained question text given to the worker, of the form "Explain how ... citing path:line for every claim" or "Find every site that ...". Do not mention answer-key contents.' },
    is_hard: { type: 'boolean', description: 'true only if a correct answer spans >=4 distinct files AND the answer is non-obvious (a surface read of one file or the docs would get it wrong or incomplete)' },
    files_spanned: { type: 'array', items: { type: 'string' } },
    traps: { type: 'array', items: { type: 'string' }, description: 'non-obvious points / near-misses that separate a careful answer from a lazy one (e.g., stale line citations in docs, a comment that contradicts code)' },
    key: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          claim: { type: 'string', description: 'one atomic, checkable fact' },
          file: { type: 'string', description: 'path relative to repo root' },
          line: { type: 'integer' },
          quote: { type: 'string', description: 'an EXACT verbatim substring of that line (>=12 chars), copied byte-for-byte' },
        },
        required: ['id', 'claim', 'file', 'line', 'quote'],
      },
    },
  },
  required: ['brief', 'is_hard', 'files_spanned', 'traps', 'key'],
}
const REFUTE_SCHEMA = {
  type: 'object',
  properties: {
    items: { type: 'array', items: { type: 'object', properties: {
      id: { type: 'string' }, verdict: { type: 'string', enum: ['correct', 'wrong-line', 'wrong-claim', 'imprecise'] },
      fix: { type: 'string', description: 'corrected claim or line+quote if not correct; empty if correct' } }, required: ['id', 'verdict', 'fix'] } },
    missing: { type: 'array', items: { type: 'object', properties: {
      claim: { type: 'string' }, file: { type: 'string' }, line: { type: 'integer' }, quote: { type: 'string' } }, required: ['claim', 'file', 'line', 'quote'] },
      description: 'material facts a complete answer must contain that the key omits' },
    brief_ok: { type: 'boolean', description: 'is the brief unambiguous and answerable from the repo?' },
    hard_ok: { type: 'boolean', description: 'does it genuinely meet the HARD bar (>=4 files, non-obvious)?' },
    notes: { type: 'string' },
  },
  required: ['items', 'missing', 'brief_ok', 'hard_ok', 'notes'],
}
const results = await pipeline(TOPICS,
  t => agent(`You are building ONE item of a frozen evaluation corpus. Repository snapshot (read-only, pinned sha 47c3317eb): ${REPO}. Read ONLY files under that path. Do not edit anything.

TOPIC: ${t.topic}
Target: ${t.hard ? 'HARD (the correct answer must span >=4 files and be non-obvious)' : 'a find-every-site brief (exhaustive site list is the key)'}.

Do this:
1. Read the code thoroughly (grep broadly, then read the relevant line ranges). Ground everything in CODE, not docs/comments — where a comment or doc cites a line number, check it; stale citations are useful traps.
2. Write the final brief text a worker will receive (self-contained; says "cite path:line for every claim"; do NOT leak the answer).
3. Write the answer key: 6-14 atomic facts (for find-every-site: one item per site, exhaustive). Each item: path relative to repo root, 1-based line number, and an EXACT verbatim substring of that line (>=12 chars) — copy it byte-for-byte from the file.
4. List the traps.
Be exhaustive and precise; this key will be used to score other models' recall.`,
    { label: `draft:${t.id}`, phase: 'Draft', model: 'claude-opus-5', effort: 'xhigh', schema: KEY_SCHEMA }),
  (draft, t) => draft && agent(`You are an adversarial checker of an evaluation answer key. Repository snapshot (read-only): ${REPO}. Read only under that path.

BRIEF:\n${draft.brief}\n\nANSWER KEY (JSON):\n${JSON.stringify(draft.key, null, 1)}\n\nClaimed hard: ${draft.is_hard}; files: ${draft.files_spanned.join(', ')}

Default to refute. For EVERY key item open the cited file at the cited line and check (a) the quote is verbatim on that line, (b) the claim is actually true of the code (read surrounding logic, not just the line). Then independently answer the brief yourself enough to find MATERIAL facts the key omits (for a find-every-site brief: any missing or wrongly-included site). Report per-item verdicts, missing items with exact line quotes, and whether the brief is unambiguous and meets the hard bar (>=4 files, non-obvious).`,
    { label: `refute:${t.id}`, phase: 'Refute', model: 'claude-opus-5', effort: 'xhigh', schema: REFUTE_SCHEMA })
    .then(r => ({ id: t.id, draft, refute: r })),
)
return results
