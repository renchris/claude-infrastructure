// run-workflow.mjs <file.workflow.js> — evaluates a Workflow script against stub agent()/parallel()/
// pipeline()/log()/phase() and prints three verdict lines for tests/cc-research-cert.bats:
//   order ok|bad      every `cc-research slot` agent ran before the first `cc-research check-round`
//   commands ok|bad   every backtick span in every prompt is a `<repo>/bin/cc-research …` command,
//                     and no prompt names a kit script or a vendor CLI
//   calls N
// Exit 1 when either verdict is bad or the script throws.
// run-workflow.mjs --check <file> compiles the body as the runtime does (an async function body:
// top-level await and return are legal there and nowhere else) and prints `parse ok`.
import { readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const REPO = '/REPO'
const REAL = resolve(dirname(fileURLToPath(import.meta.url)), '../../..')
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor
const PARAMS = ['args', 'agent', 'parallel', 'pipeline', 'log', 'phase', 'budget', 'workflow']
const load = (f) => readFileSync(f, 'utf8').replace(/^export const meta\s*=/m, 'const meta =')
if (process.argv[2] === '--check') {
  try { new AsyncFunction(...PARAMS, load(process.argv[3])) } catch (e) {
    console.log(`parse failed: ${e.message}`)
    process.exit(1)
  }
  console.log('parse ok')
  process.exit(0)
}
const src = load(process.argv[2])
const calls = []
const stub = (label) => ({
  exit: 0, output: '', voided: [], findings: [], frames: ['are you sure'], reply: 'demo: certified',
  tools: ['cc-research verdict demo'], pid: label.split(':')[1] || '',
  slots: [{ pid: 'r1p1', vendor: 'anthropic', strategy: 'full-context', role: 'reviewer', round: '1' },
          { pid: 'r1p2', vendor: 'openai', strategy: 'plan-only', role: 'reviewer', round: '1' }],
  raters: [{ pid: 'r1rater1', slot: 1, vendor: 'openai', family: 'openai', fresh_process: false }],
})
const agent = async (prompt, opts = {}) => {
  calls.push({ prompt, label: opts.label || '' })
  return stub(opts.label || '')
}
const parallel = async (thunks) => Promise.all(thunks.map(t => t().catch(() => null)))
const pipeline = async (items, ...stages) => Promise.all(items.map(async (it, i) => {
  let v = it
  for (const s of stages) v = await s(v, it, i)
  return v
}))
const args = { program: 'demo', round: 1, plan: `${REPO}/PLAN.md`, brief: `${REPO}/brief.txt`, repo: REPO,
  outside_cwd: '/elsewhere', trials_file: '/tmp/trials.jsonl' }
const budget = { total: null, spent: () => 0, remaining: () => Infinity }
const exec = (code, a, depth) => new AsyncFunction(...PARAMS, code)(a, agent, parallel, pipeline, () => {}, () => {},
  budget, async (ref, childArgs) => { // one nesting level, as the runtime allows; /REPO maps to this checkout
    if (depth) throw new Error('workflow() nests one level only')
    return exec(load(ref.scriptPath.replace(REPO, REAL)), childArgs, depth + 1)
  })
let ok = true
try {
  await exec(src, args, 0)
} catch (e) {
  console.log(`threw ${e && e.message}`)
  ok = false
}
// Per round: each check-round follows at least one slot since the previous check, and no slot
// runs after the last check (the stubbed check voids nothing, so no re-run is due).
let since = 0, checks = 0, order = true
for (const c of calls) {
  if (/cc-research slot /.test(c.prompt)) since++
  if (/cc-research check-round /.test(c.prompt)) { order = order && since > 0; since = 0; checks++ }
}
if (checks) {
  order = order && since === 0
  console.log(`order ${order ? 'ok' : 'bad'}`)
  ok = ok && order
}
const bad = []
for (const c of calls) {
  for (const m of c.prompt.matchAll(/`([^`]+)`/g))
    if (!m[1].startsWith(`${REPO}/bin/cc-research `)) bad.push(m[1])
  for (const m of c.prompt.matchAll(/\b(courier\.sh|round\.sh|gate\.sh|probe-run\.sh|codex|gemini)\b/g)) bad.push(m[1])
}
console.log(`commands ${bad.length ? 'bad: ' + bad.join(' | ') : 'ok'}`)
console.log(`calls ${calls.length}`)
process.exit(ok && !bad.length && calls.length ? 0 : 1)
