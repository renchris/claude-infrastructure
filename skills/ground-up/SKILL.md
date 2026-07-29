---
name: ground-up
description: Run a from-first-principles, ground-up-zero rebuild of ONE subsystem — the distilled methodology from the 2026-07-28 landing-pipeline rebuild (9 lands, week-long blockage ended in one session). Use when a subsystem has resisted a week of in-frame fixes, when the user says "/ground-up <topic>", "rebuild X from first principles", "no thought pollution", or when dispatching per-topic rebuild sessions from docs/plans/GROUND_UP_REBUILD_MAP.md. NOT for routine features or identified bugs (normal worklist), and never for more than ONE subsystem per session.
---

# /ground-up <subsystem> — first-principles rebuild, distilled from the one that worked

The 2026-07-28 landing rebuild succeeded because of five prompt clauses — and five things
the prompt never said that had to be improvised. This skill encodes all ten. The exemplar
run (read it before your first rebuild): docs/plans/LAND_PIPELINE_V2.md.

## Phase 0 — frame (before any tool call)

Freeze the DoD as ONE falsifiable sentence with a NUMBER in it
(`Scope (frozen): <subsystem> achieves <metric target> under <standing constraint>`).
Superlatives ("perfect", "100/100") are BANNED from the DoD: they change no engineering
decision and make completion unfalsifiable — the exemplar's Stop-hook thrashed on exactly
this. State the standing constraint that kills lazy designs up front (for landing it was
"no quiet period will ever exist"; find this subsystem's equivalent). Time and effort of
implementation are zero-factors; never start from the cheaper-to-build option.

## Phase 1 — measure the incumbent to death (don't-inherit ≠ don't-measure)

Fan out read-only researchers (target ~3: failure archaeology of prior docs/attempts ·
live telemetry re-derived from disk · the adjacent-layer/deploy seams). Rules that earned
their place: every handed-down count is a CLAIM — re-derive it from primary disk truth
before gating any decision on it (three "facts" fell this way in the exemplar); harvest
stranded reports from transcripts by agentName (idle ≠ delivered); read the load-bearing
code yourself — subagent summaries are for breadth, your own reads are for the decisions.

## Phase 2 — split INVARIANTS from ARCHITECTURE

First principles is not amnesia. Walk MEMORY.md + the incident docs and sort every
hard-won lesson into: (a) INVARIANTS — properties any design must keep (content-verified
lands, bounded external calls, non-verdict ≠ red, absence-is-loud…) — these become
numbered requirements; (b) ARCHITECTURE — the incumbent's mechanisms, inherited by
default from nothing. The exemplar's R1-R9 table is the shape. The design section must
name the INVERSION or structural change that dissolves the failure class (if the new
design is the old one with bigger constants, return to Phase 1).

## Phase 3 — design doc with the four load-bearing sections

docs/plans/<TOPIC>_V2.md (plan-conventions apply: Phase 0 orchestration first, INTEGRATE
edits only): measured-constants table WITH CITATIONS · failure-mode table (every observed
mode → its structural answer — a mode without an answer is an unfinished design) ·
REJECTED ALTERNATIVES with reasons (prevents relitigating; the exemplar's §8) · acceptance
criteria as DISK-TRUTH READS, not narration (which file/log proves each claim, exemplar
§7). Every new mechanism ships with an env kill switch, never a revert-as-plan.

## Phase 4 — build via teammates, prove adversarially

Agent Teams per the standard discipline (disjoint file ownership, ≤150-line briefs,
phase-checkpoint reviews against criteria WRITTEN IN THE PLAN before spawning). Non-negotiable
proof bar, all from the exemplar's catches: RED-proof every new test against the pristine
pre-change tree recovered via `git archive` (never a hand-edited approximation); positive
control next to every absence assertion; `|| false` on non-final `[[ ]]` in bats; re-run
controls under `/bin/bash` when the artifact ships to launchd (the Bash tool runs zsh).
Expect your own gates to catch YOUR defects — the exemplar's bootstrap land correctly
refused itself once; fix, pin, re-land.

## Phase 5 — land, activate, hand off honestly

Land through the v2 fast lane as you go (never batch a week). Name the classifier-terminal
operator steps EARLY, stage them (live pending-activation dir + repo SSOT), and platter
the exact runnable command — with its env seams pre-resolved (the exemplar's activation
needed CC_REPO pointed at the landed worktree; hand the command that WORKS, not the one
that should). Close against the frozen DoD in three buckets: PROVEN (disk reads) ·
IN FLIGHT (autonomous, who owns it) · ACCRUING (time-dependent proof and where it will be
read). Never let an unfalsifiable "perfection" clause keep the session hostage: state the
ceiling and the accrual read, then stop.

## Dispatch (the fan-out the map uses)

One subsystem per session, ONE or TWO concurrent across the fleet at most (each rebuild
lands aggressively; the box and the operator are shared). Fire via /handoff with:
`/ground-up <topic-slug> — scope row from docs/plans/GROUND_UP_REBUILD_MAP.md; read the
map row + this skill + the exemplar plan FIRST.` Update the map row (status, plan link,
landed shas) as part of the rebuild's own DoD.
