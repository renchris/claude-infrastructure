export const meta = {
  name: 'tokeff-f2-probe-scope',
  description: 'F2 mechanism probe: workflow-lean plus a one-line scope clause, on the 5 briefs where lean padded',
  phases: [{ title: 'Slots', detail: '20 lean slots (reps 9-12) with the scope clause' }],
}

// Frozen population built by f2/setup.sh. Every slot writes ONLY to its own OUTDIR.
const F = '/tmp/tokeff-gate/f2'
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

// PROBE (post-gate, not part of the verdict): only the 5 briefs where lean padded; lean only; reps 9-12;
// the brief carries one extra clause. Tests whether a scope instruction removes the padding regression.
const SCOPE = 'Answer exactly what the brief asks: no sections, rankings or extras it did not request, and keep to any length it names.'
const PROBE = ['B01', 'B02', 'B05', 'B06', 'B07']
const slots = []
BRIEFS.filter((b) => PROBE.includes(b.id)).forEach((b) => {
  ;[9, 10, 11, 12].forEach((rep) => slots.push({ brief: b, rep, arm: 'workflow-lean' }))
})

phase('Slots')
const results = await parallel(
  slots.map((s) => () => {
    const out = `${F}/out/${s.brief.id}-r${s.rep}`
    return agent(`${s.brief.text}\n\n${SCOPE}\n\n${RULES(out)}`, {
      label: `f2:${s.brief.id}:r${s.rep}`, phase: 'Slots', schema: SCHEMA, agentType: 'workflow-lean',
    }).then((r) => ({ brief: s.brief.id, rep: s.rep, arm: s.arm, result: r }))
  })
)
return results.filter(Boolean)
