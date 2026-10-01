export const meta = {
  name: 'calib-a3-timing',
  description: 'A3 calibration: measure research wall-clock per held-out plan from session transcripts',
  phases: [{ title: 'Timing', detail: 'one read-only transcript miner per plan' }],
}
const T = { type: 'object', required: ['plan', 'research_start', 'freeze_time', 'calendar_days', 'active_hours', 'sessions', 'method', 'confidence'],
  properties: { plan: { type: 'string' }, research_start: { type: 'string' }, freeze_time: { type: 'string' }, calendar_days: { type: 'number' },
    active_hours: { type: 'number' }, sessions: { type: 'number' }, decisions: { type: 'number' }, components: { type: 'number' },
    method: { type: 'string' }, confidence: { type: 'string' }, note: { type: 'string' } } }
const res = await parallel(args.plans.map(p => () => agent(`You are strictly read-only: never edit, write, move or delete any file except none; never run git checkout, switch, worktree, stash, reset, commit or fetch. Nobody can answer a permission prompt for you.

Measure how long the research behind one plan took, from first research activity to the plan's freeze.
Plan id: ${p}. Read ${args.cache}/history/${p}.json for the repo, plan path, freeze_sha, freeze_date and size.
1. freeze_time: git -C <repo> show -s --format=%cI <freeze_sha>.
2. research_start: the earliest transcript activity that is research for THIS plan. Transcripts are JSONL files under ~/.claude/projects, ~/.claude-next/projects, ~/.claude-tertiary/projects, ~/.claude-quaternary/projects, ~/.claude-next2/projects, ~/.claude-next3/projects, ~/.claude-next4/projects (whichever exist). Use rg -l with the plan's file name, its research directory name or distinctive topic phrases to find candidate sessions, then read their first timestamps. Also check the git log of the plan's research directory (first commit) and of the plan. Take the earliest that is clearly this plan's research, not an unrelated earlier mention.
3. calendar_days = (freeze_time - research_start) in days. active_hours: sum over the sessions that worked on this research before the freeze of (last timestamp - first timestamp) of their research span, capped at 8 h per session; sessions = how many.
4. decisions and components at freeze, from the history file's size field.
Give your method in one line and confidence high, medium or low. Do not read or quote message contents beyond what you need to date them.`,
  { label: `timing:${p}`, phase: 'Timing', schema: T, effort: 'high', agentType: 'workflow-lean' })))
return res.filter(Boolean)
