---
status: complete
resolution: research complete — verdict CHANGE NOTHING in commands/handoff.md (R5 success outcome)
findings: docs/research/handoff-high-value-capture-2026-08-19.md
---

# /handoff — capture the high-value information a succession currently drops

**Owner file:** `commands/handoff.md` (736 lines; symlinked to `~/.claude/commands/handoff.md`)
**Origin:** reso session `579d2a59` (wt-pool-8), 2026-08-19
**Gate:** research-first — implementation was BLOCKED until R2 was answered (operator directive).
**GATE CLEARED 2026-08-19** — R2 answered in `docs/research/handoff-high-value-capture-2026-08-19.md`.
**W3 was NOT taken: the verdict is CHANGE NOTHING in `commands/handoff.md`**, which R5 names as a
success outcome. The file was never opened for editing. See the status log for the full record.

---

## Phase 0 — Agent Team Orchestration

| Wave | Execution locus | Why | Status |
|---|---|---|---|
| **W1 · research** | **S** — this dispatched session, fanning research subagents and/or a Dynamic Workflow | Read-only breadth; S is the default for a dispatched phase and needs no justification | ✅ **DONE** — 2 Dynamic Workflow rounds, 23 agents |
| **W2 · adversarial pass** | **S** — same session | The stated risk is a FALSE POSITIVE change, so the synthesis must be attacked before it is trusted | ✅ **DONE** — 5 refuters + 1 completeness critic across both rounds; round 1's synthesis was refuted on its own headline, which is why round 2 exists |
| **W3 · implementation** | **S** — gated on W1+W2 | Only if the evidence justifies a change. If it becomes ≥2 code-writing tasks, escalate to teammates (`Agent({name})`) per the agent-teams skill | ⛔ **NOT TAKEN — correctly.** The evidence does not justify a change; R5 names this a success outcome. `commands/handoff.md` is byte-identical |

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
- **Length for its own sake.** ⚠️ **Rule stands; its original justification is REFUTED — do not
  re-argue this on cost.** It read "the file is injected whole, every time; a change can be
  net-negative on cost alone", which is false: measured, the file reaches **3.87% of sessions**
  (149 injections / 40 days), at **$0.61–$1.72 per line-year** — economics that would *pay* for a
  reliable fix, not forbid one (findings §R2.3). The rule survives on **attention**, not price: the
  bridge is 1.7% of a successor's first turn, and length competes there.
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

- **2026-08-19 · RESEARCH COMPLETE — verdict: CHANGE NOTHING in `commands/handoff.md`.**
  Findings: **`docs/research/handoff-high-value-capture-2026-08-19.md`**. Two Dynamic Workflow rounds,
  23 agents, ~4.6M subagent tokens, 966 tool calls, read-only on tracked files throughout —
  `commands/handoff.md` was never opened for editing, per the R3 gate.

  **Method actually run** (R3 satisfied): round 1 = 9 finders over orthogonal axes → synthesis →
  3 adversarial refuters + 1 completeness critic. All four returned **NEEDS-REVISION**: the
  recommendation survived, several of its supports did not, and the critic named five unadjudicated
  gaps. Round 2 = 6 gap-closers → re-based synthesis → 2 refuters (**SOUND** / **NEEDS-REVISION**).
  Six further corrections were then applied by the lead in place, each marked inline.

  **R2 answers, in brief** (full evidence + citations in the findings doc):
  - **R2.1** — the machinery-findings gap is **not** what the plan hypothesised. The class *is*
    carried by bridges (84% of succession bridges; 18/18 hand-adjudicated; 3 chains accreting).
    Measured re-derivation is real but cheap: 9 tool calls / 6 sessions / 8 days / **0** operator
    round-trips. **R1's `n=1` premise STANDS** — round 1 claimed the finding was already durable 13
    days earlier and that was refuted by all three refuters and settled by git in round 2 (the 08-19
    failure mode is emitted by the 08-06 fix's *own* code, so it is chronologically impossible as
    prior art).
  - **R2.2** — **reflex, not template.** The reflex already runs at a 22.5-min median capture
    latency, fires 658× vs the template's 183×, and a template-shaped remedy already shipped 31 days
    ago at the arm step (`5d5e734`). A section here would be a second, weaker copy.
  - **R2.3** — the plan's cost premise is **quantitatively wrong** and does not carry the verdict:
    the file reaches 3.9% of sessions (149 injections / 40 days), ~$0.61–1.72 per line-year.
  - **R2.4** — fifteen failure modes, each with a worked example, extending R4's five.
  - **R2.5** — every class is already carried elsewhere; the payoff class is the *dominant* content
    of this repo's memory system. Pointer, not new section.

  **What the verdict rests on** (three attacked-and-surviving supports; a fourth was demoted
  post-review): the class is already carried · **no reachable site beats the existing convention**
  (best candidate reaches 15.6% of recycle authors and **0 of 41** identifiable firing sessions) ·
  prose-only rules here have no runner and a one-way ratchet behind them (32 commits, 922 added /
  186 deleted, **no commit has ever reduced this file**).

  **R5 bullet 3 is not owed** — no change means no negative control for this file. Controls were
  built and **RUN, failing pre-fix**, for three of the *elsewhere* levers (F1, F2, F5); two more are
  specified-but-not-run and labelled as such rather than claimed.

  **Out of scope but real — filed, not done:** F1–F10 in §5 of the findings doc. The two most
  actionable: **F5** (`bin/cc-await-ping`'s WAKE-PATH-DOWN notice names a decision and never names
  the check — **confirmed LIVE**, not closed by the sibling fix, and observed first-hand by the
  session that ran this wave) and **F10** (the only site where a brief-content check could reach
  every fire path is `scripts/handoff-fire.sh`, not this file — filed with three gates it must clear
  first, explicitly **not** recommended).

  **Known residual bound, carried in the verdict rather than a footnote:** everything is measured on
  the `--recycle` arm — 96 of 694 succession-shaped events (13.8%). The new-pane fired-peer arm is
  structurally unmeasurable from today's instruments (open item O1). Eleven open items are recorded
  with what would settle each.

  ⚠️ **The raw evidence base is not durable.** Round-1 artifacts live in a reboot-bounded `/tmp`
  store measured decaying at 23.6%/9 days, and `handoffs.jsonl` is a *ring buffer* that deletes rows.
  The findings doc §2.2 dates every short-half-life fact with its decay mode and re-derivation
  command. **Re-derive those numbers; do not quote them.**

- **2026-08-19 · closed** — verified against trunk, not re-derived. `cf7a5490` (ancestor of
  `origin/main`) carries both the 708-line findings doc and this plan's completion, and it touched
  **only those two files** — so W3's "`commands/handoff.md` is byte-identical" claim is confirmed by
  the commit's own stat, not by assertion. R5 is met in full (findings §8). The two-of-twelve
  heading scan that re-dispatched this item reads per-section markers, which this plan never used;
  its frontmatter `status: complete` and the Phase 0 table were already the truth.

  **One authorised edit was outstanding and is now applied:** findings §R2.3 authorised striking R4
  anti-goal 3's *justification* while keeping its rule, and §8 lists it as owed to the plan. It was
  not carried over when the verdict landed, leaving a refuted cost argument standing in the
  anti-goals — exactly what a re-opener would have read first. The second authorised edit (the
  arm-scope qualifier, `--recycle` = 96/694 succession-shaped events) was already present above and
  is unchanged. The forbidden edit — rewriting R1 to claim the finding was already durable — was
  **not** made; R1 stands as written.
