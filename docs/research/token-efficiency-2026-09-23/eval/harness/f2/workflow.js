export const meta = {
  name: 'tokeff-f2-gate',
  description: 'F2 offline gate: 10 read-only briefs x 8 slots, agentType alternating default / workflow-lean',
  phases: [{ title: 'Slots', detail: '80 read-only slots over a frozen tree, 4 per arm per brief' }],
}

// Frozen population built by f2/setup.sh. Every slot writes ONLY to its own OUTDIR.
// args.root (default /tmp/tokeff-gate) lets a re-gate run over a copy of the population without
// overwriting the recorded gate's slots; collect.py reads the same root from GATE_ROOT.
const ROOT = (typeof args === 'object' && args && args.root) || '/tmp/tokeff-gate'
const F = `${ROOT}/f2`
const T = `${F}/tree`
const RULES = (out) =>
  `Rules: this is READ-ONLY work. Read anything you need, but create or modify files ONLY inside ${out}/ ` +
  `(no scratch files in /tmp or anywhere else, no edits to the tree). Write your full answer to ${out}/answer.md. ` +
  `Then return the structured output: answer_path = ${out}/answer.md, headline = your answer in one sentence, ` +
  `numbers = the named numeric results the brief asks for (use {} if it asks for none).`

const BRIEFS = [
  { id: 'B01', text: `In ${T}/hooks/session-continue.sh, list every condition under which this Stop hook blocks a stop (emits a block decision or a blocking reason). For each give the line number, one sentence on the trigger, and the env var or kill switch that disables it, if any. numbers: {"conditions": <how many you listed>}.` },
  { id: 'B02', text: `Census of CLAUDE_CONFIG_DIR fallbacks under ${T}/bin, ${T}/hooks and ${T}/scripts (all depths). Count every parameter expansion of the form \${CLAUDE_CONFIG_DIR:-<fallback>} on lines that are code, not comments (a line whose first non-space character is # is a comment). Report the total, how many have an EMPTY fallback (\${CLAUDE_CONFIG_DIR:-}), and how many distinct files contain at least one. Tabulate the distinct fallback values with counts. numbers: {"expansions": N, "empty_fallbacks": N, "files": N}.` },
  { id: 'B03', text: `${F}/corpus holds session transcripts, one JSON record per line. A "Stop hook feedback" record is a record with "isMeta": true whose message content is a string starting with "Stop hook feedback". Count the sessions (files), the sessions containing at least one such record, and the total number of such records. Beware of ordinary user messages that merely mention the phrase. numbers: {"sessions": N, "sessions_with_feedback": N, "feedback_records": N}.` },
  { id: 'B04', text: `How big is the bats test suite in ${T}/tests? Count the .bats files (all depths) and the total number of @test cases across them. Name the 3 files with the most @test cases. numbers: {"bats_files": N, "test_cases": N}.` },
  { id: 'B05', text: `Read ${T}/.claude/settings.json. How many entries are in permissions.allow, and how many of them start with "Bash(cc-"? List the cc- entries. Summarise in two sentences what the _why_converge note says the carve-out does NOT allow. numbers: {"allow_entries": N, "cc_entries": N}.` },
  { id: 'B06', text: `Review ${F}/review/rotate-logs.sh for bugs. List each real bug with the line, what goes wrong, and a one-line fix. Do not list style nits separately from real bugs; rank by severity. Do not run the script. numbers: {"bugs": <how many real bugs>}.` },
  { id: 'B07', text: `Measure the hook scripts: for the files directly inside ${T}/hooks whose names end in .sh (not subdirectories), report how many there are, their total line count, and the 3 largest by line count with their line counts. numbers: {"sh_files": N, "total_lines": N}.` },
  { id: 'B08', text: `From ${T}/docs/research/token-efficiency-2026-09-23/BASELINE.md, extract the table whose first column header is ctx_type: for every row give ctx_type, contexts and the "$ own" value exactly as written. Then say in one sentence which ctx_type has the highest $ own per context. numbers: {"rows": <row count>}.` },
  { id: 'B09', text: `List the migrations in ${T}/migrations: files named NNNN-<slug>.sh. How many are there and what is the highest number? For the 3 highest-numbered, give the slug and one sentence on what each does (from its header comment). numbers: {"count": N, "highest": N}.` },
  { id: 'B10', text: `In ${T}/scripts/wrap-ledger.sh, which environment variables act as kill switches or off-switches (a variable that, when set to off/0, disables a section or check)? For each give the variable, the line, and what it turns off. numbers: {"kill_switches": <how many>}.` },
]

const SCHEMA = {
  type: 'object',
  properties: {
    answer_path: { type: 'string' },
    headline: { type: 'string' },
    numbers: { type: 'object' },
  },
  required: ['answer_path', 'headline', 'numbers'],
}

// Per brief: ABBA ABBA over 8 reps; A = default on even-indexed briefs, workflow-lean on odd ones.
const slots = []
BRIEFS.forEach((b, i) => {
  const [A, B] = i % 2 === 0 ? ['default', 'workflow-lean'] : ['workflow-lean', 'default']
  const order = [A, B, B, A, A, B, B, A]
  order.forEach((arm, r) => slots.push({ brief: b, rep: r + 1, arm }))
})

// args.only = ["B04:4", ...] re-runs just those slots (a harness-faulted cell, never a re-draw).
const only = (typeof args === 'object' && args && args.only) || null
const todo = only ? slots.filter((s) => only.includes(`${s.brief.id}:${s.rep}`)) : slots

phase('Slots')
const results = await parallel(
  todo.map((s) => () => {
    const out = `${F}/out/${s.brief.id}-r${s.rep}`
    const opts = { label: `f2:${s.brief.id}:r${s.rep}`, phase: 'Slots', schema: SCHEMA }
    if (s.arm === 'workflow-lean') opts.agentType = 'workflow-lean'
    return agent(`${s.brief.text}\n\n${RULES(out)}`, opts).then((r) => ({
      brief: s.brief.id, rep: s.rep, arm: s.arm, result: r,
    }))
  })
)
const done = results.filter(Boolean)
log(`${done.length}/${slots.length} slots returned`)
return { slots: slots.map((s) => ({ brief: s.brief.id, rep: s.rep, arm: s.arm })), results: done }
