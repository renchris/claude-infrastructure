---
status: open
---

# /handoff — capture the high-value information a succession currently drops

**Owner file:** `commands/handoff.md` (736 lines; symlinked to `~/.claude/commands/handoff.md`)
**Origin:** reso session `579d2a59` (wt-pool-8), 2026-08-19
**Gate:** research-first — implementation is BLOCKED until R2 is answered (operator directive)

---

## Phase 0 — Agent Team Orchestration

| Wave | Execution locus | Why |
|---|---|---|
| **W1 · research** | **S** — this dispatched session, fanning research subagents and/or a Dynamic Workflow | Read-only breadth; S is the default for a dispatched phase and needs no justification |
| **W2 · adversarial pass** | **S** — same session | The stated risk is a FALSE POSITIVE change, so the synthesis must be attacked before it is trusted |
| **W3 · implementation** | **S** — gated on W1+W2 | Only if the evidence justifies a change. If it becomes ≥2 code-writing tasks, escalate to teammates (`Agent({name})`) per the agent-teams skill |

**Dependency graph:** W1 → W2 → W3. W3 is not merely last, it is CONDITIONAL — "change nothing"
is a legitimate terminal state (see R5).

**Worktree:** one dedicated worktree off `origin/main` of `claude-infrastructure` (the fire creates
it). No other session should be editing `commands/handoff.md` concurrently — check before writing.

**Lead context budget + succession point:** the research fan-out is read-only and returns findings,
so the lead's window pays only for synthesis. If W3 turns into a multi-file edit and the lead passes
~67% fill, persist findings to `docs/research/` and recycle rather than riding it down.

**Subagents are research-only** — they never write `commands/handoff.md`.

---

## The operator's ask, verbatim in substance

> "improve `/handoff` to concisely capture relevant highest-value details/information distilled
> into the handoff prompt so we don't lose it crossing into the new session. Do not overfit or too
> 'hardcode' this in. we should be thorough so we dont make false positive changes that are
> net-negative, so ensure that we use a Dynamic Workflow and/or research subagent session before
> jumping into any implementation."

Preceded by the question that generated it: *"is our /handoff perfect to capture the high-value
details and we just misspoke? or do we need to make serious changes and we've been silently
dropping high value information every time we handoff and self recycle?"*

---

## R1 — Current state: what is known, and how strong the evidence is

**One session's evidence, not a survey. Treat every claim below as n=1 unless the research
re-derives it.** The evidence cuts BOTH ways and both halves are recorded deliberately — a research
pass that sees only the confirming half will overfit.

### The brief held up (evidence AGAINST a format problem)

The bridge written by session `579d2a59` was audited against what a successor needs and carried:
the landed shas one line each, the two research docs, two non-obvious facts, the live preview URL +
its restart command, the open items *with why each is a value call rather than work*, and a
`NOT defects` section so settled questions are not re-dispatched. The specific loss the operator
challenged — the preview URL — was **already in the brief**, verified by grep before the fire. That
claim was a misspoke by the firing session, nothing more.

### One class WAS silently dropped (evidence FOR a real gap)

The same session established a reproducible defect in the recycle mechanism: `--recycle` prints
`armed … heartbeat verified`, then fails when the `/exit` it types lands as *plain text inside a
running turn* (the case under an autonomous `/loop`), so the pane never reaches a shell prompt and
the watcher exits after 600s. **Nothing is delivered back to the session when that happens** —
armed and dead are indistinguishable from inside, and the firing session kept telling the operator
"type `/exit` and this pane relaunches" when it would not.

Tested at the time: that finding existed **nowhere durable** — a `/var/folders` log (reaped) and the
session's context. It is now in memory (`reference-recycle-probe-types-into-live-composer.md`), but
only because the operator's challenge prompted the check.

**Candidate mechanism — a HYPOTHESIS to test, not a finding:** a brief is scoped to the WORK, so
findings about the MACHINERY have no home in it and die at every succession — and they are exactly
the class a successor cannot re-derive, because their evidence lives in temp logs.

