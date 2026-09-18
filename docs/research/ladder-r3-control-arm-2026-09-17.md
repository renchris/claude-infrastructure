# R3 receipt — the one unrun experiment that is the whole 72-vs-90 gap

Receipt for decision packet `a825773ca37b` (class C, conviction 72), filed
2026-09-17 against `docs/plans/NONLIMIT_RESUME_LADDER.md` § W3 R3.

**The decision.** Should a session escalate to the frontier model AUTOMATICALLY
whenever its own conviction is still under 90% after research, or should that
escalation stay a recipe the session chooses to reach for?

## Why the conviction is 72 and not higher

`git show origin/main:docs/plans/NONLIMIT_RESUME_LADDER.md | sed -n '769,790p'`:

> One trial, and it has no control arm. In the W1 run, the Fable pass had (i) a
> different model, (ii) a completely fresh context, and (iii) a written, distilled
> brief instead of accumulated session state. **Nobody ran the cheap arm** — recycle
> into a fresh *Opus 5* session with the same brief — so the nine refutations cannot
> be attributed to the model. […] Two of the nine items (#5 the task-notification
> substrate, #6 `turn_duration`) are *disk facts a fresh reader finds*, not model
> insight.

This repo's own rule, cited by the plan against itself:
`docs/lessons/one-armed-adjudication-only-convicts.md` — asymmetric evidence can
convict and never acquit, and its silence is read in the direction the analysis
already leans.

## What would lift it past 90, and it is cheap

Recycle the W1 brief into a fresh **Opus 5** session — `handoff-fire.sh --recycle
--model claude-opus-5` with the same `--prompt-file` — and count how many of the nine
refutations it also reaches. If it reaches most of them, the effect is **fresh
context, not the model tier**, and R3 should be REJECTED rather than adopted.

Two reasons it is not run in the session that filed this: running an unattended
frontier-class recycle to decide whether unattended frontier-class recycles should be
automatic is the decision deciding itself, and the operator's answer may make the
experiment moot.

## What is already decided and needs nothing from the operator

The ladder EXISTS and is correct either way. R1 landed the recipe into CLAUDE.md
§ Frontier Tier Routing (`c50a363b1`) and R2 landed its bound — the spawn gate's
session arm (`3d0af8257`) plus `migrations/0029` for its registration. **This packet
is only about whether a session fires the ladder without choosing to.** Nothing is
blocked on the answer; the status quo after R1 is "Recipe", and it is reversible to
"Automatic" by one sentence.
