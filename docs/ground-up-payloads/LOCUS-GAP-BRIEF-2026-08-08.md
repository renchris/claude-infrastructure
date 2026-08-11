Investigate and fix ONE behavioural gap in claude-infrastructure. The investigation is largely
DONE — this brief carries the finding and the evidence. Your job is to verify it, decide the
design, and implement. Do not re-derive the diagnosis from scratch.

## The operator's report

After a long-horizon design session on reso's `/preview/bottle-service-motion`, the operator
asked: *"Shouldn't our claude-infrastructure have our Claude agent behavior to fire off every
independent and isolated task to a /handoff to preserve context in the main session to be the
driver and judgement of the long-horizon task? I thought we just fixed this about an hour ago."*

They are right on both counts. `9ad8ae40 feat(plan-conventions): Phase 0 named who does the
work, never where — so delegating harder burned the lead` DID land ~1h before. It did not fire
where it mattered.

## The finding — VERIFIED, not hypothesised

**The Execution Locus rule is enforced ONLY on the plan-authoring path.** Both hooks that carry
it gate on plan-file PATHS:

- `hooks/plan-agent-teams-default.sh` (PreToolUse) — cases at lines 18-24: `~/.claude/plans/*.md`,
  `*/.claude-plans/*.md`, `*/docs/plans/*.md`, `*PLAN*.md`, `*plan*.md`
- `hooks/validate-plan-structure.sh` (PostToolUse) — cases at lines 57-61, same shape
- Both registered in `~/.claude/settings.json` (lines 485, 542)

So the locus decision point exists only if the agent WRITES A PLAN FILE.

**Implementation that arrives as operator feedback never touches a plan file.** In the session
that produced this brief, four implementation slices arrived as corrections — "the URL is
stale", "these toggles make no sense", "the dropdown gets in the way of comparing", "I don't
know how to see carry/wipe". Each produced real code. None began at a plan edit. The lead ran
all four inline (locus `L`) without ever writing the one-line justification the rule requires.

The hook fired EXACTLY ONCE, and too late to govern anything: on a RETROSPECTIVE plan-doc write
made after the code was already written, gated and landed. Its text —
`⚠️ EXECUTION LOCUS MISSING … no wave declares WHERE it runs` — is correct and arrived after the
decision it exists to govern. It is also advisory `additionalContext`, so ignoring it is free.

**Net:** the sensor is bound to the wrong path and fires after the fact. Not "no rule", not "no
sensor" — a sensor on the path the work did not take.

## The second failure mode, and it is the harder one

**Salami-slicing.** No single operator correction looks like a wave. Slice 1 inline is genuinely
defensible — it was investigative, needed the live browser, and the operator was in a tight
feedback loop where a dispatch round trip would have been slower. Slices 1-4 inline is a wave,
and by then the lead had spent its window on ~15 browser measurement round trips, 4 full gate
runs and 3 lands.

So a correctly-placed sensor is still not enough: it has to ACCUMULATE ACROSS TURNS. The
question is not "is this task big" but "is this the Nth implementation slice of one theme in one
session".

## What to decide and build

1. **Where does the locus decision point live for work that never touches a plan?** Candidates,
   none obviously right — argue it, do not just pick:
   - a turn-scoped counter that notices N edits to source files in one session with no dispatch
   - a UserPromptSubmit hook that classifies the incoming prompt as implementation-shaped
   - a Stop-hook arm that reports slices-run-inline and nags at a threshold
2. 🚨 **The known trap: a Stop hook cannot scope-judge and cannot reach the model except by
   BLOCKING** (this is already written in global CLAUDE.md § Session Close Protocol — an
   advisory Stop hook is inert). Whatever you build must be fact-bound, not judgment-bound.
3. **Do not build a nag.** A sensor that fires on every source edit will be ignored inside a day,
   which is exactly how the current one failed. Prefer one that fires rarely and accurately.
4. **State the counter-argument in whatever you land.** "Dispatch everything" is wrong: it would
   have made this session's operator feedback loop materially slower, and the diagnosis slice
   genuinely belonged inline. The rule needs a defensible inline case, not a prohibition.

## Constraints

- INTEGRATE, never overwrite (global CLAUDE.md File Update Rule). `hooks/`, `skills/
  plan-conventions/`, and global `CLAUDE.md` all already carry locus text — extend, do not replace.
- Land through the repo's own gates. Do not `--no-verify`.
- If you conclude the right answer is "no new hook, change the always-resident rule wording
  instead", that is a legitimate outcome — say so with the reasoning.

## Stop on first issue and report back rather than widening scope.

Evidence session: reso worktree `wt-cc-005159-55873`, commits `3529f15b0`, `ab7b28ff5`,
`8623109d6` (all landed on reso `origin/main`).