### Why the work itself survives today

Not because `/handoff` captures it — because it goes to commits, docs, backlog and memory *as it is
produced*. The brief is a **pointer, not a container**; when persistence is continuous, dropping the
brief costs nothing. Any proposal that weakens that property is suspect.

---

## R2 — What the research must answer BEFORE any edit

1. **Is the machinery-findings gap real and recurring, or n=1?** Sample real bridges and payloads
   (`~/.claude/logs/handoffs.jsonl`, surviving `/tmp/fire-*.txt`, prior bridges) and ask what each
   dropped that its successor later had to RE-DERIVE. Hunt the re-derivation, not the omission — an
   omission with no downstream cost is not a loss.
2. **Is a TEMPLATE the right lever at all?** The competing hypothesis is a *reflex* ("tooling finding
   → memory the moment it is measured"), which needs no `/handoff` change. They fail differently: a
   template yields empty ceremony sections; a reflex yields nothing when the author forgets. Decide
   on evidence, not taste.
3. **What is the cost side?** `commands/handoff.md` is 736 lines and is injected IN FULL on every
   typed `/handoff`. Any addition is paid at every invocation, forever, by every session. Quantify
   before adding.
4. **What would a NET-NEGATIVE change look like?** Derive the failure modes explicitly so the
   implementation can be checked against them (R4 is a starting list, not a complete one).
5. **Do adjacent mechanisms already cover it?** `dod-persist.sh`, the memory system, `cc-backlog`,
   `handoff-disposition.sh`, SessionStart re-injection. A gap already covered elsewhere needs a
   pointer, not a new section.

---

## R3 — Method (MANDATORY, operator-directed)

**Research or a Dynamic Workflow FIRST; implementation is gated behind its findings.** Do not open
`commands/handoff.md` for editing until R2 is answered with evidence.

Suggested shape — the executing session decides the real decomposition, do NOT treat this as the
spec: breadth-first subagents over the distinct axes (historical bridge/payload corpus · the
competing-lever question · cost-of-injection · adjacent-mechanism coverage · failure-mode
derivation), then an adversarial pass over whatever the synthesis proposes, because the operator's
stated fear is a false-positive change rather than a missed one.

Per `~/.claude/CLAUDE.md`: decompose before counting, read the subagent count off the decomposition,
default N=10 (band 8-12), no parallelism cap, 15-20% adversarial floor.

---

## R4 — Explicit anti-goals (a change doing any of these is net-negative)

- **Ceremony sections.** A mandatory heading that is usually empty or filler trains every future
  author to skim the template. Worse than no section.
- **Overfitting to this session.** The recycle-machinery finding is ONE instance. A rule shaped
  exactly around it may be a category error rather than a general law — R2.1 exists to test that.
- **Length for its own sake.** The file is injected whole, every time; a change can be net-negative
  on cost alone.
- **Duplicating durable state into the bridge.** Squarely against the skill's own Core rule (the
  staleness trap). Any proposal moving content INTO the brief rather than pointing at it must clear
  that rule explicitly.
- **A guard that cannot fail.** If the proposal is a check, it needs a negative control — run it
  against a bridge that SHOULD fail and observe the failure.

---

## R5 — Definition of done

- R2's five questions answered with cited evidence (file:line, corpus counts, or measured cost).
- A recommendation that may legitimately be **"change nothing in `commands/handoff.md`"** — that is
  a SUCCESS outcome if the evidence supports it, not a failure to deliver.
- If a change IS recommended: it ships with the R4 negative control, and its cost (added lines ×
  injection frequency) is stated.
- Findings written to `docs/research/` in this repo; this plan's status log updated IN PLACE
  (INTEGRATE, never overwrite).

---

## Status log

- **2026-08-19 · opened** by reso session `579d2a59` (wt-pool-8) at the operator's direction, after a
  `/handoff` exchange in which the firing session made a false claim about context loss (the URL was
  in the brief) but a real, separate loss was then found and persisted.
