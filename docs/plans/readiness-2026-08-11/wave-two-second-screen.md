You are W2 of the READINESS wave in claude-infrastructure. Read
docs/plans/BACKLOG_CONSOLIDATION_2026-08-09.md § "READINESS (2026-08-11)" R4, then
§ "CURRENCY (2026-08-11)" — the latter SPECIFIES what you are building and explains why nobody
built it. W0 landed already (c61ee7147).

GOAL: build THE SECOND SCREEN — a probe is only coverage if it would have FAILED on the day its
item was filed.

THE EVIDENCE, from the CURRENCY pass's own adversarial review: 16 of 26 hand-reviewed probes were
REFUTED, and the dominant class (8 instances vs 2 for the next) was "the grep was already true at
filing" — 918e9bac60b6's lint landed 4 days before its item, 80e6637dfd9e's `default: high` 8 days
before, 8e07e87770ce's string 5 minutes before. Such a probe discriminates NOTHING: it would have
retracted the item the moment it was written. That is not weak coverage, it is ANTI-coverage — a
row that reads as checked and is a guaranteed false retraction. The lead's own 5-item spot check
caught 1 of the 16, because it sampled for the failure mode already known.

The mechanical form is given in the plan and you should start from it, not reinvent it:
    git log -S<token> --before=<item lastTs>
A token already in the tree at filing time cannot be the remedy's signature.

FILES YOU OWN (do not edit any other tracked file; W1 owns bin/cc-dispatch + bin/cc-venue,
W3 owns bin/cc-backlog + scripts/backlog-consolidation-trigger.sh):
  bin/cc-premise       · the predicate — it already reads RAW records and owns the falsifier re-run
  tests/cc-premise*.bats

BUILD:

1. A `filing-day discrimination` arm in cc-premise: given an item's stored falsifier and its
   filing timestamp, decide whether the probe COULD have failed then. Three verdicts, not two —
   DISCRIMINATING · ANTI-COVERAGE · UNDECIDABLE. Undecidable must be its own state and must NOT
   collapse into either neighbour (this repo has paid for a 2-state answer to a 3-state question
   more than once; see MEMORY abstain-rule-can-retire-the-common-case).

2. FAIL-OPEN, matching cc-premise's existing contract (its header states why: it advises and
   almost never refuses, because refusing strands real work). This arm SURFACES anti-coverage; it
   must not retract an item by itself.

3. A RETRO-SCAN over the stored probes, reported not applied: `cc-premise` gains a mode that
   classifies every currently-stored falsifier (157 of them at last count) into the three
   verdicts and prints the ANTI-COVERAGE list with each item's id, probe, and the sha/date that
   proves the token pre-dated the filing. DO NOT auto-clear anything — `cc-backlog falsify
   --clear` exists and is W3-adjacent; a human or a later wave decides. Your deliverable is the
   evidence, and the CURRENCY pass is explicit that closing on second-hand evidence is the weaker
   move.

DoD — every one proven by a command you RUN and PRINT:
  · `bats tests/cc-premise*.bats` green; each NEW case RED-proven against
    `git show origin/main:bin/cc-premise`.
  · a POSITIVE CONTROL from the real store: at least one of the three named anti-coverage items
    (918e9bac60b6, 80e6637dfd9e, 8e07e87770ce) is classified ANTI-COVERAGE by your arm, and at
    least one genuinely-discriminating probe is classified DISCRIMINATING. Both printed. A screen
    that cannot separate those two is not built.
  · the retro-scan runs over the live store and prints its three-way tally.
  · landed via `bash scripts/ship-land.sh` from your worktree, content-verified with
    `git show origin/main:bin/cc-premise` — NEVER by commit count.

CONSTRAINTS: never commit in ~/Development/claude-infrastructure (shared checkout — this repo's
.claude/CLAUDE.md forbids it); work only in your worktree. cc-premise is Python and its git arms
have a history of fabricating verdicts when the repo is unreadable — there is a `_git_usable`
positive control already in the file; use it, do not add a second one. Stop and message the lead
on anything you cannot resolve inside bin/cc-premise.
